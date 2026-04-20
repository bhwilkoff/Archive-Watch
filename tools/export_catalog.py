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
        "require_artwork":   True,   # must have real designed poster
        "require_playable":  True,   # must have a verified MP4 url
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
        sql = f"""
            SELECT works.canonical_id
            FROM works
            JOIN sources  ON sources.canonical_id = works.canonical_id
                         AND sources.source_type = 'archive_org'
            LEFT JOIN engagement ON engagement.source_type = sources.source_type
                                AND engagement.source_id   = sources.source_id
            WHERE sources.raw_json LIKE ?
              AND works.quality_score    >= 40
              AND works.popularity_score >= 25
            GROUP BY works.canonical_id
            ORDER BY {order_by}
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
    off this. TMDb/Commons/Wikidata posters are "real designed art";
    Archive thumbnails are placeholder-territory."""
    if not url:
        return "none"
    low = url.lower()
    if "image.tmdb.org" in low:
        return "tmdb"
    if "upload.wikimedia.org" in low or "commons.wikimedia.org" in low:
        return "commons"
    if "wikidata.org" in low:
        return "wikidata"
    if "archive.org" in low:
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


def build_item(row, shelf_membership):
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
    has_real_artwork = src in ("tmdb", "commons", "wikidata", "external")

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

def select_tiered(items, *, profile, editors_picks_ids, shelf_required_ids):
    """Pick up to profile.max_items with diversity across contentType.

    Order of inclusion:
      1. Editor's Picks — mandatory, score-independent.
      2. Items referenced by any shelf — mandatory (curator intent).
      3. Round-robin fill from each contentType bucket by popularity, up to
         per_type_min per bucket.
      4. If cap isn't reached, top up with the highest-popularity residue
         regardless of type.
    """
    max_items = profile.get("max_items")
    per_type  = profile.get("per_type_min") or 0

    must_have = {i["archiveID"]: i for i in items
                 if i.get("archiveID") in editors_picks_ids
                 or i.get("archiveID") in shelf_required_ids
                 or any(sid for sid in (i.get("shelves") or []))}
    picked = list(must_have.values())

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
        by_type[t].sort(key=lambda x: (x.get("popularityScore") or 0), reverse=True)

    # Diversity pass: up to per_type from each bucket
    for t, bucket in by_type.items():
        take = min(per_type, len(bucket), remaining)
        picked.extend(bucket[:take])
        for x in bucket[:take]: used_ids.add(x["archiveID"])
        remaining -= take
        if remaining <= 0:
            break

    # Top-up pass: pop from the strongest-remaining regardless of type
    if remaining > 0:
        leftover = sorted(
            (i for i in pool if i["archiveID"] not in used_ids),
            key=lambda x: (x.get("popularityScore") or 0), reverse=True,
        )
        picked.extend(leftover[:remaining])

    # Return in popularity order so the app's first shelf reads are snappy.
    picked.sort(key=lambda x: (x.get("popularityScore") or 0), reverse=True)
    return picked[:max_items]


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

    # 1. Compute shelf membership: for each shelf, list canonical_ids.
    shelf_ids = {}  # canonical_id -> [shelf_id]
    for shelf in featured.get("shelves", []):
        members = resolve_shelf_items(conn, shelf)
        for cid in members:
            shelf_ids.setdefault(cid, []).append(shelf["id"])

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
    emit_set = defaulted | set(shelf_ids.keys())

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
        item = build_item(row, shelf_ids)
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
