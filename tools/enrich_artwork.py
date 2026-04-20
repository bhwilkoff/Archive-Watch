#!/usr/bin/env python3
"""
enrich_artwork.py — add poster/backdrop/cast/genre metadata to the
federated video registry, for works the base pipeline couldn't enrich.

Three passes, fastest + highest-quality first:

  1. TMDb /find/{imdb_id}     — for items where Archive's external-identifier
                                gave us an IMDb ID. Hits ~4 req/sec. Returns
                                TMDb poster + backdrop + overview + cast +
                                genres in one call pair. Highest quality.

  2. Wikidata batched SPARQL  — for remaining items with Archive IA IDs.
                                Queries 200 IA IDs per request (small enough
                                to complete in ~5 sec each), collects P18
                                (Commons poster), P57 (director), P161 (cast),
                                P136 (genre). The original broad query timed
                                out; batching by known IA IDs avoids that.

  3. Archive thumbnail URL    — universal fallback:
                                https://archive.org/services/img/{id}
                                Low-quality (first frame), but it's something
                                visual while the app's procedural fallback
                                would otherwise take over. Tagged with
                                artwork_source='archive' so hasRealArtwork
                                stays false in the exporter — the app
                                still renders a designed procedural poster
                                when it wants one.

Reads TMDb bearer token from, in priority order:
    TMDB_BEARER_TOKEN env var
    Secrets.xcconfig at repo root

Zero state beyond the DB; safe to re-run. Uses INSERT OR IGNORE so
existing enrichment rows survive; updates posters and archive-fallback
URLs on the poster_url column specifically.

Usage:
    python tools/enrich_artwork.py                  # all three passes
    python tools/enrich_artwork.py --only tmdb      # just one
    python tools/enrich_artwork.py --only wikidata
    python tools/enrich_artwork.py --only archive
    python tools/enrich_artwork.py --limit 100      # smoke test
"""

import argparse
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path

import requests

REPO = Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO / "video_registry.db"

TMDB_API       = "https://api.themoviedb.org/3"
TMDB_IMG_BASE  = "https://image.tmdb.org/t/p/w500"
TMDB_BDROP_URL = "https://image.tmdb.org/t/p/w1280"
WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"
USER_AGENT = "ArchiveWatch-Enrichment/1.0 (learningischange.com) python-requests"


# ---------------------------------------------------------------------------
# TMDb token
# ---------------------------------------------------------------------------

def load_tmdb_token():
    tok = os.environ.get("TMDB_BEARER_TOKEN")
    if tok:
        return tok
    secrets = REPO / "Secrets.xcconfig"
    if secrets.exists():
        for line in secrets.read_text(encoding="utf-8").splitlines():
            m = re.match(r"\s*TMDB_BEARER_TOKEN\s*=\s*(\S+)", line)
            if m:
                return m.group(1).strip()
    return None


# ---------------------------------------------------------------------------
# Pass 1: TMDb /find
# ---------------------------------------------------------------------------

def tmdb_find_by_imdb(token, imdb_id, session):
    """Call TMDb /find/{imdb_id}. Returns (movie_dict or None, tv_dict or None)."""
    url = f"{TMDB_API}/find/{imdb_id}"
    r = session.get(
        url,
        headers={"Authorization": f"Bearer {token}",
                 "User-Agent": USER_AGENT},
        params={"external_source": "imdb_id"},
        timeout=20,
    )
    if r.status_code == 404:
        return None, None
    r.raise_for_status()
    data = r.json()
    movie = (data.get("movie_results")    or [None])[0]
    tv    = (data.get("tv_results")       or [None])[0]
    return movie, tv


def tmdb_movie_detail(token, tmdb_id, session):
    """Pull cast + genres + runtime in one /movie/{id}?append_to_response=credits."""
    url = f"{TMDB_API}/movie/{tmdb_id}"
    r = session.get(
        url,
        headers={"Authorization": f"Bearer {token}",
                 "User-Agent": USER_AGENT},
        params={"append_to_response": "credits"},
        timeout=20,
    )
    if r.status_code != 200:
        return None
    return r.json()


