#!/usr/bin/env python3
"""
discover_tv_shows.py — find NEW television items on the Internet Archive to
feed the canonical TV builder, growing the series count over time.

The canonical builder (build_canonical_tv.py) resolves titles to a TVmaze
show and pools Archive items per show. This feed widens its input: it mines
Archive's TV-heavy collections + TV-subject searches for items we don't yet
have, and writes them to shared/editorial/tv_discovery.json. The builder
loads that file as additional candidates, so a freshly-discovered "Dragnet"
episode automatically pools into the canonical Dragnet series.

Read-only w.r.t. the catalogs. Cursor-paginated, daily-capped, popularity-
floored so it runs politely in CI. Accumulates across runs (skips ids we
already have or already discovered).

Usage:
    python tools/discover_tv_shows.py --per-collection 800
    python tools/discover_tv_shows.py --collections classic_tv --limit 50
"""

import argparse
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
SERIES_DIR = REPO / "series"
DISCOVERY = REPO / "shared" / "editorial" / "tv_discovery.json"

SCRAPE = "https://archive.org/services/search/v1/scrape"
UA = A.UA

# TV-heavy Archive collections + subject searches. Every hit is mediatype
# movies (Archive files video under "movies"); the builder decides what's a
# real show via TVmaze.
DEFAULT_COLLECTIONS = ["classic_tv", "classic_tv_movies", "classictvcommercials"]
SUBJECT_QUERIES = [
    'mediatype:movies AND (subject:"television" OR subject:"tv series" OR subject:"TV")',
    'mediatype:movies AND (subject:"sitcom" OR subject:"television series")',
]


def existing_ids():
    have = set()
    for p in (FULL_CATALOG, SEED_CATALOG):
        if p.exists():
            for it in json.loads(p.read_text(encoding="utf-8")).get("items", []):
                a = it.get("archiveID")
                if a:
                    have.add(a); have.add(a.rsplit(".", 1)[0])
    # episodes already inside series files
    for f in SERIES_DIR.glob("*.json"):
        d = json.loads(f.read_text(encoding="utf-8"))
        for s in d.get("seasons", []):
            for e in s.get("episodes", []):
                if e.get("archiveID"):
                    have.add(e["archiveID"])
    return have


def scrape(q, session, *, limit, min_downloads):
    cursor = None; got = 0
    while got < limit:
        params = {"q": q, "fields": "identifier,title,year,downloads",
                  "count": min(500, limit - got), "sorts": "downloads desc"}
        if cursor:
            params["cursor"] = cursor
        r = session.get(SCRAPE, params=params, headers={"User-Agent": UA}, timeout=60)
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
            yield it; got += 1
            if got >= limit:
                return
        cursor = data.get("cursor")
        if not cursor:
            return
        time.sleep(0.3)


def year_of(it):
    m = re.search(r"(\d{4})", str(it.get("year") or ""))
    return int(m.group(1)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--collections", help="comma-separated (default TV set)")
    ap.add_argument("--per-collection", type=int, default=800)
    ap.add_argument("--min-downloads", type=int, default=120)
    ap.add_argument("--limit", type=int, default=0, help="overall cap (testing)")
    ap.add_argument("--no-subject", action="store_true",
                    help="skip the broad subject queries (collections only)")
    args = ap.parse_args()

    colls = (args.collections.split(",") if args.collections else DEFAULT_COLLECTIONS)
    have = existing_ids()
    print(f"[tv-discover] catalog/episodes have {len(have):,} ids; "
          f"mining {len(colls)} collections + {0 if args.no_subject else len(SUBJECT_QUERIES)} subject queries",
          flush=True)

    doc = {"items": []}
    if DISCOVERY.exists():
        doc = json.loads(DISCOVERY.read_text(encoding="utf-8"))
    seen = {i["archiveID"] for i in doc.get("items", [])}

    session = requests.Session()
    queries = [f"collection:{c} AND mediatype:movies" for c in colls]
    if not args.no_subject:
        queries += SUBJECT_QUERIES

    added = 0
    for q in queries:
        n_q = 0
        for it in scrape(q, session, limit=args.per_collection,
                         min_downloads=args.min_downloads):
            iid = it.get("identifier")
            title = it.get("title")
            if not iid or not title:
                continue
            if iid in have or iid in seen:
                continue
            seen.add(iid)
            doc["items"].append({"archiveID": iid, "title": str(title),
                                 "year": year_of(it), "source": "tv-discover"})
            added += 1; n_q += 1
            if args.limit and added >= args.limit:
                break
        print(f"  + {n_q:4} new from: {q[:50]}", flush=True)
        if args.limit and added >= args.limit:
            break

    DISCOVERY.parent.mkdir(parents=True, exist_ok=True)
    DISCOVERY.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[tv-discover] +{added} new TV items; queue now {len(doc['items'])} "
          f"-> {DISCOVERY}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
