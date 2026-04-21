#!/usr/bin/env python3
"""
enrich_artwork.py — add poster/backdrop/cast/genre metadata to the
federated video registry, for works the base pipeline couldn't enrich.

Passes, ordered from highest-quality-designed-art to last-resort fallback.
Each pass COALESCEs into enrichment.poster_url so earlier wins stick.

  1. TMDb /find/{imdb_id}     — the primary designed-art source. Returns
                                TMDb poster + backdrop + overview + cast +
                                genres in one call pair.

  2. Fanart.tv                — secondary designed-art source keyed on
                                IMDb ID. Community-curated "movieposter"
                                artwork — fills gaps for older + cult
                                films that TMDb missed. Requires
                                FANART_TV_KEY.

  3. OMDb                     — third designed-art source keyed on IMDb ID.
                                Pulls `Poster` which is a high-res
                                Amazon-hosted poster. Requires OMDB_KEY.

  4. LoC raw_json             — zero-network: extract resources[0].poster
                                from the sources.raw_json already in the DB
                                for loc-sourced items.

  5. Wikidata batched SPARQL  — for remaining items with Archive IA IDs.
                                Queries 80 IA IDs per request, collects P18
                                (Commons poster), P57 (director), P161
                                (cast), P136 (genre).

  6. TMDb /search/movie       — title + year fuzzy-match for items lacking
                                IMDb IDs, guarded by Dice bigram similarity
                                ≥ 0.82 + ±1y year check.

  7. Wikipedia pageimages     — lead infobox image, good hit rate for older
                                films with Wikipedia articles.

  8. AAPB thumbnail           — HEAD-verified stills from American Archive
                                of Public Broadcasting for aapb-sourced
                                items. Real stills from the program, marked
                                as designed-ish art (hasRealArtwork=true).

  9. Archive.org thumbnail    — universal last-resort fallback:
                                services/img/{id}. First-frame grab, tagged
                                artwork_source='archive' so the app treats
                                it as non-designed and falls back to its
                                procedural poster card.

Reads secrets from (priority order):
    env:    TMDB_BEARER_TOKEN, FANART_TV_KEY, OMDB_KEY
    file:   Secrets.xcconfig at repo root (same keys)

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
WIKIPEDIA_API  = "https://en.wikipedia.org/w/api.php"
FANART_API     = "https://webservice.fanart.tv/v3/movies"
OMDB_API       = "https://www.omdbapi.com/"
AAPB_THUMB_TPL = "https://s3.amazonaws.com/americanarchive.org/thumbnail/{id}.jpg"
TVMAZE_API     = "https://api.tvmaze.com"
USER_AGENT = "ArchiveWatch-Enrichment/1.0 (learningischange.com) python-requests"


# ---------------------------------------------------------------------------
# Fuzzy title matching (for TMDb search-by-title without IMDb ID)
# ---------------------------------------------------------------------------
# Ported from the JS builder's Dice bigram similarity. When TMDb's /search
# returns a candidate, we verify title+year match before accepting — skips
# false positives when an obscure Archive item happens to have the same
# title as a famous film.

def _bigrams(s):
    s = re.sub(r"[^a-z0-9]", "", s.lower())
    return {s[i:i+2] for i in range(len(s) - 1)} if len(s) > 1 else set()

def dice_similarity(a, b):
    ba, bb = _bigrams(a), _bigrams(b)
    if not ba or not bb:
        return 0.0
    return 2 * len(ba & bb) / (len(ba) + len(bb))


def normalize_title(t):
    """Normalize for comparison: strip parenthetical year, punctuation, articles."""
    if not t: return ""
    t = re.sub(r"\(\d{4}\)", "", str(t))
    t = re.sub(r"[^\w\s]", " ", t, flags=re.UNICODE)
    t = re.sub(r"\s+", " ", t).strip().lower()
    for art in ("the ", "a ", "an ", "le ", "la ", "les ", "el "):
        if t.startswith(art):
            t = t[len(art):]
            break
    return t


def extract_series_title(title):
    """Boil a messy Archive TV episode title down to its series name.
    Archive TV uploads are noisy — 'Dragnet - Episode #18 The Big Seventeen',
    'Twilight Zone 1959 S01', 'Green Acres Complete Series', Petticoat
    Junction "Spur Line To Shady Rest". The series name is always the
    prefix; we strip the episode/season/series chrome so the TV search
    APIs can match the show."""
    if not title: return ""
    t = str(title)
    # 1. Quoted episode name — everything after (and including) the first
    #    quotation mark is episode-level chrome. '"Thriller" Caldera' is
    #    the one exception where the quote STARTS the title; handle by
    #    stripping leading+trailing quotes first.
    t_stripped = t.strip().strip('"').strip("'").strip()
    if '"' in t_stripped or "'" in t_stripped:
        # If there's a lingering inner quote, cut at it.
        for q in ('"', "'"):
            idx = t_stripped.find(q)
            if idx > 0:
                t_stripped = t_stripped[:idx]
                break
    t = t_stripped
    # 2. Cut at episode/part separators.
    for sep in (" - Episode", " - episode", " Episode #", " episode #",
                " Episode ", " episode ", " - Ep ", " - ep ",
                " - ", " — ", " – ", " | ", ": ", "—"):
        idx = t.find(sep)
        if idx > 0:
            t = t[:idx]
            break
    # 3. Strip trailing S##E## / S## / Season ## / season ## markers.
    t = re.sub(r"\s+S\d+(\s*E\d+)?\b.*$", "", t, flags=re.IGNORECASE)
    t = re.sub(r"\s+Season\s+\d+.*$", "", t, flags=re.IGNORECASE)
    # 4. Strip "Complete Series/Season", "Collection", "Miniseries" suffixes.
    t = re.sub(
        r"\s*[\(\[]?\s*(complete|collection|series|season|miniseries|"
        r"disc\s*\d+|part\s*\d+|vol(ume)?\s*\d+|\d+\s*episodes?)\b.*$",
        "", t, flags=re.IGNORECASE,
    )
    # 5. Strip ANY (YYYY) parenthetical — whatever follows is episode
    #    chrome, not series chrome ('The Three Stooges (1950) Colorized').
    t = re.sub(r"\s*\(\s*\d{4}\s*\).*$", "", t)
    # 6. Collapse whitespace, drop stray punctuation.
    t = t.strip(" -.,;:[](){}\u2013\u2014")
    return re.sub(r"\s+", " ", t).strip()


# ---------------------------------------------------------------------------
# Secret loader (env → Secrets.xcconfig → None)
# ---------------------------------------------------------------------------

def load_secret(name):
    v = os.environ.get(name)
    if v:
        return v.strip()
    secrets = REPO / "Secrets.xcconfig"
    if secrets.exists():
        # xcconfig strips comments — but a stray // inside a token would
        # break the file for Xcode anyway, so the naive regex is fine.
        pat = re.compile(rf"\s*{re.escape(name)}\s*=\s*(\S+)")
        for line in secrets.read_text(encoding="utf-8").splitlines():
            m = pat.match(line)
            if m:
                return m.group(1).strip()
    return None


def load_tmdb_token():
    return load_secret("TMDB_BEARER_TOKEN")


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

def enrich_via_wikidata(conn, *, batch_size=80, limit=None):
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
            # POST avoids the 414 URI-too-long when long Archive IDs
            # push a URL-encoded GET past the 8k limit.
            r = session.post(
                WIKIDATA_SPARQL,
                data={"query": query, "format": "json"},
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
# Pass 2.5: LoC posters from stored raw_json
# ---------------------------------------------------------------------------
# LoC's API returns `image_url` and `resources[0].poster` as part of each
# item record. Those are already in the sources.raw_json blob. Extract
# them into the enrichment table — zero network calls.

def enrich_via_loc(conn, *, limit=None):
    cur = conn.execute("""
        SELECT s.canonical_id, s.raw_json
        FROM sources s
        LEFT JOIN enrichment e ON e.canonical_id = s.canonical_id
        WHERE s.source_type = 'loc'
          AND (e.poster_url IS NULL OR e.poster_url = '')
    """)
    todo = cur.fetchall()
    if limit:
        todo = todo[:limit]
    total = len(todo)
    print(f"[loc] extracting posters from {total:,} LoC raw_json blobs", flush=True)
    got = 0
    for cid, raw in todo:
        try:
            d = json.loads(raw)
        except Exception:
            continue
        # Prefer resources[0].poster (the actual still frame) over image_url
        # (which is the animated GIF thumbnail). LoC's fields are
        # inconsistently list-or-scalar across items — handle both.
        def _first_str(v):
            if isinstance(v, list):
                for x in v:
                    if isinstance(x, str) and x:
                        return x
                return None
            return v if isinstance(v, str) and v else None

        poster = None
        res = d.get("resources")
        if isinstance(res, list) and res:
            first = res[0] if isinstance(res[0], dict) else {}
            poster = _first_str(first.get("poster")) or _first_str(first.get("image"))
        if not poster:
            poster = _first_str(d.get("image_url"))
        if not poster:
            continue
        # LoC URLs sometimes come with leading `//` — normalize to https.
        if poster.startswith("//"):
            poster = "https:" + poster
        conn.execute("""
            INSERT INTO enrichment (canonical_id, poster_url)
            VALUES (?, ?)
            ON CONFLICT(canonical_id) DO UPDATE SET
                poster_url = COALESCE(enrichment.poster_url, excluded.poster_url)
        """, (cid, poster))
        got += 1
    conn.commit()
    print(f"[loc] done: {got:,} LoC posters filled", flush=True)
    return got


# ---------------------------------------------------------------------------
# Pass 2.6: TMDb search-by-title for items without IMDb IDs
# ---------------------------------------------------------------------------
# Many catalog items lack IMDb IDs but have recognizable titles. TMDb's
# /search/movie accepts title + optional year. Risk: false positives when
# a title matches something unrelated. Guard with:
#   1. year must match within ±1 year (if known)
#   2. Dice bigram similarity ≥ 0.82 on normalized titles
#   3. only the first result is considered (TMDb sorts by popularity)

def tmdb_search_movie(token, title, year, session):
    url = f"{TMDB_API}/search/movie"
    params = {"query": title, "include_adult": "false"}
    if year:
        params["year"] = str(year)
    r = session.get(
        url,
        headers={"Authorization": f"Bearer {token}", "User-Agent": USER_AGENT},
        params=params,
        timeout=20,
    )
    if r.status_code != 200:
        return []
    return (r.json().get("results") or [])[:5]


def enrich_via_tmdb_search(conn, token, *, limit=None, similarity_threshold=0.82):
    """Pass 2.6: For works without poster_url AND without imdb_id, try
    TMDb /search/movie by title+year, verify by fuzzy match + year check."""
    cur = conn.execute("""
        SELECT w.canonical_id, w.title, w.year
        FROM works w
        LEFT JOIN enrichment e ON e.canonical_id = w.canonical_id
        WHERE (e.poster_url IS NULL OR e.poster_url = '')
          AND (e.imdb_id    IS NULL OR e.imdb_id    = '')
          AND w.work_type IN ('feature_film', 'short_film', 'documentary',
                              'animated_short', 'tv_movie')
          AND w.quality_score    >= 45
          AND w.popularity_score >= 40
          AND w.title IS NOT NULL
        ORDER BY w.popularity_score DESC
    """)
    rows = cur.fetchall()
    if limit:
        rows = rows[:limit]
    total = len(rows)
    if total == 0:
        print("[tmdb-search] nothing to search — all likely candidates already enriched", flush=True)
        return 0
    print(f"[tmdb-search] searching {total:,} titles (threshold={similarity_threshold})", flush=True)

    session = requests.Session()
    got = rejected = 0
    for i, (cid, title, year) in enumerate(rows, start=1):
        try:
            results = tmdb_search_movie(token, title, year, session)
        except Exception:
            results = []
        pick = None
        for r in results:
            cand_title = r.get("title") or r.get("original_title") or ""
            cand_year  = None
            if r.get("release_date"):
                m = re.match(r"(\d{4})", str(r["release_date"]))
                if m: cand_year = int(m.group(1))
            # Year gate
            if year and cand_year and abs(cand_year - year) > 1:
                continue
            # Similarity gate
            sim = dice_similarity(normalize_title(title), normalize_title(cand_title))
            if sim >= similarity_threshold:
                pick = (r, sim)
                break

        if pick:
            r, sim = pick
            poster = r.get("poster_path")
            tmdb_id = r.get("id")
            conn.execute("""
                INSERT INTO enrichment (canonical_id, tmdb_id, poster_url)
                VALUES (?, ?, ?)
                ON CONFLICT(canonical_id) DO UPDATE SET
                    tmdb_id    = COALESCE(enrichment.tmdb_id, excluded.tmdb_id),
                    poster_url = COALESCE(enrichment.poster_url, excluded.poster_url)
            """, (
                cid, str(tmdb_id) if tmdb_id else None,
                f"{TMDB_IMG_BASE}{poster}" if poster else None,
            ))
            got += 1
        else:
            rejected += 1

        if i % 100 == 0:
            conn.commit()
            print(f"  [tmdb-search] matched {got:,}, rejected {rejected:,}  ({i:,}/{total:,})", flush=True)
        time.sleep(0.28)  # respect TMDb 40/10s
    conn.commit()
    print(f"[tmdb-search] done: {got:,} matched, {rejected:,} rejected", flush=True)
    return got


# ---------------------------------------------------------------------------
# Pass 2.7: Wikipedia pageimages lookup
# ---------------------------------------------------------------------------
# Wikipedia's MediaWiki API exposes pageimages for any article — often the
# infobox lead image. Cheap to query (no key), good cultural hit rate for
# older + obscure films that have Wikipedia articles but missing TMDb data.

def wikipedia_pageimages(title, session):
    """Resolve `title` to a Wikipedia article (with redirect-following) and
    return its lead image URL. Returns (article_url, image_url) or None."""
    r = session.get(
        WIKIPEDIA_API,
        params={
            "action": "query", "format": "json",
            "prop": "pageimages|info",
            "inprop": "url",
            "redirects": "1",
            "piprop": "original",
            "titles": title,
        },
        headers={"User-Agent": USER_AGENT},
        timeout=15,
    )
    if r.status_code != 200:
        return None
    pages = r.json().get("query", {}).get("pages", {}) or {}
    for _, page in pages.items():
        if page.get("missing") is not None:
            continue
        img = (page.get("original") or {}).get("source")
        url = page.get("fullurl")
        if img:
            return (url, img)
    return None


def enrich_via_wikipedia(conn, *, limit=None):
    """Pass 2.7: items still without poster_url, try Wikipedia pageimages."""
    cur = conn.execute("""
        SELECT w.canonical_id, w.title, w.year
        FROM works w
        LEFT JOIN enrichment e ON e.canonical_id = w.canonical_id
        WHERE (e.poster_url IS NULL OR e.poster_url = '')
          AND w.quality_score    >= 50
          AND w.popularity_score >= 45
          AND w.title IS NOT NULL
        ORDER BY w.popularity_score DESC
    """)
    rows = cur.fetchall()
    if limit:
        rows = rows[:limit]
    total = len(rows)
    if total == 0:
        print("[wikipedia] nothing to search", flush=True)
        return 0
    print(f"[wikipedia] querying {total:,} pageimages", flush=True)

    session = requests.Session()
    got = failed = 0
    for i, (cid, title, year) in enumerate(rows, start=1):
        # Try "Title (year film)" first — Wikipedia's disambiguation
        # convention. Fall back to bare title.
        attempts = []
        if year:
            attempts.append(f"{title} ({year} film)")
            attempts.append(f"{title} ({year})")
        attempts.append(title)

        match = None
        for t in attempts:
            try:
                m = wikipedia_pageimages(t, session)
            except Exception:
                m = None
            if m:
                match = m
                break

        if match:
            article, img = match
            conn.execute("""
                INSERT INTO enrichment (canonical_id, wikipedia_url, poster_url)
                VALUES (?, ?, ?)
                ON CONFLICT(canonical_id) DO UPDATE SET
                    wikipedia_url = COALESCE(enrichment.wikipedia_url, excluded.wikipedia_url),
                    poster_url    = COALESCE(enrichment.poster_url,    excluded.poster_url)
            """, (cid, article, img))
            got += 1
        else:
            failed += 1

        if i % 100 == 0:
            conn.commit()
            print(f"  [wikipedia] matched {got:,}, none {failed:,}  ({i:,}/{total:,})", flush=True)
        time.sleep(0.2)  # polite
    conn.commit()
    print(f"[wikipedia] done: {got:,} matched", flush=True)
    return got


# ---------------------------------------------------------------------------
# Pass: Fanart.tv (IMDb-ID → designed movieposter)
# ---------------------------------------------------------------------------
# Fanart.tv hosts community-curated artwork. For `movies`, the key fields
# are `movieposter` (ranked by likes) and `moviebackground`. Coverage is
# especially good for older + cult titles TMDb has passed over.
#
# API shape: GET /v3/movies/{imdb_id}?api_key=KEY
#   → { "movieposter": [{url, lang, likes}, ...],
#       "moviebackground": [{url, lang, likes}, ...], ... }
# A 404 means "no artwork known" — benign.
#
# Rate limit: the personal key tier is ~5 req/sec, well within reach.

def fanarttv_lookup(imdb_id, api_key, session):
    url = f"{FANART_API}/{imdb_id}"
    r = session.get(
        url,
        params={"api_key": api_key},
        headers={"User-Agent": USER_AGENT},
        timeout=20,
    )
    if r.status_code == 404:
        return None
    if r.status_code != 200:
        return None
    return r.json()


def _best_fanart_url(items, prefer_lang="en"):
    """Pick the best artwork URL from a Fanart.tv list — prefer English,
    fall back to any, break ties on `likes`."""
    if not items:
        return None
    eng = [x for x in items if (x.get("lang") or "").lower() in (prefer_lang, "00")]
    pool = eng or items
    pool = sorted(pool, key=lambda x: int(x.get("likes") or 0), reverse=True)
    return pool[0].get("url")


def enrich_via_fanarttv(conn, api_key, *, limit=None):
    """Items with IMDb IDs whose poster is missing or only an Archive
    first-frame thumbnail → try Fanart.tv for real designed art."""
    cur = conn.execute("""
        SELECT e.canonical_id, e.imdb_id
        FROM enrichment e
        LEFT JOIN works w ON w.canonical_id = e.canonical_id
        WHERE e.imdb_id IS NOT NULL
          AND (e.poster_url IS NULL
               OR e.poster_url = ''
               OR e.poster_url LIKE 'https://archive.org/services/img/%')
        ORDER BY w.popularity_score DESC
    """)
    rows = cur.fetchall()
    if limit:
        rows = rows[:limit]
    total = len(rows)
    if total == 0:
        print("[fanart] nothing to enrich", flush=True)
        return 0
    print(f"[fanart] trying {total:,} items with IMDb IDs but no poster", flush=True)

    session = requests.Session()
    got = miss = 0
    for i, (cid, imdb_id) in enumerate(rows, start=1):
        try:
            data = fanarttv_lookup(imdb_id, api_key, session)
        except Exception:
            data = None
        poster = _best_fanart_url((data or {}).get("movieposter")) if data else None
        if poster:
            # Overwrite only if current is null/empty/archive-thumbnail;
            # keep earlier higher-quality TMDb/Wikidata/Commons wins.
            conn.execute("""
                UPDATE enrichment SET
                    poster_url = ?
                WHERE canonical_id = ?
                  AND (poster_url IS NULL
                       OR poster_url = ''
                       OR poster_url LIKE 'https://archive.org/services/img/%')
            """, (poster, cid))
            got += 1
        else:
            miss += 1
        if i % 100 == 0:
            conn.commit()
            print(f"  [fanart] matched {got:,}, missed {miss:,}  ({i:,}/{total:,})", flush=True)
        time.sleep(0.22)  # ~4.5 req/sec, under Fanart's personal-key ceiling
    conn.commit()
    print(f"[fanart] done: {got:,} matched, {miss:,} missed", flush=True)
    return got


# ---------------------------------------------------------------------------
# Pass: OMDb (IMDb-ID → Poster)
# ---------------------------------------------------------------------------
# OMDb returns a single `Poster` URL per IMDb ID — usually the IMDb /
# Amazon-hosted promotional image. Historically free tier was 1000
# req/day; the patreon tier raises that. API responds `"Response": "False"`
# with an `Error` field when unknown.

def omdb_lookup(imdb_id, api_key, session):
    r = session.get(
        OMDB_API,
        params={"i": imdb_id, "apikey": api_key},
        headers={"User-Agent": USER_AGENT},
        timeout=20,
    )
    if r.status_code != 200:
        return None
    d = r.json()
    if str(d.get("Response", "")).lower() != "true":
        return None
    return d


def enrich_via_omdb(conn, api_key, *, limit=None):
    """Items with IMDb IDs still lacking designed art → ask OMDb. Archive
    thumbnails count as "still lacking" since OMDb is an upgrade."""
    cur = conn.execute("""
        SELECT e.canonical_id, e.imdb_id
        FROM enrichment e
        LEFT JOIN works w ON w.canonical_id = e.canonical_id
        WHERE e.imdb_id IS NOT NULL
          AND (e.poster_url IS NULL
               OR e.poster_url = ''
               OR e.poster_url LIKE 'https://archive.org/services/img/%')
        ORDER BY w.popularity_score DESC
    """)
    rows = cur.fetchall()
    if limit:
        rows = rows[:limit]
    total = len(rows)
    if total == 0:
        print("[omdb] nothing to enrich", flush=True)
        return 0
    print(f"[omdb] trying {total:,} items with IMDb IDs but no poster", flush=True)

    session = requests.Session()
    got = miss = 0
    for i, (cid, imdb_id) in enumerate(rows, start=1):
        try:
            data = omdb_lookup(imdb_id, api_key, session)
        except Exception:
            data = None
        poster = None
        if data:
            p = data.get("Poster")
            # OMDb returns "N/A" (literal string) when they have no image
            if p and p != "N/A":
                poster = p
        if poster:
            # Same overwrite rule as Fanart: only replace null/empty/archive-thumb.
            conn.execute("""
                UPDATE enrichment SET
                    poster_url = ?
                WHERE canonical_id = ?
                  AND (poster_url IS NULL
                       OR poster_url = ''
                       OR poster_url LIKE 'https://archive.org/services/img/%')
            """, (poster, cid))
            got += 1
        else:
            miss += 1
        if i % 100 == 0:
            conn.commit()
            print(f"  [omdb] matched {got:,}, missed {miss:,}  ({i:,}/{total:,})", flush=True)
        # Free tier is 1000/day — we throttle lightly here and rely on
        # the IMDb-ID pool (~1–3k items) fitting under that daily cap.
        time.sleep(0.15)
    conn.commit()
    print(f"[omdb] done: {got:,} matched, {miss:,} missed", flush=True)
    return got


# ---------------------------------------------------------------------------
# Pass: TMDb /search/tv  (fuzzy-match TV shows by series title + year)
# ---------------------------------------------------------------------------
# All prior TMDb passes key on IMDb ID — but Archive.org rarely surfaces
# IMDb IDs for TV items, so we skip ~1k classic-TV items despite TMDb
# having data for every one of them. This pass hits /search/tv with the
# series title (extracted from the messy Archive episode title) and the
# year. Match gated by Dice bigram similarity + ±1y year check — same
# rigor as the movies search pass.

def tmdb_search_tv(token, title, session):
    """Title-only TMDb TV search. We DON'T pass first_air_date_year —
    that filters by premiere year, and Archive TV items carry the
    *episode* year which often lands years after the show started.
    Year filtering is done client-side with a wide plausibility window."""
    r = session.get(
        f"{TMDB_API}/search/tv",
        headers={"Authorization": f"Bearer {token}", "User-Agent": USER_AGENT},
        params={"query": title, "include_adult": "false"},
        timeout=20,
    )
    if r.status_code != 200:
        return []
    return (r.json().get("results") or [])[:5]


# SQL that picks TV-ish works missing designed art. We accept both
# strict tv_episode/tv_movie and 'unknown'-typed items that happen to
# live in classic_tv collections (very common — the pipeline's type
# classifier is conservative, so lots of TV is left as 'unknown').
_TV_CANDIDATE_SQL = """
SELECT DISTINCT w.canonical_id, w.title, w.year
FROM works w
LEFT JOIN enrichment e ON e.canonical_id = w.canonical_id
LEFT JOIN sources    s ON s.canonical_id = w.canonical_id
WHERE w.title IS NOT NULL
  AND (e.poster_url IS NULL
       OR e.poster_url = ''
       OR e.poster_url LIKE 'https://archive.org/services/img/%')
  AND (w.work_type IN ('tv_episode', 'tv_movie')
       OR (s.source_type = 'archive_org'
           AND (s.raw_json LIKE '%classic_tv%'
                OR s.raw_json LIKE '%"television"%')))
  AND w.quality_score    >= 30
  AND w.popularity_score >= 20
