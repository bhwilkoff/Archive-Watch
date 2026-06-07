#!/usr/bin/env python3
"""
enrich_tvdb_movies.py — professional movie posters from TheTVDB for items that
lack real designed art (the titles the frame-capture "vision" pipeline targeted).

For each catalog movie with no professional poster, search TheTVDB /movies by
title+year and adopt the matched poster (artworkSource -> "tvdb"). A REAL poster
always beats a frame capture, so this runs BEFORE apply_covers (which only fills
items still missing art). Never overwrites an existing tmdb/omdb/commons/fanart
poster. Conservative year+title match so we don't paste the wrong film's art.

Targets film-like content TheTVDB actually carries (feature/silent/animation/
documentary/short) — not commercials/ephemera/newsreels/home-movies.

Catalog lives on the release (Decision 018): fetch -> this -> publish.
Run: python tools/enrich_tvdb_movies.py [--limit N]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tvdb_lib as TV

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
CACHE = Path(__file__).resolve().parent / "tvdb_movie_cache.json"
TARGET_TYPES = {"feature-film", "silent-film", "animation", "documentary", "short-film"}
KEEP_SOURCES = {"tmdb", "omdb", "commons", "fanart", "wikidata", "loc"}


def norm(s: str) -> str:
    s = re.sub(r"\(\d{4}\)", " ", s or "")
    s = re.sub(r"[^a-z0-9 ]", " ", s.lower())
    s = re.sub(r"\b(the|a|an)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def needs(it: dict) -> bool:
    if it.get("contentType") not in TARGET_TYPES:
        return False
    if it.get("artworkSource") in KEEP_SOURCES and it.get("posterURL"):
        return False
    return True


def best_match(results: list, title: str, year):
    nt = norm(title)
    best, bs = None, -1.0
    for r in results:
        if r.get("type") not in (None, "movie"):
            continue
        rn = norm(r.get("name") or "")
        try:
            ry = int(str(r.get("year"))[:4])
        except (TypeError, ValueError):
            ry = None
        a, b = set(nt.split()), set(rn.split())
        overlap = len(a & b) / max(len(a | b), 1)
        year_ok = (year is None or ry is None or abs(ry - year) <= 1)
        exact = rn == nt and (year is None or ry is None or ry == year)
        if not (exact or (overlap >= 0.7 and year_ok)):
            continue
        img = r.get("image_url") or r.get("thumbnail")
        if not img or "images/missing/" in img:
            continue
        score = overlap + (1 if (year and ry == year) else 0) + (0.5 if exact else 0)
        if score > bs:
            bs, best = score, img
    return best


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    if not CATALOG.exists():
        print("[tvdb-mov] no catalog.json (fetch first)"); return 2
    key = TV.load_key(REPO / "Secrets.xcconfig")
    if not key:
        print("[tvdb-mov] no THETVDB_API_KEY"); return 0
    token = TV.login(key)
    if not token:
        print("[tvdb-mov] login failed"); return 1

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    targets = [it for it in items if needs(it)]
    if args.limit:
        targets = targets[:args.limit]
    print(f"[tvdb-mov] {len(targets)} movies lack a professional poster")

    filled = looked = 0
    for i, it in enumerate(targets, 1):
        ckey = f"{(it.get('title') or '').lower()}|{it.get('year') or ''}"
        if ckey in cache:
            poster = cache[ckey]
        else:
            looked += 1
            results = TV.search(token, it.get("title") or "", "movie", it.get("year"))
            poster = best_match(results, it.get("title") or "", it.get("year")) or ""
            cache[ckey] = poster
            time.sleep(0.25)
        if poster:
            it["posterURL"] = poster
            it["artworkSource"] = "tvdb"
            it["hasRealArtwork"] = True
            filled += 1
        if i % 100 == 0 or i == len(targets):
            CACHE.write_text(json.dumps(cache))
            print(f"[{i:>5}/{len(targets)}] looked {looked} | filled {filled}")
    CACHE.write_text(json.dumps(cache))

    tmp = CATALOG.with_suffix(".json.tmp")
    json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
    tmp.replace(CATALOG)
    print(f"[tvdb-mov] done: {filled} movie posters from TheTVDB -> {CATALOG.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
