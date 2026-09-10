#!/usr/bin/env python3
"""
measure_image_dims.py — record the pixel size of every image the Roku Search
feed would publish, so the feed can refuse the ones Roku will refuse.

WHY. Roku's Search feed validator downloads every image and rejects a main
poster whose aspect is not 2:3 or 16:9 — IMAGE_INVALID_MAIN, 907 assets in
the first live run. Sampled and measured: OMDb posters at 300x229, 300x300
and 300x400, TMDb posters at 500x663..707, Commons stills at 997x678. The
spec's "4:3, 3:4, 1:1 are also supported" is not what the validator does; a
300x400 (exactly 3:4) and a 300x300 (exactly 1:1) were both refused. Nothing
in the catalog records an image's size, so a feed cannot know which posters
will be thrown out — this tool is that record.

WHAT. `ops/image-dims.json`: url -> [width, height], or 0 for a URL that is
definitively gone (404/410). A range GET of the first 64 KB is enough for
PIL to read a JPEG/PNG/GIF header; a header that needs more falls back to a
bounded full read. Transient failures (429, 5xx, timeouts) leave the URL
UNRECORDED so it is asked again next run — Decision 088's rule, because a
throttle recorded as a verdict is a wrong verdict forever.

Resumable and budgeted: --limit caps the URLs measured per run; the cache is
committed by publish-db beside the web index, and the feed reads it at deploy
time. Anything unmeasured ships as-is (Roku will judge it), so the feed never
waits on this tool — it only gets truer as the cache fills.

Run:
  python tools/catalog_release.py fetch
  python tools/measure_image_dims.py --limit 4000
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import io
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import build_roku_search_feed as F  # noqa: E402

CACHE = REPO / "ops" / "image-dims.json"
DEAD_CODES = {404, 410}
HEADER_BYTES = 65535
FULL_CAP = 4 * 1024 * 1024


def load_cache() -> dict:
    if CACHE.exists():
        return json.loads(CACHE.read_text(encoding="utf-8"))
    return {}


def save_cache(cache: dict) -> None:
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cache, sort_keys=True, separators=(",", ":")),
                   encoding="utf-8")
    tmp.replace(CACHE)


def _size_of(data: bytes):
    from PIL import Image
    im = Image.open(io.BytesIO(data))
    return list(im.size)


def measure(url: str, timeout: float = 15.0):
    """Return [w, h], 0 (dead), or None (transient: ask again next run)."""
    headers = {"User-Agent": F.USER_AGENT, "Accept": "image/*,*/*"}
    for attempt, rng in enumerate((f"bytes=0-{HEADER_BYTES}", None)):
        h = dict(headers)
        if rng:
            h["Range"] = rng
        req = urllib.request.Request(url, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read(FULL_CAP)
        except urllib.error.HTTPError as e:
            if e.code in DEAD_CODES:
                return 0
            if e.code == 429:
                try:
                    time.sleep(min(float(e.headers.get("Retry-After") or 2), 15.0))
                except (TypeError, ValueError):
                    time.sleep(2)
            return None
        except Exception:  # noqa: BLE001
            return None
        try:
            return _size_of(data)
        except Exception:  # noqa: BLE001
            if attempt == 1:
                return None
    return None


def candidate_urls(catalog: dict, index_ids: set, tier: str, resolver) -> list:
    """Every image the feed would publish, non-generated first — the sources
    whose aspect is arbitrary are the ones worth measuring soonest."""
    urls, seen = [], set()
    rank = {"tmdb": 2, "generated": 3}
    rows = []
    for it in catalog.get("items", []):
        if F.eligibility(it, index_ids, tier):
            continue
        main = resolver.resolve(F.image_url(it.get("posterURL")))
        bg = resolver.resolve(F.image_url(it.get("backdropURL"), "background"))
        pri = rank.get(it.get("artworkSource") or "", 1)
        for u in (main, bg):
            if u and u not in seen:
                seen.add(u)
                rows.append((pri, u))
    rows.sort(key=lambda r: r[0])
    return [u for _, u in rows]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=str(REPO / "catalog.json"))
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--tier", choices=("catalog", "strict"), default="catalog")
    ap.add_argument("--limit", type=int, default=4000)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--remeasure", action="store_true",
                    help="measure cached URLs again as well")
    args = ap.parse_args()

    cat_path = Path(args.catalog)
    if not cat_path.exists():
        print("[dims] no catalog.json — run tools/catalog_release.py fetch first",
              file=sys.stderr)
        return 1
    catalog = json.loads(cat_path.read_text(encoding="utf-8"))
    index_ids = {r[0] for r in json.loads(Path(args.index).read_text(encoding="utf-8"))["items"]}
    resolver = F.ImageResolver(network=True)
    eligible = [it for it in catalog.get("items", []) if not F.eligibility(it, index_ids, args.tier)]
    resolver.prefetch_commons([F.image_url(it.get("posterURL")) or "" for it in eligible])

    cache = load_cache()
    urls = candidate_urls(catalog, index_ids, args.tier, resolver)
    # Generated covers are 600x900 by construction and TMDb backdrops are
    # 16:9 by TMDb's own rule; measuring them is spend without information.
    urls = [u for u in urls if "/items/archivewatch-covers/" not in u
            and not ("image.tmdb.org" in u and "/w1280/" in u)]
    todo = [u for u in urls if args.remeasure or u not in cache][:args.limit]
    print(f"[dims] cache {len(cache)} · candidates {len(urls)} · measuring {len(todo)}",
          flush=True)

    counts = {"sized": 0, "dead": 0, "transient": 0}
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        for i, (u, res) in enumerate(zip(todo, ex.map(measure, todo)), 1):
            if res is None:
                counts["transient"] += 1
            else:
                cache[u] = res
                counts["dead" if res == 0 else "sized"] += 1
            if i % 500 == 0:
                save_cache(cache)
                print(f"[dims] {i}/{len(todo)} {counts} {time.time() - t0:.0f}s", flush=True)
    save_cache(cache)
    print(f"[dims] done: {counts} · cache now {len(cache)} · {time.time() - t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
