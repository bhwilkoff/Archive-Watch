#!/usr/bin/env python3
"""
scrub_poster_urls.py — sweep the enrichment table for broken poster
URLs and normalize what's fixable.

Fixes:
  1. http://commons.wikimedia.org → https://commons.wikimedia.org
     (tvOS ATS blocks plain HTTP. ~750 posters in the catalog.)
  2. HEAD-verify every TMDb / Commons / Amazon / Wikipedia / fanart /
     tvmaze URL. Anything that doesn't return HTTP 200 + image/* gets
     replaced with the Archive first-frame thumbnail (the same
     fallback the exporter uses for items with no poster at all).
  3. Skip archive.org/services/img URLs — those are the fallback
     already, always reachable.

Runs in parallel with a bounded worker pool (network is the bottleneck,
not CPU).

Usage:
  python tools/scrub_poster_urls.py              # scrub all
  python tools/scrub_poster_urls.py --dry-run    # report only
  python tools/scrub_poster_urls.py --host tmdb  # just one host
"""

import argparse
import sqlite3
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlparse

import requests

UA = "ArchiveWatch-Scrubber/1.0 (learningischange.com) python-requests"
TIMEOUT = 10

SCRUB_HOSTS = {
    "image.tmdb.org",
    "commons.wikimedia.org",
    "upload.wikimedia.org",
    "m.media-amazon.com",
    "ia.media-imdb.com",
    "en.wikipedia.org",
    "assets.fanart.tv",
    "static.tvmaze.com",
    "s3.amazonaws.com",
}

SKIP_HOSTS = {
    "archive.org",
    "www.archive.org",
}


def normalize(url):
    """Scheme upgrade + trivial fixes. Returns (new_url, changed)."""
    if not url:
        return url, False
    changed = False
    # http://commons.wikimedia.org → https://
    if url.startswith("http://commons.wikimedia.org"):
        url = url.replace("http://", "https://", 1)
        changed = True
    elif url.startswith("http://upload.wikimedia.org"):
        url = url.replace("http://", "https://", 1)
        changed = True
    return url, changed


def verify(url):
    """Returns True if HEAD returns 200 + image/* content-type."""
    try:
        r = requests.head(
            url, allow_redirects=True, timeout=TIMEOUT,
            headers={"User-Agent": UA},
        )
        if r.status_code != 200:
            return False
        ct = r.headers.get("Content-Type", "").lower()
        return ct.startswith("image/")
    except Exception:
        return False


def archive_fallback_for(conn, canonical_id):
    """Return the Archive.org first-frame thumbnail URL for the item's
    source_id, or None if there's no archive_org source."""
    row = conn.execute(
        """SELECT source_id FROM sources
           WHERE canonical_id = ? AND source_type = 'archive_org'
           ORDER BY id ASC LIMIT 1""",
        (canonical_id,),
    ).fetchone()
    if not row:
        return None
    return f"https://archive.org/services/img/{row[0]}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="video_registry.db")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--host", help="only scrub urls with this host substring")
    ap.add_argument("--workers", type=int, default=16)
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)

    rows = conn.execute("""
        SELECT canonical_id, poster_url
        FROM enrichment
        WHERE poster_url IS NOT NULL AND poster_url != ''
    """).fetchall()
    print(f"[scrub] inspecting {len(rows):,} poster URLs", flush=True)

    # Pass 1 — normalize schemes, no network.
    normalized = 0
    to_verify = []
    for cid, url in rows:
        new_url, changed = normalize(url)
        if args.host and args.host not in (urlparse(new_url).hostname or ""):
            continue
        host = urlparse(new_url).hostname or ""
        if host in SKIP_HOSTS:
            continue
        if changed and not args.dry_run:
            conn.execute(
                "UPDATE enrichment SET poster_url = ? WHERE canonical_id = ?",
                (new_url, cid),
            )
            normalized += 1
        if host in SCRUB_HOSTS:
            to_verify.append((cid, new_url))
    if not args.dry_run:
        conn.commit()
    print(f"[scrub] normalized {normalized:,} http→https URLs", flush=True)
    print(f"[scrub] HEAD-verifying {len(to_verify):,} URLs …", flush=True)

    # Pass 2 — HEAD-verify with a thread pool. IO-bound.
    broken = []
    ok = 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(verify, url): (cid, url) for cid, url in to_verify}
        for i, fut in enumerate(as_completed(futures), start=1):
            cid, url = futures[fut]
            try:
                good = fut.result()
            except Exception:
                good = False
            if good:
                ok += 1
            else:
                broken.append((cid, url))
            if i % 500 == 0:
                print(f"  [scrub] {i:,}/{len(to_verify):,}  ok={ok:,} broken={len(broken):,}",
                      flush=True)

    print(f"[scrub] done HEAD-verify: ok={ok:,} broken={len(broken):,}", flush=True)
    if broken[:5]:
        print(f"        samples:")
        for cid, u in broken[:5]:
            print(f"          {cid}  {u[:90]}")

    if args.dry_run:
        print("[scrub] --dry-run, skipping fixes")
        return 0

    # Pass 3 — replace broken URLs with the archive fallback where
    # possible, else NULL them (so the exporter / app cascade treats
    # them as missing and reaches for its own defaults).
    replaced_archive = 0
    nulled = 0
    for cid, _url in broken:
        fallback = archive_fallback_for(conn, cid)
        if fallback:
            conn.execute(
                "UPDATE enrichment SET poster_url = ? WHERE canonical_id = ?",
                (fallback, cid),
            )
            replaced_archive += 1
        else:
            conn.execute(
                "UPDATE enrichment SET poster_url = NULL WHERE canonical_id = ?",
                (cid,),
            )
            nulled += 1
    conn.commit()
    print(f"[scrub] replaced {replaced_archive:,} with archive fallback, "
          f"nulled {nulled:,} with no fallback", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
