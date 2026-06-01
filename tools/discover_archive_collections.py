#!/usr/bin/env python3
"""
discover_archive_collections.py — mine PD-rich Internet Archive collections.

Complements the Wikidata discovery feed (discover_wikidata_pd.py). Wikidata
gives us rights-flagged films but many lack a playable Internet Archive ID;
this feed is the inverse — it walks Archive's big public-domain movie
collections directly, so every candidate is ALREADY a playable item with an
IA id. No title-resolution needed.

Collections mined (all overwhelmingly public-domain / free-to-share):
  feature_films, silent_films, classic_tv, prelinger, more_animation,
  film_noir-era titles via subject, scifi_horror, comedy, etc.

Items already in our catalogs (by archiveID) are skipped. New ones are
appended to shared/editorial/discovery_candidates.json with status="new",
source="archive_collection", and a rights confidence derived from the
collection + year. The ingest step drains them like any other candidate.

Read-only w.r.t. the catalogs. Cursor-paginated, daily-capped per
collection so it runs politely in CI.

Usage:
    python tools/discover_archive_collections.py --per-collection 600
    python tools/discover_archive_collections.py --collections feature_films,silent_films
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
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
CANDIDATES   = REPO / "shared" / "editorial" / "discovery_candidates.json"

SCRAPE = "https://archive.org/services/search/v1/scrape"
UA = A.UA
PD_YEAR_CUTOFF = 1930

# Collections that are overwhelmingly public-domain / free moving images.
# Ordered by value (richest, most-curated first).
DEFAULT_COLLECTIONS = [
    "feature_films",
    "silent_films",
    "classic_tv",
    "prelinger",
    "animationandcartoons",
    "more_animation",
    "film_noir",
    "SciFi_Horror",
    "comedy_films",
    "short_films",
    "newsandpublicaffairs",
    "documentary_films",
]


def load_existing_ids():
    ia = set()
    for p in (FULL_CATALOG, SEED_CATALOG):
        if not p.exists():
            continue
        for it in json.loads(p.read_text(encoding="utf-8")).get("items", []):
            a = it.get("archiveID")
            if a:
                ia.add(a)
                ia.add(a.rsplit(".", 1)[0])
    return ia


def scrape_query(q, session, *, limit, min_downloads):
    """Cursor-paginate any scrape query, most-downloaded first. Yields
    dicts with identifier/title/year/downloads/subject."""
    cursor = None
    got = 0
    while got < limit:
        params = {
            "q": q,
            "fields": "identifier,title,year,downloads,subject",
            "count": min(500, limit - got),
            "sorts": "downloads desc",
        }
        if cursor:
            params["cursor"] = cursor
        r = session.get(SCRAPE, params=params, headers={"User-Agent": UA},
                        timeout=60)
        if not r.ok:
            return
        data = r.json()
        items = data.get("items", [])
        if not items:
            return
        for it in items:
            try:
                if int(it.get("downloads") or 0) < min_downloads:
                    continue
            except (TypeError, ValueError):
                pass
            yield it
            got += 1
            if got >= limit:
                return
        cursor = data.get("cursor")
        if not cursor:
            return
        time.sleep(0.3)


def scrape_collection(coll, session, *, per_collection, min_downloads):
    """Mine one Archive collection (movies only), most-downloaded first."""
    yield from scrape_query(f"collection:{coll} AND mediatype:movies", session,
                            limit=per_collection, min_downloads=min_downloads)


def year_of(it):
    m = re.search(r"(\d{4})", str(it.get("year") or ""))
    return int(m.group(1)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--collections", help="Comma-separated collection ids "
                    "(default: the built-in PD-rich set).")
    ap.add_argument("--per-collection", type=int, default=600,
                    help="Max items to pull per collection (default 600).")
    ap.add_argument("--min-downloads", type=int, default=200,
                    help="Popularity floor — skips obscure/broken uploads "
                         "(default 200).")
    ap.add_argument("--pd-day-years", default="1928,1929,1930",
                    help="Comma-separated publication years to mine as a "
                         "Public-Domain-Day feed (films of these years are "
                         "PD by age). Default: the most recently entered. "
                         "Empty string disables.")
    ap.add_argument("--pd-day-cap", type=int, default=400,
                    help="Max items per PD-Day year (default 400).")
    args = ap.parse_args()

    collections = (args.collections.split(",") if args.collections
                   else DEFAULT_COLLECTIONS)
    have_ia = load_existing_ids()
    print(f"[arch-discover] catalog has {len(have_ia):,} IA ids; "
          f"mining {len(collections)} collections", flush=True)

    # Merge into the existing candidate queue (preserve statuses).
    existing = {}
    doc = {"candidates": []}
    if CANDIDATES.exists():
        doc = json.loads(CANDIDATES.read_text(encoding="utf-8"))
        for c in doc.get("candidates", []):
            # Key archive-collection candidates by IA id; Wikidata ones by QID.
            k = c.get("iaid") or c.get("wikidataQID")
            if k:
                existing[k] = c

    session = requests.Session()
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    added = 0

    def add_candidate(it, *, source, collection=None):
        iaid = it.get("identifier")
        if not iaid:
            return False
        if iaid in have_ia or iaid.rsplit(".", 1)[0] in have_ia:
            return False
        if iaid in existing:
            return False
        existing[iaid] = {
            "iaid": iaid,
            "title": it.get("title") or iaid,
            "year": year_of(it),
            "imdbID": None,
            "wikidataQID": None,
            "pdFlagged": True,
            "rightsConfidence": "high",
            "source": source,
            "archiveCollection": collection,
            "status": "new",
            "discovered_at": now,
        }
        have_ia.add(iaid)
        return True

    # Feed 1 — curated PD collections.
    for coll in collections:
        coll = coll.strip()
        if not coll:
            continue
        c_added = 0
        for it in scrape_collection(coll, session,
                                    per_collection=args.per_collection,
                                    min_downloads=args.min_downloads):
            if add_candidate(it, source="archive_collection", collection=coll):
                added += 1
                c_added += 1
        print(f"  collection:{coll:24} +{c_added} new", flush=True)

    # Feed 2 — Public Domain Day: films published in a just-entered PD year
    # (e.g. 1930 entered US PD on 2026-01-01). PD by age, regardless of
    # collection — catches films outside the curated collections above.
    pd_years = [y.strip() for y in (args.pd_day_years or "").split(",") if y.strip()]
    for yr in pd_years:
        y_added = 0
        q = f"mediatype:movies AND year:{yr}"
        for it in scrape_query(q, session, limit=args.pd_day_cap,
                               min_downloads=args.min_downloads):
            if add_candidate(it, source="public_domain_day"):
                added += 1
                y_added += 1
        print(f"  pd-day:{yr:>27} +{y_added} new", flush=True)

    # Re-order: archive-collection candidates (already playable) and
    # high-confidence first.
    cands = list(existing.values())
    cands.sort(key=lambda c: (
        c.get("rightsConfidence") != "high",
        c.get("iaid") is None,
        -(c.get("year") or 0),
    ))
    awaiting = sum(1 for c in cands if c["status"] == "new")
    out = {
        "schema": 1,
        "updated_at": now,
        "description": doc.get("description",
            "Public-domain candidates from Wikidata + Internet Archive "
            "collections, not yet in our catalogs. Drained by ingest_candidates.py."),
        "stats": {
            "total": len(cands),
            "new_this_run": added,
            "awaiting_ingest": awaiting,
            "with_archive_id": sum(1 for c in cands if c.get("iaid")),
        },
        "candidates": cands,
    }
    CANDIDATES.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[arch-discover] +{added:,} new candidates; queue now "
          f"{awaiting:,} awaiting ingest", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
