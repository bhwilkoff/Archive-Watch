#!/usr/bin/env python3
"""
export_catalog.py
-----------------
Reads the federated video registry at video_registry.db and emits
catalog.json in the exact shape the Archive Watch tvOS app's
`Catalog.Item` model decodes. Replaces the JS-only build-catalog.mjs
with a pipeline-backed exporter that preserves every app-level
convention (shelves, Editor's Picks, procedural-fallback flags).

Responsibilities
  1. Query works_default (quality + popularity filtered) + enrichment
     + best_source. Prefer HEAD-verified playable sources.
  2. Map work_type → contentType via shared/editorial/work_type_map.json,
     overriding to "silent-film" when the work's is_silent flag is set.
  3. Resolve each Archive.org source's collection list from raw_json so
     the app's featured.json shelf queries can be satisfied.
  4. For each shelf in featured.json, execute its query against the DB
     and attach the matching canonical IDs to each item's shelves[].
  5. Crosswalk featured.json's Editor's Picks (archive IDs) to canonical
     IDs so curated picks survive the pipeline switch.
  6. Construct a VideoFile dict from the resolved Archive derivative (or
     mark unplayable so the app's procedural fallback kicks in).
  7. Emit Catalog.Item dicts → catalog.json.

Usage
    python tools/export_catalog.py \
        --db SchemaWork/video_registry.db \
        --featured featured.json \
        --out ArchiveWatch/ArchiveWatch/catalog.json

Zero network calls — everything reads from the local DB + editorial JSON.
"""

import argparse
import json
import re
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


# ---------------------------------------------------------------------------
# Tier profiles — the two shapes catalog.json gets shipped in.
# ---------------------------------------------------------------------------
# Apple TV is Wi-Fi only, so we don't worry about cellular size caps. But we
# still want the bundled seed to be small enough for instant first-launch:
# ~3k items is the sweet spot (5–10 MB JSON, parses in well under a second).
# The full hosted catalog is fetched by the app's CatalogRefreshService and
# can be an order of magnitude bigger without hurting UX.
#
# Diversity-aware selection: instead of "top 3000 by popularity" (which would
# be 90% feature films and 0 silent-era), we take top-N per work_type so each
# category has room to breathe. Editor's Picks are always included, never
# filtered by score — they're the product's editorial voice.

PROFILES = {
    "seed": {
        "min_quality":       45,
        "min_popularity":    50,
        # NOTE: require_artwork used to be True, but the Wikidata SPARQL
        # enrichment can time out (the q.w.o endpoint is flaky), and
        # without that pass almost no items have poster_url. The app has
        # a procedural poster fallback for un-arted items, so we'd
        # rather ship a populated seed with some procedural cards than
        # a nearly-empty one. Re-enable when enrichment is reliable.
        "require_artwork":   False,
        "require_playable":  True,   # must have a resolved MP4 url
        "max_items":         3000,
        "per_type_min":      150,    # diversity floor per work_type
    },
    "full": {
        "min_quality":       40,
        "min_popularity":    30,
        "require_artwork":   False,
        "require_playable":  True,   # always require playable — unplayable is noise
        "max_items":         25000,
        "per_type_min":      1000,
    },
    # Researcher / debugging profile — everything that passes quality, no caps.
    "raw": {
        "min_quality":       25,
        "min_popularity":    0,
        "require_artwork":   False,
        "require_playable":  False,
        "max_items":         None,
        "per_type_min":      None,
    },
}

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
EDITORIAL = REPO / "shared" / "editorial"


# ---------------------------------------------------------------------------
# Editorial configs
# ---------------------------------------------------------------------------

def load_editorial(name):
    path = EDITORIAL / f"{name}.json"
    if not path.exists():
        print(f"[export] missing {path}", file=sys.stderr)
        sys.exit(2)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


WORK_TYPE_MAP      = load_editorial("work_type_map")["mapping"]
ADULT_COLLECTIONS  = set(load_editorial("adult_collections")["collections"])
COLLECTION_META    = {
    c["id"]: c for c in load_editorial("collection_metadata")["collections"]
}


# ---------------------------------------------------------------------------
# Shelf query translator
# ---------------------------------------------------------------------------
# featured.json uses Archive.org scrape-API syntax:
#   "mediatype:movies AND collection:feature_films"
# The exporter parses this into SQL against the federated DB. Only three
# query atoms are used today: mediatype, collection, and composites.
# Anything we can't translate we log and skip (safer than emitting wrong
# shelves).

IA_QUERY_COLLECTION = re.compile(r"\bcollection\s*:\s*([A-Za-z0-9_\-]+)", re.IGNORECASE)

