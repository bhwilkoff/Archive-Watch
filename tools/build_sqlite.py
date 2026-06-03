#!/usr/bin/env python3
"""
build_sqlite.py — compile catalog.json + series/*.json into a prebuilt SQLite
database the tvOS app queries on disk (Decision 017).

Why: the app can't hold a 100k-item catalog in RAM (3 GB device shared with
4K AVPlayer). SQLite lets it query on disk — only visible rows are resident —
with FTS5 search. SQLite + FTS5 are built into tvOS (no third-party package).

Output:
  catalog.sqlite       (the DB)
  catalog.sqlite.gz    (gzipped for upload; ~5x smaller)
  catalog-manifest.json (version pointer the app fetches first)

Schema (see docs/architecture/catalog-delivery.md):
  items        — lean browse/home/search columns (the hot path)
  item_detail  — heavy fields fetched by PK on the Detail screen
  item_genres  — (archiveID, genre) for indexed genre filtering
  item_shelves — (shelfID, archiveID, position) for Home shelves
  items_fts    — FTS5(archiveID UNINDEXED, title, names) for search
  series, episodes — TV
  meta         — generatedAt / schemaVersion / counts

IMDb-dedup happens HERE (best copy per imdb id) so the app never does an
in-memory dedup pass.

Usage:
  python tools/build_sqlite.py
  python tools/build_sqlite.py --no-gzip      # skip the .gz (faster local test)
"""

import argparse
import datetime as _dt
import gzip
import json
import random
import shutil
import sqlite3
import zlib
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
FEATURED = REPO / "featured.json"

# Adult-collection markers (Decision 012), from featured.json with a fallback.
# isAdult is computed at build time so the app filters via a WHERE clause
# instead of scanning each item's collections at runtime.
def _adult_markers():
    try:
        raw = json.loads(FEATURED.read_text(encoding="utf-8")).get("adultCollections")
    except Exception:
        raw = None
    raw = raw or ["pron", "adult", "erotica", "sexploitation", "nudism", "mature-content"]
    return [m.lower() for m in raw if m.lower() != "fav-"]

ADULT_MARKERS = _adult_markers()

# Only the curator-registered collections are browseable (CollectionsView reads
# collection_metadata.json), so item_collections stores just those — not all
# ~48 noisy Archive memberships per item.
def _registered_collections():
    try:
        d = json.loads((REPO / "shared" / "editorial" / "collection_metadata.json").read_text())
        return {c["id"] for c in d.get("collections", [])}
    except Exception:
        return set()

REGISTERED_COLLECTIONS = _registered_collections()

def _is_adult(it):
    # Honor the item-level flag set by remediate_catalog.py (subject/genre/
    # title keyword detection — catches adult films that aren't in an adult
    # COLLECTION, e.g. foreign sexploitation like "Carne"). Then fall back to
    # the collection markers.
    if it.get("isAdult"):
        return 1
    for c in (it.get("collections") or []):
        cl = str(c).lower()
        if any(m in cl for m in ADULT_MARKERS):
            return 1
    return 0
SERIES_DIR = REPO / "series"
OUT_DB = REPO / "catalog.sqlite"
OUT_GZ = REPO / "catalog.sqlite.gz"
# Raw-DEFLATE (RFC1951, no container) for the app to inflate with Apple's
# native Compression framework (COMPRESSION_ZLIB == raw deflate). Decision 019.
OUT_ZZ = REPO / "catalog.sqlite.zz"
OUT_MANIFEST = REPO / "catalog-manifest.json"

SCHEMA_VERSION = 1


def jdump(v):
    return json.dumps(v, ensure_ascii=False, separators=(",", ":")) if v else None


def _t(v):
    """Coerce a value to TEXT-or-None. Archive metadata fields are sometimes
    lists (e.g. multiple descriptions) — flatten so SQLite can bind them."""
    if v is None:
        return None
    if isinstance(v, str):
        return v
    if isinstance(v, list):
        return " ".join(str(x) for x in v) or None
    return str(v)


def dedupe_by_imdb(items):
    """Keep the best single item per IMDb id (mirrors AppStore.dedupedByIMDb);
    items without an imdb id are all kept."""
    def score(i):
        r = 0
        if i.get("hasRealArtwork") or (i.get("artworkSource") not in (None, "archive")):
            r += 8
        if i.get("enrichmentTier") == "fullyEnriched":
            r += 4
        if (i.get("downloadURL") or "").lower().endswith(".mp4"):
            r += 2
        if i.get("runtimeSeconds"):
            r += 1
        return (r, i.get("imdbVotes") or 0, i.get("archiveID") or "")
    best = {}
    for it in items:
        k = it.get("imdbID")
        if not k:
            continue
        if k not in best or score(it) > score(best[k]):
            best[k] = it
    winners = {b["archiveID"] for b in best.values()}
    out = []
    for it in items:
        k = it.get("imdbID")
        if not k or it["archiveID"] in winners:
            out.append(it)
    return out


