#!/usr/bin/env python3
"""
discover_wikidata_pd.py — find public-domain films we don't have yet.

OMDb can't discover content (no rights filter, no enumeration — see
docs/research/omdb-and-pd-discovery.md), so discovery runs off Wikidata's
SPARQL endpoint, which carries both an Internet Archive ID (P724, → a
playable file) and an IMDb ID (P345, → TMDb/OMDb enrichment) on the same
row. Two feeds:

  A. Films with an Internet Archive ID (P724). Every row is already
     joinable to a playable IA item — the highest-value lead. ~5,000 films.
  B. Films explicitly flagged copyright status = public domain
     (P6216 = Q19652). Larger (~13,000) but only some carry an IA ID;
     those without one still get queued (the ingest step will try to find
     a matching IA item by title/year).

Output: shared/editorial/discovery_candidates.json — every candidate NOT
already in our catalogs (by Internet Archive ID or IMDb ID), with a
`status` of "new". The ingest step (tools/ingest_candidates.py) drains
this queue a daily-capped batch at a time. Read-only: this script never
touches the catalogs.

Usage:
    python tools/discover_wikidata_pd.py            # refresh candidate queue
    python tools/discover_wikidata_pd.py --limit 200   # smaller sample
"""

import argparse
import datetime as dt
import json
import sys
import time
from pathlib import Path

import requests

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
CANDIDATES   = REPO / "shared" / "editorial" / "discovery_candidates.json"

SPARQL = "https://query.wikidata.org/sparql"
UA = "ArchiveWatch-Discovery/1.0 (https://github.com/bhwilkoff/Archive-Watch; learningischange.com)"

# US public-domain publication cutoff. Works published before this year are
# PD by age alone (rolls forward every Jan 1: <1929 in 2025, <1930 in 2026).
# Bump this each year — or compute from the current year if you prefer.
PD_YEAR_CUTOFF = 1930

# Feed A — films with an Internet Archive ID (already playable).
QUERY_IA = """
SELECT DISTINCT ?film ?filmLabel ?imdb ?iaid ?year ?pd WHERE {
  ?film wdt:P31 wd:Q11424 ; wdt:P724 ?iaid .
  OPTIONAL { ?film wdt:P345 ?imdb. }
  OPTIONAL { ?film wdt:P577 ?pub. BIND(YEAR(?pub) AS ?year) }
  OPTIONAL { ?film wdt:P6216 ?cs. BIND(IF(?cs = wd:Q19652, true, false) AS ?pd) }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT %d
"""

# Feed B — films flagged public-domain (P6216 = Q19652), IA ID optional.
QUERY_PD = """
SELECT DISTINCT ?film ?filmLabel ?imdb ?iaid ?year WHERE {
  ?film wdt:P31 wd:Q11424 ; wdt:P6216 wd:Q19652 .
  OPTIONAL { ?film wdt:P345 ?imdb. }
  OPTIONAL { ?film wdt:P724 ?iaid. }
  OPTIONAL { ?film wdt:P577 ?pub. BIND(YEAR(?pub) AS ?year) }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT %d
"""


def run_sparql(query, retries=3):
    last = None
    for attempt in range(retries):
        try:
            r = requests.get(
                SPARQL,
                params={"query": query, "format": "json"},
                headers={"User-Agent": UA, "Accept": "application/sparql-results+json"},
                timeout=120,
            )
            if r.status_code == 429:
                wait = int(r.headers.get("Retry-After", 30))
                print(f"  rate-limited, waiting {wait}s", flush=True)
                time.sleep(wait)
                continue
            r.raise_for_status()
            return r.json()["results"]["bindings"]
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"SPARQL failed after {retries} tries: {last}")


def val(row, key):
    return row.get(key, {}).get("value")


def qid_of(uri):
    return uri.rsplit("/", 1)[-1] if uri else None


def load_existing_ids():
    """Sets of Internet Archive IDs and IMDb IDs already in our catalogs."""
    ia, imdb = set(), set()
    for p in (FULL_CATALOG, SEED_CATALOG):
        if not p.exists():
            continue
        for it in json.loads(p.read_text(encoding="utf-8")).get("items", []):
            aid = it.get("archiveID")
            if aid:
                # archiveID is sometimes a file ("Foo.avi"); also key the bare id.
                ia.add(aid)
                ia.add(aid.rsplit(".", 1)[0])
            im = it.get("imdbID")
            if im:
                imdb.add(im)
    return ia, imdb


