#!/usr/bin/env python3
"""
enrich_tv_episodes.py — for every tv_series with a tmdb_id, fetch
series-level metadata (overview, backdrop, networks, creator) and the
episode list for every season. Update tv_series + tv_episodes in place.

Flow per series:
  1. GET /tv/{id}                 → series overview + backdrop + seasons[]
  2. For each season s in the show, GET /tv/{id}/season/{s}
       → episode list with name, overview, still_path, air_date, runtime
  3. For each TMDb episode with (season, episode_number), try to match
     it to an existing tv_episodes row (same series_id + same S/E).
     If matched → fill title/overview/still_url/air_date.
     If not matched → skip (we can't play it; it's not on Archive).

Rate limits:
  TMDb: 40 req / 10 s. We throttle to 0.28s/req with 1 retry on 429.

Usage:
  python tools/enrich_tv_episodes.py              # all series with tmdb_id
  python tools/enrich_tv_episodes.py --limit 20   # smoke test
"""

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path

import re
import requests

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from enrich_artwork import (
    load_tmdb_token, TMDB_API, TMDB_IMG_BASE, TMDB_BDROP_URL, USER_AGENT,
    normalize_title, dice_similarity,
)

STILL_URL_BASE = "https://image.tmdb.org/t/p/w300"


def extract_episode_specific_title(raw_title, series_title):
    """Given a raw Archive episode title + the series title, return the
    part that's the EPISODE-specific name — what's left after we strip
    the series prefix and any S##E## / Episode N chrome."""
    t = raw_title or ""
    # Strip leading series title (case-insensitive, allow " - ", ": ", etc.
    # as separators).
    if series_title:
        pat = re.compile(
            rf"^\s*{re.escape(series_title)}\s*(?:[-:—|]+\s*|\.\s+|#\d+\s*-?\s*|)",
            re.IGNORECASE,
        )
        t = pat.sub("", t, count=1)
    # Strip S##E## / E## markers.
    t = re.sub(r"\b[Ss]\d+[EeXx]\d+\b", "", t)
    t = re.sub(r"\b[Ee]p(isode)?\s*#?\s*\d+\b", "", t, flags=re.IGNORECASE)
    # Strip quoted wrappers and leading episode number like "18:" or "#18".
    t = t.strip().strip('"').strip("'").strip()
    t = re.sub(r"^#?\d+\s*[-:.]\s*", "", t)
    # Strip trailing (year) and season descriptors.
    t = re.sub(r"\s*\(\s*\d{4}\s*\)\s*$", "", t)
    t = re.sub(r"\bseason\s+\d+\b", "", t, flags=re.IGNORECASE)
    return t.strip(" -:._;,\"'").strip()


def tmdb_get(token, path, session):
    r = session.get(
        f"{TMDB_API}{path}",
        headers={"Authorization": f"Bearer {token}", "User-Agent": USER_AGENT},
        timeout=20,
    )
    if r.status_code == 429:
        time.sleep(2)
        r = session.get(
            f"{TMDB_API}{path}",
            headers={"Authorization": f"Bearer {token}", "User-Agent": USER_AGENT},
            timeout=20,
        )
    if r.status_code != 200:
        return None
    return r.json()


