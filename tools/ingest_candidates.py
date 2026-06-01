#!/usr/bin/env python3
"""
ingest_candidates.py — turn discovered PD candidates into catalog items.

Drains shared/editorial/discovery_candidates.json (produced by
tools/discover_wikidata_pd.py) a daily-capped batch at a time. For each
candidate it:

  1. Fetches live Archive metadata for the candidate's Internet Archive ID
     and picks the best playable video derivative. (Many Wikidata IA IDs
     are stale/renamed/darkened — those are marked status="no_video" and
     skipped, never retried.)
  2. Builds a normalized catalog item (same schema the JS builder emits),
     classifying content type from collections/subjects/runtime.
  3. Enriches via OMDb (poster + rich fields) when the candidate has an
     IMDb ID, using the shared tools/omdb_lib.py.
  4. Appends it to BOTH catalogs (full + bundled seed) and marks the
     candidate status="ingested".

Idempotent: an already-ingested archiveID is never added twice. Rights:
only candidates with rightsConfidence=="high" are ingested by default
(genuinely PD by flag or age) — low-confidence ones (incidental recent
uploads) are left in the queue unless --include-low-confidence.

Usage:
    python tools/ingest_candidates.py --max-items 40
    python tools/ingest_candidates.py --max-items 5 --dry-run
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
import omdb_lib as L  # noqa: E402
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
CANDIDATES   = REPO / "shared" / "editorial" / "discovery_candidates.json"
CACHE_PATH   = REPO / "shared" / "editorial" / "omdb_cache.json"
SECRETS_PATH = REPO / "Secrets.xcconfig"

ARCHIVE_DL = A.ARCHIVE_DL

# Archive helpers now live in archive_lib (shared with backfill_tv_episodes).
archive_meta = A.archive_meta
pick_video = A.pick_video


def load_json(p):
    return json.loads(p.read_text(encoding="utf-8"))

def dump_json(p, data):
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)


def classify(collections, subjects, runtime_sec, year):
    """Lightweight content-type classifier. Mirrors the JS builder's
    heuristics closely enough for discovery items; the weekly rebuild can
    refine later."""
    cl = " ".join(collections).lower()
    subj = " ".join(subjects).lower()
    if "tv" in cl or "television" in cl or "classic_tv" in cl:
        return "tv-series" if "series" in cl else "tv-special"
    if "animation" in cl or "cartoon" in cl or "animation" in subj:
        return "animation"
    if "newsreel" in cl or "news" in cl:
        return "newsreel"
    if "prelinger" in cl or "ephemeral" in cl or "advertising" in subj:
        return "ephemeral"
    if year and year < 1928:
        return "silent-film"
    if runtime_sec and runtime_sec < 2400:  # < 40 min
        return "short-film"
    if "documentary" in cl or "documentary" in subj:
        return "documentary"
    return "feature-film"


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def build_item(cand, meta, session, omdb_key, omdb_cache, now):
    """Construct a catalog item from Archive metadata + candidate, enriched
    via OMDb. Returns (item, reason) — item is None with a reason string
    when the candidate can't be ingested."""
    md = meta.get("metadata", {})
    files = meta.get("files", [])
    iaid = cand["iaid"]

    if md.get("mediatype") not in (None, "movies", "video"):
        return None, "not_video_mediatype"

    vf = pick_video(files)
    if not vf:
        return None, "no_video"

    collections = [c.lower() for c in as_list(md.get("collection"))]
    if A.is_adult(collections):
        return None, "adult_collection"

    subjects = as_list(md.get("subject"))
    title = md.get("title") or cand.get("title") or iaid

    # Year: prefer Archive, fall back to candidate's Wikidata year.
    year = None
    for src in (md.get("year"), md.get("date"), cand.get("year")):
        if src:
            m = re.search(r"(\d{4})", str(src))
            if m:
                year = int(m.group(1))
                break

    runtime_sec = None
    rt = vf.get("length")  # "HH:MM:SS" or seconds
    if rt:
        parts = str(rt).split(":")
        try:
            if len(parts) == 3:
                runtime_sec = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(float(parts[2]))
            elif len(parts) == 2:
                runtime_sec = int(parts[0]) * 60 + int(float(parts[1]))
            else:
                runtime_sec = int(float(parts[0]))
        except ValueError:
            runtime_sec = None

    download_url = A.download_url(iaid, vf["name"])

    item = {
        "archiveID": iaid,
        "title": title,
        "year": year,
        "decade": (year // 10 * 10) if year else None,
        "runtimeSeconds": runtime_sec,
        "synopsis": (md.get("description") or None),
        "collections": as_list(md.get("collection")),
        "subjects": subjects[:25] if isinstance(subjects, list) else [],
        "mediatype": md.get("mediatype") or "movies",
        "language": (as_list(md.get("language")) or [None])[0],
        "imdbID": cand.get("imdbID"),
        "tmdbID": None,
        "wikidataQID": cand.get("wikidataQID"),
        "tvmazeID": None,
        "videoFile": {
            "name": vf["name"],
            "format": vf.get("format") or "",
            "sizeBytes": int(vf.get("size") or 0),
            "tier": 1,
        },
        "downloadURL": download_url,
        "posterURL": "https://archive.org/services/img/" + iaid,
        "backdropURL": None,
        "hasRealArtwork": False,
        "artworkSource": "archive",
        "contentType": classify(collections, subjects, runtime_sec, year),
        "genres": [],
        "countries": as_list(md.get("country")),
        "cast": [],
        "director": (as_list(md.get("director")) or [None])[0],
        "producer": (as_list(md.get("producer")) or [None])[0],
        "seriesName": None,
        "network": None,
        "enrichmentTier": "archiveOnly",
        "shelves": [],
        "rightsStatus": "public_domain" if cand.get("rightsConfidence") == "high" else "unknown",
        "qualityScore": None,
        "popularityScore": None,
        "bestSourceType": "archive_org",
        "isSilentFilm": (year is not None and year < 1928),
        "discoverySource": "wikidata",
    }

    # OMDb enrichment (poster + rich fields) when we have an IMDb ID.
    imdb = cand.get("imdbID")
    if imdb and omdb_key:
        entry = omdb_cache["entries"].get(imdb)
        rec = None
        if entry and not entry.get("error") and int(entry.get("schema", 1)) >= L.CACHE_SCHEMA_VERSION:
            rec = {k: entry.get(k) for k in
                   ("poster_url", "imdb_rating", "imdb_votes", "content_rating", "plot", "runtime_min")}
        else:
            try:
                rec = L.fetch_omdb(imdb, omdb_key, session)
                omdb_cache["entries"][imdb] = L.cache_record(rec, now)
            except RuntimeError:
                rec = None
        if rec:
            L.apply_rich(item, rec)
            if item.get("hasRealArtwork"):
                item["enrichmentTier"] = "identifierResolved"

    return item, "ok"


def existing_archive_ids(*catalogs):
    s = set()
    for cat in catalogs:
        for it in cat.get("items", []):
            aid = it.get("archiveID")
            if aid:
                s.add(aid)
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-items", type=int, default=40,
                    help="Max candidates to ingest this run (default 40).")
    ap.add_argument("--include-low-confidence", action="store_true",
                    help="Also ingest rightsConfidence=='low' candidates.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Resolve + classify but don't write catalogs.")
    ap.add_argument("--throttle", type=float, default=0.3,
                    help="Seconds between Archive fetches (default 0.3).")
    ap.add_argument("--resolve-limit", type=int, default=120,
                    help="Max high-confidence candidates WITHOUT an Archive id "
                         "to resolve by title+year this run (default 120). "
                         "0 disables the resolver.")
    args = ap.parse_args()

    if not CANDIDATES.exists():
        print("[ingest] no candidates file — run discover_wikidata_pd.py first", file=sys.stderr)
        return 1

    cand_doc = load_json(CANDIDATES)
    candidates = cand_doc.get("candidates", [])
    full_catalog = load_json(FULL_CATALOG)
    seed_catalog = load_json(SEED_CATALOG)
    omdb_cache = load_json(CACHE_PATH)
    omdb_cache.setdefault("entries", {})
    omdb_key = L.load_omdb_key(SECRETS_PATH)

    have = existing_archive_ids(full_catalog, seed_catalog)
    session = requests.Session()
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

    # ── Resolver pass ──────────────────────────────────────────────────
    # High-confidence PD candidates with NO Archive id (the ~6,800 that
    # Wikidata flags PD but lacks a P724) get matched to a playable Archive
    # item by title+year. This is the big unlock — without it those films
    # are undiscoverable. Each candidate is resolved at most once: success
    # stamps `iaid` + resolvedVia="title"; a miss marks status="unresolved"
    # so we don't re-search it every day.
    if args.resolve_limit:
        unresolved = [c for c in candidates
                      if c.get("status") == "new" and not c.get("iaid")
                      and c.get("title")
                      and (args.include_low_confidence or c.get("rightsConfidence") == "high")]
        # Prefer older (more likely genuinely PD) titles first.
        unresolved.sort(key=lambda c: (c.get("year") or 9999))
        resolved_n = miss_n = 0
        for cand in unresolved[:args.resolve_limit]:
            try:
                iaid, score, doc = A.resolve_title(cand["title"], cand.get("year"), session)
            except Exception:  # noqa: BLE001
                iaid = None
            if iaid and iaid not in have:
                cand["iaid"] = iaid
                cand["resolvedVia"] = "title"
                cand["resolveScore"] = score
                resolved_n += 1
            else:
                cand["status"] = "unresolved"
                miss_n += 1
            time.sleep(args.throttle)
        print(f"[ingest] title-resolver: matched {resolved_n} / "
              f"{min(len(unresolved), args.resolve_limit)} "
              f"({miss_n} no Archive match)", flush=True)

    # Pick the queue: status "new", now has an IA id (native or resolved),
    # right confidence.
    workable = [c for c in candidates
                if c.get("status") == "new" and c.get("iaid")
                and (args.include_low_confidence or c.get("rightsConfidence") == "high")]
    print(f"[ingest] {len(workable):,} workable candidates (status=new, has IA id, "
          f"{'any' if args.include_low_confidence else 'high'} confidence)", flush=True)

    ingested = no_video = skipped = errored = 0
    new_items = []

    for cand in workable[:args.max_items]:
        iaid = cand["iaid"]
        if iaid in have or iaid.rsplit(".", 1)[0] in have:
            cand["status"] = "duplicate"
            skipped += 1
            continue
        try:
            meta = archive_meta(iaid, session)
        except Exception as e:  # noqa: BLE001
            cand["status"] = "error"
            cand["error"] = str(e)
            errored += 1
            time.sleep(args.throttle)
            continue

        item, reason = build_item(cand, meta, session, omdb_key, omdb_cache, now)
        if item is None:
            cand["status"] = reason          # no_video / adult_collection / not_video_mediatype
            no_video += 1
            time.sleep(args.throttle)
            continue

        new_items.append(item)
        have.add(iaid)
        cand["status"] = "ingested"
        cand["ingested_at"] = now
        ingested += 1
        print(f"  + {iaid:45.45} [{item['contentType']}] "
              f"{'OMDb' if item.get('hasRealArtwork') else 'archive-art'}", flush=True)
        time.sleep(args.throttle)

    cand_doc["candidates"] = candidates
    cand_doc["updated_at"] = now

    if not args.dry_run and new_items:
        full_catalog["items"].extend(new_items)
        seed_catalog["items"].extend(new_items)
        dump_json(FULL_CATALOG, full_catalog)
        dump_json(SEED_CATALOG, seed_catalog)
        dump_json(CACHE_PATH, omdb_cache)
        dump_json(CANDIDATES, cand_doc)
    elif not args.dry_run:
        # Still persist candidate status changes (no_video, error, dup).
        dump_json(CANDIDATES, cand_doc)
        dump_json(CACHE_PATH, omdb_cache)

    print(f"[ingest] done: +{ingested} ingested, {no_video} no-video/skip, "
          f"{skipped} dup, {errored} err", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
