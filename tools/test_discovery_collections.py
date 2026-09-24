#!/usr/bin/env python3
"""Every collection the nightly sweep mines must return items on archive.org.

Collection ids are case-sensitive: `film_noir` and `comedy_films` returned 0
on every run for months while `Film_Noir` / `Comedy_Films` hold ~1,600 each,
and nothing said so because an empty sweep looks like "no new items".
Control: a deliberately wrong-cased id must read 0.

    python3 tools/test_discovery_collections.py
"""
import json, sys, time, urllib.parse, urllib.request
sys.path.insert(0, __import__("os").path.dirname(__file__))
from discover_archive_collections import DEFAULT_COLLECTIONS

def count(coll):
    q = urllib.parse.quote(f"collection:{coll} AND mediatype:movies")
    url = f"https://archive.org/advancedsearch.php?q={q}&fl%5B%5D=identifier&rows=0&output=json"
    return json.load(urllib.request.urlopen(url, timeout=60))["response"]["numFound"]

fail = 0
if count("film_noir") != 0:
    print("CONTROL FAIL: wrong-cased film_noir should read 0 — the check cannot discriminate"); sys.exit(2)
for c in DEFAULT_COLLECTIONS:
    n = count(c); time.sleep(0.3)
    ok = n > 0
    fail |= not ok
    print(f"  {'ok  ' if ok else 'FAIL'} {c:28} {n:>8,}")
print("PASS" if not fail else "FAIL — a swept collection returns nothing")
sys.exit(1 if fail else 0)