def translate_sort(sort_spec):
    """Archive scrape sort → SQL ORDER BY fragment.

    Accepts both the old `"-downloads"` style and the new `"downloads desc"`
    style that featured.json started using after the shift in the IA API.
    Recognised fields: downloads, week, date, publicdate, addeddate.
    Falls back to popularity_score."""
    if not sort_spec:
        return "popularity_score DESC, year DESC"
    spec = sort_spec[0] if isinstance(sort_spec, list) else sort_spec
    spec = str(spec).strip()
    field, direction = None, "DESC"
    if spec.startswith("-"):
        field, direction = spec[1:], "DESC"
    else:
        parts = spec.split()
        field = parts[0]
        if len(parts) > 1:
            direction = parts[1].upper()
    mapping = {
        "downloads":   "engagement.downloads",
        "week":        "engagement.week_views",
        "date":        "year",
        "publicdate":  "works.created_at",
        "addeddate":   "works.created_at",
    }
    col = mapping.get(field, "popularity_score")
    return f"{col} {direction} NULLS LAST, popularity_score DESC"


def resolve_shelf_items(conn, shelf):
    """Return the list of canonical_ids that satisfy a shelf definition.

    - Curated shelves (type=curated): crosswalk Archive IDs → canonical IDs.
    - Dynamic shelves (type=dynamic): parse query for collection atom,
      translate to SQL, apply sort + limit.
    - Seeded shelves (type=seeded): placeholder for future (wikidata-pd).
    """
    stype = shelf.get("type", "dynamic")
    limit = int(shelf.get("limit") or 24)

    if stype == "curated":
        out = []
        for entry in shelf.get("items", []) or []:
            ia_id = entry.get("archiveID") if isinstance(entry, dict) else None
            if not ia_id:
                continue
            row = conn.execute(
                """SELECT canonical_id FROM sources
                   WHERE source_type='archive_org' AND source_id=?""",
                (ia_id,),
            ).fetchone()
            if row:
                out.append(row[0])
        return out

    if stype == "dynamic":
        q = shelf.get("query") or ""
        coll_match = IA_QUERY_COLLECTION.search(q)
        if not coll_match:
            return []
        collection = coll_match.group(1)
        order_by = translate_sort(shelf.get("sort"))

        # Collection membership check piggy-backs on raw_json. SQLite's
        # JSON1 extension is usually present; LIKE fallback if not.
        # We want shelves to prefer designed art within each shelf, so that
        # a shelf's limit (say 24) fills with the 24 best-*enriched* items,
        # not whatever happens to match the collection + sort first. Items
        # with no designed art still appear in the tail if the shelf isn't
        # full — never lost silently.
        sql = f"""
            SELECT works.canonical_id
            FROM works
            JOIN sources  ON sources.canonical_id = works.canonical_id
                         AND sources.source_type = 'archive_org'
            LEFT JOIN engagement  ON engagement.source_type = sources.source_type
                                 AND engagement.source_id   = sources.source_id
            LEFT JOIN enrichment  ON enrichment.canonical_id = works.canonical_id
            WHERE sources.raw_json LIKE ?
              AND works.quality_score    >= 40
              AND works.popularity_score >= 25
            GROUP BY works.canonical_id
            ORDER BY
              CASE
                WHEN enrichment.poster_url IS NOT NULL
                 AND enrichment.poster_url != ''
                 AND enrichment.poster_url NOT LIKE 'https://archive.org/services/img/%'
                THEN 0 ELSE 1
              END,
              {order_by}
            LIMIT ?
        """
        like = f'%"{collection}"%'
        return [row[0] for row in conn.execute(sql, (like, limit))]

    # seeded / unrecognised: empty, logged so we don't silently drop.
    print(f"[shelf] skipping shelf id={shelf.get('id')} type={stype} (not yet supported)",
          file=sys.stderr)
    return []


# ---------------------------------------------------------------------------
# Item construction
# ---------------------------------------------------------------------------

ARTWORK_SOURCE_BY_HOST = {
    "image.tmdb.org":              "tmdb",
    "upload.wikimedia.org":        "commons",
    "commons.wikimedia.org":       "commons",
    "www.wikidata.org":            "wikidata",
    "archive.org":                 "archive",
    "ia800":                       "archive",   # CDN prefix
}