def enrich_via_tmdb(conn, token, *, limit=None):
    """Pass 1: for every work with an IMDb ID but no TMDb poster,
    hit /find and /movie/{id} to fill enrichment."""
    cur = conn.execute("""
        SELECT e.canonical_id, e.imdb_id
        FROM enrichment e
        LEFT JOIN works w ON w.canonical_id = e.canonical_id
        WHERE e.imdb_id IS NOT NULL
          AND (e.poster_url IS NULL OR e.poster_url = '')
        ORDER BY w.popularity_score DESC
    """)
    rows = cur.fetchall()
    if limit:
        rows = rows[:limit]
    total = len(rows)
    if total == 0:
        print("[tmdb] nothing to enrich — all IMDb-ID'd items already have posters", flush=True)
        return 0
    print(f"[tmdb] enriching {total:,} items with posters + cast", flush=True)

    session = requests.Session()
    got = failed = 0
    for i, (cid, imdb_id) in enumerate(rows, start=1):
        try:
            movie, tv = tmdb_find_by_imdb(token, imdb_id, session)
        except Exception as e:
            failed += 1
            if i % 50 == 0:
                print(f"  [tmdb] err {type(e).__name__} at {i}/{total}", flush=True)
            continue

        pick = movie or tv
        if not pick:
            failed += 1
        else:
            poster   = pick.get("poster_path")
            backdrop = pick.get("backdrop_path")
            tmdb_id  = pick.get("id")
            overview = pick.get("overview")
            # One extra call for credits (cast + crew)
            detail = tmdb_movie_detail(token, tmdb_id, session) if movie else None
            cast = []
            directors = []
            genres = []
            runtime_sec = None
            if detail:
                credits = detail.get("credits") or {}
                cast = [p.get("name") for p in (credits.get("cast") or [])[:10] if p.get("name")]
                directors = [p.get("name") for p in (credits.get("crew") or [])
                             if p.get("job") == "Director" and p.get("name")]
                genres = [g.get("name") for g in (detail.get("genres") or []) if g.get("name")]
                if detail.get("runtime"):
                    runtime_sec = int(detail["runtime"]) * 60

            conn.execute("""
                UPDATE enrichment SET
                    tmdb_id       = COALESCE(?, tmdb_id),
                    poster_url    = COALESCE(?, poster_url),
                    directors     = COALESCE(?, directors),
                    cast_list     = COALESCE(?, cast_list),
                    genres        = COALESCE(?, genres)
                WHERE canonical_id = ?
            """, (
                str(tmdb_id) if tmdb_id else None,
                f"{TMDB_IMG_BASE}{poster}" if poster else None,
                json.dumps(directors) if directors else None,
                json.dumps(cast) if cast else None,
                json.dumps(genres) if genres else None,
                cid,
            ))
            # Fill runtime on works if still unset.
            if runtime_sec:
                conn.execute(
                    "UPDATE works SET runtime_sec = COALESCE(runtime_sec, ?) WHERE canonical_id = ?",
                    (runtime_sec, cid),
                )
            got += 1

        if i % 100 == 0:
            conn.commit()
            print(f"  [tmdb] {got:,} ok, {failed:,} failed  ({i:,}/{total:,})", flush=True)
        # TMDb: 40 req / 10 sec → 0.25s per is safe. We also issue a second
        # call per success (detail), so throttle harder.
        time.sleep(0.28)

    conn.commit()
    print(f"[tmdb] done: {got:,} enriched, {failed:,} failed (of {total:,})", flush=True)
    return got


# ---------------------------------------------------------------------------
# Pass 2: Wikidata in batches by IA ID
# ---------------------------------------------------------------------------

