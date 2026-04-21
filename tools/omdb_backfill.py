#!/usr/bin/env python3
"""
omdb_backfill.py — one daily pass of OMDb lookups for catalog items
missing designed artwork, staying under the free-tier 1000 req/day.

Operates on the committed catalogs (not the 240 MB gitignored SQLite),
so it can run unattended in GitHub Actions. Writes three files:

  - shared/editorial/omdb_cache.json       (positive + negative results)
  - docs/catalog.json                       (full hosted catalog)
  - ArchiveWatch/ArchiveWatch/catalog.json  (bundled seed catalog)

Cache semantics:
  - `poster_url: "https://..."` → OMDb had art; apply it.
  - `poster_url: null`          → OMDb said no; don't retry tomorrow.
  - `error: "message"`          → transient HTTP failure; will retry
                                   next run.

Daily budget:
  The OMDb free tier is 1000 req/day. We default to `--max-calls 950`
  so GitHub Actions can't accidentally tip over the limit (safer margin
  since CI clocks may drift relative to OMDb's rollover).

Usage:
    python tools/omdb_backfill.py                     # default 950 calls
    python tools/omdb_backfill.py --max-calls 100     # smaller sample
    python tools/omdb_backfill.py --dry-run           # probe counts only
"""

import argparse
import datetime as dt
import json
import os
import sys
import time
from pathlib import Path

import requests

REPO = Path(__file__).resolve().parent.parent
CACHE_PATH    = REPO / "shared" / "editorial" / "omdb_cache.json"
FULL_CATALOG  = REPO / "docs" / "catalog.json"
SEED_CATALOG  = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
SECRETS_PATH  = REPO / "Secrets.xcconfig"

OMDB_API = "https://www.omdbapi.com/"
USER_AGENT = "ArchiveWatch-OMDb-Backfill/1.0 (learningischange.com) python-requests"
DESIGNED_SOURCES = {"tmdb", "fanart", "omdb", "commons", "wikidata", "aapb"}


# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

def load_omdb_key():
    """GH Actions secret → local env → Secrets.xcconfig."""
    v = os.environ.get("OMDB_KEY")
    if v:
        return v.strip()
    if SECRETS_PATH.exists():
        for line in SECRETS_PATH.read_text().splitlines():
            if line.strip().startswith("OMDB_KEY"):
                _, _, rhs = line.partition("=")
                return rhs.strip()
    return None


# ---------------------------------------------------------------------------
# JSON I/O
# ---------------------------------------------------------------------------

def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))

def dump_json(path, data):
    # Match the exporter's formatting: compact but readable. Stable key order
    # so diffs in git remain small.
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


# ---------------------------------------------------------------------------
# OMDb
# ---------------------------------------------------------------------------

def omdb_lookup(imdb_id, api_key, session):
    """Returns poster URL on hit, None on "no poster", or raises on transient."""
    r = session.get(
        OMDB_API,
        params={"i": imdb_id, "apikey": api_key},
        headers={"User-Agent": USER_AGENT},
        timeout=20,
    )
    # 401 = daily quota exhausted. Bubble up so the caller can stop early.
    if r.status_code == 401:
        raise RuntimeError("OMDb daily quota exhausted (HTTP 401)")
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}")
    d = r.json()
    if str(d.get("Response", "")).lower() != "true":
        # Legitimate "not found" — negative cache.
        return None
    p = d.get("Poster")
    if p and p != "N/A":
        return p
    return None


# ---------------------------------------------------------------------------
# Queue builder
# ---------------------------------------------------------------------------

def collect_queue(catalogs, cache_entries):
    """Union of every IMDb-ID'd item across both catalogs that (a) isn't
    currently showing designed art, and (b) isn't already in the cache.
    Seed catalog items are prioritized (they ship bundled)."""
    # Use an ordered dict — Python preserves insertion order, so seed items
    # inserted first are processed first.
    queue = {}
    for is_seed, catalog in catalogs:
        for item in catalog.get("items", []):
            imdb = item.get("imdbID")
            if not imdb:
                continue
            if imdb in cache_entries:
                continue
            src = item.get("artworkSource")
            if src in DESIGNED_SOURCES:
                continue
            if imdb not in queue:
                queue[imdb] = {"is_seed": is_seed, "title": item.get("title")}
            elif is_seed:
                queue[imdb]["is_seed"] = True
    # Sort: seed items first.
    return sorted(queue.items(), key=lambda kv: (not kv[1]["is_seed"], kv[0]))


