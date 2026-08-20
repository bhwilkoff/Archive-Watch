#!/usr/bin/env python3
"""Catch the ways a workflow can be broken while reporting success.

Every failure found in this repo's CI has been of that kind, not a red X:

  * `word-index` logged "audio download failed" for months. The download was
    fine; a Python import was missing, AFTER it. Green, 260 minutes, 0 films.
  * `stock-index` scanned real films and indexed 0 shots, four times a day, for
    ~95 minutes a run. Green. The scene detector was never printing its results.
  * `validate-posters` was green while a spoofed User-Agent drew 429s from
    Wikimedia for 53% of what it checked.
  * `omdb-backfill` was green with an EMPTY repo secret.
  * `faststart-derivatives` fixed items, wrote the catalog, then hit GitHub's
    360-minute cap and SKIPPED every publish step. Reported as "cancelled".
  * `auto-captions` rejected every film nightly because a hosted runner has no
    speech models and never can.

A human reading a green tick learns none of that. So this reads what each
workflow's last run actually PRODUCED and flags the patterns:

  BROKEN     ran, took real time, produced nothing
  DROPPED    cancelled before any step ran (displaced in the queue)
  KILLED     died at a timeout with publish steps skipped
  DRAINED    genuinely finished its backlog but still running at full cadence
  SILENT     no yield line at all — cannot be judged, which is its own problem

Exit code is non-zero when anything needs attention, so it can gate a workflow.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

REPO = os.environ.get("GITHUB_REPOSITORY", "bhwilkoff/Archive-Watch")
_REPO_DIR = pathlib.Path(__file__).resolve().parents[1]
# These do not produce catalog yield and never will: they build, deploy, probe
# or sweep. Flagging them as SILENT is noise that trains a reader to skim.
NOT_PRODUCERS = {
    "App Store build (cloud)", "Deploy Pages", "pages-build-deployment",
    "Retry infrastructure failures", "Probe speech assets (diagnostic)",
    "Probe candidate sources", "Publish catalog DB", "Faststart remux (generate + host)",
    # Itself. Judging its own last run makes one failure permanent: it fails,
    # then reports that failure as a finding, which fails it again.
    "Workflow health",
}
LOOKBACK_HOURS = int(os.environ.get("LOOKBACK_HOURS", "36"))
# A run that took longer than this and produced nothing is not "no work to do".
REAL_WORK_MINUTES = float(os.environ.get("REAL_WORK_MINUTES", "10"))

# "+0 films", "0 shots total", "passed=0", "candidates=0" — the shapes a tool
# uses to say it did nothing. Kept broad deliberately; a false flag costs a
# glance, a missed one costs months.
ZERO = re.compile(
    r"(\+0\s+\w+|\b0\s+(shots?|films?|items?|cues?|posters?|timings?|covers?)\b"
    r"|passed=0|candidates=0|\bnothing to (do|apply)\b)", re.I)
# Search the RAW line rather than anchoring after stripping a timestamp: the
# `gh run view --log` prefix is "job<TAB>step<TAB>2026-...Z", and stripping it
# by pattern dropped real summaries — stock-tags reported "tagged 2876 shots"
# and this called it silent.
YIELD_LINE = re.compile(r"\[[a-z0-9_-]{2,}\]\s+\S", re.I)


def gh(*args: str) -> str:
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    return r.stdout


def api(path: str):
    try:
        return json.loads(gh("api", f"repos/{REPO}/{path}"))
    except json.JSONDecodeError:
        return {}


def minutes(run: dict) -> float:
    try:
        a = datetime.fromisoformat(run["run_started_at"].replace("Z", "+00:00"))
        b = datetime.fromisoformat(run["updated_at"].replace("Z", "+00:00"))
        return (b - a).total_seconds() / 60
    except Exception:
        return 0.0


def cron_period_hours(path: str) -> float | None:
    """Roughly how often this workflow is SUPPOSED to run, from its own cron.

    A fixed lookback cannot audit a fleet whose cadences span hourly to monthly:
    with LOOKBACK_HOURS=36, seven weekly/monthly workflows were skipped outright,
    and tv-canonical sat FAILED for four days while the daily report said
    "Nothing needs attention". Judge each workflow against its own period
    instead. Returns None when the workflow has no schedule (dispatch-only).
    """
    try:
        text = (_REPO_DIR / path).read_text(encoding="utf-8")
    except OSError:
        return None
    crons = re.findall(r"cron:\s*['\"]([^'\"]+)['\"]", text)
    best = None
    for c in crons:
        f = c.split()
        if len(f) != 5:
            continue
        minute, hour, dom, _mon, dow = f
        if dom != "*" and not dom.startswith("*/"):
            hrs = 720.0                       # a day-of-month cron is monthly
        elif dow != "*":
            hrs = 168.0                       # a day-of-week cron is weekly
        elif dom.startswith("*/"):
            hrs = 24.0 * int(dom[2:] or 1)
        elif hour.startswith("*/"):
            hrs = float(int(hour[2:] or 1))
        elif hour == "*":
            hrs = float(int(minute[2:] or 1)) / 60 if minute.startswith("*/") else 1.0
        else:
            hrs = 24.0                        # a fixed hour every day
        best = hrs if best is None else min(best, hrs)
    return best


def judge(name: str, run: dict) -> tuple[str, str] | None:
    """Return (severity, explanation) when this run deserves a human's attention."""
    concl = run.get("conclusion")
    mins = minutes(run)

    if concl == "cancelled":
        jobs = api(f"actions/runs/{run['id']}/jobs").get("jobs", [])
        if not any(j.get("steps") for j in jobs):
            return ("DROPPED", "displaced in the concurrency queue before any step ran")
        skipped = [s["name"] for j in jobs for s in j.get("steps", [])
                   if s.get("conclusion") == "skipped"]
        publishy = [s for s in skipped if re.search(r"publish|commit|upload|rebuild", s, re.I)]
        if publishy:
            return ("KILLED", f"died at {mins:.0f}m and SKIPPED {len(publishy)} publish "
                              f"step(s): {publishy[0]}")
        return ("KILLED", f"cancelled after {mins:.0f}m")

    if concl != "success":
        return ("FAILED", f"conclusion={concl}")

    # Green. Did it do anything?
    log = gh("run", "view", str(run["id"]), "--log")
    yields = []
    for line in log.split("\n"):
        m = YIELD_LINE.search(line)
        if m and "[command]" not in line and "[36;1m" not in line:
            yields.append(line[m.start():].strip())
    if not yields:
        return ("SILENT", f"{mins:.0f}m, no yield line — cannot tell what it did")
    # A SHARDED workflow prints one summary per shard, and the last line in a
    # concatenated log may come from a merge job that says nothing about yield.
    # So judge every summary-shaped line, not the final one: it is only broken
    # if NONE of them produced anything.
    summaries = [y for y in yields
                 if re.search(r"(\+\d+\s+\w+|\btotal\b|passed=|done:|candidates=|"
                              r"\b(tagged|wrote|applied|upgraded|indexed|published|"
                              r"harvested|fixed|classified)\b)", y, re.I)]
    if not summaries:
        # No line announced a total. Fall back to the last line carrying a
        # number rather than calling the run silent — "tagged 2876 shots" is a
        # perfectly good report that simply does not use the word "total", and
        # flagging it trains a reader to skim the ones that matter.
        summaries = [y for y in yields if re.search(r"\d", y)][-1:]
    if not summaries:
        return ("SILENT", f"{mins:.0f}m, nothing reported — cannot tell what it did")
    if all(ZERO.search(s) for s in summaries):
        last = summaries[-1][:110]
        if mins >= REAL_WORK_MINUTES:
            return ("BROKEN", f"ran {mins:.0f}m and produced nothing — {last}")
        return ("DRAINED", f"nothing to do in {mins:.0f}m — {last}")
    return None


