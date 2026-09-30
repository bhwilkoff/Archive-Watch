#!/usr/bin/env python3
"""
fetch_origin_countries.py — record where a matched film was MADE, for the URAA
rule (remediate `uraa_restored`).

The catalog's `countries` is empty on almost every item, and language alone
misses a British film (The 39 Steps, 1935) whose US copyright URAA restored
just as surely as M's. TMDb's production_countries and original_language, read
by the item's stored tmdbID (Decision 026 — no title search), are cached in
shared/editorial/origin_cache.json {tmdbID: {"c": [ISO codes], "l": lang}} so
the build, which has no network, can read them.

Run: python tools/fetch_origin_countries.py [--limit N] [--workers 6]
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import sys
import threading
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
CACHE = REPO / "shared/editorial/origin_cache.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    a = ap.parse_args()
    token = T.load_tmdb_token(REPO / "Secrets.xcconfig")
    if not token:
        print("[origin] no TMDB_BEARER_TOKEN — skipping (not an error).")
        return 0
    items = json.loads(CATALOG.read_text())["items"]
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    todo = sorted({str(it["tmdbID"]) for it in items
                   if it.get("tmdbID") and not it.get("excluded")} - set(cache))
    if a.limit:
        todo = todo[:a.limit]
    print(f"[origin] {len(todo)} to fetch, {len(cache)} cached", flush=True)
    tl = threading.local()

    def fetch(mid):
        s = getattr(tl, "s", None) or requests.Session()
        tl.s = s
        try:
            r = s.get(f"{T.TMDB_API}/movie/{mid}", headers=T._headers(token), timeout=20)
        except requests.RequestException:
            return mid, None
        if r.status_code == 404:
            return mid, {"c": [], "l": None}
        if not r.ok:
            return mid, None
        d = r.json()
        return mid, {"c": [c.get("iso_3166_1") for c in d.get("production_countries") or [] if c.get("iso_3166_1")],
                     "l": d.get("original_language")}

    done = 0
    with cf.ThreadPoolExecutor(a.workers) as ex:
        for i in range(0, len(todo), 600):
            for mid, rec in ex.map(fetch, todo[i:i + 600]):
                if rec is not None:
                    cache[mid] = rec
                    done += 1
            CACHE.write_text(json.dumps(cache, separators=(",", ":"), sort_keys=True))
            print(f"[origin] {done}/{len(todo)}", flush=True)
    print(f"[origin] fetched {done}, cache now {len(cache)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
