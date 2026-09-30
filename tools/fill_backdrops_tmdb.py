#!/usr/bin/env python3
"""
fill_backdrops_tmdb.py — give a film that already carries a live TMDb match the
professional BACKDROP TMDb holds for it.

WHY: backdrops were only ever written as a side effect of a poster change
(resource_posters_tmdb, enrich_artwork), so a film matched while its poster was
already professional never asked for one. Measured 2026-09-29: 7,909 served
films had a tmdbID and no backdropURL, and TMDb had a backdrop for 18 of a
random 40 — roughly 3,500 heroes and Detail headers left on a fallback.

SAFE, as resource_posters_tmdb is: the match is the stored tmdbID (Decision
026, no title search); the backdrop is refused when the item's year and TMDb's
differ by more than 2 or a B&W film meets a 1970+ release (Decision 025);
a person-named image in image_rejects.json is never set. An item TMDb has no
backdrop for is stamped `tmdbBackdropCheckedAt` and not asked again for
--reprobe-days.

Run: python tools/fill_backdrops_tmdb.py [--limit N] [--dry-run] [--reprobe-days 60]
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import datetime as dt
import json
import sys
import threading
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T                      # noqa: E402
from resource_posters_tmdb import (       # noqa: E402
    CATALOG, SECRETS, FILM_TYPES, load, dump, _now, _item_year, _pop)

REPO = Path(__file__).resolve().parent.parent
MARK = "tmdbBackdropCheckedAt"


def _rejected_urls():
    p = REPO / "shared/editorial/image_rejects.json"
    if not p.exists():
        return {}
    return {k: (v or {}).get("url") for k, v in json.loads(p.read_text()).items()
            if not k.startswith("_")}


def is_target(it):
    return bool(it.get("contentType") in FILM_TYPES and not it.get("excluded")
                and it.get("tmdbID") and not it.get("backdropURL"))


def _recent(it, days):
    ts = it.get(MARK)
    if not ts or days <= 0:
        return False
    try:
        when = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return False
    return (dt.datetime.now(dt.timezone.utc) - when).days < days


def judge(it, rec, rejects):
    """-> (backdrop URL or None, reason)."""
    ty, iy = rec.get("year"), _item_year(it)
    if iy and ty and abs(iy - ty) > 2:
        return None, "year_mismatch"
    if it.get("colorMode") == "bw" and ty and ty >= 1970:
        return None, "bw_modern"
    url = rec.get("backdrop_url")
    if not url:
        return None, "no_backdrop"
    rej = rejects.get(it.get("archiveID"))
    if rej and (rej == url or url.endswith(rej)):
        return None, "rejected"
    return url, "filled"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--reprobe-days", type=int, default=60)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = T.load_tmdb_token(SECRETS)
    if not token:
        print("[backdrops] no TMDB_BEARER_TOKEN — skipping (not an error).")
        return 0
    catalog = load(CATALOG)
    items = catalog["items"] if isinstance(catalog, dict) else catalog
    rejects = _rejected_urls()
    targets = sorted((it for it in items if is_target(it) and not _recent(it, args.reprobe_days)),
                     key=_pop, reverse=True)
    work = targets[:args.limit] if args.limit else targets
    print(f"[backdrops] {len(work)} to attempt ({sum(map(is_target, items))} targets)"
          f"{' DRY-RUN' if args.dry_run else ''}", flush=True)

    tl = threading.local()

    def fetch(it):
        s = getattr(tl, "s", None) or requests.Session()
        tl.s = s
        try:
            return it, T.movie_detail(it["tmdbID"], token, s)
        except RuntimeError:
            return it, "fatal"

    now, stats, examples = _now(), {}, []
    for start in range(0, len(work), 500):
        with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
            results = list(ex.map(fetch, work[start:start + 500]))
        if any(r == "fatal" for _, r in results):
            print("[backdrops] TMDb refused (auth/quota) — stopping", flush=True)
            break
        for it, rec in results:
            url, why = judge(it, rec or {}, rejects) if rec else (None, "no_detail")
            stats[why] = stats.get(why, 0) + 1
            if args.dry_run:
                continue
            it[MARK] = now
            if url:
                it["backdropURL"] = url
                if len(examples) < 10:
                    examples.append((it.get("title"), _item_year(it), url))
        if not args.dry_run:
            dump(CATALOG, catalog)
        print(f"[backdrops] {min(start + 500, len(work))}/{len(work)} · {stats}", flush=True)
    for t, y, u in examples:
        print(f"  • {t!r} ({y}) -> {u}")
    print(f"[backdrops] done: {stats}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
