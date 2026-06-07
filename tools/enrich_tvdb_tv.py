#!/usr/bin/env python3
"""
enrich_tvdb_tv.py — upgrade TV series with professional posters + overviews +
cast from TheTVDB (api4). TheTVDB has true poster art (not stills) and reaches
obscure PD shows. Per series/*.json: match by title+year, then fill —
  - posterURL: replace tvmaze/archive/none with the top-scored TheTVDB poster
    (artworkSource -> "tvdb"); never overwrites an existing tmdb poster.
  - overview: fill if missing.
  - cast: fill if missing (TheTVDB characters; keeps existing TVmaze cast).
  - tvdbID: recorded for reuse.

Conservative matching: requires a year match (±2) when we know the year, or an
exact normalized-title match otherwise — so we never paste the wrong show's art.

Run: python tools/enrich_tvdb_tv.py [--refresh] [--limit N]
"""

from __future__ import annotations

import argparse
import glob
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tvdb_lib as TV

REPO = Path(__file__).resolve().parent.parent
SERIES = REPO / "series"


def norm(s: str) -> str:
    s = re.sub(r"\(\d{4}\)", " ", s or "")
    s = re.sub(r"[^a-z0-9 ]", " ", s.lower())
    s = re.sub(r"\b(the|a|an)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def pick(results: list, title: str, year: int | None):
    nt = norm(title)
    best, best_score = None, -1.0
    for r in results:
        if r.get("type") not in (None, "series"):
            continue
        rn = norm(r.get("name") or "")
        ry = None
        try:
            ry = int(str(r.get("year"))[:4])
        except (TypeError, ValueError):
            pass
        # name overlap
        a, b = set(nt.split()), set(rn.split())
        overlap = len(a & b) / max(len(a | b), 1)
        year_ok = (year is None or ry is None or abs(ry - year) <= 2)
        exact = rn == nt
        if not (exact or (overlap >= 0.6 and year_ok)):
            continue
        score = overlap + (1.0 if (year and ry and ry == year) else 0) + (0.5 if exact else 0)
        if score > best_score:
            best_score, best = score, r
    return best


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    key = TV.load_key(REPO / "Secrets.xcconfig")
    if not key:
        print("[tvdb] no THETVDB_API_KEY"); return 0
    token = TV.login(key)
    if not token:
        print("[tvdb] login failed"); return 1

    files = sorted(glob.glob(str(SERIES / "*.json")))
    if args.limit:
        files = files[:args.limit]

    up_poster = up_over = up_cast = matched = 0
    for i, f in enumerate(files, 1):
        d = json.load(open(f))
        # skip fully-enriched-by-tvdb unless refreshing
        if not args.refresh and d.get("tvdbID") and d.get("artworkSource") == "tvdb" \
           and d.get("overview") and d.get("cast"):
            continue
        results = TV.search(token, d.get("title") or "", "series", d.get("yearStart"))
        m = pick(results, d.get("title") or "", d.get("yearStart"))
        if not m:
            time.sleep(0.2); continue
        matched += 1
        tvdb_id = m.get("tvdb_id") or m.get("id", "").replace("series-", "")
        ext = TV.series_extended(token, tvdb_id)
        if not ext:
            time.sleep(0.2); continue
        changed = False
        d["tvdbID"] = tvdb_id
        # poster: upgrade non-professional (never clobber tmdb)
        poster = TV.best_poster(ext)
        if poster and d.get("artworkSource") != "tmdb" and \
           (args.refresh or d.get("artworkSource") in (None, "tvmaze", "archive", "")):
            if d.get("posterURL") != poster:
                d["posterURL"] = poster; d["artworkSource"] = "tvdb"; up_poster += 1; changed = True
        if (args.refresh or not (d.get("overview") or "").strip()) and (ext.get("overview") or "").strip():
            d["overview"] = ext["overview"]; up_over += 1; changed = True
        if not d.get("cast"):
            cast = TV.cast_from(ext)
            if cast:
                d["cast"] = cast; up_cast += 1; changed = True
        if changed:
            Path(f).write_text(json.dumps(d, ensure_ascii=False, indent=2))
        if i % 25 == 0 or i == len(files):
            print(f"[{i:>4}/{len(files)}] matched {matched} | +poster {up_poster} "
                  f"+overview {up_over} +cast {up_cast}")
        time.sleep(0.25)
    print(f"[tvdb] done: matched {matched} | +{up_poster} posters, +{up_over} overviews, +{up_cast} cast")
    return 0


if __name__ == "__main__":
    sys.exit(main())
