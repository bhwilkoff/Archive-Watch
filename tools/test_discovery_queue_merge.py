#!/usr/bin/env python3
"""The Wikidata step must keep every queued candidate it did not find itself.

It keyed its merge on wikidataQID alone; archive-collection and wants
candidates carry None, so all of them collapsed onto one key and were deleted
every night (2026-09-25: 15,084 of 27,143 lost per run). Control: keying on
the QID alone must lose them.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from discover_wikidata_pd import queue_key

prior = [{"wikidataQID": "Q1", "iaid": "a"}, {"wikidataQID": None, "iaid": "b", "status": "held_suspect_year"},
         {"wikidataQID": None, "iaid": "c"}, {"wikidataQID": None, "iaid": None, "title": "a want"},
         {"wikidataQID": None, "iaid": None, "title": "another want"}]
kept = {queue_key(i, c): c for i, c in enumerate(prior)}
control = {c["wikidataQID"]: c for c in prior}
if len(control) == len(prior):
    print("CONTROL FAIL: QID-only keying should collapse the None entries"); sys.exit(2)
ok = len(kept) == len(prior) and any(c.get("status") == "held_suspect_year" for c in kept.values())
print(f"kept {len(kept)}/{len(prior)} (QID-only kept {len(control)})")
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