def main() -> int:
    workflows = [w for w in api("actions/workflows?per_page=100").get("workflows", [])
                 if w.get("state") == "active" and w.get("path", "").startswith(".github")]
    cutoff = datetime.now(timezone.utc) - timedelta(hours=LOOKBACK_HOURS)

    findings: list[tuple[str, str, str]] = []
    checked = 0
    for w in sorted(workflows, key=lambda x: x["name"]):
        # The most recent COMPLETED run, not simply the most recent. A workflow
        # whose newest run is still in flight was otherwise invisible to this —
        # which is how the first version reported "nothing needs attention"
        # while stock-index sat on a zero-yield run from the night before.
        runs = [r for r in api(f"actions/workflows/{w['id']}/runs?per_page=10")
                .get("workflow_runs", []) if r.get("status") == "completed"]
        if not runs:
            continue
        # Judge the CADENCE, not whatever ran last. A manual workflow_dispatch
        # is an experiment — someone testing a fix with a tiny --limit — and
        # taking it as the verdict cuts both ways: it raised a false BROKEN for
        # a deliberate 3-film word-index probe, and far worse, a SUCCESSFUL
        # dispatch sitting on top of a failed scheduled run would report the
        # workflow healthy while its schedule was broken. word-index had two
        # consecutive scheduled failures (2026-08-18, 08-19) hidden behind
        # exactly that on 08-20.
        sched = [r for r in runs if r.get("event") == "schedule"]
        run = sched[0] if sched else runs[0]
        try:
            started = datetime.fromisoformat(run["run_started_at"].replace("Z", "+00:00"))
        except Exception:
            continue
        if w["name"] in NOT_PRODUCERS:
            continue
        # Window sized to THIS workflow's cadence, not a fixed 36h. A weekly
        # job's newest run is always older than 36h, so the old fixed cutoff
        # skipped it forever — which is how tv-canonical stayed FAILED for four
        # days under a green "Nothing needs attention".
        period = cron_period_hours(w.get("path", ""))
        window = timedelta(hours=max(LOOKBACK_HOURS, 2.5 * period)) if period else None
        age = datetime.now(timezone.utc) - started
        if window is None:
            if started < cutoff:
                continue                      # dispatch-only: keep the old rule
        elif age > window:
            # It has not run in over two of its own periods. That is itself the
            # finding — a schedule that stopped firing produces no failing run
            # to notice.
            checked += 1
            findings.append(("STALE", w["name"],
                             f"last completed run was {age.total_seconds() / 3600:.0f}h ago; "
                             f"cadence is ~{period:.0f}h"))
            continue
        checked += 1
        verdict = judge(w["name"], run)
        if verdict:
            why = verdict[1]
            # A monthly workflow cannot confirm a fix for up to a month, so a
            # true finding can outlive the repair by weeks — faststart's budget
            # landed 2026-08-09, eight days after the Aug 1 run this reports.
            # The VERDICT still comes from the schedule (a dispatch must never
            # be able to mask a broken one); a later successful dispatch is
            # appended only as CONTEXT, so nobody re-investigates a fix that
            # already shipped.
            newer_ok = [r for r in runs
                        if r.get("event") != "schedule"
                        and r.get("conclusion") == "success"
                        and (r.get("run_started_at") or "") > (run.get("run_started_at") or "")]
            if newer_ok:
                why += (f" — but a manual run on "
                        f"{newer_ok[0]['run_started_at'][:10]} SUCCEEDED, so this "
                        f"may already be fixed and awaiting its next scheduled run")
            findings.append((verdict[0], w["name"], why))

    order = {"BROKEN": 0, "KILLED": 1, "FAILED": 2, "DROPPED": 3, "STALE": 4, "SILENT": 5, "DRAINED": 6}
    findings.sort(key=lambda f: (order.get(f[0], 9), f[1]))

    print(f"Checked {checked} workflows, each against its OWN cadence "
          f"(dispatch-only ones against {LOOKBACK_HOURS}h).\n")
    if not findings:
        print("Nothing needs attention: every recent run produced something.")
        return 0
    for sev, name, why in findings:
        print(f"  {sev:8} {name[:38]:40} {why}")

    urgent = [f for f in findings if f[0] in ("BROKEN", "KILLED", "FAILED")]
    print(f"\n{len(findings)} finding(s); {len(urgent)} need action rather than a decision.")
    return 1 if urgent else 0


if __name__ == "__main__":
    sys.exit(main())
