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


# A title search with no year is how "Silence" (a 19-second clip) became
# Scorsese's 2016 film and a 14-minute Prelinger reel became Ivan Reitman's
# Evolution (2001): with nothing to disambiguate, the most popular film of that
# name wins. So a yearless search is accepted only when the title is EXACT and
# the film's own runtime agrees with the file's, and a dated search never takes
# a film released more than MAX_YEAR_GAP years from the item's year.
MAX_YEAR_GAP = 2
YEARLESS_RUNTIME_TOLERANCE = 0.25


def year_gap_ok(year, release_year):
    """False only when both years are known and further apart than MAX_YEAR_GAP."""
    if not year or not release_year:
        return True
    return abs(int(release_year) - int(year)) <= MAX_YEAR_GAP


def runtime_agrees(runtime_min, file_runtime_s, tol=YEARLESS_RUNTIME_TOLERANCE):
    """The film's runtime (minutes) is within `tol` of the file's (seconds)."""
    if not runtime_min or not file_runtime_s:
        return False
    film = runtime_min * 60.0
    return abs(file_runtime_s - film) <= tol * film


def search_movie(title, year, token, session, *, timeout=20, file_runtime_s=None,
                 trust_yearless=False):
    """Return the best-matching TMDb movie id for title+year, or None.
    Guards against wrong matches with a title-similarity floor.

    With no year, abstains unless exactly one result has the exact title and
    its runtime is within 25% of `file_runtime_s`. `trust_yearless=True` is for
    a caller that verifies the result by evidence of its own (cast overlap) and
    keeps the old behavior."""
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

    if not year and not trust_yearless:
        exact = [m for m in results
                 if want and want in (_norm(m.get("title")), _norm(m.get("original_title")))]
        if len(exact) != 1 or not file_runtime_s:
            return None
        d = session.get(f"{TMDB_API}/movie/{exact[0].get('id')}",
                        headers=_headers(token), timeout=timeout)
        if not d.ok or not runtime_agrees((d.json() or {}).get("runtime"), file_runtime_s):
            return None
        return exact[0].get("id")

    best = max(results, key=score)
    best_norm = _norm(best.get("title") or best.get("original_title"))
    if difflib.SequenceMatcher(None, want, best_norm).ratio() < 0.6:
        return None
    rd = (best.get("release_date") or "")[:4]
    if year and rd.isdigit() and not year_gap_ok(year, int(rd)):
        return None
    # Abstain on ambiguity (Decision 026): if >=2 results share the winning
    # normalized title within the ±2yr window, a common title can't be
    # disambiguated without the Archive's own imdb id — better no match.
    if year:
        same = 0
        for m in results:
            cn = _norm(m.get("title") or m.get("original_title"))
            rd = (m.get("release_date") or "")[:4]
            if cn == best_norm and rd.isdigit() and abs(int(rd) - year) <= 2:
                same += 1
        if same >= 2:
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


def find_by_imdb(imdb_id, token, session, *, timeout=20):
    """Resolve a TMDb movie id from an IMDb id via /find (authoritative key —
    no fuzzy title match). Returns the movie id or None. Raises RuntimeError on
    auth/rate-limit so callers can stop the run cleanly."""
    if not imdb_id:
        return None
    r = session.get(f"{TMDB_API}/find/{imdb_id}",
                    params={"external_source": "imdb_id"},
                    headers=_headers(token), timeout=timeout)
    if r.status_code == 401:
        raise RuntimeError("TMDb auth failed (401) — check TMDB_BEARER_TOKEN")
    if r.status_code == 429:
        raise RuntimeError("TMDb rate limited (429)")
    if not r.ok:
        return None
    mr = (r.json() or {}).get("movie_results") or []
    return mr[0]["id"] if mr else None


def resolve(title, year, token, session, *, file_runtime_s=None):
    """title+year -> normalized detail record, or None."""
    mid = search_movie(title, year, token, session, file_runtime_s=file_runtime_s)
    if not mid:
        return None
    rec = movie_detail(mid, token, session)
    if rec and not year_gap_ok(year, rec.get("year")):
        return None
    return rec
