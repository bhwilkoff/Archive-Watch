#!/usr/bin/env python3
"""Assert every split workflow's apply job is fully gated.

An `apply` job skips the catalog fetch when there are no deltas. Any step after
that check which is NOT gated on it then runs against a catalog that is not
there — remediating nothing, or publishing nothing over something.

This slipped twice while converting workflows by script: once because a step had
no `if:` at all, and once because it already had one (`dry_run != 'true'`) that
neither the "add" nor the "replace" branch matched. So it is a check now rather
than a habit.

It also asserts that every step which RUNS `gh` has a GH_TOKEN in scope. A
runner has no ambient credential, so `gh` fails with a message about setting
GH_TOKEN -- and when that step is a publish, everything after it is SKIPPED
and the `if: always()` upload finds nothing to upload. publish-db shipped no
catalog DB for two days on exactly that, with the run going red every hour in
a way nobody read as "the pipeline is down".
"""
import re
import sys, pathlib, yaml

GATE = "steps.gate.outputs.go"

# A COMMAND, not prose. Matching a bare "gh " anywhere finds "high enough" and
# "through" in comments, which is three false alarms out of four.
GH_CMD = re.compile(r"(?:^|[|&;(]\s*|\$\(\s*)(?:gh|bash tools/gh_retry\.sh)\s")
GH_TOOL = re.compile(r"catalog_release\.py\s+(?:publish|fetch)")


def runs_gh(run: str) -> bool:
    for line in (run or "").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if GH_CMD.search(line) or GH_TOOL.search(line):
            return True
    return False


bad = []
for f in sorted(pathlib.Path(".github/workflows").glob("*.yml")):
    doc = yaml.safe_load(f.read_text()) or {}
    job = (doc.get("jobs") or {}).get("apply")
    if not job:
        continue
    seen = False
    for step in job.get("steps", []):
        name = step.get("name", "") or step.get("uses", "")
        if "Stop if nothing changed" in name:
            seen = True
            continue
        if seen and GATE not in str(step.get("if", "")):
            bad.append(f"{f.stem}: '{name}' runs even with no deltas")

# An AUDITOR never fails. A workflow going red is a statement that IT could
# not do its job; failing one to signal somebody ELSE's problem is a category
# error, and an alert channel that cries wolf gets muted — after which a real
# break goes unread. Findings belong in a report (the step summary, an issue),
# never in an exit code. The owner has corrected this twice.
REPORTERS = {"workflow-health", "pulse"}
reporting_fails = []
for name in sorted(REPORTERS):
    f = pathlib.Path(".github/workflows") / f"{name}.yml"
    if not f.exists():
        continue
    doc = yaml.safe_load(f.read_text()) or {}
    for jname, job in (doc.get("jobs") or {}).items():
        for step in job.get("steps", []):
            run = step.get("run", "") or ""
            if step.get("continue-on-error"):
                continue
            # `exit 1` anywhere, not only at the start of a line — the
            # first version of this check missed `echo ...; exit 1`.
            # `exit 1` anywhere, not only at the start of a line — the first
            # version of this check missed `echo ...; exit 1` — plus the two
            # ways an inline python heredoc ends a run.
            if not re.search(r"(?:(?:^|[;&\n])\s*exit [1-9]"
                             r"|sys\.exit\(\s*[1-9]"
                             r"|raise SystemExit\(\s*[1-9])", run, re.M):
                continue
            # A reporter MAY fail over its OWN mechanics — it could not write or
            # push its file. Telling that apart from failing over what it READ
            # is not something a regex can judge, so the AUTHOR states it, in
            # the step, in words: `# reporter-may-fail: <why>`. Explicit, and
            # impossible to add by accident.
            why = re.search(r"#\s*reporter-may-fail:\s*(\S.*)", run)
            if why:
                continue
            reporting_fails.append(
                f"{name} [{jname}]: '{step.get('name')}' exits non-zero with no "
                f"`# reporter-may-fail: <why>` — a reporter reports its findings, "
                f"it does not fail on them")

untokened = []
for f in sorted(pathlib.Path(".github/workflows").glob("*.yml")):
    doc = yaml.safe_load(f.read_text()) or {}
    top = "GH_TOKEN" in (doc.get("env") or {})
    for jname, job in (doc.get("jobs") or {}).items():
        jenv = "GH_TOKEN" in (job.get("env") or {})
        for step in job.get("steps", []):
            if not runs_gh(step.get("run", "")):
                continue
            if top or jenv or "GH_TOKEN" in (step.get("env") or {}):
                continue
            untokened.append(f"{f.stem} [{jname}]: '{step.get('name')}' "
                             f"runs gh with no GH_TOKEN in scope")

for b in bad + untokened + reporting_fails:
    print("  " + b)
print(f"{len(bad)} ungated step(s)" if bad else "every apply job is fully gated")
print(f"{len(untokened)} gh step(s) with no token"
      if untokened else "every gh step has a token")
print(f"{len(reporting_fails)} reporting step(s) that can fail a run"
      if reporting_fails else "no reporting workflow fails on its findings")
sys.exit(1 if (bad or untokened or reporting_fails) else 0)
