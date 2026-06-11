#!/usr/bin/env python3
"""
discover_pd_wants.py — title-FIRST public-domain discovery (the inverted
pipeline): instead of enriching Archive items we already found, enumerate
films the metadata world says are public domain / lost-copyright and queue
them as WANTS for the Archive hunter.

Three feeds, each contributing titles with identity (IMDb/Wikidata/TMDb
ids) attached, so a hunted match arrives with impeccable metadata and is
verifiable per Decision 026 (corroborated ids, never fuzzy-title-only):

  W. Wikipedia's curated "List of films in the public domain in the
     United States" — the canonical table of renewal-failure and
     notice-defect films (His Girl Friday, Night of the Living Dead,
     Charade, McLintock!…), each row carrying the year AND the reason
     copyright lapsed. Parsed from wikitext; each film link's Wikidata
     QID is batch-resolved to an IMDb id.
  T. TMDb /discover for films released before the rolling US PD-by-age
     cutoff, most popular first — surfaces well-known pre-cutoff titles
     (with posters/cast ready to go) that none of our Archive-side scans
     ever queued. Needs TMDB_BEARER_TOKEN; the feed is skipped without it.
  A. Wikidata films published before the cutoff that carry an IMDb id but
     NO P6216 public-domain flag — the long tail feed B (P6216) misses.

Every want we don't already have (by IMDb id, IA id, QID, or normalized
title+year) is appended to shared/editorial/discovery_candidates.json with
iaid=null — tools/ingest_candidates.py already resolves those against
archive.org by title+year (archive_lib.resolve_title), confirms a playable
derivative, and ingests. Downstream, audit_rights (Decision 027) remains
the rights gate; this tool only nominates.

Read-only on the catalogs; append/merge-only on the candidate queue (the
ingest step's statuses survive re-runs). Report: wants_report.csv next to
the queue summarises what was added this run and why.

Usage:
    python tools/discover_pd_wants.py                     # all feeds
    python tools/discover_pd_wants.py --tmdb-pages 20     # smaller TMDb pull
    python tools/discover_pd_wants.py --skip wikipedia    # drop a feed
    python tools/discover_pd_wants.py --dry-run           # report only
"""

import argparse
import csv
import datetime as dt
import json
import os
import re
import sys
import time
from pathlib import Path

import requests

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
CANDIDATES = REPO / "shared" / "editorial" / "discovery_candidates.json"
REPORT = REPO / "shared" / "editorial" / "wants_report.csv"

UA = "ArchiveWatch-Discovery/1.0 (https://github.com/bhwilkoff/Archive-Watch; learningischange.com)"
WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
WIKIDATA_API = "https://www.wikidata.org/w/api.php"
SPARQL = "https://query.wikidata.org/sparql"
TMDB = "https://api.themoviedb.org/3"

# Rolling US PD-by-age cutoff: works published before (current year - 95)
# are PD on age alone (1930 films entered PD on 2026-01-01).
PD_YEAR_CUTOFF = dt.date.today().year - 95

# Curated list pages. Each is a wikitable whose rows lead with the film
# link, then year, director, studio, and the reason copyright lapsed.
WIKIPEDIA_LISTS = [
    "List of films in the public domain in the United States",
]


def session():
    s = requests.Session()
    s.headers["User-Agent"] = UA
    return s


def http_get(s, url, params, retries=3, timeout=60):
    last = None
    for attempt in range(retries):
        try:
            r = s.get(url, params=params, timeout=timeout)
            if r.status_code == 429:
                time.sleep(5 * (attempt + 1))
                continue
            r.raise_for_status()
            return r.json()
        except Exception as e:           # noqa: BLE001 — feed-level resilience
            last = e
            time.sleep(2 * (attempt + 1))
    print(f"[wants] WARN: giving up on {url}: {last}", flush=True)
    return None


def norm_title(t):
    t = re.sub(r"\(.*?\)", " ", (t or "").lower())
    t = re.sub(r"[^a-z0-9]+", " ", t)
    return " ".join(t.split())


def title_year_key(title, year):
    return f"{norm_title(title)}|{year or ''}"


# ---------------------------------------------------------------- feed W ---

