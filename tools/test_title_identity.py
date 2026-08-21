#!/usr/bin/env python3
"""Precision controls for the wrong-film audit.

Acting is deliberately narrower than detecting: it is better to leave a wrong
match visible than to clear a right one (Decisions 035/040/064). These pin the
boundary — especially the cases the rule must NOT touch.
"""
import sys
sys.path.insert(0, "tools")
from audit_title_identity import wrong_members, clear_match, norm_title, conflicts

def item(aid, imdb, director=None, **kw):
    d = {"archiveID": aid, "imdbID": imdb, "director": director,
         "title": kw.pop("title", "X"), "year": kw.pop("year", 1949),
         "contentType": "feature-film"}
    d.update(kw); return d

ok = True
def check(name, cond, detail=""):
    global ok; ok &= bool(cond)
    print(f"  {'PASS' if cond else 'FAIL'} {name}{(' — ' + detail) if detail else ''}")

# THE REPORTED CASE
mem = [item("restored", "tt0040566", "Lawrence Huntington"),
       item("colorized", "tt26931594", "Morgan Neville")]
w = wrong_members(1949, mem)
check("1949 film + modern id => names the modern copy",
      len(w) == 1 and w[0]["imdbID"] == "tt26931594")

# MUST NOT ACT — two genuinely old works sharing a title
check("two LOW ids => abstains (distinct old works)",
      wrong_members(1915, [item("a", "tt0006497"), item("b", "tt0005077")]) == [])
# MUST NOT ACT — a modern film legitimately has a modern id
check("modern film => abstains entirely",
      wrong_members(2015, [item("a", "tt4123430"), item("b", "tt4123431")]) == [])
# MUST NOT ACT — if EVERY member is modern we cannot tell which is wrong
check("all-modern ids => abstains",
      wrong_members(1949, [item("a", "tt9000001"), item("b", "tt9000002")]) == [])
check("no year => abstains", wrong_members(None, mem) == [])

# CLEARING takes the match-derived fields AND the match-keyed captions
it = item("colorized", "tt26931594", "Morgan Neville", tmdbID=1260643,
          posterURL="https://image.tmdb.org/x.jpg", artworkSource="tmdb",
          hasRealArtwork=True, subtitleHLS="https://x/master.m3u8",
          captions=[{"lang": "en", "source": "subsource"}])
clear_match(it)
check("clears imdb/tmdb/director", not it["imdbID"] and not it["tmdbID"])
check("clears match-derived artwork",
      it["posterURL"] is None and it["hasRealArtwork"] is False)
check("drops imdb-keyed captions and the HLS", it["captions"] == []
      and "subtitleHLS" not in it)

# archive-native captions belong to the ITEM, not the match — they must survive
it2 = item("x", "tt26931594", captions=[{"lang": "en", "source": "archive"}],
           artworkSource="archive", posterURL="https://archive.org/services/img/x")
clear_match(it2)
check("keeps archive-native captions", len(it2["captions"]) == 1)
check("keeps archive-native artwork", it2["posterURL"] is not None)

# clustering must survive the qualifier noise these copies carry
check("normalises release qualifiers",
      norm_title("Man on the Run") == norm_title("The Man on the Run COLORIZED 720p HD"))
# a cluster that AGREES is not a conflict
check("agreeing copies are not flagged",
      conflicts([item("a", "tt1", title="Q"), item("b", "tt1", title="Q")]) == [])

print("\nALL PASS" if ok else "\nFAILURES")
sys.exit(0 if ok else 1)
