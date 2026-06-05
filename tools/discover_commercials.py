#!/usr/bin/env python3
"""
discover_commercials.py — queue rights-clear vintage commercials for ingest.

Searches archive.org for advertising/commercial movie items that carry an
explicit Public Domain Mark / CC0 license (the only commercial content whose
rights fit a public, free App Store app — Decision 010). Duke AdViews and the
bulk of `classic_tv_commercials` are deliberately EXCLUDED: they have no license
and the rights holders never transferred copyright, so they fail our bar.

Each match is appended to shared/editorial/discovery_candidates.json as a
status="new" candidate tagged:
    source           = "commercials"
    contentTypeHint  = "commercial"   (ingest_candidates honors this verbatim)
    rightsConfidence = "high"         (PD/CC0 -> rightsStatus public_domain)
ingest_candidates.py then drains the queue, picks the H.264 derivative, and adds
a synthetic "aw_commercials" collection so the app's Commercials collection
groups them. Commercials never appear on Home (CatalogDB.notCommercial); they
surface only via the Commercials collection, the Random Commercial action, and
(future) as channel breaks — see docs/design/channels-tv-guide.md.

Idempotent: re-running only appends archive IDs not already queued or in the
catalog. Safe to wire into discover-content.yml or run by hand.

Usage:
    python tools/discover_commercials.py            # full sweep
    python tools/discover_commercials.py --limit 200 --dry-run
"""

import argparse
import datetime as dt
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CANDIDATES = REPO / "shared" / "editorial" / "discovery_candidates.json"

# Ad/commercial content signal (subject OR title) AND an explicit PD/CC0 license.
# Mirrors the vetted query from the rights survey (2,510 items, ~70% PD/CC0).
AD = ("(subject:(commercials OR advertising OR advertisement) OR "
      "title:(commercial OR advertisement OR advert))")
LICENSE = "(licenseurl:*publicdomain* OR licenseurl:*zero*)"
QUERY = f"mediatype:movies AND {AD} AND {LICENSE}"


def search_page(query, page, rows=200):
    params = [("q", query), ("rows", str(rows)), ("page", str(page)),
              ("output", "json"), ("sort", "downloads desc")]
    for f in ("identifier", "title", "year", "licenseurl"):
        params.append(("fl[]", f))
    url = "https://archive.org/advancedsearch.php?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url, headers={"User-Agent": "ArchiveWatch-discovery (ben@learningischange.com)"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r).get("response", {})
        except Exception as e:  # noqa: BLE001
            if attempt == 3:
                raise
            time.sleep(3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0,
                    help="Max NEW candidates to queue (0 = all matches).")
    ap.add_argument("--rows", type=int, default=200, help="Page size.")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    doc = json.loads(CANDIDATES.read_text(encoding="utf-8"))
    candidates = doc.get("candidates", [])
    have = {c.get("iaid") for c in candidates if c.get("iaid")}
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

    first = search_page(QUERY, 1, args.rows)
    total = first.get("numFound", 0)
    pages = (total + args.rows - 1) // args.rows
    print(f"[commercials] query matched {total} PD/CC0 ad items across {pages} pages", flush=True)

    added = 0
    for page in range(1, pages + 1):
        resp = first if page == 1 else search_page(QUERY, page, args.rows)
        for d in resp.get("docs", []):
            iaid = d.get("identifier")
            if not iaid or iaid in have:
                continue
            year = None
            y = d.get("year")
            if y:
                try:
                    year = int(str(y)[:4])
                except ValueError:
                    year = None
            candidates.append({
                "iaid": iaid,
                "imdbID": None,
                "wikidataQID": None,
                "title": d.get("title") or iaid,
                "year": year,
                "source": "commercials",
                "archiveCollection": "aw_commercials",
                "contentTypeHint": "commercial",
                "pdFlagged": True,
                "rightsConfidence": "high",
                "status": "new",
                "discovered_at": now,
            })
            have.add(iaid)
            added += 1
            if args.limit and added >= args.limit:
                break
        if args.limit and added >= args.limit:
            break
        if page < pages:
            time.sleep(0.5)

    print(f"[commercials] queued {added} new candidates "
          f"({len(candidates)} total in queue)", flush=True)

    if args.dry_run:
        print("[commercials] dry-run — not written")
        return 0

    doc["candidates"] = candidates
    doc["updated_at"] = now
    stats = doc.setdefault("stats", {})
    stats["total"] = len(candidates)
    tmp = CANDIDATES.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(CANDIDATES)
    return 0


if __name__ == "__main__":
    sys.exit(main())
