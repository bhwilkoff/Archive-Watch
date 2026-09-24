#!/usr/bin/env python3
"""§ More Like This — the pipeline ranking (tools/build_related.py).

Pins what the ranking exists for, on a fixture, so a weight change cannot
quietly bring back the failures that shaped it (2026-09-24):
  * a shared PERSON outranks a pile of rare keywords (His Girl Friday put
    "wager" + "fugitive" above Howard Hawks's own Red River);
  * a film never lists another COPY of itself (the first draft filled
    Nosferatu's shelf with five Nosferatus);
  * ineligible (hidden / adult) films never appear;
  * era and genre alone are not a reason.
Control: with KEYWORD_PAIR_CAP lifted, the keyword pile must win.
"""
import sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
import build_related as B

def film(aid, title, year, **kw):
    d = {"archiveID": aid, "title": title, "year": year, "contentType": "feature-film",
         "genres": ["Comedy"], "decade": year // 10 * 10}
    d.update(kw); return d

rare = [f"rare{i}" for i in range(16)]   # shared ONLY by hgf and pile
items = [
    film("hgf", "His Girl Friday", 1940, director="Howard Hawks", keywords=rare + ["newspaper"]),
    film("rr", "Red River", 1948, director="Howard Hawks"),
    film("pile", "Keyword Pile", 1940, keywords=rare),
    film("hgf2", "His Girl Friday", 1940, director="Howard Hawks"),           # another copy
    film("hidden", "Hidden Hawks", 1941, director="Howard Hawks"),
    film("era", "Same Era Comedy", 1940),                                     # era + genre only
] + [film(f"f{i}", f"Filler {i}", 1950 + i % 40, keywords=["newspaper"]) for i in range(200)]
# 200 fillers make a keyword on two films rare enough to name a reason on its
# own (the ranking now admits only candidates with a named link), so the
# control below can still show the pile winning without the cap.
eligible = lambda it: it["archiveID"] != "hidden"

def shelf(cap):
    B.KEYWORD_PAIR_CAP = cap
    return [r for r, _s, _w in B.compute_related(items, eligible=eligible)["hgf"]]

ok = True
def check(name, cond):
    global ok; ok &= bool(cond); print(f"  {'ok  ' if cond else 'FAIL'} {name}")

s = shelf(24)
check("the director's other film leads the shelf", s and s[0] == "rr")
check("the director outranks the keyword pile", "pile" not in s or s.index("rr") < s.index("pile"))
check("never another copy of itself", "hgf2" not in s)
check("never an ineligible film", "hidden" not in s)
check("era + genre alone is not a reason", "era" not in s)
reason = dict((r, w) for r, _s, w in B.compute_related(items, eligible=eligible)["hgf"])
check("the reason names the person", reason.get("rr") == "director:Howard Hawks")
c = shelf(10_000)
if c and c[0] == "rr":
    print("CONTROL FAIL: without the cap the keyword pile should win — the test cannot discriminate"); sys.exit(2)
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
