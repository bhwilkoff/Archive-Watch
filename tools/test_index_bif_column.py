#!/usr/bin/env python3
"""
test_index_bif_column.py — the Roku channel and the index must agree on a
column POSITION, in two languages that cannot import each other.

The defect this locks out: 16,697 trick-play BIFs were generated and uploaded
to archive.org over several days, and the channel never asked for a single one
of them — `MainScene.brs` offers a BIF only when `it.awBif` is true, `awBif`
is read from row column 15, and `build_catalog_index.py` emitted 15 columns
(0-14). Roku certification 4.7 requires trick-play over fifteen minutes, so
the submission would have failed on a requirement we had already paid for.

Checked to FAIL against the 15-column index.

Run: python3 tools/test_index_bif_column.py
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


src = (REPO / "tools" / "build_catalog_index.py").read_text()
m = re.search(r'"fields":\s*\[(.*?)\]', src, re.S)
fields = [f.strip().strip('"') for f in m.group(1).split(",") if f.strip()]
check("the index declares a bif column", "bif" in fields, str(fields))
if "bif" not in fields:
    # Report the whole contract as broken rather than dying here: a test that
    # crashes tells you less than one that says which side is wrong.
    print("\n  the index has no bif column — every reader below is unmatched")
    print(f"\n{ok} passed, {fail + 1} failed")
    sys.exit(1)
pos = fields.index("bif")

# Every BrightScript reader of the index, found rather than listed: a new one
# added at the wrong offset must fail here too.
readers = []
for brs in (REPO / "roku").rglob("*.brs"):
    for mm in re.finditer(r"awBif\s*=\s*\(r\[(\d+)\]\s*=\s*1\)", brs.read_text()):
        readers.append((brs.name, int(mm.group(1))))
check("at least two BrightScript files read the flag", len(readers) >= 2, str(readers))
for name, idx in readers:
    check(f"{name} reads column {idx}, the index writes {pos}", idx == pos)

for brs in (REPO / "roku").rglob("*.brs"):
    t = brs.read_text()
    for mm in re.finditer(r"r\.Count\(\)\s*>\s*(\d+)\s*then\s*\w+\.awBif", t):
        check(f"{brs.name} guards the row length correctly",
              int(mm.group(1)) == pos, mm.group(1))

# The row the builder appends must actually be that long.
row = re.search(r"rows\.append\(\[(.*?)\]\)", src, re.S).group(1)
n = row.count(",") + 1
check(f"the appended row carries {len(fields)} values", n == len(fields), f"{n} values")

main = (REPO / "roku" / "components" / "MainScene.brs").read_text()
check("a flagged film gets the archive.org bif url",
      "archivewatch-bifs/" in main and "awBif = true" in main)
check("the player passes it to the Roku Video node",
      "HDBifUrl" in (REPO / "roku" / "components" / "PlayerScreen.brs").read_text())

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
