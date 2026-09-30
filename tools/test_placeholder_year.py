#!/usr/bin/env python3
"""Ingest holds an uploader's 1900/1901 placeholder year (ingest_candidates._placeholder_year)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ingest_candidates as I

OPEN = {"collection": ["opensource_movies", "community"]}
cases = [
    ("placeholder on an open upload", {"archiveID": "jake-pilot", "title": "Jake's Team Pirate Pilot", "year": 1900}, OPEN, {}, True),
    ("1901 is a placeholder too", {"archiveID": "e5675", "title": "Mall Moods", "year": 1901}, OPEN, {}, True),
    ("CONTROL: year in the identifier", {"archiveID": "fire-1901-williamson", "title": "Fire!", "year": 1901}, OPEN, {}, False),
    ("CONTROL: Wikidata year backs it", {"archiveID": "x", "title": "Scrooge", "year": 1901}, OPEN, {"year": 1901}, False),
    ("CONTROL: an IMDb id backs it", {"archiveID": "x", "title": "Kiss", "year": 1900}, OPEN, {"imdbID": "tt0"}, False),
    ("CONTROL: a curated collection", {"archiveID": "x", "title": "Tetherball", "year": 1900}, {"collection": ["silent_films"]}, {}, False),
    ("CONTROL: any other year", {"archiveID": "x", "title": "Y", "year": 1905}, OPEN, {}, False),
]
fails = 0
for name, item, md, cand, want in cases:
    got = I._placeholder_year(item, md, cand)
    ok = got == want
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name)
print(f"{len(cases) - fails}/{len(cases)}")
sys.exit(1 if fails else 0)
