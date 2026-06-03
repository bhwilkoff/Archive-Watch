#!/usr/bin/env python3
"""
probe_collections.py — research aid for Track A (source breadth). Queries the
Archive scrape API for the movie-item count of each candidate collection so we
can decide which to add to discover_archive_collections.DEFAULT_COLLECTIONS.

Network-only: must run in CI (the dev sandbox can't reach archive.org). It only
READS counts — it never ingests. Run via .github/workflows/probe-sources.yml
(workflow_dispatch) and read the counts from the step summary.

Usage:
  python tools/probe_collections.py                 # probe the built-in list
  python tools/probe_collections.py a,b,c           # probe specific collections
"""

import json
import sys
import time
import urllib.parse
import urllib.request

SCRAPE = "https://archive.org/services/search/v1/scrape"
UA = "ArchiveWatch/1.0 (+https://github.com/bhwilkoff/Archive-Watch)"

# Already mined (DEFAULT_COLLECTIONS) — skip these in the report.
ALREADY = {
    "feature_films", "silent_films", "classic_tv", "prelinger",
    "animationandcartoons", "more_animation", "film_noir", "SciFi_Horror",
    "comedy_films", "short_films", "newsandpublicaffairs", "documentary_films",
    "FedFlix", "nasa", "ephemera", "universal_newsreels", "computerchronicles",
    "academic_films",
}

# Candidate PD / PD-rich VIDEO collections to evaluate. The probe reveals which
# exist + have meaningful counts; non-existent ids simply report 0.
CANDIDATES = [
    "classic_cartoons", "publicmovies212", "avgeeks", "stock_footage",
    "serials", "B_movies", "bmovies", "horror_films", "horrormovies",
    "western_movies", "westerns", "scifi_movies", "silent_comedy",
    "educationalfilms", "vintage_tv", "tv_classics", "60s_70s_tv",
    "militaryfilms", "usnationalarchives", "us_government_films",
    "movietrailers", "regional_film", "world_cinema", "foreign_films",
    "home_movies", "amateur_films", "newsreels", "publicaffairs",
    "internet_archive_films", "feature_films_silent", "noir", "pulp_fiction",
    "opensource_movies",
]


def count(coll):
    q = f"collection:{coll} AND mediatype:movies"
    url = SCRAPE + "?" + urllib.parse.urlencode({"q": q, "count": 100})
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r).get("total", 0)
    except Exception as e:
        return f"err({type(e).__name__})"


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    colls = [c.strip() for c in arg.split(",") if c.strip()] or CANDIDATES
    rows = []
    for c in colls:
        if c in ALREADY:
            continue
        rows.append((c, count(c)))
        time.sleep(0.3)
    # numeric first, descending
    rows.sort(key=lambda r: (isinstance(r[1], str), -(r[1] if isinstance(r[1], int) else 0)))
    print(f"{'collection':32} count")
    print("-" * 44)
    for c, n in rows:
        print(f"{c:32} {n}")
    worthy = [c for c, n in rows if isinstance(n, int) and n >= 100]
    print("\nWORTHY (>=100 items), comma-list for DEFAULT_COLLECTIONS:")
    print(",".join(worthy))
    return 0


if __name__ == "__main__":
    sys.exit(main())
