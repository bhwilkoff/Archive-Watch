#!/usr/bin/env python3
"""Re-run workflow runs that GitHub's hosted-runner fleet never actually started.

Runner-allocation failures — "The job was not acquired by Runner of type hosted even
after multiple attempts", or a bare "Set up job" failure — are GitHub-side infrastructure
faults, not faults in our code: not one step of ours ever executed. During an Actions
incident these silently drop scheduled work until the next cron tick, which for a daily
cron means a whole missed day.

This sweeper finds those runs and re-runs just their failed jobs. It is deliberately
conservative; a run is only re-run when all of these hold:

  * its conclusion is `failure` (never `cancelled` — that is usually a human or a
    concurrency group, and re-running would fight whoever cancelled it),
  * every bad job got no further than "Set up job", so none of our own steps ran,
  * it has been retried fewer than MAX_ATTEMPTS times, and
  * no later run of the same workflow has since succeeded — an hourly cron heals
    itself, and re-running a stale one is pure waste.

Because "no step of ours ran" is the gate, a re-run can never repeat a side effect:
there was no side effect. A genuine code failure always shows a completed "Set up job"
plus a failing step of ours, so it is never touched here.

Env:
  GH_TOKEN          auth for the gh CLI (the workflow passes the default token)
  GITHUB_REPOSITORY owner/name; falls back to the repo of the current directory
  LOOKBACK_HOURS    how far back to sweep (default 12) — wide enough to still heal a
                    backlog after a multi-hour incident, since the sweeper's own cron
                    ticks are dropped during one too
  MAX_ATTEMPTS      give up after this many attempts of a run (default 3)
  MAX_RERUNS        cap on re-runs per sweep, so a bad day cannot become a storm (default 10)
  DRY_RUN           set to 1 to report what would be re-run without doing it
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

LOOKBACK_HOURS = int(os.environ.get("LOOKBACK_HOURS", "12"))
MAX_ATTEMPTS = int(os.environ.get("MAX_ATTEMPTS", "3"))
MAX_RERUNS = int(os.environ.get("MAX_RERUNS", "10"))
DRY_RUN = os.environ.get("DRY_RUN", "") not in ("", "0", "false")

# Steps the runner harness contributes itself. Anything else is ours.
HARNESS_STEPS = {"Set up job", "Complete job"}

STATUS_URL = "https://www.githubstatus.com/api/v2/components.json"
# Retrying INTO an ongoing outage is how the retry budget gets burned before Actions
# is well again: at a 30-minute cadence, three attempts are spent in 90 minutes and
# the run is then abandoned for good. Sit out an outage instead and heal afterwards —
# which is what the 12-hour lookback is for. Degraded performance still gets retried;
# only a declared outage is worth waiting out.
OUTAGE_STATUSES = {"major_outage", "partial_outage"}


def gh(*args: str) -> str:
    proc = subprocess.run(
        ["gh", *args], capture_output=True, text=True, check=False
    )
    if proc.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def gh_json(*args: str):
    return json.loads(gh(*args) or "null")


def actions_outage() -> str | None:
    """Return the Actions component status when GitHub is declaring an outage.

    Best-effort: if the status API cannot be reached, say nothing is wrong and let
    the sweep proceed — a status page we cannot read must not block healing.
    """
    try:
        with urllib.request.urlopen(STATUS_URL, timeout=15) as resp:
            components = json.load(resp)["components"]
    except Exception:
        return None
    for component in components:
        if component.get("name") == "Actions":
            status = component.get("status")
            return status if status in OUTAGE_STATUSES else None
    return None


def repo_slug() -> str:
    slug = os.environ.get("GITHUB_REPOSITORY")
    if slug:
        return slug
    return gh_json("repo", "view", "--json", "nameWithOwner")["nameWithOwner"]


def parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def never_ran_our_code(repo: str, run_id: int) -> bool:
    """True when every bad job in the run died before any step of ours executed."""
    jobs = gh_json("api", f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")["jobs"]
    bad = [j for j in jobs if j.get("conclusion") in ("failure", "cancelled")]
    if not bad:
        return False
    for job in bad:
        for step in job.get("steps") or []:
            if step.get("name") in HARNESS_STEPS:
                continue
            if step.get("conclusion") is not None:
                return False  # a step of ours ran — this is a real failure
    return True


def healed_since(repo: str, workflow_id: int, created_at: datetime) -> bool:
    """True when a later run of the same workflow already succeeded."""
    runs = gh_json(
        "api",
        f"repos/{repo}/actions/workflows/{workflow_id}/runs"
        "?status=success&per_page=20",
    )["workflow_runs"]
    return any(parse_ts(r["created_at"]) > created_at for r in runs)


def main() -> int:
    repo = repo_slug()
    outage = actions_outage()
    if outage and not DRY_RUN:
        report = (
            f"GitHub Actions is reporting {outage}. Sitting this sweep out so the "
            f"retry budget survives the incident; the {LOOKBACK_HOURS}h lookback "
            "heals the backlog once Actions recovers."
        )
        print(report)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a") as fh:
                fh.write(f"## Runner-allocation sweep\n\n{report}\n")
        return 0

    cutoff = datetime.now(timezone.utc) - timedelta(hours=LOOKBACK_HOURS)
    self_name = os.environ.get("GITHUB_WORKFLOW", "")

    runs = gh_json(
        "api", f"repos/{repo}/actions/runs?status=failure&per_page=100"
    )["workflow_runs"]

    reran, skipped = [], []
    for run in runs:
        created = parse_ts(run["created_at"])
        if created < cutoff:
            continue
        if run["name"] == self_name:
            continue  # never chase our own tail
        if run.get("run_attempt", 1) >= MAX_ATTEMPTS:
            skipped.append((run, f"already at attempt {run['run_attempt']}"))
            continue
        if not never_ran_our_code(repo, run["id"]):
            continue  # a real failure — leave it alone and let it be seen
        if healed_since(repo, run["workflow_id"], created):
            skipped.append((run, "a later run of this workflow already succeeded"))
            continue
        if len(reran) >= MAX_RERUNS:
            skipped.append((run, f"hit the {MAX_RERUNS}-re-run cap for this sweep"))
            continue

        if not DRY_RUN:
            try:
                gh("api", "-X", "POST",
                   f"repos/{repo}/actions/runs/{run['id']}/rerun-failed-jobs")
            except RuntimeError as exc:
                skipped.append((run, f"re-run rejected: {exc}"))
                continue
        reran.append(run)

    prefix = "would re-run" if DRY_RUN else "re-ran"
    lines = [f"Swept {repo} for runner-allocation failures in the last {LOOKBACK_HOURS}h."]
    for run in reran:
        lines.append(f"  {prefix}: {run['name']} #{run['run_number']} — {run['html_url']}")
    for run, why in skipped:
        lines.append(f"  skipped: {run['name']} #{run['run_number']} — {why}")
    if not reran and not skipped:
        lines.append("  nothing to do — no infrastructure failures found.")
    report = "\n".join(lines)
    print(report)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as fh:
            fh.write(f"## Runner-allocation sweep\n\n```\n{report}\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
