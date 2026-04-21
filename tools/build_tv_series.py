#!/usr/bin/env python3
"""
build_tv_series.py — cluster individual tv_episode works into
tv_series + tv_episodes rows.

How it works:
  1. Select all works classified as TV (work_type IN (tv_episode, tv_movie)
     OR sourced from classic_tv/television collections).
  2. For each, extract the series title (shared with enrich_artwork.py's
     extract_series_title) and the episode's (season, episode) tuple.
  3. Group by normalized series title → one tv_series row per group.
     Aggregate year range, poster (best-enriched episode's), popularity
     (max across episodes), TMDb ID (most common across episodes).
  4. Write tv_episodes rows linking each Archive item to its series.

After this runs, run `enrich_tv_episodes.py` to fetch episode-level
metadata (names, overviews, stills) from TMDb.

The clustering is conservative:
  - No cross-year merges (a 1951 "Dragnet" and a 1987 "Dragnet" stay
    separate).
  - Singletons (series with only 1 episode) still get a tv_series row
    so the UI can render them uniformly.
  - Anthology series (Studio One, Playhouse 90) are treated as a single
    series — per user direction.

Usage:
    python tools/build_tv_series.py               # cluster + write
    python tools/build_tv_series.py --dry-run     # report only
    python tools/build_tv_series.py --db video_registry.db
"""

import argparse
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from enrich_artwork import extract_series_title, normalize_title


# Match S##E##, S# E#, s01e01 variants. Captures season+episode.
SE_RE = re.compile(
    r"[Ss](\d{1,2})\s*[Ee](\d{1,3})"
)
# Archive uses "Episode #12" / "Episode 12" / "Ep 12" / "E12" sometimes.
EP_ONLY_RE = re.compile(
    r"\b(?:Episode|Ep|E)\s*#?\s*(\d{1,3})\b",
    re.IGNORECASE,
)
# Leading ordinal: "23 Studio One ..." (index number in an upload series)
LEADING_NUM_RE = re.compile(r"^\s*#?(\d{1,3})\b")


def extract_season_episode(raw_title):
    """Best-effort (season, episode) extraction from a messy Archive title.
    Returns (season_or_None, episode_or_None).

    Priority:
      1. S##E## — most authoritative
      2. Explicit "Episode N" / "Ep N" / "E##" → episode N, season 1 by default
      3. Leading ordinal like "23 Studio One" → episode 23
    """
    if not raw_title:
        return (None, None)
    m = SE_RE.search(raw_title)
    if m:
        return (int(m.group(1)), int(m.group(2)))
    m = EP_ONLY_RE.search(raw_title)
    if m:
        return (1, int(m.group(1)))
    m = LEADING_NUM_RE.match(raw_title)
    if m:
        n = int(m.group(1))
        if n >= 1 and n <= 500:        # sanity — avoid catching years
            return (1, n)
    return (None, None)


def slugify(s):
    s = re.sub(r"[^\w\s-]", "", s.lower())
    s = re.sub(r"\s+", "-", s).strip("-")
    return s[:60]


TV_SELECT = """
SELECT DISTINCT
    w.canonical_id,
    w.title,
    w.year,
    w.popularity_score,
    w.quality_score,
    e.poster_url,
    e.tmdb_id,
    e.imdb_id,
    e.wikidata_qid,
    e.wikipedia_url,
    e.genres
FROM works w
LEFT JOIN enrichment e ON e.canonical_id = w.canonical_id
LEFT JOIN sources    s ON s.canonical_id = w.canonical_id
WHERE w.title IS NOT NULL
  AND (w.work_type IN ('tv_episode', 'tv_movie')
       OR (s.source_type = 'archive_org'
           AND (s.raw_json LIKE '%classic_tv%'
                OR s.raw_json LIKE '%"television"%')))
  AND w.quality_score    >= 30
  AND w.popularity_score >= 20
"""


