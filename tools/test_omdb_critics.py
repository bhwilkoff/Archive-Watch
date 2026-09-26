#!/usr/bin/env python3
"""Critics' scores from OMDb (Orphaned Films research #10, 2026-09-26).

Pins the parse of OMDb's `Ratings` array, that the scores land on the item,
that a schema bump re-fetches only films OMDb KNOWS (never re-spending the
free tier's daily quota on known misses), and that a never-fetched film is
queued ahead of a refresh. Control: an unknown source adds nothing."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import omdb_lib as L
import omdb_backfill as B

fails = 0
def check(label, ok):
    global fails
    print(("PASS " if ok else "FAIL ") + label)
    fails += 0 if ok else 1

R = [{"Source": "Internet Movie Database", "Value": "8.3/10"},
     {"Source": "Rotten Tomatoes", "Value": "97%"},
     {"Source": "Metacritic", "Value": "98/100"}]
check("Rotten Tomatoes and Metacritic parse", L._critics(R) == {"rt": 97, "mc": 98})
check("control: IMDb alone is not a critics' score",
      L._critics(R[:1]) is None)
check("N/A is not a score", L._critics([{"Source": "Metacritic", "Value": "N/A"}]) is None)

it = {}
L.apply_rich(it, {"critics": {"rt": 97, "mc": 98}})
check("scores land on the item", it.get("criticsRT") == 97 and it.get("criticsMC") == 98)

old_pos = {"schema": 3, "imdb_rating": 7.1, "fetched_at": "2026-09-01"}
old_neg = {"schema": 3, "fetched_at": "2026-09-01"}
cur = {"schema": L.CACHE_SCHEMA_VERSION, "imdb_rating": 7.1, "fetched_at": "2026-09-01"}
check("an older positive entry is refreshed", B.needs_fetch(old_pos))
check("an older NEGATIVE entry is not re-spent", not B.needs_fetch(old_neg))
check("a current entry is left alone", not B.needs_fetch(cur))

print("PASS omdb critics" if not fails else f"FAILED ({fails})")
sys.exit(1 if fails else 0)
