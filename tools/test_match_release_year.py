#!/usr/bin/env python3
"""An unverified match that stands gives a yearless item its release year, marked.

2026-09-30: 91 served titles kept an unverifiable TMDb match and no year, so
the printed-renewal check (title AND year) could never reach them."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_external_match as V

V.archive_meta = lambda aid: (None, None)
def run(item, matched):
    V.matched_film_release_year = lambda *a, **k: matched
    it = dict(item)
    return V.verify(it, None, None, tmdb_token="x"), it

base = {"archiveID": "HellsHeadquarters", "title": "Hell's Headquarters", "contentType": "feature-film",
        "tmdbID": 123, "imdbID": None}
fails = 0
def check(name, ok):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name)

v, it = run(base, 1932)
check("a standing match gives a yearless item its release year", v == "unverifiable" and it.get("year") == 1932
      and it.get("yearSource") == "match-release-year" and it.get("decade") == 1930)
v, it = run(base, 1985)
check("CONTROL: a modern match is still cleared, never adopted", v == "cleared_modern" and it.get("year") is None)
v, it = run({**base, "year": 1931}, 1932)
check("CONTROL: an item with its own year keeps it", it.get("year") == 1931 and it.get("yearSource") is None)
v, it = run(base, None)
check("CONTROL: no matched year leaves no year", it.get("year") is None)
sys.exit(1 if fails else 0)