WIKIDATA_BATCH_QUERY = """
SELECT ?film ?iaID
       (SAMPLE(?image) AS ?poster)
       (SAMPLE(?imdbID) AS ?imdbIDValue)
       (SAMPLE(?tmdbID) AS ?tmdbIDValue)
       (SAMPLE(?article) AS ?articleValue)
       (GROUP_CONCAT(DISTINCT ?directorLabel; separator="|") AS ?directors)
       (GROUP_CONCAT(DISTINCT ?castLabel;     separator="|") AS ?cast)
       (GROUP_CONCAT(DISTINCT ?genreLabel;    separator="|") AS ?genres)
WHERE {
  VALUES ?iaID { %VALUES% }
  ?film wdt:P724 ?iaID .
  OPTIONAL { ?film wdt:P18   ?image }
  OPTIONAL { ?film wdt:P345  ?imdbID }
  OPTIONAL { ?film wdt:P4947 ?tmdbID }
  OPTIONAL {
    ?article schema:about ?film ;
             schema:isPartOf <https://en.wikipedia.org/> .
  }
  OPTIONAL {
    ?film wdt:P57 ?director .
    ?director rdfs:label ?directorLabel . FILTER(LANG(?directorLabel) = "en")
  }
  OPTIONAL {
    ?film wdt:P161 ?castMember .
    ?castMember rdfs:label ?castLabel . FILTER(LANG(?castLabel) = "en")
  }
  OPTIONAL {
    ?film wdt:P136 ?genre .
    ?genre rdfs:label ?genreLabel . FILTER(LANG(?genreLabel) = "en")
  }
}
GROUP BY ?film ?iaID
"""

def enrich_via_wikidata(conn, *, batch_size=150, limit=None):
    """Pass 2: for works with an archive_org source but no TMDb/Wikidata
    enrichment yet, batch-query Wikidata by IA ID."""
    cur = conn.execute("""
        SELECT s.source_id, s.canonical_id
        FROM sources s
        LEFT JOIN enrichment e ON e.canonical_id = s.canonical_id
        WHERE s.source_type = 'archive_org'
          AND (e.poster_url IS NULL OR e.poster_url = '')
    """)
    todo = cur.fetchall()
    if limit:
        todo = todo[:limit]
    total = len(todo)
    if total == 0:
        print("[wd] nothing to enrich", flush=True)
        return 0
    print(f"[wd] querying Wikidata for {total:,} IA IDs in batches of {batch_size}", flush=True)

    session = requests.Session()
    enriched = 0
    for i in range(0, total, batch_size):
        batch = todo[i:i+batch_size]
        id_to_cid = {ia: cid for ia, cid in batch}
        values = " ".join(f'"{ia}"' for ia in id_to_cid.keys())
        query = WIKIDATA_BATCH_QUERY.replace("%VALUES%", values)
        try:
            r = session.get(
                WIKIDATA_SPARQL,
                params={"query": query, "format": "json"},
                headers={"User-Agent": USER_AGENT,
                         "Accept": "application/sparql-results+json"},
                timeout=60,
            )
            r.raise_for_status()
            bindings = r.json()["results"]["bindings"]
        except Exception as e:
            print(f"  [wd] batch {i//batch_size+1} failed: {e}", flush=True)
            time.sleep(2)
            continue

        for b in bindings:
            ia_id = b.get("iaID", {}).get("value")
            cid = id_to_cid.get(ia_id)
            if not cid:
                continue
            poster = b.get("poster", {}).get("value")
            imdb   = b.get("imdbIDValue", {}).get("value")
            tmdb   = b.get("tmdbIDValue", {}).get("value")
            wiki   = b.get("articleValue", {}).get("value")
            dirs   = [s for s in b.get("directors", {}).get("value", "").split("|") if s]
            cast   = [s for s in b.get("cast",      {}).get("value", "").split("|") if s]
            genres = [s for s in b.get("genres",    {}).get("value", "").split("|") if s]

            # Commons File: URLs need unwrapping — Wikidata returns the
            # File page, we want the actual image URL via Special:FilePath.
            if poster and "commons.wikimedia.org" in poster and "/Special:FilePath/" not in poster:
                # Skip if it's already a direct file URL
                pass

            conn.execute("""
                INSERT INTO enrichment (canonical_id, wikidata_qid, imdb_id, tmdb_id,
                                        wikipedia_url, directors, cast_list, genres,
                                        poster_url)
                VALUES (?,?,?,?,?,?,?,?,?)
                ON CONFLICT(canonical_id) DO UPDATE SET
                    wikidata_qid   = COALESCE(enrichment.wikidata_qid, excluded.wikidata_qid),
                    imdb_id        = COALESCE(enrichment.imdb_id,      excluded.imdb_id),
                    tmdb_id        = COALESCE(enrichment.tmdb_id,      excluded.tmdb_id),
                    wikipedia_url  = COALESCE(enrichment.wikipedia_url, excluded.wikipedia_url),
                    directors      = COALESCE(enrichment.directors,    excluded.directors),
                    cast_list      = COALESCE(enrichment.cast_list,    excluded.cast_list),
                    genres         = COALESCE(enrichment.genres,       excluded.genres),
                    poster_url     = COALESCE(enrichment.poster_url,   excluded.poster_url)
            """, (
                cid,
                b["film"]["value"].rsplit("/", 1)[-1] if b.get("film") else None,
                imdb, tmdb, wiki,
                json.dumps(dirs) if dirs else None,
                json.dumps(cast) if cast else None,
                json.dumps(genres) if genres else None,
                poster,
            ))
            enriched += 1

        conn.commit()
        done = min(i + batch_size, total)
        print(f"  [wd] {done:,}/{total:,}  matched so far: {enriched:,}", flush=True)
        time.sleep(1.5)  # polite — q.w.o is rate-sensitive

    print(f"[wd] done: {enriched:,} items matched", flush=True)
    return enriched


