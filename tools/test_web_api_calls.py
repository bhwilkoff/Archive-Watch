#!/usr/bin/env python3
"""Every `API.<name>` the web app calls must be something js/api.js exports.

A room link on the web called `API.summary`, which never existed, from
v1.42.469 to v1.42.584: every browser guest saw "Watching ... with the room"
and no player. Plain JavaScript has no compiler to say so; this does.

    python3 tools/test_web_api_calls.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
api = (ROOT / "js/api.js").read_text()
block = api[api.rindex("return {"):]
exported = set(re.findall(r"\b([A-Za-z_]\w*)\b", block[:block.index("}")])) - {"return"}

callers = ["watch.js", "tv.js", "curate/curate.js"]
bad = []
for name in callers:
    p = ROOT / name
    if not p.exists():
        continue
    for n, line in enumerate(p.read_text().splitlines(), 1):
        for used in re.findall(r"(?<![\w.])API\.([A-Za-z_]\w*)", line):
            if used not in exported:
                bad.append(f"{name}:{n} API.{used}")

# Control: the check must be able to fail.
assert "summary" not in exported, "control: API.summary should not be exported"
print(f"js/api.js exports: {', '.join(sorted(exported))}")
if bad:
    print("FAIL: calls to things js/api.js does not export:\n  " + "\n  ".join(bad))
    sys.exit(1)
print("PASS: every API.<name> the web app calls exists")