def enrich_series(conn, token, *, limit=None):
    cur = conn.execute("""
        SELECT series_id, tmdb_id, title, episodes_count
        FROM tv_series
        WHERE tmdb_id IS NOT NULL
        ORDER BY popularity_score DESC
    """)
    series = cur.fetchall()
    if limit:
        series = series[:limit]
    total = len(series)
    print(f"[tv-episodes] enriching {total:,} series via TMDb", flush=True)

    session = requests.Session()
    series_updated = 0
    eps_matched = 0
    eps_failed = 0

    for i, (series_id, tmdb_id, series_title, arch_eps) in enumerate(series, start=1):
        detail = tmdb_get(token, f"/tv/{tmdb_id}", session)
        time.sleep(0.28)
        if not detail:
            continue

        # Update series-level fields from /tv/{id}
        overview = detail.get("overview")
        backdrop_path = detail.get("backdrop_path")
        networks = [n.get("name") for n in (detail.get("networks") or []) if n.get("name")]
        creators = [c.get("name") for c in (detail.get("created_by") or []) if c.get("name")]
        poster_path = detail.get("poster_path")

        # TMDb show-level poster WINS over the episode-thumbnail-derived
        # one we picked during clustering — TMDb posters are designed
        # marketing art, episode thumbnails are first-frame fallbacks.
        tmdb_poster = f"{TMDB_IMG_BASE}{poster_path}" if poster_path else None
        conn.execute("""
            UPDATE tv_series SET
                overview      = COALESCE(NULLIF(?,'' ), overview),
                backdrop_url  = COALESCE(?, backdrop_url),
                poster_url    = COALESCE(?, poster_url),
                networks      = COALESCE(?, networks),
                creator       = COALESCE(?, creator),
                updated_at    = CURRENT_TIMESTAMP
            WHERE series_id = ?
        """, (
            overview or None,
            f"{TMDB_BDROP_URL}{backdrop_path}" if backdrop_path else None,
            tmdb_poster,
            json.dumps(networks) if networks else None,
            creators[0] if creators else None,
            series_id,
        ))
        # Force-overwrite poster when TMDb has one (COALESCE above would
        # preserve the older value).
        if tmdb_poster:
            conn.execute(
                "UPDATE tv_series SET poster_url = ? WHERE series_id = ?",
                (tmdb_poster, series_id),
            )
        series_updated += 1

        # Build the set of Archive episodes for this series and an index
        # keyed on the normalized episode-specific title + any numeric
        # (S, E) hint we could extract at clustering time. The matcher
        # will use both signals.
        arch = conn.execute("""
            SELECT canonical_id, season_number, episode_number, title
            FROM tv_episodes WHERE series_id = ?
        """, (series_id,)).fetchall()

        by_se = {}           # (season_number, episode_number) → canonical_id
        by_title = {}        # normalized episode title → canonical_id
        unassigned = set()   # canonical_ids still available for match

        for cid, sn, en, raw_title in arch:
            unassigned.add(cid)
            if sn is not None and en is not None:
                by_se[(sn, en)] = cid
            ep_name = extract_episode_specific_title(raw_title, series_title)
            norm = normalize_title(ep_name)
            if norm:
                by_title.setdefault(norm, []).append(cid)

        # Walk TMDb seasons/episodes; for each, try (S,E) first, then
        # title match. Fill the winning Archive row with TMDb metadata.
        seasons = detail.get("seasons") or []
        for s in seasons:
            sn = s.get("season_number")
            if sn is None:
                continue
            season_data = tmdb_get(token, f"/tv/{tmdb_id}/season/{sn}", session)
            time.sleep(0.28)
            if not season_data:
                continue
            for ep in (season_data.get("episodes") or []):
                en = ep.get("episode_number")
                ep_name = ep.get("name") or ""
                cid = None

                # 1. Exact (S, E) hit.
                cid = by_se.get((sn, en))

                # 2. Title fuzzy match — take the best Dice score over
                #    unassigned Archive rows, accept if ≥ 0.85.
                if cid is None and ep_name:
                    norm_tmdb = normalize_title(ep_name)
                    # Direct lookup first (both normalized).
                    if norm_tmdb in by_title:
                        for candidate in by_title[norm_tmdb]:
                            if candidate in unassigned:
                                cid = candidate
                                break
                    # Full fuzzy pass if direct didn't land.
                    if cid is None:
                        best_sim = 0.0
                        best_cid = None
                        for norm_arch, candidates in by_title.items():
                            sim = dice_similarity(norm_tmdb, norm_arch)
                            if sim > best_sim:
                                for candidate in candidates:
                                    if candidate in unassigned:
                                        best_sim = sim
                                        best_cid = candidate
                                        break
                        if best_sim >= 0.85:
                            cid = best_cid

                if cid and cid in unassigned:
                    conn.execute("""
                        UPDATE tv_episodes SET
                            season_number  = COALESCE(season_number, ?),
                            episode_number = COALESCE(episode_number, ?),
                            title          = ?,
                            overview       = COALESCE(?, overview),
                            still_url      = COALESCE(?, still_url),
                            air_date       = COALESCE(?, air_date)
                        WHERE canonical_id = ?
                    """, (
                        sn, en,
                        ep_name or None,
                        ep.get("overview") or None,
                        f"{STILL_URL_BASE}{ep['still_path']}" if ep.get("still_path") else None,
                        ep.get("air_date") or None,
                        cid,
                    ))
                    unassigned.discard(cid)
                    eps_matched += 1
                else:
                    eps_failed += 1

        if i % 25 == 0:
            conn.commit()
            print(f"  [tv-episodes] {i:,}/{total:,}  series done, "
                  f"{eps_matched:,} eps matched, {eps_failed:,} TMDb eps not in our catalog",
                  flush=True)

    conn.commit()

    # Recompute seasons_count from actual matched episodes.
    conn.execute("""
        UPDATE tv_series SET seasons_count = (
            SELECT COUNT(DISTINCT COALESCE(season_number, 0))
            FROM tv_episodes WHERE tv_episodes.series_id = tv_series.series_id
        )
    """)
    conn.commit()

    print(f"[tv-episodes] done: {series_updated:,} series enriched, "
          f"{eps_matched:,} episodes matched", flush=True)
    return eps_matched


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="video_registry.db")
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    token = load_tmdb_token()
    if not token:
        print("[tv-episodes] no TMDB_BEARER_TOKEN — cannot run", file=sys.stderr)
        return 1

    conn = sqlite3.connect(args.db)
    enrich_series(conn, token, limit=args.limit)
    return 0


if __name__ == "__main__":
    sys.exit(main())
