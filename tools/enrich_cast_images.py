#!/usr/bin/env python3
"""
enrich_cast_images.py — fill missing cast/crew photos from TMDb /search/person.

Movie cast photos come from /movie/{id}/credits (~79% covered) and TV cast now
comes from TVmaze (sparse photos for old actors). This backfills the REMAINDER:
for every cast member with no profilePath, look the person up by name on TMDb
/search/person and take the best match's profile_path. Works for BOTH movies
(catalog.json items) and TV (series/*.json).

A global name->path cache (tools/cast_image_cache.json) means each unique name is
looked up once and the job is resumable. Idempotent: only fills blank profilePaths.

TMDb token: env TMDB_BEARER_TOKEN or Secrets.xcconfig (see tmdb_lib).
Rate limit: 40 req / 10s -> throttle 0.28s.

Run:
    python tools/enrich_cast_images.py --tv          # series/*.json
    python tools/enrich_cast_images.py --movies      # ./catalog.json (fetch first)
    python tools/enrich_cast_images.py --tv --movies [--limit-names N]
"""

from __future__ import annotations

import argparse
import glob
import json
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SERIES = REPO / "series"
CACHE = Path(__file__).resolve().parent / "cast_image_cache.json"
TMDB_API = "https://api.themoviedb.org/3"


def load_cache() -> dict:
    if CACHE.exists():
        try:
            return json.loads(CACHE.read_text())
        except json.JSONDecodeError:
            return {}
    return {}


def search_person(name: str, token: str, session) -> str:
    """Best TMDb profile_path for a person name (highest-popularity match that has
    a photo), or "" if none. Returns the TMDb path (PersonChip prepends the host)."""
    try:
        r = session.get(f"{TMDB_API}/search/person",
                        params={"query": name, "include_adult": "false"},
                        headers={"Authorization": f"Bearer {token}",
                                 "User-Agent": "ArchiveWatch-cast-images"},
                        timeout=20)
        if r.status_code == 429:
            time.sleep(2); return search_person(name, token, session)
        if r.status_code != 200:
            return ""
        results = r.json().get("results") or []
        for p in results:                       # results are popularity-sorted
            if p.get("profile_path"):
                return p["profile_path"]
        return ""
    except requests.RequestException:
        return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--movies", action="store_true")
    ap.add_argument("--tv", action="store_true")
    ap.add_argument("--limit-names", type=int, default=0, help="cap unique lookups (testing)")
    args = ap.parse_args()
    if not (args.movies or args.tv):
        ap.error("pass --movies and/or --tv")

    token = T.load_tmdb_token()
    if not token:
        print("[cast-img] no TMDB_BEARER_TOKEN — skipping"); return 0
    session = requests.Session()
    cache = load_cache()

    # Gather targets: (file-or-None, container-list, member) for each member needing a photo.
    movie_items = []
    series_docs = []   # (path, doc)
    needed_names = set()

    if args.movies and CATALOG.exists():
        cat = json.load(open(CATALOG))
        movie_items = cat["items"] if isinstance(cat, dict) else cat
        for it in movie_items:
            for m in (it.get("cast") or []):
                if not m.get("profilePath"):
                    needed_names.add(m["name"])
        _movie_cat = cat
    if args.tv:
        for f in sorted(glob.glob(str(SERIES / "*.json"))):
            d = json.load(open(f))
            if not d.get("cast"):
                continue
            if any(not m.get("profilePath") for m in d["cast"]):
                series_docs.append((f, d))
                for m in d["cast"]:
                    if not m.get("profilePath"):
                        needed_names.add(m["name"])

    # Resolve names not already cached.
    to_lookup = [n for n in sorted(needed_names) if n not in cache]
    if args.limit_names:
        to_lookup = to_lookup[:args.limit_names]
    print(f"[cast-img] members needing a photo across {len(needed_names)} unique names; "
          f"{len(to_lookup)} to look up ({len(cache)} cached)")
    for i, name in enumerate(to_lookup, 1):
        cache[name] = search_person(name, token, session)
        if i % 50 == 0 or i == len(to_lookup):
            CACHE.write_text(json.dumps(cache))
            hits = sum(1 for v in cache.values() if v)
            print(f"[{i:>5}/{len(to_lookup)}] cached {len(cache)} ({hits} with photo)")
        time.sleep(0.28)
    CACHE.write_text(json.dumps(cache))

    # Apply cache -> fill blanks.
    def fill(members) -> int:
        n = 0
        for m in members or []:
            if not m.get("profilePath"):
                p = cache.get(m["name"])
                if p:
                    m["profilePath"] = p; n += 1
        return n

    if args.movies and movie_items:
        filled = sum(fill(it.get("cast")) for it in movie_items)
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(_movie_cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)
        print(f"[cast-img] movies: filled {filled} cast photos -> {CATALOG.name}")
    if args.tv:
        tv_filled = tv_files = 0
        for f, d in series_docs:
            n = fill(d.get("cast"))
            if n:
                tv_filled += n; tv_files += 1
                Path(f).write_text(json.dumps(d, ensure_ascii=False, indent=2))
        print(f"[cast-img] tv: filled {tv_filled} cast photos across {tv_files} series files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
