#!/usr/bin/env python3
"""
discover_loc.py — ingest public-domain films from the Library of Congress
National Screening Room.

A distinct content source from the Internet Archive: ~1,294 US-government /
library-attested public-domain films, served as downloadable MP4 directly
from loc.gov (with duration + poster + date in one API call). These are
generally NOT on the Internet Archive, so this genuinely widens the catalog.

Unlike the Wikidata/Archive feeds (which queue candidates for the ingest
step), LoC items are self-contained — one item-detail call yields a
playable MP4 + metadata — so this script builds finished catalog items and
appends them straight to both catalogs. archiveID is namespaced "loc:{id}"
so it never collides with an Internet Archive id; the app plays the
loc.gov MP4 URL exactly like an Archive one.

Daily-capped + paginated; idempotent (skips loc: ids we already have).

Usage:
    python tools/discover_loc.py --max-items 40
    python tools/discover_loc.py --max-items 5 --dry-run
"""

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

import requests

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"

COLLECTION = "https://www.loc.gov/collections/national-screening-room/"
UA = "ArchiveWatch-LoC/1.0 (https://github.com/bhwilkoff/Archive-Watch; learningischange.com)"
PD_YEAR_CUTOFF = 1930


def load_json(p):
    return json.loads(p.read_text(encoding="utf-8"))

def dump_json(p, data):
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)


def loc_id(item_url):
    """http://www.loc.gov/item/2021604034/ → 2021604034"""
    m = re.search(r"/item/([^/]+)/?", item_url or "")
    return m.group(1) if m else None


def year_of(item):
    for k in ("date", "dates"):
        v = item.get(k)
        if isinstance(v, list):
            v = v[0] if v else None
        m = re.search(r"(\d{4})", str(v or ""))
        if m:
            return int(m.group(1))
    return None


def first(v):
    if isinstance(v, list):
        return v[0] if v else None
    return v


def classify(title, subjects, runtime_sec, year):
    blob = (title + " " + " ".join(subjects)).lower()
    if year and year < 1928:
        return "silent-film"
    if any(w in blob for w in ("cartoon", "animation", "animated")):
        return "animation"
    if any(w in blob for w in ("newsreel", "news review")):
        return "newsreel"
    if runtime_sec and runtime_sec < 2400:
        return "short-film"
    if any(w in blob for w in ("documentary", "educational")):
        return "documentary"
    return "feature-film"


