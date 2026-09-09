#!/usr/bin/env python3
"""
report_workflow_health.py — carry the auditor's findings to a GitHub issue.

An auditor never fails. A workflow going red says "I could not do my job",
and the auditor did its job the moment it looked. Failing it to signal
somebody ELSE's problem is a category error, and an alert channel that cries
wolf is one the owner mutes — after which a real break goes unread. The owner
has corrected this twice:

    "I shouldn't receive a failure alert for a non-failure status."

So urgent findings go to ONE issue, by title:

  * nothing urgent  -> any open issue is closed with a note
  * something urgent -> the issue is opened, or its body UPDATED in place

Updating rather than commenting is deliberate: the question a reader has is
"what is wrong NOW", not "what has ever been wrong". The issue body always
holds the current state, and its existence is the alert.

Run (from the audit step, which writes its findings to the step summary):
  python3 tools/report_workflow_health.py --summary "$GITHUB_STEP_SUMMARY"
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

TITLE = "Workflow health: attention needed"
LABEL = "workflow-health"
# Findings that nothing else alerts for. A FAILED run already emails through
# GitHub; a BROKEN one (green, produced nothing) and a KILLED one (cancelled,
# publish skipped) do not.
URGENT = ("BROKEN", "KILLED")


def gh(*args, check=True):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[:300])
    return r.stdout.strip()


def findings(summary_path: str) -> list:
    """The auditor's own lines, read back from the step summary."""
    try:
        text = open(summary_path, encoding="utf-8").read()
    except OSError:
        return []
    out = []
    for line in text.splitlines():
        m = re.match(r"\s*(BROKEN|KILLED|FAILED|DROPPED|STALE|SILENT|DRAINED)\s+(.+)", line)
        if m:
            out.append((m.group(1), m.group(2).strip()))
    return out


def open_issue() -> dict | None:
    try:
        rows = json.loads(gh("issue", "list", "--state", "open", "--search",
                             f'"{TITLE}" in:title', "--json", "number,title"))
    except RuntimeError:
        return None
    return next((r for r in rows if r["title"] == TITLE), None)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--summary", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    found = findings(a.summary)
    urgent = [f for f in found if f[0] in URGENT]
    run = (f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/"
           f"{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/"
           f"{os.environ.get('GITHUB_RUN_ID', '')}")

    print(f"{len(found)} finding(s), {len(urgent)} urgent")
    for sev, what in found:
        print(f"  {sev:<8} {what[:90]}")
    if a.dry_run:
        return 0

    existing = open_issue()

    if not urgent:
        if existing:
            gh("issue", "close", str(existing["number"]), "--comment",
               f"The fleet is clean as of the latest audit — {run}")
            print(f"closed #{existing['number']}: nothing urgent")
        else:
            print("nothing urgent, no open issue — nothing to do")
        return 0

    body = ["These are the failures **nothing else alerts for**: a run that was",
            "green but produced nothing, or one cancelled with its publish steps",
            "skipped. GitHub emails about ordinary failures already.", "",
            "| severity | workflow |", "|---|---|"]
    body += [f"| **{sev}** | {what} |" for sev, what in urgent]
    other = [f for f in found if f[0] not in URGENT]
    if other:
        body += ["", "Also reported, not urgent:", ""]
        body += [f"- `{sev}` {what}" for sev, what in other]
    body += ["", f"Latest audit: {run}", "",
             "_This issue is updated in place by the daily audit and closes",
             "itself when the fleet is clean._"]
    text = "\n".join(body)

    if existing:
        gh("issue", "edit", str(existing["number"]), "--body", text)
        print(f"updated #{existing['number']} with {len(urgent)} urgent finding(s)")
    else:
        try:
            gh("issue", "create", "--title", TITLE, "--body", text, "--label", LABEL)
        except RuntimeError:
            # A missing label must not lose the alert.
            gh("issue", "create", "--title", TITLE, "--body", text)
        print(f"opened the health issue with {len(urgent)} urgent finding(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
