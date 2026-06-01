#!/usr/bin/env python3
"""
enrich_movies.py — the movie analog of the canonical TV builder.

TV gets a canonical spine by resolving each show to TVmaze by title+year.
Movies need the same: ~18k catalog movies are "archiveOnly" — just an
Archive thumbnail + uploader title, no IMDb ID, cast, director, genres,
rating, or runtime. omdb_backfill.py can't help them because it only looks
up items that ALREADY have an IMDb ID.

This tool RESOLVES a movie by title+year (OMDb t=) to recover its IMDb ID
and full metadata (poster, plot, cast, director, genres, rating, votes,
content rating, runtime), then applies it without clobbering existing good
data. Once an item gains an IMDb ID here, omdb_backfill keeps it fresh.

Rate reality: OMDb's free tier is ~1000 req/day, so this is INCREMENTAL —
it enriches a daily batch and catches up over time. For a one-shot bulk
pass, set TMDB_BEARER_TOKEN (TMDb has no daily cap + better artwork); this
tool prefers TMDb when the token is present. See
docs/research/omdb-and-pd-discovery.md.

Idempotent: a per-item cache records hits + misses so we never re-query.

Usage:
    python tools/enrich_movies.py --dry-run
    python tools/enrich_movies.py --max-calls 900
    python tools/enrich_movies.py --max-calls 50   # small sample
"""

import argparse
import datetime as dt
import json
import re
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import omdb_lib as O  # noqa: E402
import tmdb_lib as T  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
CACHE = REPO / "shared" / "editorial" / "movie_enrich_cache.json"
SECRETS = REPO / "Secrets.xcconfig"

SKIP_TYPES = {"tv-series"}   # series handled by the canonical TV pipeline


def load(p):
    return json.loads(p.read_text(encoding="utf-8"))

def dump(p, d):
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)


def clean_movie_title(t):
    """Strip Archive cruft for an OMDb title lookup: parentheticals, brackets,
    trailing year, quality/edition tags, separators."""
    if not t:
        return ""
    s = re.sub(r"\([^)]*\)", " ", t)
    s = re.sub(r"\[[^\]]*\]", " ", s)
    s = re.sub(r"\b(19|20)\d{2}\b", " ", s)
    s = re.sub(r"\b(restored|colou?ri[sz]ed|hd|remastered|full\s*movie|"
               r"public\s+domain|silent|sound\s+version|complete)\b", " ", s, flags=re.I)
    s = re.sub(r"[_]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip(" -:–\"'")
    return s


def needs_enrichment(it):
    if it.get("contentType") in SKIP_TYPES:
        return False
    # Already has an IMDb id -> omdb_backfill's job, not ours.
    if it.get("imdbID"):
        return False
    # Target the thin ones: archiveOnly tier or just a placeholder poster.
    if it.get("enrichmentTier") == "archiveOnly":
        return True
    if (it.get("artworkSource") in (None, "archive")) and not it.get("cast"):
        return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-calls", type=int, default=900,
                    help="OMDb call budget this run (free tier ~1000/day).")
    ap.add_argument("--throttle", type=float, default=0.1)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    tmdb = T.load_tmdb_token(SECRETS)
    key = O.load_omdb_key(SECRETS)
    source = "tmdb" if tmdb else ("omdb" if key else None)
    if not source:
        print("[enrich-movies] no TMDB_BEARER_TOKEN or OMDB_KEY — skipping.")
        return 0
    print(f"[enrich-movies] source = {source.upper()}"
          f"{' (no daily cap, bulk-capable)' if source=='tmdb' else ' (~1000/day cap)'}",
          flush=True)

    full = load(FULL_CATALOG)
    seed = load(SEED_CATALOG)
    seed_by_id = {i["archiveID"]: i for i in seed["items"]}
    cache = load(CACHE) if CACHE.exists() else {}

    candidates = [it for it in full["items"] if needs_enrichment(it)
                  and it["archiveID"] not in cache]
    print(f"[enrich-movies] {len(candidates)} un-tried candidates "
          f"(budget {args.max_calls} calls){' DRY-RUN' if args.dry_run else ''}",
          flush=True)

    session = requests.Session()
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    calls = enriched = hits = 0

    for it in candidates:
        if calls >= args.max_calls:
            break
        q = clean_movie_title(it.get("title"))
        if not q:
            cache[it["archiveID"]] = {"imdb_id": None, "fetched_at": now}
            continue
        calls += 1
        try:
            if source == "tmdb":
                rec = T.resolve(q, it.get("year"), tmdb, session)
            else:
                rec = O.fetch_omdb_full(key, session, title=q, year=it.get("year"))
        except RuntimeError as e:
            print(f"[enrich-movies] stopping: {e} (after {calls} calls)", flush=True)
            break
        time.sleep(args.throttle)
        if not rec or rec.get("omdb_type") == "episode":
            cache[it["archiveID"]] = {"imdb_id": None, "fetched_at": now}
            continue
        hits += 1
        if not args.dry_run:
            def apply_all(target):
                c = O.apply_identity(target, rec) | O.apply_rich(target, rec)
                if rec.get("tmdb_id") and not target.get("tmdbID"):
                    target["tmdbID"] = rec["tmdb_id"]; c = True
                if target.get("imdbID") or target.get("artworkSource") == "tmdb":
                    target["enrichmentTier"] = "fullyEnriched"
                return c
            changed_it = apply_all(it)
            twin = seed_by_id.get(it["archiveID"])   # mirror onto bundled seed
            if twin is not None:
                apply_all(twin)
            if changed_it:
                enriched += 1
        cache[it["archiveID"]] = {"imdb_id": rec.get("imdb_id"),
                                  "tmdb_id": rec.get("tmdb_id"), "fetched_at": now}

    print(f"[enrich-movies] calls={calls} omdb-hits={hits} items-enriched={enriched}",
          flush=True)

    if not args.dry_run:
        dump(FULL_CATALOG, full)
        dump(SEED_CATALOG, seed)
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        dump(CACHE, cache)
        print("[enrich-movies] wrote catalogs + cache")
    return 0


if __name__ == "__main__":
    sys.exit(main())
