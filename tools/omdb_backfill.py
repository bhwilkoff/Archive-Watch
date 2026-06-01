#!/usr/bin/env python3
"""
omdb_backfill.py — daily OMDb enrichment for every IMDb-keyed catalog item.

Originally this only fetched posters for items missing designed art. It now
fetches the full rich record (poster + imdbRating + imdbVotes + content
rating + full plot + runtime) for EVERY IMDb-keyed item, so the app gets
ratings-based ranking and richer Detail screens — see
docs/research/omdb-and-pd-discovery.md.

Stays under the free-tier 1000 req/day (default --max-calls 950). Operates
on the committed catalogs (not the gitignored SQLite), so it runs
unattended in GitHub Actions. Writes:

  - shared/editorial/omdb_cache.json       (rich results, positive + negative)
  - catalog.json                            (full hosted catalog)
  - ArchiveWatch/ArchiveWatch/catalog.json  (bundled seed catalog)

Cache (schema v2): each entry holds poster_url + the rich fields + a
`schema` marker. Entries written by the old poster-only pipeline (schema
< 2, or missing) are re-fetched once to pick up the rich fields, then never
re-fetched again (unless they were a transient error). A `poster_url: null`
v2 entry still means "OMDb has nothing" and is not retried.

Usage:
    python tools/omdb_backfill.py                  # default 950 calls
    python tools/omdb_backfill.py --max-calls 100  # smaller sample
    python tools/omdb_backfill.py --dry-run        # probe counts only
"""

import argparse
import datetime as dt
import json
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import omdb_lib as L  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CACHE_PATH    = REPO / "shared" / "editorial" / "omdb_cache.json"
FULL_CATALOG  = REPO / "catalog.json"
SEED_CATALOG  = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
SECRETS_PATH  = REPO / "Secrets.xcconfig"


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))

def dump_json(path, data):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def needs_fetch(entry):
    """True if this IMDb ID should be (re)fetched.

    - No entry at all                      → fetch.
    - Transient error last time            → retry.
    - Pre-rich entry (schema < 2 / absent) → re-fetch once for rich fields.
    - Rich entry (schema >= 2)             → done; skip (incl. negative).
    """
    if entry is None:
        return True
    if entry.get("error"):
        return True
    return int(entry.get("schema", 1)) < L.CACHE_SCHEMA_VERSION


def collect_queue(catalogs, cache_entries):
    """Every IMDb-ID'd item across both catalogs that needs a (re)fetch.
    Seed-catalog items are prioritized (they ship bundled in the app)."""
    queue = {}
    for is_seed, catalog in catalogs:
        for item in catalog.get("items", []):
            imdb = item.get("imdbID")
            if not imdb:
                continue
            if not needs_fetch(cache_entries.get(imdb)):
                continue
            if imdb not in queue:
                queue[imdb] = {"is_seed": is_seed, "title": item.get("title")}
            elif is_seed:
                queue[imdb]["is_seed"] = True
    return sorted(queue.items(), key=lambda kv: (not kv[1]["is_seed"], kv[0]))


def apply_cache_to_catalog(catalog, cache_entries):
    """Apply every positive cache entry to matching catalog items.
    Returns number of items changed."""
    n = 0
    for item in catalog.get("items", []):
        imdb = item.get("imdbID")
        if not imdb:
            continue
        entry = cache_entries.get(imdb)
        if not entry or entry.get("error"):
            continue
        # Reconstruct a normalized record from the cache entry.
        rec = {
            "poster_url":     entry.get("poster_url"),
            "imdb_rating":    entry.get("imdb_rating"),
            "imdb_votes":     entry.get("imdb_votes"),
            "content_rating": entry.get("content_rating"),
            "plot":           entry.get("plot"),
            "runtime_min":    entry.get("runtime_min"),
        }
        if L.apply_rich(item, rec):
            n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-calls", type=int, default=950,
                    help="Cap OMDb requests this run (free tier 1000/day).")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print queue size only; no HTTP, no writes.")
    ap.add_argument("--throttle", type=float, default=0.15,
                    help="Seconds between calls (default 0.15).")
    args = ap.parse_args()

    cache = load_json(CACHE_PATH)
    cache["schema"] = L.CACHE_SCHEMA_VERSION
    entries = cache.setdefault("entries", {})
    full_catalog = load_json(FULL_CATALOG)
    seed_catalog = load_json(SEED_CATALOG)

    queue = collect_queue([(True, seed_catalog), (False, full_catalog)], entries)
    total = len(queue)
    n_seed = sum(1 for _, v in queue if v["is_seed"])
    print(f"[omdb-backfill] queue: {total:,} items need OMDb fetch "
          f"(seed {n_seed:,} / full {total - n_seed:,})", flush=True)

    if args.dry_run or total == 0:
        # Even on a no-fetch day, re-apply the cache so a schema/field
        # change propagates into the catalogs.
        if not args.dry_run:
            cs = apply_cache_to_catalog(seed_catalog, entries)
            cf = apply_cache_to_catalog(full_catalog, entries)
            if cs or cf:
                dump_json(SEED_CATALOG, seed_catalog)
                dump_json(FULL_CATALOG, full_catalog)
                print(f"[omdb-backfill] no fetches; re-applied cache: "
                      f"+{cs} seed +{cf} full", flush=True)
        return 0

    api_key = L.load_omdb_key(SECRETS_PATH)
    if not api_key:
        print("[omdb-backfill] OMDB_KEY not set — cannot run", file=sys.stderr)
        return 1

    session = requests.Session()
    got = miss = errored = 0
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

    for i, (imdb, meta) in enumerate(queue[:args.max_calls], start=1):
        try:
            rec = L.fetch_omdb(imdb, api_key, session)
        except RuntimeError as e:
            msg = str(e)
            if "quota" in msg.lower():
                print(f"[omdb-backfill] stopping early: {msg}", flush=True)
                break
            # Transient — mark error, retry next run.
            prev = entries.get(imdb) or {}
            prev.update({"error": msg, "last_tried": now})
            entries[imdb] = prev
            errored += 1
            time.sleep(args.throttle)
            continue

        entries[imdb] = L.cache_record(rec, now)
        if rec and rec.get("poster_url"):
            got += 1
        else:
            miss += 1

        if i % 100 == 0:
            print(f"  [omdb-backfill] {got:,} hit, {miss:,} miss, {errored:,} err "
                  f"({i:,}/{min(total, args.max_calls):,})", flush=True)
        time.sleep(args.throttle)

    cache["updated_at"] = now

    changed_seed = apply_cache_to_catalog(seed_catalog, entries)
    changed_full = apply_cache_to_catalog(full_catalog, entries)

    dump_json(CACHE_PATH, cache)
    dump_json(SEED_CATALOG, seed_catalog)
    dump_json(FULL_CATALOG, full_catalog)

    print(f"[omdb-backfill] done: {got:,} hit, {miss:,} miss, {errored:,} err", flush=True)
    print(f"                catalogs: +{changed_seed} seed  +{changed_full} full", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