def create_schema(db):
    db.executescript("""
    PRAGMA journal_mode = OFF;
    PRAGMA synchronous = OFF;

    CREATE TABLE items (
      archiveID TEXT PRIMARY KEY, title TEXT, year INTEGER, decade INTEGER,
      runtimeSeconds INTEGER, contentType TEXT, posterURL TEXT,
      hasRealArtwork INTEGER, artworkSource TEXT, imdbID TEXT,
      imdbRating REAL, imdbVotes INTEGER, popularityScore INTEGER,
      qualityScore INTEGER, isSilentFilm INTEGER, rightsStatus TEXT,
      contentRating TEXT, language TEXT, network TEXT, director TEXT,
      seriesID TEXT, yearEnd INTEGER, seasonsCount INTEGER, episodesCount INTEGER,
      isAdult INTEGER
    );
    -- Full item as JSON in a side table so the lean `items` table stays small
    -- for scalar WHERE/ORDER scans; the app JOINs this only for the handful of
    -- rows a screen actually shows and decodes them with the existing Codable.
    -- Full item as JSON; the app JOINs + decodes only the rows a screen shows.
    CREATE TABLE item_json (archiveID TEXT PRIMARY KEY, json TEXT);
    CREATE TABLE item_genres (archiveID TEXT, genre TEXT);
    CREATE TABLE item_collections (archiveID TEXT, collection TEXT);
    CREATE TABLE item_shelves (shelfID TEXT, archiveID TEXT, position INTEGER);
    CREATE TABLE series (
      seriesID TEXT PRIMARY KEY, title TEXT, yearStart INTEGER, yearEnd INTEGER,
      overview TEXT, posterURL TEXT, backdropURL TEXT, networks_json TEXT,
      genres_json TEXT, creator TEXT, tvmazeID INTEGER,
      episodesCount INTEGER, canonicalEpisodesCount INTEGER
    );
    CREATE TABLE episodes (
      seriesID TEXT, seasonNumber INTEGER, episodeNumber INTEGER, title TEXT,
      overview TEXT, stillURL TEXT, airDate TEXT, year INTEGER,
      runtimeSeconds INTEGER, downloadURL TEXT, videoFile_json TEXT, position INTEGER
    );
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);

    CREATE VIRTUAL TABLE items_fts USING fts5(archiveID UNINDEXED, title, names);
    """)


def _rotated_shelf_positions(items, rotate_seed):
    """Date-seeded editorial rotation (#10). Returns {(shelfID, archiveID):
    position}. Each shelf's members are shuffled with a per-shelf, per-day seed
    so the leading titles change daily — the seed.sqlite first paint and the
    Top Shelf snapshot (neither of which gets the app's per-visit shuffle) stay
    fresh. Real-artwork items still sort ahead of placeholders at query time
    (CatalogDB.shelf ORDER BY hasRealArtwork DESC, position), so rotation only
    reshuffles WITHIN those bands — it never surfaces a poster-less tile first."""
    members = defaultdict(list)
    for it in items:
        aid = it.get("archiveID")
        if not aid:
            continue
        for s in (it.get("shelves") or []):
            members[s].append(aid)
    positions = {}
    for shelf_id, aids in members.items():
        rng = random.Random(f"{shelf_id}:{rotate_seed}")
        rng.shuffle(aids)
        for pos, aid in enumerate(aids):
            positions[(shelf_id, aid)] = pos
    return positions


