#!/usr/bin/env python3
"""
validate_posters.py — verify catalog poster URLs are LIVE and demote dead ones.

WHY: the catalog bakes a posterURL per item from whichever source resolved it
(TMDb, OMDb, Commons, TVDB, fanart, …). Some of those hosts ROT: measured on the
live catalog, ~62% of `omdb` posters (the m.media-amazon.com IMDb image CDN) now
return HTTP 404 because IMDb rotated the image hash, and Commons throttles. A dead
posterURL surfaces as a MISSING POSTER on the homepage — exactly the "a few posters
were missing, which should not happen" the owner reported. The current pipeline had
NO poster liveness check (scrub_poster_urls.py / enrich_artwork.py are orphaned tools
on the retired SQLite plane), so decayed art was never caught.

WHAT: HEAD/GET-verify the poster of every decay-prone item (resumable, concurrent).
  * ALIVE (HTTP 200) -> mark `posterChecked` so re-runs are cheap.
  * DEAD (404/410)   -> fall the posterURL back to the always-available archive.org
                        item thumbnail (`archive.org/services/img/{id}`), set
                        artworkSource="archive" + hasRealArtwork=False (so Home's
                        designed-art gate, build_sqlite, stops LEADING with it — but
                        every surface still shows a real frame, never a blank), and
                        record `posterDead`/`posterDeadURL` as a durable wants-marker
                        for a future re-enrichment / cover pass.
  * TRANSIENT (403/429/5xx/timeout) -> left UNCHANGED and UNMARKED so the next run
                        retries. A throttled Commons 429 is NOT a dead poster — never
                        demote on it (the same "never wrongly hide" discipline as
                        check_liveness.py / audit_rights.py --confirm).

SKIPPED sources (not decay-prone, or already the fallback): `tmdb` (image.tmdb.org —
reliable; huge; skip unless --include-tmdb), `generated` (archive.org/archivewatch-
covers — verified 100% live), `archive`/`none` (already the services/img fallback).

Priority: popularity-first, so the homepage-leading items are validated first.

Run: python tools/validate_posters.py [--limit N] [--workers 16] [--refresh]
                                      [--include-tmdb] [--source omdb] [--dry-run]
Catalog I/O via the local catalog.json (catalog_release.py fetch first in CI).
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import quote

import urllib.request
import urllib.error

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")

# Hosts that rot and are worth re-checking. tmdb is reliable + 12k items, so it is
# off by default (gate behind --include-tmdb). generated/archive/none are skipped.
DECAY_SOURCES = {"omdb", "commons", "wikidata", "external", "fanart", "aapb",
                 "tvdb", "tvmaze"}

DEAD_CODES = {404, 410}                       # definitively gone -> demote
# everything else (403/429/5xx/0) is treated as transient -> retry next run


def archive_thumb(archive_id: str) -> str:
    return f"https://archive.org/services/img/{quote(archive_id, safe='')}"


def check(url: str, timeout: float = 12.0) -> int:
    """Return the HTTP status (a redirect chain is followed); 0 on network error.
    A range GET of the first byte is enough to confirm the object exists without
    downloading the whole image — and works on hosts that reject HEAD."""
    req = urllib.request.Request(url, method="GET", headers={
        "User-Agent": UA, "Range": "bytes=0-0", "Accept": "image/*,*/*"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="cap items checked this run")
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--refresh", action="store_true",
                    help="re-check items already marked posterChecked")
    ap.add_argument("--include-tmdb", action="store_true",
                    help="also verify image.tmdb.org posters (big; reliable)")
    ap.add_argument("--source", default="", help="only this artworkSource")
    ap.add_argument("--dry-run", action="store_true", help="report only; write nothing")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[posters] no catalog.json (run catalog_release.py fetch first)")
        return 1
    cat = json.load(open(CATALOG))
    items = cat["items"]

    sources = set(DECAY_SOURCES)
    if args.include_tmdb:
        sources.add("tmdb")
    if args.source:
        sources = {args.source}

    def needs(it) -> bool:
        if not it.get("posterURL"):
            return False
        if (it.get("artworkSource") or "") not in sources:
            return False
        if it.get("posterChecked") and not args.refresh:
            return False
        return True

    targets = [it for it in items if needs(it)]
    targets.sort(key=lambda it: -(it.get("popularity") or 0))   # homepage-leading first
    if args.limit:
        targets = targets[: args.limit]
    print(f"[posters] {len(targets)} posters to verify "
          f"(sources={sorted(sources)}, total catalog={len(items)})", flush=True)
    if not targets:
        return 0

    lock = threading.Lock()
    stats = {"alive": 0, "dead": 0, "transient": 0, "done": 0}
    t0 = time.time()

    def work(it):
        code = check(it["posterURL"])
        with lock:
            stats["done"] += 1
            if code == 200 or code == 206:
                if not args.dry_run:
                    it["posterChecked"] = True
                stats["alive"] += 1
            elif code in DEAD_CODES:
                stats["dead"] += 1
                if not args.dry_run:
                    it["posterDeadURL"] = it["posterURL"]
                    it["posterDead"] = True
                    it["posterURL"] = archive_thumb(it["archiveID"])
                    it["artworkSource"] = "archive"
                    it["hasRealArtwork"] = False
                    it["posterChecked"] = True
            else:
                stats["transient"] += 1            # leave unchanged + unmarked -> retry
            if stats["done"] % 500 == 0:
                r = stats["done"] / max(1e-6, time.time() - t0)
                print(f"[posters]   {stats['done']}/{len(targets)} "
                      f"(alive={stats['alive']} dead={stats['dead']} "
                      f"transient={stats['transient']}) {r:.0f}/s", flush=True)
            # checkpoint so a crash/timeout is resumable
            if stats["done"] % 2000 == 0 and not args.dry_run:
                tmp = CATALOG.with_suffix(".json.tmp")
                tmp.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
                tmp.replace(CATALOG)

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for _ in as_completed([ex.submit(work, it) for it in targets]):
            pass

    if not args.dry_run:
        tmp = CATALOG.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
        tmp.replace(CATALOG)

    print(f"\n[posters] alive={stats['alive']} dead/demoted={stats['dead']} "
          f"transient(retry)={stats['transient']} "
          f"{'(dry-run, nothing written)' if args.dry_run else '-> wrote catalog.json'}")
    if stats["dead"]:
        print("[posters] demoted dead posters to the Archive thumbnail "
              "(hasRealArtwork=False); re-enrich/cover them via posterDead=True")
    return 0


if __name__ == "__main__":
    sys.exit(main())