# ---------------------------------------------------------------------------
# Pass 3: Archive.org thumbnail fallback
# ---------------------------------------------------------------------------

def fill_archive_thumbnails(conn, *, limit=None):
    """Pass 3: for every remaining archive_org source without a poster_url,
    fill in https://archive.org/services/img/{id} as a fallback. The exporter's
    artwork_source_for() classifies this as 'archive' → hasRealArtwork=False,
    so the app still uses its procedural poster. But the URL is valid if the
    UI wants to render a thumbnail somewhere else (hero backdrop, etc.)."""
    cur = conn.execute("""
        SELECT s.source_id, s.canonical_id
        FROM sources s
        LEFT JOIN enrichment e ON e.canonical_id = s.canonical_id
        WHERE s.source_type = 'archive_org'
          AND (e.poster_url IS NULL OR e.poster_url = '')
    """)
    todo = cur.fetchall()
    if limit:
        todo = todo[:limit]
    total = len(todo)
    print(f"[archive] filling thumbnail fallback for {total:,} items", flush=True)
    n = 0
    for ia_id, cid in todo:
        url = f"https://archive.org/services/img/{ia_id}"
        conn.execute("""
            INSERT INTO enrichment (canonical_id, poster_url)
            VALUES (?, ?)
            ON CONFLICT(canonical_id) DO UPDATE SET
                poster_url = COALESCE(enrichment.poster_url, excluded.poster_url)
        """, (cid, url))
        n += 1
        if n % 5000 == 0:
            conn.commit()
            print(f"  [archive] {n:,}/{total:,}", flush=True)
    conn.commit()
    print(f"[archive] done: {n:,} thumbnails filled", flush=True)
    return n


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--only", choices=["tmdb", "wikidata", "archive"])
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)

    if args.only in (None, "tmdb"):
        tok = load_tmdb_token()
        if not tok:
            print("[tmdb] no TMDB_BEARER_TOKEN in env or Secrets.xcconfig — "
                  "skipping pass 1", file=sys.stderr)
        else:
            enrich_via_tmdb(conn, tok, limit=args.limit)

    if args.only in (None, "wikidata"):
        enrich_via_wikidata(conn, limit=args.limit)

    if args.only in (None, "archive"):
        fill_archive_thumbnails(conn, limit=args.limit)

    conn.close()


if __name__ == "__main__":
    main()