def populate_items(db, items, rotate_seed="0"):
    item_rows, json_rows, genre_rows, coll_rows, shelf_rows, fts_rows = [], [], [], [], [], []
    shelf_pos = _rotated_shelf_positions(items, rotate_seed)
    for it in items:
        aid = it["archiveID"]
        item_rows.append((
            aid, _t(it.get("title")), it.get("year"), it.get("decade"),
            it.get("runtimeSeconds"), _t(it.get("contentType")), _t(it.get("posterURL")),
            1 if (it.get("hasRealArtwork") or it.get("artworkSource") not in (None, "archive")) else 0,
            _t(it.get("artworkSource")), _t(it.get("imdbID")), it.get("imdbRating"),
            it.get("imdbVotes"), it.get("popularityScore"), it.get("qualityScore"),
            1 if (it.get("isSilentFilm") or it.get("contentType") == "silent-film") else 0,
            _t(it.get("rightsStatus")), _t(it.get("contentRating")), _t(it.get("language")),
            _t(it.get("network")), _t(it.get("director")), _t(it.get("seriesID")),
            it.get("yearEnd"), it.get("seasonsCount"), it.get("episodesCount"),
            _is_adult(it),
        ))
        json_rows.append((aid, json.dumps(it, ensure_ascii=False, separators=(",", ":"))))
        for g in (it.get("genres") or []):
            if g:
                genre_rows.append((aid, g))
        for c in (it.get("collections") or []):
            if c and str(c) in REGISTERED_COLLECTIONS:
                coll_rows.append((aid, str(c)))
        for s in (it.get("shelves") or []):
            shelf_rows.append((s, aid, shelf_pos.get((s, aid), 0)))
        names = " ".join([it.get("director") or ""]
                         + [c.get("name", "") for c in (it.get("cast") or [])]
                         + [it.get("producer") or ""]).strip()
        fts_rows.append((aid, it.get("title") or "", names))

    db.executemany("INSERT OR IGNORE INTO items VALUES (%s)" % ",".join("?" * 25), item_rows)
    db.executemany("INSERT OR IGNORE INTO item_json VALUES (?,?)", json_rows)
    db.executemany("INSERT INTO item_genres VALUES (?,?)", genre_rows)
    db.executemany("INSERT INTO item_collections VALUES (?,?)", coll_rows)
    db.executemany("INSERT INTO item_shelves VALUES (?,?,?)", shelf_rows)
    db.executemany("INSERT INTO items_fts VALUES (?,?,?)", fts_rows)
    return len(item_rows)


def populate_series(db):
    s_rows, e_rows = [], []
    for f in sorted(SERIES_DIR.glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        sid = d.get("seriesID") or f.stem
        s_rows.append((
            sid, d.get("title"), d.get("yearStart"), d.get("yearEnd"),
            d.get("overview"), d.get("posterURL"), d.get("backdropURL"),
            jdump(d.get("networks")), jdump(d.get("genres")), d.get("creator"),
            d.get("tvmazeID"), d.get("episodesCount"), d.get("canonicalEpisodesCount"),
        ))
        pos = 0
        for season in d.get("seasons", []):
            for ep in season.get("episodes", []):
                e_rows.append((
                    sid, ep.get("seasonNumber"), ep.get("episodeNumber"),
                    ep.get("title"), ep.get("overview"), ep.get("stillURL"),
                    ep.get("airDate"), ep.get("year"), ep.get("runtimeSeconds"),
                    ep.get("downloadURL"), jdump(ep.get("videoFile")), pos,
                ))
                pos += 1
    db.executemany("INSERT OR IGNORE INTO series VALUES (%s)" % ",".join("?" * 13), s_rows)
    db.executemany("INSERT INTO episodes VALUES (%s)" % ",".join("?" * 12), e_rows)
    return len(s_rows), len(e_rows)


def create_indexes(db):
    db.executescript("""
    CREATE INDEX idx_items_type     ON items(contentType);
    CREATE INDEX idx_items_decade   ON items(decade);
    CREATE INDEX idx_items_pop      ON items(popularityScore DESC);
    CREATE INDEX idx_items_series   ON items(seriesID);
    CREATE INDEX idx_genres_genre   ON item_genres(genre);
    CREATE INDEX idx_genres_item    ON item_genres(archiveID);
    CREATE INDEX idx_coll_coll      ON item_collections(collection);
    CREATE INDEX idx_items_director ON items(director);
    CREATE INDEX idx_items_quality  ON items(qualityScore);
    CREATE INDEX idx_shelves_shelf  ON item_shelves(shelfID);
    CREATE INDEX idx_episodes_series ON episodes(seriesID, position);
    """)


SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
SEED_DB = REPO / "ArchiveWatch" / "ArchiveWatch" / "seed.sqlite"


# First-paint seed size. The app shows this instantly from the app bundle,
# then swaps to the full downloaded DB within seconds (Decision 017/018), so
# the seed only needs enough to make Home + the TV tab look populated.
SEED_ITEM_LIMIT = 1500


def select_seed_items(items):
    """Pick a small first-paint subset of catalog items: every TV-series card
    (so the TV tab works offline-first), every shelf-referenced item (so Home's
    curated shelves paint), plus the top-N by popularity for Browse/hero. The
    bundled seed is derived from the full catalog so we no longer commit a
    separate 14 MB seed catalog.json (Decision 018)."""
    chosen = {}
    for it in items:
        aid = it.get("archiveID")
        if not aid:
            continue
        if it.get("contentType") == "tv-series" or it.get("shelves"):
            chosen[aid] = it
    ranked = sorted((it for it in items if it.get("archiveID")),
                    key=lambda it: (it.get("popularityScore") or 0), reverse=True)
    for it in ranked[:SEED_ITEM_LIMIT]:
        chosen[it["archiveID"]] = it
    return list(chosen.values())


def build_db_obj(cat, out_db, rotate_seed="0"):
    """Compile an in-memory catalog dict into a SQLite DB at out_db. Returns
    (cat, n_items, n_series, n_eps)."""
    deduped = dedupe_by_imdb(cat["items"])
    if out_db.exists():
        out_db.unlink()
    db = sqlite3.connect(out_db)
    create_schema(db)
    n_items = populate_items(db, deduped, rotate_seed=rotate_seed)
    n_series, n_eps = populate_series(db)
    create_indexes(db)
    db.execute("INSERT OR REPLACE INTO meta VALUES ('schemaVersion', ?)", (str(SCHEMA_VERSION),))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('generatedAt', ?)", (cat.get("generatedAt", ""),))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('itemCount', ?)", (str(n_items),))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('seriesCount', ?)", (str(n_series),))
    db.commit()
    db.execute("PRAGMA optimize")
    db.execute("VACUUM")
    db.close()
    print(f"[sqlite] wrote {out_db.name}: {out_db.stat().st_size/1e6:.1f} MB "
          f"({n_items:,} items, {n_series:,} series, {n_eps:,} episodes)", flush=True)
    return cat, n_items, n_series, n_eps


