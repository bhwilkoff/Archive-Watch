#!/usr/bin/env python3
"""Tonight (WEB-DESIGN §4.1c): one rule-picked film a day. A published day
never changes, no film repeats within the gap, and only the marquee's pool is
eligible. Control: a film under the vote floor is never picked."""
import datetime as dt, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_catalog_index as B

def row(i, votes=5000, minutes=80, hero=1):
    r = [f"f{i}", f"Film {i}", 1925, "silent-film", "p", 1, "", None, 1, 0, 70, votes,
         "", "", "b", 0, hero, minutes]
    return r
rows = [row(i) for i in range(200)] + [row(900, votes=10), row(901, minutes=30), row(902, hero=0)]
today = dt.date(2026, 9, 26)
t = B.tonight_schedule(rows, {}, today=today)
fails = 0
def check(label, ok):
    global fails; print(("PASS " if ok else "FAIL ") + label); fails += 0 if ok else 1
check("yesterday through 13 days ahead", len(t) == 15 and "2026-09-25" in t and "2026-10-09" in t)
check("no repeats inside the schedule", len(set(t.values())) == len(t))
check("control: under the vote floor is never picked", "f900" not in t.values())
check("short and non-marquee films are never picked", not {"f901", "f902"} & set(t.values()))
later = B.tonight_schedule(rows, t, today=today + dt.timedelta(days=5))
check("a published day keeps its film on a later rebuild",
      all(later[d] == t[d] for d in later if d in t))
gone = dict(t); pool_minus = [r for r in rows if r[0] != t["2026-09-27"]]
again = B.tonight_schedule(pool_minus, gone, today=today)
check("a day whose film left the pool is re-picked", again["2026-09-27"] != t["2026-09-27"])
print("PASS tonight" if not fails else f"FAILED ({fails})"); sys.exit(1 if fails else 0)
