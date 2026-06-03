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
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "catalog.json"
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

# DATA-DRIVEN candidates: real, proven-existing Archive collection ids taken
# from the catalog items' own `collections[]` (guessing ids failed — the first
# probe found none). Excludes already-mined collections, user favorite lists
# (fav-*), and generic/umbrella/admin collections. The probe then reports each
# one's FULL Archive size (often larger than our incidental membership), so we
# add the worthy ones to DEFAULT_COLLECTIONS.
_GENERIC = {
    "moviesandfilms", "stream_only", "additional_collections", "opensource_movies",
    "opensource_media", "community", "television", "audio", "movies", "data",
    "colorized-movies",        # colorization can create new copyright — skip for PD
    "feature_films_unsorted",  # dumping ground where junk lands — don't mine
    "whisper_test", "test_collection",
}

def derive_candidates(top=40):
    from collections import Counter
    try:
        items = json.loads((CATALOG).read_text())["items"]
    except Exception:
        return []
    c = Counter()
    for it in items:
        for coll in (it.get("collections") or []):
            if (coll and coll not in ALREADY and coll not in _GENERIC
                    and not coll.startswith("fav-")
                    and not coll.lower() in {m.lower() for m in ALREADY}):
                c[coll] += 1
    return [coll for coll, _ in c.most_common(top)]

CANDIDATES = []  # populated from the catalog at runtime (see main)


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
    colls = [c.strip() for c in arg.split(",") if c.strip()] or derive_candidates()
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
