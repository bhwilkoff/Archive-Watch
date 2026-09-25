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
    # Collection ids are CASE-SENSITIVE: `film_noir` and `comedy_films`
    # returned 0 items on every run until 2026-09-24.
    "Film_Noir",
    "SciFi_Horror",
    "Comedy_Films",
    "short_films",
    "newsandpublicaffairs",
    # `documentary_films` was here and does not exist on archive.org under
    # any spelling (0 items, 2026-09-24); documentaries arrive via FedFlix,
    # prelinger and the government collections below.
    # Government / public-domain collections that fill weak categories
    # (newsreel, ephemeral, documentary were badly under-populated). All are
    # PD or US-gov works — no rights risk. Verified counts (2026-06) in parens.
    "FedFlix",              # US-gov PD films (~13.5k)
    "nasa",                 # NASA films, PD (~13.5k)
    "ephemera",             # industrial / educational ephemera (~21k)
    "universal_newsreels",  # classic newsreels (~600)
    "computerchronicles",   # Computer Chronicles, classic PD TV (~630)
    "academic_films",       # educational / documentary (~470)
    # Data-derived (2026-06): real content collection seen on 1.2k catalog items
    # but not mined directly. Mining it fully grows the German-cinema shelf.
    "mid-century-german-film",
    # Probe-verified (advancedsearch numFound, 2026-06) genuine PD content
    # collections — curated to exclude Archive admin/umbrella collections
    # (loggedin, no-preview, geo_restricted, deemphasize, *_video catch-alls).
    "classic_tv_1950s", "classic_tv_1960s", "classic_tv_1970s",
    "classic_tv_1980s", "classic_tv_1990s",   # decade TV -> TV decade shelves
    "silenthalloffame",                        # silent classics (441)
    "feature_films_picfixer",                  # PicFixer restorations (355)
    "film_scifi",                              # sci-fi features (295)
    "TheVideoCellarCollection",                # curated PD films (230)
    "culturalandacademicfilms", "educationalfilms",  # educational PD
    "avgeeks", "prelingerhomemovies", "DriveInMovieAds",  # ephemera
    "german_cinema",                           # German PD (104)
    "classic_cartoons", "segundodechomon",     # cartoons / early silent pioneer
    "georgesmelies", "vintage_cartoons",       # Home shelves never swept (2026-09-24)
    "nasaeclips", "jsc-pao-video-collection",  # NASA gov PD
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


