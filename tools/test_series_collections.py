#!/usr/bin/env python3
"""Film SERIES collections (2026-09-24) stay well-formed.

A `series-*` entry in collection_metadata.json is not an Archive.org
collection: its members are films whose `franchise` it lists, and both
builders (build_sqlite, build_catalog_index) read SERIES_BY_FRANCHISE.
Checks: every series entry names franchises, no franchise is claimed twice,
ids are unique, the app copy is the same file, and a film carrying a listed
franchise maps to its entry. Control: an unlisted franchise maps to nothing.
"""
import json, sys
from pathlib import Path
R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import build_sqlite as b

shared = R / "shared/editorial/collection_metadata.json"
app = R / "ArchiveWatch/ArchiveWatch/collection_metadata.json"
d = json.loads(shared.read_text())
ids = [c["id"] for c in d["collections"]]
series = [c for c in d["collections"] if c["id"].startswith("series-")]
claimed = [f for c in series for f in c.get("franchises") or []]
ok = True
def check(name, cond):
    global ok; ok &= bool(cond); print(f"  {'ok  ' if cond else 'FAIL'} {name}")
check("ids are unique", len(ids) == len(set(ids)))
check("every series entry lists franchises", all(c.get("franchises") for c in series))
check("no franchise is claimed twice", len(claimed) == len(set(claimed)))
check("the app bundle reads the same file", app.resolve() == shared.resolve() or app.read_text() == shared.read_text())
check("a listed franchise maps to its entry",
      b.SERIES_BY_FRANCHISE.get("Sherlock Holmes (Basil Rathbone) Collection") == "series-sherlock-holmes-rathbone")
check("control: an unlisted franchise maps to nothing", b.SERIES_BY_FRANCHISE.get("Carry On Collection") is None)
print(f"{len(series)} series collections")
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
