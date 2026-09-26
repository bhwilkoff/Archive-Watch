#!/usr/bin/env python3
"""A removal request hides the film and keeps it hidden (takedown.html).

The listed id is excluded with excludedReason "takedown" — a marker the rights
reconcile keeps (Decision 083) — and an unlisted id is untouched (the control).
Run: python3 tools/test_takedowns.py
"""
import json, sys, tempfile
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R
import audit_rights as A

tmp = Path(tempfile.mkdtemp())
(tmp / "shared/editorial").mkdir(parents=True)
(tmp / "shared/editorial/takedowns.json").write_text(json.dumps({
    "_how": "ignored", "asked-to-remove": {"date": "2026-09-26", "from": "test"}}))
R.REPO = tmp
items = [{"archiveID": "asked-to-remove"}, {"archiveID": "left-alone"}]
stats = Counter()
R.exclude_takedowns(items, stats)
ok = True
def check(label, cond):
    global ok
    print(("PASS " if cond else "FAIL ") + label); ok &= bool(cond)
check("the listed film is hidden", items[0].get("excluded") is True)
check("with the takedown marker", items[0].get("excludedReason") == "takedown")
check("CONTROL: an unlisted film is untouched", "excluded" not in items[1])
check("the _how note is not an id", stats["takedown_excluded"] == 1)
src = Path(A.__file__).read_text()
check("the rights reconcile keeps excludedReason (it will not un-hide it)",
      '"excludedReason"' in src.split("FOREIGN = (", 1)[1].split(")", 1)[0])
sys.exit(0 if ok else 1)
