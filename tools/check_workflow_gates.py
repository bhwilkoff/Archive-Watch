#!/usr/bin/env python3
"""Assert every split workflow's apply job is fully gated.

An `apply` job skips the catalog fetch when there are no deltas. Any step after
that check which is NOT gated on it then runs against a catalog that is not
there — remediating nothing, or publishing nothing over something.

This slipped twice while converting workflows by script: once because a step had
no `if:` at all, and once because it already had one (`dry_run != 'true'`) that
neither the "add" nor the "replace" branch matched. So it is a check now rather
than a habit.
"""
import sys, pathlib, yaml

GATE = "steps.gate.outputs.go"
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

for b in bad:
    print("  " + b)
print(f"{len(bad)} ungated step(s)" if bad else "every apply job is fully gated")
sys.exit(1 if bad else 0)
