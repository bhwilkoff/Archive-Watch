#!/usr/bin/env python3
"""
tmdb_lib.py — TMDb (The Movie Database) fetch + normalize helpers.

TMDb is the high-quality, no-daily-cap source for movie metadata + artwork
(40 req/10s, free non-commercial tier — see Decision 007). Unlike OMDb it
can be used for a one-shot bulk pass over the whole catalog.

These helpers resolve a movie by title+year and return a record shaped to
match omdb_lib's apply_identity + apply_rich, so enrich_movies can apply
either source through the same code path. Auth uses the v4 read-access
bearer token (TMDB_BEARER_TOKEN).
"""

from __future__ import annotations

import difflib
import os
import re
from pathlib import Path

import requests

TMDB_API = "https://api.themoviedb.org/3"
IMG_BASE = "https://image.tmdb.org/t/p/w780"
USER_AGENT = "ArchiveWatch-TMDb/1.0 (learningischange.com)"


def load_tmdb_token(secrets_path: Path | None = None):
    """GH Actions secret / env → Secrets.xcconfig."""
    v = os.environ.get("TMDB_BEARER_TOKEN")
    if v:
        return v.strip()
    if secrets_path and secrets_path.exists():
        for line in secrets_path.read_text().splitlines():
            if line.strip().startswith("TMDB_BEARER_TOKEN"):
                _, _, rhs = line.partition("=")
                return rhs.strip()
    return None


def _norm(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def _headers(token):
    return {"Authorization": f"Bearer {token}", "User-Agent": USER_AGENT,
            "accept": "application/json"}


def search_movie(title, year, token, session, *, timeout=20):
    """Return the best-matching TMDb movie id for title+year, or None.
    Guards against wrong matches with a title-similarity floor."""
    params = {"query": title, "include_adult": "false"}
    if year:
        params["year"] = str(year)
    r = session.get(f"{TMDB_API}/search/movie", params=params,
                    headers=_headers(token), timeout=timeout)
    if r.status_code == 401:
        raise RuntimeError("TMDb auth failed (401) — check TMDB_BEARER_TOKEN")
    if r.status_code == 429:
        raise RuntimeError("TMDb rate limited (429)")
    if not r.ok:
        return None
    results = r.json().get("results") or []
    if not results:
        return None
    want = _norm(title)

    def score(m):
        cand = _norm(m.get("title") or m.get("original_title"))
        sim = difflib.SequenceMatcher(None, want, cand).ratio()
        rd = (m.get("release_date") or "")[:4]
        ybonus = 0.0
        if year and rd.isdigit():
            diff = abs(int(rd) - year)
            ybonus = 0.15 if diff == 0 else (0.07 if diff <= 2 else -0.05 * diff)
        pop = min(0.1, (m.get("popularity") or 0) / 1000.0)
        return sim + ybonus + pop

    best = max(results, key=score)
    if difflib.SequenceMatcher(None, want,
                               _norm(best.get("title") or best.get("original_title"))).ratio() < 0.6:
        return None
    return best.get("id")


def movie_detail(movie_id, token, session, *, timeout=20):
    """Fetch full detail + credits and normalize to the shared record shape
    (compatible with omdb_lib.apply_identity / apply_rich)."""
    r = session.get(f"{TMDB_API}/movie/{movie_id}",
                    params={"append_to_response": "credits,release_dates"},
                    headers=_headers(token), timeout=timeout)
    if not r.ok:
        return None
    d = r.json()
    crew = (d.get("credits") or {}).get("crew") or []
    cast = (d.get("credits") or {}).get("cast") or []
    director = next((c["name"] for c in crew if c.get("job") == "Director"), None)
    poster = d.get("poster_path")
    backdrop = d.get("backdrop_path")
    rd = (d.get("release_date") or "")[:4]
    return {
        "imdb_id":        d.get("imdb_id") or None,
        "tmdb_id":        d.get("id"),
        "title":          d.get("title"),
        "year":           int(rd) if rd.isdigit() else None,
        "poster_url":     (IMG_BASE + poster) if poster else None,
        "backdrop_url":   ("https://image.tmdb.org/t/p/w1280" + backdrop) if backdrop else None,
        "plot":           (d.get("overview") or None),
        "genres":         [g["name"] for g in (d.get("genres") or []) if g.get("name")],
        "runtime_min":    d.get("runtime") or None,
        "director":       director,
        "actors":         [c["name"] for c in cast[:10] if c.get("name")],
        "vote_average":   d.get("vote_average") or None,
        # OMDb-only fields TMDb doesn't supply (left for omdb_backfill):
        "imdb_rating":    None, "imdb_votes": None, "content_rating": None,
        "artwork_source": "tmdb",
    }


def resolve(title, year, token, session):
    """title+year -> normalized detail record, or None."""
    mid = search_movie(title, year, token, session)
    if not mid:
        return None
    return movie_detail(mid, token, session)
