#!/usr/bin/env python3
"""A publish over a MOVED release merges this run's changes; it never reverts another's.

2026-09-30: review batch E16 was published at ~05:45 UTC and gone by 12:20 —
a workflow that fetched earlier published its whole stale file over it.
catalog_release._merge_onto_newer carries only the fields this run changed."""
import gzip
import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog_release as C

tmp = Path(tempfile.mkdtemp())
C.CATALOG, C.BASE, C.GZ = tmp / "catalog.json", tmp / "base.json.gz", tmp / "catalog.json.gz"

def gz(path, items):
    with gzip.open(path, "wt", encoding="utf-8") as f:
        json.dump({"items": items}, f)

base = [{"archiveID": "a", "title": "A", "synopsis": "old"}, {"archiveID": "b", "title": "B", "posterURL": "p0"}]
gz(C.BASE, base)
# theirs: someone else rewrote a's synopsis and added item c
theirs = [{"archiveID": "a", "title": "A", "synopsis": "REVIEWED"}, {"archiveID": "b", "title": "B", "posterURL": "p0"},
          {"archiveID": "c", "title": "C"}]
# mine: this run changed b's poster and ingested d; it never touched a
mine = [{"archiveID": "a", "title": "A", "synopsis": "old"}, {"archiveID": "b", "title": "B", "posterURL": "p1"},
        {"archiveID": "d", "title": "D"}]
C.CATALOG.write_text(json.dumps({"items": mine}))

class R:
    returncode, stderr = 0, ""
def fake_net(*a):
    gz(C.GZ, theirs)
    return R()
C._gh_net = fake_net

rc = C._merge_onto_newer()
out = {i["archiveID"]: i for i in json.loads(C.CATALOG.read_text())["items"]}
checks = [
    ("merge succeeds", rc == 0),
    ("another writer's change survives (the E16 case)", out["a"]["synopsis"] == "REVIEWED"),
    ("this run's change lands", out["b"]["posterURL"] == "p1"),
    ("another writer's new item survives", "c" in out),
    ("this run's new item lands", "d" in out),
]
C.BASE.unlink()
checks.append(("CONTROL: no base on disk refuses rather than overwrite", C._merge_onto_newer() == 3))
fails = 0
for n, ok in checks:
    fails += not ok
    print(("PASS " if ok else "FAIL ") + n)
sys.exit(1 if fails else 0)