def artwork_source_for(url):
    """Classify poster_url provenance — the app's hasRealArtwork flag keys
    off this. TMDb/Fanart/OMDb/Commons/Wikidata/AAPB posters are "real
    designed art"; Archive first-frame thumbnails are placeholder-territory."""
    if not url:
        return "none"
    low = url.lower()
    if "image.tmdb.org" in low:
        return "tmdb"
    if "fanart.tv" in low:
        return "fanart"
    if "m.media-amazon.com" in low or "ia.media-imdb.com" in low:
        return "omdb"   # OMDb returns IMDb/Amazon-hosted posters
    if "upload.wikimedia.org" in low or "commons.wikimedia.org" in low:
        return "commons"
    if "wikidata.org" in low:
        return "wikidata"
    if "americanarchive.org" in low:
        return "aapb"
    if "archive.org" in low:
        # archive.org/services/img/{id} is the first-frame fallback.
        return "archive"
    return "external"


def decade_for(year):
    if not year:
        return None
    try: return (int(year) // 10) * 10
    except (TypeError, ValueError): return None


def build_video_file(row):
    """Construct the app's VideoFile shape from the best_source columns.
    Only emits when we have a real derivative name AND verified playability."""
    if not row["best_derivative"]:
        return None
    return {
        "name":      row["best_derivative"],
        "format":    row["best_format"] or "h.264",
        "sizeBytes": int(row["best_file_size"]) if row["best_file_size"] else None,
        "tier":      1 if row["best_verified_playable"] == 1 else 2,
    }


def build_download_url(row):
    """Prefer the verified stream_url; reject folder URLs that can't play."""
    url = row["best_stream_url"]
    if not url:
        return None
    # Archive.org's /download/{id} folder URL is unplayable — reject.
    if url.endswith(f"/download/{row['best_source_type']}") or re.match(
        r"^https?://archive\.org/download/[^/]+/?$", url
    ):
        return None
    return url


def parse_cast_list(json_str):
    """enrichment.cast_list is a JSON array of names. App expects richer
    CastMember objects (name/character/order/profilePath)."""
    if not json_str:
        return []
    try:
        names = json.loads(json_str)
    except (ValueError, TypeError):
        return []
    return [
        {"name": n, "character": None, "order": i, "profilePath": None}
        for i, n in enumerate(names) if n
    ][:20]


def collections_from_raw(row):
    """Pull the Archive.org collection array from the best source's raw_json."""
    raw = row["raw_json"] if "raw_json" in row.keys() else None
    if not raw:
        return []
    try:
        d = json.loads(raw)
        v = d.get("collection") or []
        return v if isinstance(v, list) else [v]
    except (ValueError, TypeError):
        return []


def build_item(row, shelf_membership, omdb_cache=None):
    """Translate one works_with_best_source row → Catalog.Item dict."""
    # archiveID: prefer the real Archive.org source_id when we have one.
    # Otherwise fall back to the canonical_id (so the app can use it as
    # an opaque identifier).
    best_type = row["best_source_type"]
    raw = {}
    try:
        raw = json.loads(row["raw_json"]) if row["raw_json"] else {}
    except (ValueError, TypeError):
        raw = {}
    archive_id = (raw.get("identifier") if best_type == "archive_org"
                  else row["canonical_id"])

    # contentType: pipeline work_type → app kebab-case, with silent override.
    base_ct = WORK_TYPE_MAP.get(row["work_type"] or "unknown", "short-film")
    if row["is_silent"]:
        content_type = "silent-film"
    else:
        content_type = base_ct

    # Poster / backdrop / artwork source.
    poster = row["poster_url"]
    src = artwork_source_for(poster)
    # OMDb cache overlay — if the scheduled backfill has a poster for this
    # item's IMDb ID AND the DB's current pick is a placeholder, upgrade.
    # This keeps local re-exports consistent with workflow-accumulated wins.
    if omdb_cache and row["imdb_id"]:
        cached = omdb_cache.get(row["imdb_id"])
        cached_url = cached.get("poster_url") if cached else None
        if cached_url and src in ("archive", "none"):
            poster = cached_url
            src = "omdb"
    has_real_artwork = src in ("tmdb", "fanart", "omdb", "commons", "wikidata", "aapb", "external")

    # Shelves — computed by the caller from featured.json, passed in.
    shelves = shelf_membership.get(row["canonical_id"], [])

    # Cast + genres + countries
    cast = parse_cast_list(row["cast_list"])
    try: genres = json.loads(row["genres"]) if row["genres"] else []
    except (ValueError, TypeError): genres = []
    try: countries = json.loads(row["countries"]) if row["countries"] else []
    except (ValueError, TypeError): countries = []
    try: subjects = json.loads(row["subjects"]) if row["subjects"] else []
    except (ValueError, TypeError): subjects = []
    try: languages = json.loads(row["languages"]) if row["languages"] else []
    except (ValueError, TypeError): languages = []

    directors = []
    try: directors = json.loads(row["directors"]) if row["directors"] else []
    except (ValueError, TypeError): pass
    director = directors[0] if directors else None

    video_file = build_video_file(row)
    download_url = build_download_url(row)

    return {
        "archiveID":        archive_id,
        "title":             row["title"],
        "year":              row["year"],
        "decade":            decade_for(row["year"]),
        "runtimeSeconds":    row["runtime_sec"],
        "synopsis":          row["description"],
        "collections":       collections_from_raw(row),
        "subjects":          subjects,
        "mediatype":         "movies" if best_type == "archive_org" else None,
        "language":          languages[0] if languages else None,
        "imdbID":            row["imdb_id"],
        "tmdbID":            int(row["tmdb_id"]) if row["tmdb_id"] and str(row["tmdb_id"]).isdigit() else None,
        "wikidataQID":       row["wikidata_qid"],
        "tvmazeID":          None,   # pipeline doesn't ingest TVmaze yet
        "videoFile":         video_file,
        "downloadURL":       download_url,
        "posterURL":         poster,
        "backdropURL":       None,   # pipeline single poster; backdrop cascade TBD
        "hasRealArtwork":    has_real_artwork,
        "artworkSource":     src,
        "contentType":       content_type,
        "genres":            genres,
        "countries":         countries,
        "cast":              cast,
        "director":          director,
        "producer":          None,
        "seriesName":        None,
        "network":           None,
        "enrichmentTier":    ("fullyEnriched" if row["imdb_id"]
                              else "identifierResolved" if row["wikidata_qid"]
                              else "archiveOnly"),
        "shelves":           shelves,
        # Optional additive fields (non-breaking in Swift's Decodable).
        "rightsStatus":      row["rights_status"],
        "qualityScore":      row["quality_score"],
        "popularityScore":   row["popularity_score"],
        "bestSourceType":    best_type,
        "isSilentFilm":      bool(row["is_silent"]),
    }


# ---------------------------------------------------------------------------
# Tiered selection — diversity + Editor's Picks override
# ---------------------------------------------------------------------------

def _selection_rank(item):
    """Secondary sort key for selection. Puts items with designed artwork
    first, breaking ties on popularity. Applied everywhere we might have
    to drop an item — guarantees we never lose a designed-art item to a
    placeholder-art item inside the same bucket.

    Python sorts ascending; we want art-first + popularity-desc:
      - `not hasRealArtwork` is False for art items → sorts before True.
      - `-popularityScore` puts high-pop first inside each group.
    """
    return (not bool(item.get("hasRealArtwork")),
            -(item.get("popularityScore") or 0))


def select_tiered(items, *, profile, editors_picks_ids, shelf_required_ids):
    """Pick up to profile.max_items with diversity across contentType,
    always preferring items with designed artwork within each bucket.

    Order of inclusion:
      1. Editor's Picks — mandatory, score-independent.
      2. Items referenced by any shelf — mandatory (curator intent). If
         the curator-mandatory set alone exceeds max_items, we still sort
         art-first + popularity-desc before capping.
      3. Round-robin fill from each contentType bucket, art-first within
         each, up to per_type_min per bucket.
      4. If cap isn't reached, top up with the highest-ranked residue
         (art-first, then popularity) regardless of type.
    """
    max_items = profile.get("max_items")
    per_type  = profile.get("per_type_min") or 0

    must_have = {i["archiveID"]: i for i in items
                 if i.get("archiveID") in editors_picks_ids
                 or i.get("archiveID") in shelf_required_ids
                 or any(sid for sid in (i.get("shelves") or []))}
    # Sort must_have by (art-first, popularity) so that if the curator-
    # mandatory set is already larger than max_items, the items we drop
    # are the ones without designed art rather than the ones with it.
    picked = sorted(must_have.values(), key=_selection_rank)

    if max_items is None:
        return items  # raw profile: no cap

    remaining = max_items - len(picked)
    if remaining <= 0:
        return picked[:max_items]

    # Bucket remainders by contentType
    used_ids = set(must_have.keys())
    pool = [i for i in items if i["archiveID"] not in used_ids]
    by_type = defaultdict(list)
    for i in pool:
        by_type[i.get("contentType") or "short-film"].append(i)
    for t in by_type:
        by_type[t].sort(key=_selection_rank)

    # Diversity pass: up to per_type from each bucket, art-first within.
    for t, bucket in by_type.items():
        take = min(per_type, len(bucket), remaining)
        picked.extend(bucket[:take])
        for x in bucket[:take]: used_ids.add(x["archiveID"])
        remaining -= take
        if remaining <= 0:
            break

    # Top-up pass: pop from the strongest-remaining, still art-first.
    if remaining > 0:
        leftover = sorted(
            (i for i in pool if i["archiveID"] not in used_ids),
            key=_selection_rank,
        )
        picked.extend(leftover[:remaining])

    # Final return order is popularity-desc — what the app expects for
    # snappy first-screen reads. (The art-preference has already done
    # its job during the *selection* above; display order is separate.)
    picked.sort(key=lambda x: (x.get("popularityScore") or 0), reverse=True)
    return picked[:max_items]


# ---------------------------------------------------------------------------
# TV series export
# ---------------------------------------------------------------------------
# When tv_series / tv_episodes tables exist, we emit:
#   - One compact SeriesCard per tv_series into the main catalog
#     (instead of ~11k individual tv-episode items).
#   - One per-series JSON blob under {out_dir}/series/{series_id}.json
#     with every episode's full metadata (title, overview, still, play
#     URL). The app lazy-loads these on Series Detail view.
# The set of canonical_ids in tv_episodes is excluded from the main
# catalog's regular item emission so we don't double-up.

def tv_episode_cids(conn):
    """Set of canonical_ids that are part of a tv_series — we never
    emit these as top-level catalog items."""
    return {r[0] for r in conn.execute("SELECT canonical_id FROM tv_episodes")}


def load_series_rows(conn):
    """All tv_series with any aggregated data. Ordered by popularity."""
    return conn.execute("""
        SELECT * FROM tv_series
        ORDER BY popularity_score DESC, title ASC
    """).fetchall()


def build_series_card(row):
    """Compact SeriesCard for the main catalog. The full episode list
    is fetched lazily from /series/{seriesID}.json."""
    poster = row["poster_url"]
    src = artwork_source_for(poster)
    has_real = src in ("tmdb", "fanart", "omdb", "commons", "wikidata", "aapb", "external")
    try: genres = json.loads(row["genres"]) if row["genres"] else []
    except (ValueError, TypeError): genres = []
    try: networks = json.loads(row["networks"]) if row["networks"] else []
    except (ValueError, TypeError): networks = []
    # Catalog.Item requires archiveID to decode — reuse the series slug
    # there. Most fields are populated with sane defaults so old app
    # builds that decode tv-series cards as regular Items still work
    # (they won't render episodes but at least they won't crash the
    # whole catalog decode with missing-key errors).
    return {
        "archiveID":        row["series_id"],
        "seriesID":         row["series_id"],
        "title":            row["title"],
        "year":             row["year_start"],
        "yearStart":        row["year_start"],
        "yearEnd":          row["year_end"],
        "decade":           (row["year_start"] // 10) * 10 if row["year_start"] else None,
        "runtimeSeconds":   None,
        "synopsis":         row["overview"],
        "overview":         row["overview"],
        "collections":      [],
        "subjects":         [],
        "mediatype":        None,
        "language":         None,
        "posterURL":        poster,
        "backdropURL":      row["backdrop_url"],
        "hasRealArtwork":   has_real,
        "artworkSource":    src,
        "contentType":      "tv-series",
        "genres":           genres,
        "countries":        [],
        "cast":             [],
        "director":         None,
        "producer":         None,
        "seriesName":       row["title"],
        "network":          (networks[0] if networks else None),
        "networks":         networks,
        "creator":          row["creator"],
        "seasonsCount":     row["seasons_count"] or 0,
        "episodesCount":    row["episodes_count"] or 0,
        "tmdbID":           int(row["tmdb_id"]) if row["tmdb_id"] and str(row["tmdb_id"]).isdigit() else None,
        "wikidataQID":      row["wikidata_qid"],
        "imdbID":           row["imdb_id"],
        "tvmazeID":         None,
        "videoFile":        None,
        "downloadURL":      None,
        "shelves":          [],
        "enrichmentTier":   "fullyEnriched" if row["tmdb_id"] else "archiveOnly",
        "popularityScore":  row["popularity_score"] or 0,
        "qualityScore":     row["quality_score"] or 0,
    }


def load_all_episodes(conn):
    """One-shot fetch of every TV episode with its best source attached,
    grouped by series_id in Python. Replaces a per-series correlated-
    view query that cost 1.6s × 6,783 = 3hrs. One-pass costs <5s.

    Returns: {series_id: [episode_row_dict, ...]} already sorted by
    (season_number, episode_number, title).
    """
    # One joined query + a window function to pick the best source per
    # canonical_id. The VIEW works_with_best_source does the same thing
    # per-canonical_id via correlated subquery, which prevents SQLite's
    # planner from caching — doing it in a single pass is orders of
    # magnitude faster.
    rows = conn.execute("""
        WITH best_source AS (
            SELECT
                canonical_id, source_type, stream_url, derivative_name,
                format_hint, file_size, verified_playable,
                ROW_NUMBER() OVER (
                    PARTITION BY canonical_id
                    ORDER BY
                        CASE WHEN verified_playable = 1 THEN 0 ELSE 1 END,
                        source_quality DESC, id ASC
                ) AS rn
            FROM sources
        )
        SELECT te.canonical_id, te.series_id, te.season_number, te.episode_number,
               te.title AS ep_title, te.overview, te.still_url, te.air_date,
               w.title AS raw_title, w.year, w.runtime_sec,
               bs.stream_url, bs.derivative_name, bs.source_type,
               bs.file_size, bs.format_hint, bs.verified_playable,
               e.poster_url AS ep_poster
        FROM tv_episodes te
        JOIN works w ON w.canonical_id = te.canonical_id
        LEFT JOIN best_source bs ON bs.canonical_id = te.canonical_id AND bs.rn = 1
        LEFT JOIN enrichment e ON e.canonical_id = te.canonical_id
        ORDER BY te.series_id,
          CASE WHEN te.season_number IS NULL THEN 9999 ELSE te.season_number END,
          CASE WHEN te.episode_number IS NULL THEN 9999 ELSE te.episode_number END,
          w.title
    """).fetchall()
    grouped = defaultdict(list)
    for r in rows:
        grouped[r["series_id"]].append(dict(r))
    return grouped


def build_series_detail(series_row, episodes_by_series_id):
    """Full per-series JSON: series header + seasons[].episodes[]. Episodes
    are grouped by season_number (NULL → 0 bucket). Each episode carries
    its Archive playback URL so the player never needs a second lookup."""
    series_id = series_row["series_id"]
    eps = episodes_by_series_id.get(series_id, [])

    seasons = {}
    for e in eps:
        sn = e["season_number"] if e["season_number"] is not None else 0
        dl = e.get("stream_url") or ""
        # Reject unplayable folder URLs (same guard as build_download_url).
        if dl and re.match(r"^https?://archive\.org/download/[^/]+/?$", dl):
            dl = ""
        if e.get("derivative_name"):
            video_file = {
                "name":      e["derivative_name"],
                "format":    e.get("format_hint") or "h.264",
                "sizeBytes": int(e["file_size"]) if e.get("file_size") else None,
                "tier":      1 if e.get("verified_playable") == 1 else 2,
            }
        else:
            video_file = None

        # archiveID: pipeline stores archive_org source_id in sources;
        # the canonical_id is our join key. For Archive-sourced episodes
        # the archiveID == the archive.org identifier embedded in the
        # stream URL. Pull it from the URL if we can.
        archive_id = e["canonical_id"]
        m = re.match(r"https?://archive\.org/download/([^/]+)/", dl or "")
        if m:
            archive_id = m.group(1)

        ep_dict = {
            "archiveID":        archive_id,
            "seasonNumber":     e["season_number"],
            "episodeNumber":    e["episode_number"],
            "title":            e.get("ep_title") or e.get("raw_title"),
            "overview":         e.get("overview"),
            "stillURL":         e.get("still_url") or e.get("ep_poster"),
            "airDate":          e.get("air_date"),
            "year":             e.get("year"),
            "runtimeSeconds":   e.get("runtime_sec"),
            "videoFile":        video_file,
            "downloadURL":      dl or None,
        }
        seasons.setdefault(sn, []).append(ep_dict)

    season_list = [
        {
            "seasonNumber": sn if sn != 0 else None,
            "episodes":     eps_list,
        }
        for sn, eps_list in sorted(seasons.items())
    ]

    card = build_series_card(series_row)
    return {
        "version":      1,
        "seriesID":     series_id,
        "title":        card["title"],
        "yearStart":    card["yearStart"],
        "yearEnd":      card["yearEnd"],
        "overview":     card["overview"],
        "posterURL":    card["posterURL"],
        "backdropURL":  card["backdropURL"],
        "genres":       card["genres"],
        "networks":     card["networks"],
        "creator":      card["creator"],
        "seasons":      season_list,
        "episodesCount": sum(len(s["episodes"]) for s in season_list),
    }


def export_tv_series(conn, out_dir_main_catalog, *, write_details=True):
    """Return the list of SeriesCards for inclusion in the main catalog.
    When write_details=True (the hosted full catalog), ALSO writes
    per-series JSON files under {main_catalog_parent}/series/ — lazy-
    loaded by the app on Series Detail open. The seed catalog passes
    write_details=False because those JSONs don't belong inside the
    app bundle (they're ~29 MB total, hosted on Pages instead)."""
    series_rows = load_series_rows(conn)

    # Pre-compute the set of series_ids that have ≥1 playable episode in
    # a single batched query. The per-series join-with-view was 0.36s
    # each, which times-out at 6.7k series (~40 min). Raw sources table
    # join completes in one SQLite pass.
    playable_series_ids = {
        r[0] for r in conn.execute("""
            SELECT DISTINCT te.series_id
            FROM tv_episodes te
            JOIN sources s ON s.canonical_id = te.canonical_id
            WHERE s.stream_url IS NOT NULL AND s.stream_url != ''
        """)
    }

    # Load ALL episodes once (only when we'll actually write details;
    # the card-only path doesn't need them and skipping it saves ~5s).
    episodes_by_series = load_all_episodes(conn) if write_details else {}

    cards = []
    series_dir = Path(out_dir_main_catalog).parent / "series"
    if write_details:
        series_dir.mkdir(parents=True, exist_ok=True)
    written = 0
    for row in series_rows:
        if row["series_id"] not in playable_series_ids:
            continue
        card = build_series_card(row)
        cards.append(card)
        if write_details:
            detail = build_series_detail(row, episodes_by_series)
            out = series_dir / f"{row['series_id']}.json"
            with open(out, "w", encoding="utf-8") as f:
                json.dump(detail, f, ensure_ascii=False, indent=2)
            written += 1
    if write_details:
        print(f"[export-tv] wrote {written:,} per-series JSON files to {series_dir}")
    else:
        print(f"[export-tv] built {len(cards):,} series cards (no per-series JSONs)")
    return cards


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db",       default="SchemaWork/video_registry.db")
    ap.add_argument("--featured", default="featured.json")
    ap.add_argument("--out",      default="ArchiveWatch/ArchiveWatch/catalog.json")
    ap.add_argument("--mode", choices=list(PROFILES.keys()), default="seed",
                    help="Export profile. seed=bundled (~3k), full=hosted "
                         "(~25k), raw=no caps (for debugging).")
    # Advanced overrides — only use if you know what you're doing.
    ap.add_argument("--min-quality",    type=int)
    ap.add_argument("--min-popularity", type=int)
    ap.add_argument("--max-items",      type=int)
    ap.add_argument("--require-playable", action="store_true",
                    help="Force require verified_playable even in raw mode.")
    ap.add_argument("--require-artwork",  action="store_true",
                    help="Force require hasRealArtwork.")
    args = ap.parse_args()

    # Apply profile with CLI overrides on top.
    profile = dict(PROFILES[args.mode])
    if args.min_quality    is not None: profile["min_quality"]    = args.min_quality
    if args.min_popularity is not None: profile["min_popularity"] = args.min_popularity
    if args.max_items      is not None: profile["max_items"]      = args.max_items
    if args.require_playable:           profile["require_playable"] = True
    if args.require_artwork:            profile["require_artwork"]  = True

    db_path = Path(args.db)
    if not db_path.exists():
        print(f"[export] DB not found: {db_path}\n"
              f"         Run `python SchemaWork/registry_pipeline.py` first.",
              file=sys.stderr)
        sys.exit(2)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row

    with open(args.featured, "r", encoding="utf-8") as f:
        featured = json.load(f)

    # Load the OMDb backfill cache if present — lets us apply workflow-
    # accumulated poster wins to newly-exported rows without needing the
    # live DB to be refreshed. Missing/malformed cache is fine — we just
    # skip the overlay.
    omdb_cache = {}
    cache_path = Path(__file__).resolve().parent.parent / "shared" / "editorial" / "omdb_cache.json"
    if cache_path.exists():
        try:
            omdb_cache = (json.loads(cache_path.read_text(encoding="utf-8"))
                          .get("entries") or {})
        except (ValueError, OSError):
            omdb_cache = {}

    # 1. Compute shelf membership: for each shelf, list canonical_ids.
    shelf_ids = {}  # canonical_id -> [shelf_id]
    for shelf in featured.get("shelves", []):
        members = resolve_shelf_items(conn, shelf)
        for cid in members:
            shelf_ids.setdefault(cid, []).append(shelf["id"])

    # TV episodes live in their own table and are emitted as series
    # cards (compact) + per-series JSON files (lazy-loaded by the app).
    # Exclude their canonical_ids from the regular item emission so we
    # don't double-count them.
    tv_ep_cids = tv_episode_cids(conn)

    # Collect the union of "works we want to emit": everything passing the
    # profile's score thresholds + everything pulled in by any shelf (so
    # curated picks survive score filtering). Editor's Picks survive cap
    # selection too (handled in select_tiered).
    defaulted = {
        r[0] for r in conn.execute(
            f"""SELECT canonical_id FROM works
                WHERE quality_score    >= {int(profile['min_quality'])}
                  AND popularity_score >= {int(profile['min_popularity'])}"""
        )
    }
    emit_set = (defaulted | set(shelf_ids.keys())) - tv_ep_cids

    # 2. Pull the fat join for every emitted work.
    placeholders = ",".join(["?"] * len(emit_set)) if emit_set else "NULL"
    rows = conn.execute(
        f"""SELECT wbs.*, s.raw_json
            FROM works_with_best_source wbs
            LEFT JOIN sources s ON s.id = (
                SELECT id FROM sources
                WHERE canonical_id = wbs.canonical_id
                ORDER BY
                    CASE WHEN verified_playable = 1 THEN 0 ELSE 1 END,
                    source_quality DESC, id ASC
                LIMIT 1
            )
            WHERE wbs.canonical_id IN ({placeholders})""",
        tuple(emit_set),
    ).fetchall()

    # 3. Build items + apply hard filters from the profile.
    items = []
    dropped_unplayable = dropped_no_artwork = 0
    for row in rows:
        item = build_item(row, shelf_ids, omdb_cache=omdb_cache)
        if profile.get("require_playable") and not item["downloadURL"]:
            dropped_unplayable += 1
            continue
        if profile.get("require_artwork") and not item.get("hasRealArtwork"):
            # Editor's Picks always survive, even without artwork — the app
            # has a procedural fallback poster renderer for these.
            if not any(sid == "editors-picks" for sid in (item.get("shelves") or [])):
                dropped_no_artwork += 1
                continue
        items.append(item)

    # 4. Apply tiered selection (diversity + cap).
    editors_picks_ids = set()
    for shelf in featured.get("shelves", []):
        if shelf.get("id") == "editors-picks":
            for e in shelf.get("items", []) or []:
                if isinstance(e, dict) and e.get("archiveID"):
                    editors_picks_ids.add(e["archiveID"])
            break
    shelf_required_ids = set()  # reserved for future "always-include" shelves
    items = select_tiered(
        items,
        profile=profile,
        editors_picks_ids=editors_picks_ids,
        shelf_required_ids=shelf_required_ids,
    )

    # 4b. Emit TV series cards. Per-series JSON files are only written
    # for the hosted full catalog (never the bundled seed — those JSONs
    # live on GH Pages for lazy-load). Seed gets a top-120 capped subset
    # to keep the bundle compact.
    series_cards = export_tv_series(
        conn, args.out, write_details=(args.mode != "seed"),
    )
    if args.mode == "seed":
        series_cards = series_cards[:120]
    items = items + series_cards

    # 4. Compute stats for the bundle header.
    n = len(items)
    stats = {
        "totalItems":         n,
        "itemsWithIMDb":      sum(1 for i in items if i.get("imdbID")),
        "itemsWithTMDb":      sum(1 for i in items if i.get("tmdbID")),
        "itemsWithWikidata":  sum(1 for i in items if i.get("wikidataQID")),
        "fullyEnriched":      sum(1 for i in items if i.get("enrichmentTier") == "fullyEnriched"),
        "itemsPlayable":      sum(1 for i in items if i.get("downloadURL")),
    }

    catalog = {
        "version":     1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "generator":   f"export_catalog.py mode={args.mode}",
        "mode":        args.mode,
        "stats":       stats,
        "items":       items,
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    size_mb = out_path.stat().st_size / (1024 * 1024)
    print(f"[export] mode={args.mode}  wrote {n} items to {out_path}  ({size_mb:.1f} MB)")
    print(f"         playable={stats['itemsPlayable']}  IMDb={stats['itemsWithIMDb']}  "
          f"TMDb={stats['itemsWithTMDb']}  WD={stats['itemsWithWikidata']}")
    if dropped_unplayable:
        print(f"         dropped {dropped_unplayable} items with no verified stream")
    if dropped_no_artwork:
        print(f"         dropped {dropped_no_artwork} items with no real artwork (seed requires it)")
    conn.close()


if __name__ == "__main__":
    main()