def build_db(catalog_path, out_db, rotate_seed="0"):
    """Compile a catalog.json file into a SQLite DB at out_db."""
    return build_db_obj(json.loads(catalog_path.read_text(encoding="utf-8")),
                        out_db, rotate_seed=rotate_seed)


def build_seed_db(full_catalog_path, out_db, rotate_seed="0"):
    """Build the small bundled seed DB from the FULL catalog's first-paint
    subset — no separate committed seed catalog.json (Decision 018)."""
    cat = json.loads(full_catalog_path.read_text(encoding="utf-8"))
    seed = dict(cat)
    seed["items"] = select_seed_items(cat["items"])
    return build_db_obj(seed, out_db, rotate_seed=rotate_seed)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-gzip", action="store_true")
    ap.add_argument("--seed-only", action="store_true",
                    help="Build only the bundled seed.sqlite (fast, for app dev).")
    ap.add_argument("--rotate-seed", default=None,
                    help="Editorial-rotation seed (#10). Default: today's UTC "
                         "date (YYYYMMDD) so the daily publish-db cron rotates "
                         "each shelf's leading titles. Pass a fixed value for "
                         "reproducible local builds.")
    args = ap.parse_args()
    rotate_seed = args.rotate_seed or _dt.datetime.now(_dt.timezone.utc).strftime("%Y%m%d")
    print(f"[sqlite] shelf rotation seed: {rotate_seed}", flush=True)

    # Bundled seed DB — small first-paint slice derived from the FULL catalog
    # (Decision 018: no committed seed catalog.json). Falls back to a legacy
    # committed seed catalog.json if the full catalog isn't present locally.
    if FULL_CATALOG.exists():
        build_seed_db(FULL_CATALOG, SEED_DB, rotate_seed=rotate_seed)
    elif SEED_CATALOG.exists():
        build_db(SEED_CATALOG, SEED_DB, rotate_seed=rotate_seed)
    else:
        print("[sqlite] no catalog.json found to build the seed from", flush=True)
        return 1
    if args.seed_only:
        return 0

    # Full DB — hosted on the catalog-db release, downloaded at runtime.
    cat, n_items, n_series, n_eps = build_db(FULL_CATALOG, OUT_DB, rotate_seed=rotate_seed)

    zz_mb = None
    if not args.no_gzip:
        # Raw DEFLATE (wbits=-15: no zlib/gzip wrapper) — the app's native
        # Compression-framework inflate consumes this directly (Decision 019).
        comp = zlib.compressobj(9, zlib.DEFLATED, -15)
        with open(OUT_DB, "rb") as fi, open(OUT_ZZ, "wb") as fo:
            while chunk := fi.read(1 << 20):
                fo.write(comp.compress(chunk))
            fo.write(comp.flush())
        zz_mb = OUT_ZZ.stat().st_size / 1e6
        print(f"[sqlite] wrote {OUT_ZZ.name}: {zz_mb:.1f} MB raw-deflate", flush=True)

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": cat.get("generatedAt", ""),
        "itemCount": n_items, "seriesCount": n_series, "episodeCount": n_eps,
        "dbBytes": OUT_DB.stat().st_size,
        "zzBytes": (OUT_ZZ.stat().st_size if zz_mb else None),
        "asset": "catalog.sqlite.zz",
    }
    OUT_MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"[sqlite] wrote {OUT_MANIFEST.name}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