# ---------------------------------------------------------------------------
# Catalog mutation
# ---------------------------------------------------------------------------

def apply_to_catalog(catalog, poster_by_imdb):
    """Walk the catalog; for each item whose imdbID now has a poster in the
    cache, overwrite poster+source+hasRealArtwork. Returns number changed."""
    n = 0
    for item in catalog.get("items", []):
        imdb = item.get("imdbID")
        if not imdb:
            continue
        poster = poster_by_imdb.get(imdb)
        if not poster:
            continue
        # Only upgrade placeholders — never overwrite already-designed art.
        if item.get("artworkSource") in DESIGNED_SOURCES:
            continue
        item["posterURL"]       = poster
        item["artworkSource"]   = "omdb"
        item["hasRealArtwork"]  = True
        n += 1
    return n


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-calls", type=int, default=950,
                    help="Cap OMDb requests this run (OMDb free tier is 1000/day; "
                         "default 950 leaves headroom).")
    ap.add_argument("--dry-run", action="store_true",
                    help="Only print queue size; no HTTP, no writes.")
    ap.add_argument("--throttle", type=float, default=0.15,
                    help="Seconds to sleep between calls (default 0.15).")
    args = ap.parse_args()

    # Load state
    cache = load_json(CACHE_PATH)
    entries = cache.setdefault("entries", {})
    full_catalog = load_json(FULL_CATALOG)
    seed_catalog = load_json(SEED_CATALOG)

    queue = collect_queue([(True, seed_catalog), (False, full_catalog)], entries)
    total = len(queue)
    print(f"[omdb-backfill] queue: {total:,} items need OMDb lookup "
          f"(seed {sum(1 for _, v in queue if v['is_seed']):,} / "
          f"full {sum(1 for _, v in queue if not v['is_seed']):,})", flush=True)

    if args.dry_run or total == 0:
        return 0

    api_key = load_omdb_key()
    if not api_key:
        print("[omdb-backfill] OMDB_KEY not set — cannot run", file=sys.stderr)
        return 1

    session = requests.Session()
    got = miss = errored = 0
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

    for i, (imdb, meta) in enumerate(queue[:args.max_calls], start=1):
        try:
            poster = omdb_lookup(imdb, api_key, session)
        except RuntimeError as e:
            msg = str(e)
            if "quota" in msg.lower():
                print(f"[omdb-backfill] stopping early: {msg}", flush=True)
                break
            # Transient — don't negative-cache. Skip; will retry tomorrow.
            entries_before = entries.get(imdb)
            if entries_before:
                entries_before["error"] = msg
                entries_before["last_tried"] = now
            else:
                entries[imdb] = {"error": msg, "last_tried": now}
            errored += 1
            if i % 50 == 0:
                print(f"  [omdb-backfill] err {errored:,} at {i}/{args.max_calls}  "
                      f"({miss:,} miss, {got:,} hit)", flush=True)
            time.sleep(args.throttle)
            continue

        if poster:
            entries[imdb] = {"poster_url": poster, "fetched_at": now}
            got += 1
        else:
            entries[imdb] = {"poster_url": None, "fetched_at": now}
            miss += 1

        if i % 100 == 0:
            print(f"  [omdb-backfill] {got:,} hit, {miss:,} miss, {errored:,} err  "
                  f"({i:,}/{min(total, args.max_calls):,})", flush=True)
        time.sleep(args.throttle)

    cache["updated_at"] = now

    # Build the imdb → poster lookup (only positive entries) and apply.
    poster_by_imdb = {k: v.get("poster_url")
                      for k, v in entries.items()
                      if v.get("poster_url")}

    changed_full = apply_to_catalog(full_catalog, poster_by_imdb)
    changed_seed = apply_to_catalog(seed_catalog, poster_by_imdb)

    dump_json(CACHE_PATH, cache)
    dump_json(FULL_CATALOG, full_catalog)
    dump_json(SEED_CATALOG, seed_catalog)

    print(f"[omdb-backfill] done: {got:,} hit, {miss:,} miss, {errored:,} err", flush=True)
    print(f"                catalogs: +{changed_seed} seed  +{changed_full} full", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