def scrape_query(q, session, *, limit, min_downloads, is_new=lambda it: True):
    """Cursor-paginate any scrape query, most-downloaded first. Yields
    dicts with identifier/title/year/downloads/subject.

    `limit` caps the items that `is_new` accepts, not the items read. It
    used to count every row, so with the catalog already holding the top of
    a collection the nightly sweep re-read the same 600 most-downloaded items
    forever: 6,521 feature_films items were never queued (2026-09-24). The
    walk is cheap (ids only, 5,000 a page); the cap is what ingest can drain."""
    cursor = None
    got = 0
    while got < limit:
        params = {
            "q": q,
            "fields": "identifier,title,year,downloads,subject",
            "count": 5000,
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
            if not is_new(it):
                continue
            yield it
            got += 1
            if got >= limit:
                return
        cursor = data.get("cursor")
        if not cursor:
            return
        time.sleep(0.3)


def scrape_collection(coll, session, *, per_collection, min_downloads, is_new):
    """Mine one Archive collection (movies only), most-downloaded first."""
    yield from scrape_query(f"collection:{coll} AND mediatype:movies", session,
                            limit=per_collection, min_downloads=min_downloads,
                            is_new=is_new)


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
    # Decision 137: never a literal year. A US work enters the public domain
    # on January 1 of year + 96, so the newest PD year is this year - 96.
    newest_pd = dt.date.today().year - 96
    ap.add_argument("--pd-day-years",
                    default=",".join(str(y) for y in range(newest_pd - 2, newest_pd + 1)),
                    help="Comma-separated publication years to mine as a "
                         "Public-Domain-Day feed (films of these years are "
                         "PD by age). Default: the three most recently "
                         "entered, from the calendar. Empty string disables.")
    ap.add_argument("--max-awaiting", type=int, default=4000,
                    help="Stop adding once this many candidates await ingest "
                         "(~4 nights at ingest's 900). Measured 2026-09-25: the "
                         "first full-depth sweep queued +12,369 in one night and "
                         "doubled the committed queue file; newsandpublicaffairs "
                         "alone holds 3.4M items, so without a ceiling the queue "
                         "grows ~11k a night forever.")
    ap.add_argument("--pd-age-backfill", type=int, default=0,
                    help="Also mine every year from 1880 up to the oldest "
                         "PD-Day year, adding at most this many new candidates "
                         "a night (0 = off). Measured 2026-09-24: 8,220 "
                         "archive.org items dated 1880-1927 were in neither the "
                         "catalog nor the queue, 3,415 above the download floor.")
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

    awaiting = [sum(1 for c in existing.values() if c.get("status") == "new")]
    print(f"[arch-discover] {awaiting[0]:,} already await ingest (ceiling {args.max_awaiting:,})",
          flush=True)

    def is_new(it):
        iaid = it.get("identifier") or ""
        return bool(iaid) and iaid not in have_ia \
            and iaid.rsplit(".", 1)[0] not in have_ia and iaid not in existing

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
        awaiting[0] += 1
        return True

    # Feed 1 — Public Domain Day (FIRST, so the ceiling below never crowds
    # out films that are public domain by age): films published in a just-entered PD year
    # (e.g. 1930 entered US PD on 2026-01-01). PD by age, regardless of
    # collection — catches films outside the curated collections above.
    pd_years = [y.strip() for y in (args.pd_day_years or "").split(",") if y.strip()]
    for yr in pd_years:
        y_added = 0
        q = f"mediatype:movies AND year:{yr}"
        # Exempt from the ceiling (self-capped): ingest takes the oldest first,
        # so these jump a queue full of ephemera rather than waiting behind it.
        for it in scrape_query(q, session, limit=args.pd_day_cap,
                               min_downloads=args.min_downloads, is_new=is_new):
            if add_candidate(it, source="public_domain_day"):
                added += 1
                y_added += 1
        print(f"  pd-day:{yr:>27} +{y_added} new", flush=True)

    # Feed 3 — PD-by-age BACKFILL: every earlier year, one query, most
    # downloaded first, capped per night. Off by default. Relies on ingest's
    # guards for what an uploader's year cannot prove: held_suspect_year (the
    # title contradicts the year) and the duplicate merge (most of the top of
    # this list is another copy of a film we have).
    if args.pd_age_backfill and pd_years:
        first = min(int(y) for y in pd_years)
        b_added = 0
        q = f"mediatype:movies AND year:[1880 TO {first - 1}]"
        for it in scrape_query(q, session, limit=args.pd_age_backfill,
                               min_downloads=args.min_downloads, is_new=is_new):
            if add_candidate(it, source="pd_age_backfill"):
                added += 1
                b_added += 1
        print(f"  pd-age backfill 1880-{first - 1}:      +{b_added} new", flush=True)

    # Feed 2 — curated PD collections, in value order, until the ceiling.
    for coll in collections:
        coll = coll.strip()
        if not coll:
            continue
        room = args.max_awaiting - awaiting[0]
        if room <= 0:
            print(f"  collection:{coll:24} skipped — queue at ceiling", flush=True)
            continue
        c_added = 0
        # The limit is the room left, so a full queue stops the WALK too —
        # rejecting every row would still page through 3.4M newsreel ids.
        for it in scrape_collection(coll, session,
                                    per_collection=min(args.per_collection, room),
                                    min_downloads=args.min_downloads,
                                    is_new=is_new):
            if add_candidate(it, source="archive_collection", collection=coll):
                added += 1
                c_added += 1
        print(f"  collection:{coll:24} +{c_added} new", flush=True)

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
