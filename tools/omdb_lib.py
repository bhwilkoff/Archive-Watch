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
CACHE_SCHEMA_VERSION = 2


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
    d = r.json()
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
    }


# ---------------------------------------------------------------------------
# Apply to a catalog item
# ---------------------------------------------------------------------------

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
    if poster and item.get("artworkSource") not in DESIGNED_SOURCES:
        item["posterURL"] = poster
        item["artworkSource"] = "omdb"
        item["hasRealArtwork"] = True
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
        "fetched_at":     now,
        "schema":         CACHE_SCHEMA_VERSION,
    }
