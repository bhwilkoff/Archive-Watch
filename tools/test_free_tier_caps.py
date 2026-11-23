#!/usr/bin/env python3
"""Free-tier caps that one workflow can quietly break for all the others.

Owner, 2026-11-23: "We should not be anywhere close to the limits on any plan
if we are using them correctly."

- ONE free OMDb key (1,000 requests a day) is shared by several workflows. A
  run that spends the whole day starves the rest with a 401 nobody sees, so
  omdb_backfill.py must default to at most 800 and the workflow must pass at
  most 800.
- subtitle-sync.yml runs for hours and resumes from verdicts carried on a
  release; two overlapping runs would race that file. It needs a fixed
  concurrency group that never cancels a run in progress.

    python3 tools/test_free_tier_caps.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fails = 0


def check(name, ok, detail=""):
    global fails
    print(f"  {'ok  ' if ok else 'FAIL'} {name}{'' if ok else f'  ({detail})'}")
    fails += 0 if ok else 1


src = (ROOT / "tools/omdb_backfill.py").read_text()
m = re.search(r'"--max-calls", type=int, default=(\d+)', src)
default = int(m.group(1)) if m else None
check("omdb_backfill.py defaults to at most 800 calls", default is not None and default <= 800, f"default {default}")

wf = (ROOT / ".github/workflows/omdb-backfill.yml").read_text()
passed = [int(n) for n in re.findall(r"omdb_backfill\.py \\\s*--max-calls \$\{\{ github\.event\.inputs\.max_calls \|\| '(\d+)' \}\}", wf)]
check("omdb-backfill.yml passes at most 800 on the schedule", bool(passed) and max(passed) <= 800, f"found {passed}")

sub = (ROOT / ".github/workflows/subtitle-sync.yml").read_text()
top = re.search(r"^concurrency:\n((?:[ \t]+.*\n|[ \t]*#.*\n)+)", sub, re.M)
body = top.group(1) if top else ""
group = re.search(r"^\s+group:\s*(\S+)", body, re.M)
check("subtitle-sync.yml has a top-level concurrency group", bool(group), "none")
check("...a FIXED group, not one per ref or run", bool(group) and "${{" not in group.group(1), group.group(1) if group else "")
check("...that never cancels a run in progress", re.search(r"cancel-in-progress:\s*false", body) is not None, "missing or true")

print(f"\n{'FAIL' if fails else 'PASS'}: {fails} failed")
sys.exit(1 if fails else 0)