def build_series(conn, *, dry_run=False):
    rows = conn.execute(TV_SELECT).fetchall()
    print(f"[tv-cluster] {len(rows):,} TV-ish works in scope", flush=True)

    # Cluster by (normalized series title, first-year-digit-bucket). The
    # year bucket prevents merging two distinct shows with the same name
    # (e.g., "Dragnet 1951" and "Dragnet 1987"). Pragmatic rule: group
    # by the show's plausible START year — the min year across all
    # episodes sharing a normalized title, rounded to the nearest 20y.
    # Bucket size 20 keeps a long-running series together while separating
    # remakes.
    by_title = defaultdict(list)
    for (cid, title, year, pop, qual, poster, tmdb, imdb, qid, wiki, genres) in rows:
        series_title = extract_series_title(title) or title
        norm = normalize_title(series_title)
        if not norm:
            continue
        by_title[norm].append({
            "canonical_id": cid,
            "raw_title": title,
            "series_title": series_title,
            "year": year,
            "popularity": pop or 0,
            "quality": qual or 0,
            "poster_url": poster,
            "tmdb_id": tmdb,
            "imdb_id": imdb,
            "wikidata_qid": qid,
            "wikipedia_url": wiki,
            "genres": genres,
        })

    # Split each title group by 20y year bucket to keep remakes apart.
    groups = []
    for norm, items in by_title.items():
        by_bucket = defaultdict(list)
        for it in items:
            y = it["year"] or 1960   # fallback — most unknown-year TV ~60s
            bucket = (y // 20) * 20
            by_bucket[bucket].append(it)
        for bucket, bucket_items in by_bucket.items():
            groups.append((norm, bucket, bucket_items))

    print(f"[tv-cluster] {len(groups):,} series groups (with 20y-bucket split)",
          flush=True)

    # Pick the "canonical" display title for each group: the longest
    # one that appears most often. We prefer the most verbose legit
    # title because Archive tends to truncate them inconsistently.
    series_rows = []
    episode_rows = []
    for (norm, bucket, items) in groups:
        # Display title: mode of the series_title values, weighted by
        # popularity. Ties broken by length (longer wins).
        title_votes = defaultdict(int)
        for it in items:
            title_votes[it["series_title"]] += (it["popularity"] or 0) + 1
        display_title = max(title_votes.items(),
                            key=lambda kv: (kv[1], len(kv[0])))[0]

        years = [it["year"] for it in items if it["year"]]
        year_start = min(years) if years else None
        year_end   = max(years) if years else None

        # Best poster: the one attached to the most-popular Archive item.
        poster = None
        for it in sorted(items, key=lambda x: x["popularity"] or 0, reverse=True):
            if it["poster_url"]:
                poster = it["poster_url"]; break

        # Most common tmdb_id — skips NULL.
        tmdb_votes = defaultdict(int)
        for it in items:
            if it["tmdb_id"]:
                tmdb_votes[it["tmdb_id"]] += 1
        tmdb_id = max(tmdb_votes.items(), key=lambda kv: kv[1])[0] if tmdb_votes else None

        # Union of genres (from enrichment).
        genre_set = set()
        for it in items:
            try:
                gs = json.loads(it["genres"]) if it["genres"] else []
                for g in gs: genre_set.add(g)
            except (ValueError, TypeError):
                continue

        # Aggregate series-level scores — use the best (max) across its
        # episodes. A series is as good as its best episode.
        max_pop  = max((it["popularity"] or 0) for it in items)
        max_qual = max((it["quality"] or 0) for it in items)

        # Stable series_id: slug of display title + start year.
        series_id = f"{slugify(display_title)}-{year_start or bucket}"

        series_rows.append({
            "series_id": series_id,
            "title": display_title,
            "title_normalized": norm,
            "year_start": year_start,
            "year_end": year_end,
            "tmdb_id": tmdb_id,
            "wikidata_qid": None,
            "imdb_id": None,
            "overview": None,
            "poster_url": poster,
            "backdrop_url": None,
            "creator": None,
            "genres": json.dumps(sorted(genre_set)) if genre_set else None,
            "networks": None,
            "seasons_count": 0,   # filled after we build episodes
            "episodes_count": len(items),
            "quality_score": max_qual,
            "popularity_score": max_pop,
        })

        # Sort episodes: extracted (S,E) if present, else by popularity.
        for it in items:
            s, e = extract_season_episode(it["raw_title"])
            episode_rows.append({
                "canonical_id": it["canonical_id"],
                "series_id": series_id,
                "season_number": s,
                "episode_number": e,
                "title": it["raw_title"],
                "overview": None,
                "still_url": None,
                "air_date": None,
            })

    # Compute seasons_count for each series (count of distinct season_number
    # values amongst its episodes, treating NULL season as one logical
    # season).
    seasons_by_series = defaultdict(set)
    for ep in episode_rows:
        seasons_by_series[ep["series_id"]].add(ep["season_number"] or 0)
    for sr in series_rows:
        sr["seasons_count"] = len(seasons_by_series[sr["series_id"]])

    # Stats report
    multi = sum(1 for s in series_rows if s["episodes_count"] > 1)
    singletons = len(series_rows) - multi
    total_eps = len(episode_rows)
    print(f"[tv-cluster] results:", flush=True)
    print(f"  - {len(series_rows):,} series total "
          f"({multi:,} multi-episode, {singletons:,} singletons)", flush=True)
    print(f"  - {total_eps:,} episodes linked", flush=True)
    top = sorted(series_rows, key=lambda s: s["episodes_count"], reverse=True)[:10]
    print(f"  - top 10 by episode count:", flush=True)
    for s in top:
        print(f"      {s['episodes_count']:>4}  {s['title'][:45]:45s}  "
              f"{s['year_start']}–{s['year_end']}", flush=True)

    if dry_run:
        print("[tv-cluster] --dry-run, skipping writes", flush=True)
        return 0

    # Wipe + reload; both tables are entirely derived. Foreign-key
    # constraints aren't enabled on this DB, so order doesn't matter.
    conn.execute("DELETE FROM tv_episodes")
    conn.execute("DELETE FROM tv_series")
    conn.executemany(
        """INSERT INTO tv_series
           (series_id, title, title_normalized, year_start, year_end,
            tmdb_id, wikidata_qid, imdb_id, overview, poster_url,
            backdrop_url, creator, genres, networks,
            seasons_count, episodes_count, quality_score, popularity_score)
           VALUES
           (:series_id, :title, :title_normalized, :year_start, :year_end,
            :tmdb_id, :wikidata_qid, :imdb_id, :overview, :poster_url,
            :backdrop_url, :creator, :genres, :networks,
            :seasons_count, :episodes_count, :quality_score, :popularity_score)""",
        series_rows,
    )
    conn.executemany(
        """INSERT OR REPLACE INTO tv_episodes
           (canonical_id, series_id, season_number, episode_number,
            title, overview, still_url, air_date)
           VALUES
           (:canonical_id, :series_id, :season_number, :episode_number,
            :title, :overview, :still_url, :air_date)""",
        episode_rows,
    )
    conn.commit()
    print(f"[tv-cluster] wrote {len(series_rows):,} tv_series + "
          f"{len(episode_rows):,} tv_episodes", flush=True)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="video_registry.db")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    conn = sqlite3.connect(args.db)
    return build_series(conn, dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