def wikipedia_qids_for(s, page_titles):
    """Batch page titles → Wikidata QIDs via prop=pageprops."""
    qids = {}
    titles = list(page_titles)
    for i in range(0, len(titles), 50):
        data = http_get(s, WIKIPEDIA_API, {
            "action": "query", "format": "json", "formatversion": 2,
            "titles": "|".join(titles[i:i + 50]),
            "prop": "pageprops", "ppprop": "wikibase_item",
            "redirects": 1,
        })
        if not data:
            continue
        redirect = {r["to"]: r["from"]
                    for r in data.get("query", {}).get("redirects", [])}
        for page in data.get("query", {}).get("pages", []):
            t = page.get("title")
            qid = page.get("pageprops", {}).get("wikibase_item")
            if not qid:
                continue
            qids[t] = qid
            if t in redirect:
                qids[redirect[t]] = qid
        time.sleep(0.2)
    return qids


def wikidata_film_facts(s, qids):
    """Batch-resolve QIDs → {qid: (imdbID, year)} via wbgetentities."""
    facts = {}
    qids = [q for q in qids if q]
    for i in range(0, len(qids), 50):
        batch = qids[i:i + 50]
        data = http_get(s, WIKIDATA_API, {
            "action": "wbgetentities", "format": "json",
            "ids": "|".join(batch), "props": "claims",
        })
        if not data:
            continue
        for qid, ent in data.get("entities", {}).items():
            claims = ent.get("claims", {})

            def first(prop):
                for c in claims.get(prop, []):
                    v = c.get("mainsnak", {}).get("datavalue", {}).get("value")
                    if v:
                        return v
                return None

            imdb = first("P345")
            year = None
            pub = first("P577")
            if isinstance(pub, dict):
                m = re.match(r"[+-](\d{4})", pub.get("time", ""))
                if m:
                    year = int(m.group(1))
            facts[qid] = (imdb if isinstance(imdb, str) else None, year)
        time.sleep(0.3)
    return facts


def feed_wikipedia(s):
    """Wants from the curated US-PD list pages. Each table row leads with
    the film wikilink; column 2 is the year; the row text states WHY the
    film is PD (not renewed / no notice) — kept as pdEvidence."""
    rows = []
    for page in WIKIPEDIA_LISTS:
        data = http_get(s, WIKIPEDIA_API, {
            "action": "parse", "page": page, "prop": "wikitext",
            "format": "json", "formatversion": 2,
        })
        wikitext = (data or {}).get("parse", {}).get("wikitext", "")
        for line in wikitext.split("\n"):
            if not line.startswith("|") or "[[" not in line:
                continue
            m = re.match(r"\|\s*'*\[\[([^\]|]+)(?:\|([^\]]+))?\]\]", line)
            if not m:
                continue
            cols = line.split("||")
            year = None
            if len(cols) >= 2:
                ym = re.search(r"\b(18\d\d|19\d\d|20\d\d)\b", cols[1])
                if ym:
                    year = int(ym.group(1))
            if year is None:        # header / prose rows
                continue
            low = line.lower()
            if "not renewed" in low:
                why = "copyright not renewed (Wikipedia US-PD list)"
            elif "notice" in low:
                why = "published without copyright notice (Wikipedia US-PD list)"
            elif "dedicat" in low:
                why = "dedicated to the public domain (Wikipedia US-PD list)"
            else:
                why = "Wikipedia US public-domain film list"
            rows.append({"wpPage": m.group(1),
                         "display": m.group(2) or m.group(1),
                         "year": year, "why": why})
    print(f"[wants] wikipedia: {len(rows):,} curated US-PD list rows", flush=True)
    qids = wikipedia_qids_for(s, {r["wpPage"] for r in rows})
    facts = wikidata_film_facts(s, set(qids.values()))
    wants = []
    for r in rows:
        qid = qids.get(r["wpPage"])
        imdb, wd_year = facts.get(qid, (None, None))
        title = re.sub(r"\s*\(.*?\)\s*$", "", r["display"])
        wants.append({
            "title": title, "year": r["year"] or wd_year, "imdbID": imdb,
            "wikidataQID": qid, "source": "wants_wikipedia",
            "pdEvidence": r["why"],
        })
    return wants


# ---------------------------------------------------------------- feed T ---

