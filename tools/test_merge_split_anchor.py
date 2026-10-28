#!/usr/bin/env python3
"""
test_merge_split_anchor.py — a merge component bridged across two imdb anchors
is split by anchor, not discarded.

merge_film_duplicates unions same-titled copies by _same_film; a bare copy
(no imdb) can be "the same film" as both anchors, so A — bare — B formed one
component, _consistent refused it for carrying two ids, and NONE of the copies
of either film merged (audit 2026-10-28; measured on the live catalog it frees
the 1913 Universal Dr Jekyll and Mr Hyde re-upload).

Controls: a bare copy that fits both anchors joins neither; Decision 084's
color veto still holds inside a sub-group; Decision 158's colorized copy still
never wins; spine-owned episodes never merge (the I4 wiring, for the index).

Run: python3 tools/test_merge_split_anchor.py
"""
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_sqlite as B  # noqa: E402

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


def c(aid, imdb, rt, year=1913, color="bw", **kw):
    d = {"archiveID": aid, "title": "Dr Jekyll and Mr Hyde", "year": year, "colorMode": color,
         "contentType": "silent-film", "runtimeSeconds": rt, "downloadURL": f"https://a/{aid}.mp4",
         "imdbID": imdb}
    d.update(kw)
    return d


def kept(items, **kw):
    out = B.merge_film_duplicates(copy.deepcopy(items), **kw)
    return {i["archiveID"] for i in out}, dict(B.merge_film_duplicates.aliases)


a1, a2 = c("jekyll-universal-a", "tt0002813", 1600), c("jekyll-universal-b", "tt0002813", 1620)
b1, b2 = c("jekyll-kinemacolor-a", "tt0003000", 1100), c("jekyll-kinemacolor-b", "tt0003000", 1110)
bridge = c("jekyll-bare-bridge", None, 1350)            # within 40% of both anchors
only_a = c("DRJEKYLLANDMRHYDE1913SilentAUniversal", None, 1590)  # within 40% of A only... and B
only_a["runtimeSeconds"] = 1900                          # 1900 vs 1100 is >40%: A only
group = [a1, a2, b1, b2, bridge, only_a]
ids, al = kept(group)
check("anchor A's copies merge", ("jekyll-universal-a" in ids) != ("jekyll-universal-b" in ids), ids)
check("anchor B's copies merge", ("jekyll-kinemacolor-a" in ids) != ("jekyll-kinemacolor-b" in ids), ids)
check("a bare copy that is only A's film joins A",
      al.get("DRJEKYLLANDMRHYDE1913SilentAUniversal", "").startswith("jekyll-universal"), al)
check("a bare copy that fits both anchors joins neither (control)", "jekyll-bare-bridge" in ids)
check("the two films stay two films", any(x.startswith("jekyll-universal") for x in ids)
      and any(x.startswith("jekyll-kinemacolor") for x in ids))

real = B._split_by_anchor
B._split_by_anchor = lambda g: []
ids_old, _ = kept(group)
B._split_by_anchor = real
check("control: without the split nothing merges (the defect)", len(ids_old) == len(group), ids_old)

veto = [c("v-a", "tt0002813", 1600, colorSat=1.0), c("v-b", "tt0002813", 1600, color="color", colorSat=30.0),
        c("v-c", "tt0003000", 1100), c("v-d", "tt0003000", 1100), c("v-bridge", None, 1350, color=None)]
ids, _ = kept(veto)
check("a confident B&W/color pair inside a sub-group still does not merge (Decision 084)",
      {"v-a", "v-b"} <= ids, ids)
col = [c("plain", "tt0002813", 1600), c("plain-colorized", "tt0002813", 1600, color="color", subtitleHLS="x"),
       c("other", "tt0003000", 1100), c("other2", "tt0003000", 1100), c("br", None, 1350, color=None)]
ids, al = kept(col)
check("a colorized copy never wins its sub-group (Decision 158)", "plain" in ids and "plain-colorized" not in ids,
      ids)

eps = [c("s1", "tt0002813", 1600), c("s2", "tt0002813", 1600)]
ids, _ = kept(eps, spine_aids=frozenset({"s1", "s2"}))
check("spine-owned episodes are never merged (what the index now passes)", ids == {"s1", "s2"})
check("control: without spine_aids they would be", len(kept(eps)[0]) == 1)

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
