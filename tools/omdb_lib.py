#!/usr/bin/env python3
"""
omdb_lib.py — shared OMDb fetch + apply helpers.

Used by both tools/omdb_backfill.py (enrich items we already have) and
tools/ingest_candidates.py (enrich newly discovered items). Keeping the
fetch + field-mapping in one place means the rich-field set can't drift
between the two pipelines.

OMDb is enrichment-only — it cannot discover content or filter by rights
(see docs/research/omdb-and-pd-discovery.md). These helpers take an
already-known IMDb ID and return a normalized dict of the fields we keep.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import requests

OMDB_API = "https://www.omdbapi.com/"
USER_AGENT = "ArchiveWatch-OMDb/2.0 (learningischange.com) python-requests"

# Artwork sources we treat as "already designed" — never overwrite these
# with an OMDb poster. (OMDb posters are good but TMDb/Wikidata/Commons
# are generally higher quality and curated.)
DESIGNED_SOURCES = {"tmdb", "fanart", "omdb", "commons", "wikidata", "aapb"}

# Cache schema version. Bumping this signals omdb_backfill that older
# entries are poster-only and should be re-fetched once to pick up the
# rich fields. v1 = poster_url only; v2 = rich fields.
CACHE_SCHEMA_VERSION = 3   # 3: + identity fields (director/actors/genres)


# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

def load_omdb_key(secrets_path: Path | None = None):
    """GH Actions secret → local env → Secrets.xcconfig."""
    v = os.environ.get("OMDB_KEY")
    if v:
        return v.strip()
    if secrets_path and secrets_path.exists():
        for line in secrets_path.read_text().splitlines():
            if line.strip().startswith("OMDB_KEY"):
                _, _, rhs = line.partition("=")
                return rhs.strip()
    return None


# ---------------------------------------------------------------------------
# Fetch
# ---------------------------------------------------------------------------

def _clean(v):
    """OMDb uses the literal string 'N/A' for missing values."""
    if v is None:
        return None
    s = str(v).strip()
    return None if (not s or s == "N/A") else s


def _int_votes(v):
    """'148,892' → 148892, or None."""
    s = _clean(v)
    if not s:
        return None
    digits = re.sub(r"[^0-9]", "", s)
    return int(digits) if digits else None


def _float_rating(v):
    """'7.8' → 7.8, or None."""
    s = _clean(v)
    if not s:
        return None
    try:
        return round(float(s), 1)
    except ValueError:
        return None


def fetch_omdb(imdb_id, api_key, session, *, full_plot=True):
    """Fetch one OMDb record by IMDb ID.

    Returns a normalized dict (see below) on a real hit, None when OMDb
    has no record ("Response": "False"), or raises RuntimeError on a
    transient failure (quota / HTTP / network) so the caller can decide
    whether to negative-cache or retry.

    Normalized keys (all optional, None when OMDb lacks them):
        poster_url, imdb_rating (float), imdb_votes (int),
        content_rating (str, OMDb "Rated"), plot (str), writer (str),
        runtime_min (int), omdb_genre (str), omdb_type (str)
    """
    params = {"i": imdb_id, "apikey": api_key}
    if full_plot:
        params["plot"] = "full"
    r = session.get(OMDB_API, params=params,
                    headers={"User-Agent": USER_AGENT}, timeout=20)
    if r.status_code == 401:
        raise RuntimeError("OMDb daily quota exhausted (HTTP 401)")
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}")
    try:
        d = r.json()
    except ValueError as e:
        # OMDb occasionally returns a non-JSON body (truncated / HTML error).
        # Treat as transient so the caller skips this one item instead of
        # crashing the whole run.
        raise RuntimeError(f"bad JSON ({e}); body[:80]={r.text[:80]!r}")
    if str(d.get("Response", "")).lower() != "true":
        return None

    runtime = _clean(d.get("Runtime"))  # e.g. "96 min"
    runtime_min = None
    if runtime:
        m = re.match(r"(\d+)", runtime)
        if m:
            runtime_min = int(m.group(1))

    return {
        "poster_url":     _clean(d.get("Poster")),
        "imdb_rating":    _float_rating(d.get("imdbRating")),
        "imdb_votes":     _int_votes(d.get("imdbVotes")),
        "content_rating": _clean(d.get("Rated")),
        "plot":           _clean(d.get("Plot")),
        "writer":         _clean(d.get("Writer")),
        "runtime_min":    runtime_min,
        "omdb_genre":     _clean(d.get("Genre")),
        "omdb_type":      _clean(d.get("Type")),
        # Identity fields — already in the fetched record, so apply_identity can
        # fill cast/director/genres with NO extra OMDb call (Track B, iter 5).
        "director":       _clean(d.get("Director")),
        "actors":         _parse_people(d.get("Actors")),
        "genres":         [g.strip() for g in (_clean(d.get("Genre")) or "").split(",") if g.strip()],
    }


def _parse_people(v, limit=10):
    s = _clean(v)
    if not s:
        return []
    return [p.strip() for p in s.split(",") if p.strip()][:limit]


def _parse_year(v):
    s = _clean(v)
    if not s:
        return None
    m = re.search(r"(\d{4})", s)
    return int(m.group(1)) if m else None


def fetch_omdb_full(api_key, session, *, imdb_id=None, title=None, year=None,
                    full_plot=True):
    """Fetch one OMDb record by IMDb ID (i=) OR by title (t=). Returns a
    superset of fetch_omdb's dict that ALSO carries identity fields needed to
    enrich an item that has no IMDb ID yet:

        imdb_id, title, year, director, actors (list[str]), genres (list[str])

    Returns None when OMDb has no match; raises RuntimeError on quota/HTTP.
    This is the movie analog of resolving a show to TVmaze by title+year."""
    params = {"apikey": api_key, "plot": "full" if full_plot else "short"}
    if imdb_id:
        params["i"] = imdb_id
    elif title:
        params["t"] = title
        if year:
            params["y"] = str(year)
    else:
        return None
    r = session.get(OMDB_API, params=params,
                    headers={"User-Agent": USER_AGENT}, timeout=20)
    if r.status_code == 401:
        raise RuntimeError("OMDb daily quota exhausted (HTTP 401)")
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}")
    try:
        d = r.json()
    except ValueError as e:
        # OMDb occasionally returns a non-JSON body (truncated / HTML error).
        # Treat as transient so the caller skips this one item instead of
        # crashing the whole run.
        raise RuntimeError(f"bad JSON ({e}); body[:80]={r.text[:80]!r}")
    if str(d.get("Response", "")).lower() != "true":
        return None
    # Only accept movies/series, not episodes, for title lookups.
    runtime = _clean(d.get("Runtime"))
    runtime_min = None
    if runtime:
        m = re.match(r"(\d+)", runtime)
        if m:
            runtime_min = int(m.group(1))
    return {
        "imdb_id":        _clean(d.get("imdbID")),
        "title":          _clean(d.get("Title")),
        "year":           _parse_year(d.get("Year")),
        "poster_url":     _clean(d.get("Poster")),
        "imdb_rating":    _float_rating(d.get("imdbRating")),
        "imdb_votes":     _int_votes(d.get("imdbVotes")),
        "content_rating": _clean(d.get("Rated")),
        "plot":           _clean(d.get("Plot")),
        "writer":         _clean(d.get("Writer")),
        "director":       _clean(d.get("Director")),
        "actors":         _parse_people(d.get("Actors")),
        "genres":         [g.strip() for g in (_clean(d.get("Genre")) or "").split(",") if g.strip()],
        "runtime_min":    runtime_min,
        "omdb_type":      _clean(d.get("Type")),
    }


# ---------------------------------------------------------------------------
# Apply to a catalog item
# ---------------------------------------------------------------------------

def apply_identity(item, rec):
    """Fill an item's IDENTITY fields (imdbID, cast, director, genres, year)
    from an OMDb record — only where currently empty, so we never clobber
    better data. Pairs with apply_rich (poster/rating/plot/runtime). Returns
    True if anything changed."""
    if not rec:
        return False
    changed = False
    if rec.get("imdb_id") and not item.get("imdbID"):
        item["imdbID"] = rec["imdb_id"]; changed = True
    if rec.get("director") and not item.get("director"):
        item["director"] = rec["director"]; changed = True
    if rec.get("genres") and not item.get("genres"):
        item["genres"] = rec["genres"]; changed = True
    if rec.get("year") and not item.get("year"):
        item["year"] = rec["year"]
        item["decade"] = rec["year"] // 10 * 10
        changed = True
    if rec.get("actors") and not item.get("cast"):
        item["cast"] = [{"name": n, "character": None, "order": i,
                         "profilePath": None}
                        for i, n in enumerate(rec["actors"])]
        changed = True
    return changed

def apply_rich(item, rec):
    """Apply a normalized OMDb record to a single catalog item in place.

    Returns True if anything changed. Rules:
      - Poster only upgrades placeholder art (never overwrites a
        TMDb/Wikidata/Commons poster).
      - Rating / votes / content rating always fill (OMDb is the
        authority for these — we have no better source).
      - Plot only fills when the existing synopsis is missing or short
        (< 80 chars), so we never clobber a good TMDb/Archive synopsis.
      - runtimeSeconds fills only when absent.
    """
    if not rec:
        return False
    changed = False

    poster = rec.get("poster_url")
    src = rec.get("artwork_source", "omdb")
    # TMDb art outranks an existing OMDb poster; otherwise don't overwrite a
    # designed source. (DESIGNED_SOURCES order isn't a ranking, so special-
    # case the TMDb upgrade explicitly.)
    cur = item.get("artworkSource")
    can_set = (cur not in DESIGNED_SOURCES) or (src == "tmdb" and cur == "omdb")
    # Never re-apply a poster validate_posters already proved DEAD (404). Otherwise
    # this restores the exact dead URL (its src isn't a DESIGNED source after the
    # demotion to "archive"), and a 404'd image leads Home. A genuinely NEW live
    # URL from a fresh OMDb fetch still passes (it won't equal posterDeadURL).
    if poster and item.get("posterDead") and poster == item.get("posterDeadURL"):
        poster = None
    if poster and can_set:
        item["posterURL"] = poster
        item["artworkSource"] = src
        item["hasRealArtwork"] = True
        changed = True

    if rec.get("backdrop_url") and not item.get("backdropURL"):
        item["backdropURL"] = rec["backdrop_url"]
        changed = True

    if rec.get("imdb_rating") is not None and item.get("imdbRating") != rec["imdb_rating"]:
        item["imdbRating"] = rec["imdb_rating"]
        changed = True
    if rec.get("imdb_votes") is not None and item.get("imdbVotes") != rec["imdb_votes"]:
        item["imdbVotes"] = rec["imdb_votes"]
        changed = True
    if rec.get("content_rating") and not item.get("contentRating"):
        item["contentRating"] = rec["content_rating"]
        changed = True

    existing = item.get("synopsis") or ""
    if rec.get("plot") and len(existing) < 80 and rec["plot"] != existing:
        item["synopsis"] = rec["plot"]
        # Track that the synopsis came from OMDb when we had nothing better.
        item["synopsisSource"] = "omdb"
        changed = True

    if rec.get("runtime_min") and not item.get("runtimeSeconds"):
        item["runtimeSeconds"] = rec["runtime_min"] * 60
        changed = True

    return changed


def cache_record(rec, now):
    """Shape a normalized record for storage in omdb_cache.json. Keeps the
    legacy `poster_url` key (so v1 readers still work) and adds the rich
    fields + a schema marker."""
    if rec is None:
        return {"poster_url": None, "fetched_at": now, "schema": CACHE_SCHEMA_VERSION}
    return {
        "poster_url":     rec.get("poster_url"),
        "imdb_rating":    rec.get("imdb_rating"),
        "imdb_votes":     rec.get("imdb_votes"),
        "content_rating": rec.get("content_rating"),
        "plot":           rec.get("plot"),
        "runtime_min":    rec.get("runtime_min"),
        # Identity fields (schema 3+) so the backfill can fill cast/director/
        # genres for IMDb-ID'd items, not just posters/ratings.
        "director":       rec.get("director"),
        "actors":         rec.get("actors") or [],
        "genres":         rec.get("genres") or [],
        "fetched_at":     now,
        "schema":         CACHE_SCHEMA_VERSION,
    }