def feed_tmdb(s, pages):
    """Pre-cutoff films from TMDb discover, popularity-first."""
    token = os.environ.get("TMDB_BEARER_TOKEN", "").strip()
    if not token:
        print("[wants] tmdb: no TMDB_BEARER_TOKEN — feed skipped", flush=True)
        return []
    s2 = session()
    s2.headers["Authorization"] = f"Bearer {token}"
    wants, ids = [], []
    for page in range(1, pages + 1):
        data = http_get(s2, f"{TMDB}/discover/movie", {
            "primary_release_date.lte": f"{PD_YEAR_CUTOFF - 1}-12-31",
            "sort_by": "popularity.desc", "include_adult": "false",
            "page": page,
        })
        if not data or not data.get("results"):
            break
        for m in data["results"]:
            year = None
            if m.get("release_date"):
                year = int(m["release_date"][:4])
            wants.append({
                "title": m.get("title") or m.get("original_title"),
                "year": year, "imdbID": None, "tmdbID": m.get("id"),
                "wikidataQID": None, "source": "wants_tmdb",
                "pdEvidence": f"released before {PD_YEAR_CUTOFF} (US PD by age)",
            })
            ids.append(m.get("id"))
        if page >= data.get("total_pages", 1):
            break
        time.sleep(0.3)   # ~40 req/10 s budget shared with external_ids below
    print(f"[wants] tmdb: {len(wants):,} pre-{PD_YEAR_CUTOFF} titles", flush=True)
    return wants


def tmdb_external_id(s, tmdb_id):
    token = os.environ.get("TMDB_BEARER_TOKEN", "").strip()
    if not token or not tmdb_id:
        return None
    s.headers["Authorization"] = f"Bearer {token}"
    data = http_get(s, f"{TMDB}/movie/{tmdb_id}/external_ids", {})
    return (data or {}).get("imdb_id") or None


# ---------------------------------------------------------------- feed A ---

# Sharded by DECADE: one big query (or deep OFFSET pages) routinely 504s
# or truncates mid-stream on WDQS; per-decade windows stay small enough to
# finish, and together they cover the whole pre-cutoff space.
QUERY_AGE = """
SELECT DISTINCT ?film ?filmLabel ?imdb ?year WHERE {
  ?film wdt:P31 wd:Q11424 ; wdt:P345 ?imdb ; wdt:P577 ?pub .
  BIND(YEAR(?pub) AS ?year)
  FILTER(?year >= %d && ?year < %d)
  FILTER NOT EXISTS { ?film wdt:P6216 ?any. }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT %d
"""