ORDER BY w.popularity_score DESC
"""


def enrich_via_tmdb_tv(conn, token, *, limit=None, similarity_threshold=0.82):
    rows = conn.execute(_TV_CANDIDATE_SQL).fetchall()
    if limit:
        rows = rows[:limit]
    total = len(rows)
    if total == 0:
        print("[tmdb-tv] nothing to enrich", flush=True)
        return 0
    print(f"[tmdb-tv] searching {total:,} TV titles (threshold={similarity_threshold})",
          flush=True)

    session = requests.Session()
    got = rejected = 0
    for i, (cid, raw_title, year) in enumerate(rows, start=1):
        title = extract_series_title(raw_title) or raw_title
        try:
            results = tmdb_search_tv(token, title, session)
        except Exception:
            results = []
        pick = None
        for r in results:
            cand_title = r.get("name") or r.get("original_name") or ""
            cand_year  = None
            if r.get("first_air_date"):
                m = re.match(r"(\d{4})", str(r["first_air_date"]))
                if m: cand_year = int(m.group(1))
            # Year plausibility: the candidate show must have *started* at
            # or before our year, plus a small slack (≤5y) for Archive
            # episodes labeled with air year vs. production year, AND no
            # more than ~30y later (rules out remakes by the same name).
            if year and cand_year:
                if cand_year > year + 5:     continue
                if cand_year < year - 40:    continue
            sim = dice_similarity(normalize_title(title), normalize_title(cand_title))
            if sim >= similarity_threshold:
                pick = r
                break
        if pick:
            poster  = pick.get("poster_path")
            tmdb_id = pick.get("id")
            # Upgrade-only: same predicate as Fanart/OMDb — never overwrite
            # designed art from a higher-quality earlier pass.
            conn.execute("""
                INSERT INTO enrichment (canonical_id, tmdb_id, poster_url)
                VALUES (?, ?, ?)
                ON CONFLICT(canonical_id) DO UPDATE SET
                    tmdb_id    = COALESCE(enrichment.tmdb_id, excluded.tmdb_id),
                    poster_url = CASE
                        WHEN enrichment.poster_url IS NULL
                          OR enrichment.poster_url = ''
                          OR enrichment.poster_url LIKE 'https://archive.org/services/img/%'
                        THEN excluded.poster_url
                        ELSE enrichment.poster_url
                    END
            """, (
                cid,
                str(tmdb_id) if tmdb_id else None,
                f"{TMDB_IMG_BASE}{poster}" if poster else None,
            ))
            got += 1
        else:
            rejected += 1
        if i % 100 == 0:
            conn.commit()
            print(f"  [tmdb-tv] matched {got:,}, rejected {rejected:,}  ({i:,}/{total:,})",
                  flush=True)
        time.sleep(0.28)
    conn.commit()
    print(f"[tmdb-tv] done: {got:,} matched, {rejected:,} rejected", flush=True)
    return got


# ---------------------------------------------------------------------------
# Pass: TVMaze (no key, strong classic-TV coverage)
# ---------------------------------------------------------------------------
# TVMaze is the fallback when TMDb's TV search misses — usually because
# TMDb simply doesn't carry a very old or regional show. /search/shows
# takes a free-text query and returns ranked results with image URLs.
# Rate limit: 20 req / 10s. Throttle 0.55s/req to stay comfortably
# under.

def tvmaze_search_shows(title, session):
    r = session.get(
        f"{TVMAZE_API}/search/shows",
        params={"q": title},
        headers={"User-Agent": USER_AGENT},
        timeout=15,
    )
    if r.status_code != 200:
        return []
    return r.json()[:5]


def enrich_via_tvmaze(conn, *, limit=None, similarity_threshold=0.80):
    rows = conn.execute(_TV_CANDIDATE_SQL).fetchall()
    if limit:
        rows = rows[:limit]
    total = len(rows)
    if total == 0:
        print("[tvmaze] nothing to enrich", flush=True)
        return 0
    print(f"[tvmaze] searching {total:,} TV titles", flush=True)

    session = requests.Session()
    got = rejected = 0
    for i, (cid, raw_title, year) in enumerate(rows, start=1):
        title = extract_series_title(raw_title) or raw_title
        try:
            results = tvmaze_search_shows(title, session)
        except Exception:
            results = []
        pick = None
        for entry in results:
            show = entry.get("show") or {}
            cand_title = show.get("name") or ""
            cand_year  = None
            if show.get("premiered"):
                m = re.match(r"(\d{4})", str(show["premiered"]))
                if m: cand_year = int(m.group(1))
            # Year guard only if both sides carry a year — TVMaze may be
            # silent on premiered for very old shows.
            if year and cand_year and abs(cand_year - year) > 2:
                continue
            sim = dice_similarity(normalize_title(title), normalize_title(cand_title))
            if sim >= similarity_threshold:
                pick = show
                break
        if pick:
            img = (pick.get("image") or {}).get("original")
            tvmaze_id = pick.get("id")
            # Store poster into enrichment; also stash the tvmaze_id on the
            # work itself if the `works.tvmaze_id` column exists (added in
            # a pipeline migration). Silently skip the ID write if not.
            if img:
                conn.execute("""
                    INSERT INTO enrichment (canonical_id, poster_url)
                    VALUES (?, ?)
                    ON CONFLICT(canonical_id) DO UPDATE SET
                        poster_url = CASE
                            WHEN enrichment.poster_url IS NULL
                              OR enrichment.poster_url = ''
                              OR enrichment.poster_url LIKE 'https://archive.org/services/img/%'
                            THEN excluded.poster_url
                            ELSE enrichment.poster_url
                        END
                """, (cid, img))
                got += 1
            else:
                rejected += 1
        else:
            rejected += 1
        if i % 100 == 0:
            conn.commit()
            print(f"  [tvmaze] matched {got:,}, rejected {rejected:,}  ({i:,}/{total:,})",
                  flush=True)
        time.sleep(0.55)
    conn.commit()
    print(f"[tvmaze] done: {got:,} matched, {rejected:,} rejected", flush=True)
    return got


# ---------------------------------------------------------------------------
# Pass: AAPB thumbnail (HEAD-verified)
# ---------------------------------------------------------------------------
# AAPB hosts still-frame thumbnails at a predictable S3 path:
#   https://s3.amazonaws.com/americanarchive.org/thumbnail/{id}.jpg
# HEAD 200 = present and public. HEAD 403/404 = access-restricted or
# not thumbnailed; skip those.
#
# These are real stills from the program — we mark them as designed art
# (the exporter's artwork_source_for() promotes them to 'aapb' which
# maps to hasRealArtwork=true).

def aapb_head(url, session):
    try:
        r = session.head(url, timeout=10, allow_redirects=True)
        return r.status_code == 200 and r.headers.get("Content-Type", "").startswith("image/")
    except Exception:
        return False


def enrich_via_aapb(conn, *, limit=None):
    cur = conn.execute("""
        SELECT s.source_id, s.canonical_id
        FROM sources s
        LEFT JOIN enrichment e ON e.canonical_id = s.canonical_id
        WHERE s.source_type = 'aapb'
          AND (e.poster_url IS NULL OR e.poster_url = '')
    """)
    rows = cur.fetchall()
    if limit:
        rows = rows[:limit]
    total = len(rows)
    if total == 0:
        print("[aapb] nothing to enrich", flush=True)
        return 0
    print(f"[aapb] HEAD-verifying {total:,} AAPB thumbnail URLs", flush=True)

    session = requests.Session()
    got = miss = 0
    for i, (aapb_id, cid) in enumerate(rows, start=1):
        url = AAPB_THUMB_TPL.format(id=aapb_id)
        if aapb_head(url, session):
            conn.execute("""
                INSERT INTO enrichment (canonical_id, poster_url)
                VALUES (?, ?)
                ON CONFLICT(canonical_id) DO UPDATE SET
                    poster_url = COALESCE(enrichment.poster_url, excluded.poster_url)
            """, (cid, url))
            got += 1
        else:
            miss += 1
        if i % 200 == 0:
            conn.commit()
            print(f"  [aapb] matched {got:,}, missed {miss:,}  ({i:,}/{total:,})", flush=True)
        # AAPB is an educational S3 bucket — polite pacing, no published limit.
        time.sleep(0.05)
    conn.commit()
    print(f"[aapb] done: {got:,} matched, {miss:,} missed", flush=True)
    return got


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
    ap.add_argument("--only", choices=[
        "tmdb", "fanart", "omdb", "tmdb-search", "tmdb-tv", "tvmaze",
        "wikidata", "wikipedia", "loc", "aapb", "archive",
    ])
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)

    # Pass order runs highest-quality designed-art → broad-net →
    # last-resort fallback. Each pass COALESCEs into poster_url so
    # earlier, higher-quality wins stick.

    # 1. TMDb find by IMDb ID — highest quality designed art.
    if args.only in (None, "tmdb"):
        tok = load_tmdb_token()
        if not tok:
            print("[tmdb] no TMDB_BEARER_TOKEN — skipping", file=sys.stderr)
        else:
            enrich_via_tmdb(conn, tok, limit=args.limit)

    # 2. Fanart.tv — IMDb-keyed designed art, TMDb gap-filler.
    if args.only in (None, "fanart"):
        fan = load_secret("FANART_TV_KEY")
        if not fan:
            print("[fanart] no FANART_TV_KEY — skipping "
                  "(register at fanart.tv/get-an-api-key → add to Secrets.xcconfig)",
                  file=sys.stderr)
        else:
            enrich_via_fanarttv(conn, fan, limit=args.limit)

    # 3. OMDb — IMDb-keyed designed art; Amazon-hosted poster.
    if args.only in (None, "omdb"):
        omdb = load_secret("OMDB_KEY")
        if not omdb:
            print("[omdb] no OMDB_KEY — skipping "
                  "(register at omdbapi.com/apikey.aspx → add to Secrets.xcconfig)",
                  file=sys.stderr)
        else:
            enrich_via_omdb(conn, omdb, limit=args.limit)

    # 4. LoC raw_json extraction — zero-network.
    if args.only in (None, "loc"):
        enrich_via_loc(conn, limit=args.limit)

    # 5. Wikidata batched SPARQL by IA ID — broad-net for items without
    #    IMDb IDs but registered as films in Wikidata via P724.
    if args.only in (None, "wikidata"):
        enrich_via_wikidata(conn, limit=args.limit)

    # 6. TMDb search by title+year with fuzzy match verification.
    if args.only in (None, "tmdb-search"):
        tok = load_tmdb_token()
        if tok:
            enrich_via_tmdb_search(conn, tok, limit=args.limit)

    # 7. Wikipedia pageimages.
    if args.only in (None, "wikipedia"):
        enrich_via_wikipedia(conn, limit=args.limit)

    # 7.5 TMDb /search/tv — fuzzy-match TV shows. IMDb-keyed passes skip
    #     TV entirely because Archive rarely surfaces TV IMDb IDs.
    if args.only in (None, "tmdb-tv"):
        tok = load_tmdb_token()
        if tok:
            enrich_via_tmdb_tv(conn, tok, limit=args.limit)

    # 7.75 TVMaze — fills whatever TMDb-TV missed. Free, no key.
    if args.only in (None, "tvmaze"):
        enrich_via_tvmaze(conn, limit=args.limit)

    # 8. AAPB thumbnail — real program stills, HEAD-verified.
    if args.only in (None, "aapb"):
        enrich_via_aapb(conn, limit=args.limit)

    # 9. Archive.org thumbnail fallback — universal last resort.
    if args.only in (None, "archive"):
        fill_archive_thumbnails(conn, limit=args.limit)

    conn.close()


if __name__ == "__main__":
    main()
