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
import gzip
import json
import shutil
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SERIES_DIR = REPO / "series"
OUT_DB = REPO / "catalog.sqlite"
OUT_GZ = REPO / "catalog.sqlite.gz"
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
      contentRating TEXT, language TEXT, network TEXT,
      seriesID TEXT, yearEnd INTEGER, seasonsCount INTEGER, episodesCount INTEGER
    );
    -- Full item as JSON in a side table so the lean `items` table stays small
    -- for scalar WHERE/ORDER scans; the app JOINs this only for the handful of
    -- rows a screen actually shows and decodes them with the existing Codable.
    CREATE TABLE item_json (archiveID TEXT PRIMARY KEY, json TEXT);
    CREATE TABLE item_genres (archiveID TEXT, genre TEXT);
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


def populate_items(db, items):
    item_rows, json_rows, genre_rows, shelf_rows, fts_rows = [], [], [], [], []
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
            _t(it.get("network")), _t(it.get("seriesID")), it.get("yearEnd"),
            it.get("seasonsCount"), it.get("episodesCount"),
        ))
        json_rows.append((aid, json.dumps(it, ensure_ascii=False, separators=(",", ":"))))
        for g in (it.get("genres") or []):
            if g:
                genre_rows.append((aid, g))
        for s in (it.get("shelves") or []):
            shelf_rows.append((s, aid, 0))
        names = " ".join([it.get("director") or ""]
                         + [c.get("name", "") for c in (it.get("cast") or [])]
                         + [it.get("producer") or ""]).strip()
        fts_rows.append((aid, it.get("title") or "", names))

    db.executemany("INSERT OR IGNORE INTO items VALUES (%s)" % ",".join("?" * 23), item_rows)
    db.executemany("INSERT OR IGNORE INTO item_json VALUES (?,?)", json_rows)
    db.executemany("INSERT INTO item_genres VALUES (?,?)", genre_rows)
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
    CREATE INDEX idx_shelves_shelf  ON item_shelves(shelfID);
    CREATE INDEX idx_episodes_series ON episodes(seriesID, position);
    """)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-gzip", action="store_true")
    args = ap.parse_args()

    cat = json.loads(FULL_CATALOG.read_text(encoding="utf-8"))
    items = cat["items"]
    print(f"[sqlite] read {len(items):,} catalog items", flush=True)
    deduped = dedupe_by_imdb(items)
    print(f"[sqlite] after IMDb dedup: {len(deduped):,} "
          f"(removed {len(items) - len(deduped):,} duplicate uploads)", flush=True)

    if OUT_DB.exists():
        OUT_DB.unlink()
    db = sqlite3.connect(OUT_DB)
    create_schema(db)
    n_items = populate_items(db, deduped)
    n_series, n_eps = populate_series(db)
    create_indexes(db)
    db.execute("INSERT OR REPLACE INTO meta VALUES ('schemaVersion', ?)", (str(SCHEMA_VERSION),))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('generatedAt', ?)",
               (cat.get("generatedAt", ""),))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('itemCount', ?)", (str(n_items),))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('seriesCount', ?)", (str(n_series),))
    db.commit()
    db.execute("PRAGMA optimize")
    db.execute("VACUUM")
    db.close()

    raw_mb = OUT_DB.stat().st_size / 1e6
    print(f"[sqlite] wrote {OUT_DB.name}: {raw_mb:.1f} MB "
          f"({n_items:,} items, {n_series:,} series, {n_eps:,} episodes)", flush=True)

    gz_mb = None
    if not args.no_gzip:
        with open(OUT_DB, "rb") as fi, gzip.open(OUT_GZ, "wb", compresslevel=9) as fo:
            shutil.copyfileobj(fi, fo)
        gz_mb = OUT_GZ.stat().st_size / 1e6
        print(f"[sqlite] wrote {OUT_GZ.name}: {gz_mb:.1f} MB gzipped", flush=True)

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": cat.get("generatedAt", ""),
        "itemCount": n_items, "seriesCount": n_series, "episodeCount": n_eps,
        "dbBytes": OUT_DB.stat().st_size,
        "gzBytes": (OUT_GZ.stat().st_size if gz_mb else None),
        "asset": "catalog.sqlite.gz",
    }
    OUT_MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"[sqlite] wrote {OUT_MANIFEST.name}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