def feed_wikidata_age(s, limit):
    wants = []
    evidence = f"published before {PD_YEAR_CUTOFF} (US PD by age; no P6216 flag)"
    decades = list(range(1880, PD_YEAR_CUTOFF, 10))
    per_shard = max(500, limit // max(1, len(decades)))
    for start in decades:
        end = min(start + 10, PD_YEAR_CUTOFF)
        data = http_get(s, SPARQL, {
            "query": QUERY_AGE % (start, end, per_shard), "format": "json",
        }, timeout=120)
        rows = (data or {}).get("results", {}).get("bindings", [])
        for row in rows:
            def val(k):
                return row.get(k, {}).get("value")
            year = val("year")
            wants.append({
                "title": val("filmLabel"), "year": int(year) if year else None,
                "imdbID": val("imdb"),
                "wikidataQID": (val("film") or "").rsplit("/", 1)[-1] or None,
                "source": "wants_wikidata_age",
                "pdEvidence": evidence,
            })
        time.sleep(1)
    print(f"[wants] wikidata-age: {len(wants):,} unflagged pre-{PD_YEAR_CUTOFF} films", flush=True)
    return wants


# ------------------------------------------------------------------ merge ---

def load_have():
    """Identity sets already in the catalogs + candidate queue."""
    have_ia, have_imdb, have_qid, have_ty = set(), set(), set(), set()
    for p in (FULL_CATALOG, SEED_CATALOG):
        if not p.exists():
            continue
        for it in json.loads(p.read_text(encoding="utf-8")).get("items", []):
            if it.get("archiveID"):
                have_ia.add(it["archiveID"])
            if it.get("imdbID"):
                have_imdb.add(it["imdbID"])
            have_ty.add(title_year_key(it.get("title"), it.get("year")))
    queue = {"schema": 1, "candidates": []}
    if CANDIDATES.exists():
        queue = json.loads(CANDIDATES.read_text(encoding="utf-8"))
    for c in queue.get("candidates", []):
        if c.get("iaid"):
            have_ia.add(c["iaid"])
        if c.get("imdbID"):
            have_imdb.add(c["imdbID"])
        if c.get("wikidataQID"):
            have_qid.add(c["wikidataQID"])
        have_ty.add(title_year_key(c.get("title"), c.get("year")))
    return queue, have_ia, have_imdb, have_qid, have_ty


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tmdb-pages", type=int, default=40,
                    help="TMDb discover pages (20 titles each; default 40).")
    ap.add_argument("--age-limit", type=int, default=6000,
                    help="Max rows for the Wikidata age feed (default 6000).")
    ap.add_argument("--skip", action="append", default=[],
                    choices=["wikipedia", "tmdb", "wikidata_age"],
                    help="Skip a feed (repeatable).")
    ap.add_argument("--dry-run", action="store_true",
                    help="Report what would be queued; write nothing.")
    args = ap.parse_args()

    s = session()
    queue, have_ia, have_imdb, have_qid, have_ty = load_have()
    print(f"[wants] PD-by-age cutoff: year < {PD_YEAR_CUTOFF}", flush=True)
    print(f"[wants] have: {len(have_imdb):,} imdb ids, {len(have_ty):,} title+year keys", flush=True)

    wants = []
    if "wikipedia" not in args.skip:
        wants += feed_wikipedia(s)
    if "tmdb" not in args.skip:
        wants += feed_tmdb(s, args.tmdb_pages)
    if "wikidata_age" not in args.skip:
        wants += feed_wikidata_age(s, args.age_limit)

    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    added, report_rows = [], []
    for w in wants:
        if not w.get("title"):
            continue
        # A Wikidata label that is just the QID means "no English label" —
        # unusable as an Archive search phrase.
        if re.fullmatch(r"Q\d+", w["title"]):
            continue
        ty = title_year_key(w["title"], w.get("year"))
        if (w.get("imdbID") and w["imdbID"] in have_imdb) \
           or (w.get("wikidataQID") and w["wikidataQID"] in have_qid) \
           or ty in have_ty:
            continue
        # TMDb wants: resolve the IMDb id ONLY for titles that survive dedup
        # (keeps the external_ids call count proportional to NEW finds).
        if w["source"] == "wants_tmdb" and not w.get("imdbID"):
            w["imdbID"] = tmdb_external_id(s, w.get("tmdbID"))
            if w["imdbID"] and w["imdbID"] in have_imdb:
                continue
        have_ty.add(ty)
        if w.get("imdbID"):
            have_imdb.add(w["imdbID"])
        if w.get("wikidataQID"):
            have_qid.add(w["wikidataQID"])
        cand = {
            "iaid": None,
            "title": w["title"],
            "year": w.get("year"),
            "imdbID": w.get("imdbID"),
            "wikidataQID": w.get("wikidataQID"),
            "pdFlagged": True,
            "rightsConfidence": "high",
            "source": w["source"],
            "pdEvidence": w["pdEvidence"],
            "status": "new",
            "discovered_at": now,
        }
        if w.get("tmdbID"):
            cand["tmdbID"] = w["tmdbID"]
        added.append(cand)
        report_rows.append([w["source"], w["title"], w.get("year") or "",
                            w.get("imdbID") or "", w["pdEvidence"]])

    by_src = {}
    for c in added:
        by_src[c["source"]] = by_src.get(c["source"], 0) + 1
    print(f"[wants] NEW wants this run: {len(added):,} {by_src}", flush=True)

    if args.dry_run:
        print("[wants] dry run — nothing written", flush=True)
        return

    queue.setdefault("candidates", []).extend(added)
    queue["updated_at"] = now
    stats = queue.setdefault("stats", {})
    stats["wants_last_run"] = {"added": len(added), "by_source": by_src, "at": now}
    CANDIDATES.parent.mkdir(parents=True, exist_ok=True)
    CANDIDATES.write_text(json.dumps(queue, indent=1, ensure_ascii=False),
                          encoding="utf-8")
    with REPORT.open("w", newline="", encoding="utf-8") as f:
        wcsv = csv.writer(f)
        wcsv.writerow(["source", "title", "year", "imdbID", "pdEvidence"])
        wcsv.writerows(report_rows)
    print(f"[wants] queued → {CANDIDATES}", flush=True)
    print(f"[wants] report → {REPORT}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