def build_item(detail, now):
    """Build a catalog item from a LoC item-detail JSON, or None if it
    has no playable MP4."""
    item = detail.get("item", {}) or {}
    resources = detail.get("resources", []) or item.get("resources", []) or []
    mp4 = None
    duration = None
    poster = None
    for r in resources:
        if r.get("video"):
            mp4 = r["video"]
            duration = r.get("duration")
            poster = r.get("poster") or r.get("image")
            break
    if not mp4:
        return None

    iid = loc_id(detail.get("url") or item.get("id") or "")
    if not iid:
        return None

    title = first(item.get("title")) or "Untitled"
    subjects = item.get("subjects") or item.get("subject") or []
    if isinstance(subjects, dict):
        subjects = list(subjects.keys())
    subjects = [str(s) for s in subjects][:25]
    year = year_of(item)
    runtime_sec = int(duration) if duration else None

    return {
        "archiveID": f"loc:{iid}",
        "title": title,
        "year": year,
        "decade": (year // 10 * 10) if year else None,
        "runtimeSeconds": runtime_sec,
        "synopsis": (first(item.get("description")) or None),
        "collections": ["national-screening-room", "library-of-congress"],
        "subjects": subjects,
        "mediatype": "movies",
        "language": first(item.get("language")) or "English",
        "imdbID": None, "tmdbID": None, "wikidataQID": None, "tvmazeID": None,
        "videoFile": {
            "name": mp4.rsplit("/", 1)[-1],
            "format": "h.264",
            "sizeBytes": 0,
            "tier": 1,
        },
        "downloadURL": mp4,
        "posterURL": poster,
        "backdropURL": None,
        "hasRealArtwork": bool(poster),
        "artworkSource": "loc" if poster else "archive",
        "contentType": classify(title, subjects, runtime_sec, year),
        "genres": [],
        "countries": ["United States"],
        "cast": [],
        "director": None, "producer": None, "seriesName": None, "network": None,
        "enrichmentTier": "archiveCurated",
        "shelves": [],
        "rightsStatus": "public_domain",
        "qualityScore": None, "popularityScore": None,
        "bestSourceType": "library_of_congress",
        "isSilentFilm": (year is not None and year < 1928),
        "discoverySource": "loc",
    }


def collection_page(session, page):
    r = session.get(COLLECTION,
                    params={"fo": "json", "c": 25, "sp": page, "at": "results,pagination"},
                    headers={"User-Agent": UA}, timeout=60)
    r.raise_for_status()
    d = r.json()
    return d.get("results", []), d.get("pagination", {})


def item_detail(session, item_url, *, retries=3):
    """Fetch an item's JSON. loc.gov throttles and occasionally returns
    truncated/HTML bodies — retry with backoff and tolerate failures."""
    import time
    for attempt in range(retries):
        try:
            r = session.get(item_url, params={"fo": "json"},
                            headers={"User-Agent": UA}, timeout=60)
            if r.status_code == 429:
                time.sleep(10 * (attempt + 1))
                continue
            if not r.ok:
                return None
            return r.json()
        except (ValueError, requests.RequestException):
            time.sleep(3 * (attempt + 1))
    return None


def existing_loc_ids(*catalogs):
    s = set()
    for cat in catalogs:
        for it in cat.get("items", []):
            a = it.get("archiveID") or ""
            if a.startswith("loc:"):
                s.add(a)
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-items", type=int, default=40,
                    help="Max NEW LoC films to ingest this run (default 40).")
    ap.add_argument("--start-page", type=int, default=1)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--throttle", type=float, default=0.3)
    args = ap.parse_args()

    full_catalog = load_json(FULL_CATALOG)
    seed_catalog = load_json(SEED_CATALOG)
    have = existing_loc_ids(full_catalog, seed_catalog)
    print(f"[loc] catalog has {len(have)} LoC films already", flush=True)

    session = requests.Session()
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    new_items = []
    page = args.start_page
    scanned = 0

    while len(new_items) < args.max_items:
        try:
            results, pg = collection_page(session, page)
        except Exception as e:  # noqa: BLE001
            print(f"[loc] page {page} error: {e}", flush=True)
            break
        if not results:
            break
        for res in results:
            iid = loc_id(res.get("id"))
            if not iid or f"loc:{iid}" in have:
                continue
            # Only items that advertise video.
            of = res.get("online_format") or []
            if "video" not in of and "video" not in str(res.get("mime_type", "")):
                continue
            detail = item_detail(session, res.get("id"))
            scanned += 1
            if not detail:
                continue
            item = build_item(detail, now)
            if item:
                new_items.append(item)
                have.add(item["archiveID"])
                print(f"  + {item['archiveID']:18} [{item['contentType']}] "
                      f"{(item['title'] or '')[:40]}", flush=True)
            import time
            time.sleep(args.throttle)
            if len(new_items) >= args.max_items:
                break
        total_pages = pg.get("total") or page
        if page >= total_pages:
            break
        page += 1

    if not args.dry_run and new_items:
        full_catalog["items"].extend(new_items)
        seed_catalog["items"].extend(new_items)
        dump_json(FULL_CATALOG, full_catalog)
        dump_json(SEED_CATALOG, seed_catalog)

    print(f"[loc] done: +{len(new_items)} LoC films "
          f"(scanned {scanned} item details){' (dry-run)' if args.dry_run else ''}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