def collect(rows, have_ia, have_imdb, candidates):
    """Fold SPARQL rows into the candidate dict (keyed by Wikidata QID),
    skipping anything we already have. Returns count of NEW additions."""
    added = 0
    for row in rows:
        qid = qid_of(val(row, "film"))
        if not qid:
            continue
        iaid = val(row, "iaid")
        imdb = val(row, "imdb")
        # Already in catalog? skip.
        if iaid and (iaid in have_ia or iaid.rsplit(".", 1)[0] in have_ia):
            continue
        if imdb and imdb in have_imdb:
            continue
        if qid in candidates:
            # Merge in any newly-seen IA/IMDb id.
            c = candidates[qid]
            c["iaid"] = c.get("iaid") or iaid
            c["imdbID"] = c.get("imdbID") or imdb
            continue
        year = val(row, "year")
        yr = int(year) if (year and year.lstrip("-").isdigit()) else None
        pd_flagged = val(row, "pd") == "true"
        candidates[qid] = {
            "wikidataQID": qid,
            "title": val(row, "filmLabel"),
            "year": yr,
            "iaid": iaid,
            "imdbID": imdb,
            "pdFlagged": pd_flagged,
            # Rights confidence: "high" = Wikidata flags PD, or published
            # before the age cutoff. "low" = neither (e.g. a recent film
            # that merely happens to have an IA upload — likely NOT PD;
            # the ingest step treats these conservatively).
            "rightsConfidence": "high" if (pd_flagged or (yr and yr < PD_YEAR_CUTOFF)) else "low",
            "status": "new",
            "discovered_at": None,  # stamped below
        }
        added += 1
    return added


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=8000,
                    help="Max rows per SPARQL feed (default 8000).")
    args = ap.parse_args()

    have_ia, have_imdb = load_existing_ids()
    print(f"[discover] catalog has {len(have_ia):,} IA ids, {len(have_imdb):,} IMDb ids", flush=True)

    # Preserve any existing candidate file (so 'queued'/'ingested'/'failed'
    # statuses set by the ingest step survive a re-discovery).
    existing = {}
    if CANDIDATES.exists():
        prior = json.loads(CANDIDATES.read_text(encoding="utf-8"))
        for c in prior.get("candidates", []):
            existing[c["wikidataQID"]] = c
    print(f"[discover] {len(existing):,} candidates already tracked", flush=True)

    candidates = dict(existing)
    before = len(candidates)

    print("[discover] feed A: films with an Internet Archive ID…", flush=True)
    rows_a = run_sparql(QUERY_IA % args.limit)
    a_new = collect(rows_a, have_ia, have_imdb, candidates)
    print(f"           {len(rows_a):,} rows → {a_new:,} new", flush=True)

    print("[discover] feed B: films flagged public-domain…", flush=True)
    rows_b = run_sparql(QUERY_PD % args.limit)
    b_new = collect(rows_b, have_ia, have_imdb, candidates)
    print(f"           {len(rows_b):,} rows → {b_new:,} new", flush=True)

    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    for c in candidates.values():
        if c.get("discovered_at") is None:
            c["discovered_at"] = now

    # Ordering for the ingest drain: rights-confident first (genuinely PD,
    # not just an incidental upload), then already-playable (has IA ID),
    # then IMDb-keyed (enrichable), then newest. This puts real PD classics
    # at the front and pushes low-confidence recent uploads to the back.
    ordered = sorted(
        candidates.values(),
        key=lambda c: (c.get("rightsConfidence") != "high",
                       c.get("iaid") is None,
                       c.get("imdbID") is None,
                       -(c.get("year") or 0)),
    )

    new_total = len(candidates) - before
    queued = sum(1 for c in ordered if c["status"] == "new")
    with_ia = sum(1 for c in ordered if c.get("iaid"))
    high_conf = sum(1 for c in ordered if c.get("rightsConfidence") == "high")
    out = {
        "schema": 1,
        "updated_at": now,
        "description": "Public-domain film candidates discovered via Wikidata "
                       "(P724 Internet Archive ID + P6216 public-domain flag), "
                       "not yet in our catalogs. Drained by tools/ingest_candidates.py.",
        "stats": {
            "total": len(ordered),
            "new_this_run": new_total,
            "awaiting_ingest": queued,
            "with_archive_id": with_ia,
            "rights_high_confidence": high_conf,
        },
        "candidates": ordered,
    }
    CANDIDATES.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[discover] {len(ordered):,} candidates total "
          f"(+{new_total:,} new, {queued:,} awaiting ingest, {with_ia:,} with IA id)", flush=True)
    print(f"[discover] wrote {CANDIDATES.relative_to(REPO)}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
