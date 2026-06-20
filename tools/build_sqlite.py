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
import re
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


def _shelf_collection_map():
    """{collectionID: [shelfID,...]} parsed from each dynamic shelf's
    `collection:X` query in featured.json. Lets build_sqlite assign Home-shelf
    membership DIRECTLY from an item's collections, instead of relying on the
    `item.shelves` field (which only build-catalog.mjs sets — so freshly-added
    shelves like Ephemera/Newsreels stayed empty, and existing ones never grew
    as discovery added items). Robust + self-healing: a shelf reflects its whole
    collection every rebuild."""
    out = defaultdict(list)
    try:
        shelves = json.loads(FEATURED.read_text(encoding="utf-8")).get("shelves", [])
    except Exception:
        return out
    for s in shelves:
        for coll in re.findall(r"collection:([A-Za-z0-9_\-]+)", s.get("query") or ""):
            out[coll].append(s["id"])
    return out

SHELF_COLLECTION_MAP = _shelf_collection_map()


def _shelf_ids_for(it):
    """Full Home-shelf membership for an item: its stored `shelves` UNION any
    shelf whose collection: query the item's collections satisfy."""
    ids = set(it.get("shelves") or [])
    for c in (it.get("collections") or []):
        ids.update(SHELF_COLLECTION_MAP.get(str(c), []))
    return ids


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
        # A captioned upload carries its OWN matching WebVTT/HLS subtitle track
        # (Decision 039), so it must win dedup — otherwise a film's only subtitled
        # copy gets dropped in favor of a caption-less sibling and the app plays
        # the deduped copy with no CC button even though captions exist. Top
        # priority (ahead of artwork/votes) since the subs+video are a matched
        # pair on that exact archiveID; can't be grafted onto another copy.
        return (1 if i.get("subtitleHLS") else 0, r,
                i.get("imdbVotes") or 0, i.get("archiveID") or "")
    best = {}
    for it in items:
        # An excluded item (rights audit / dead-on-Archive — Decision 027) must
        # never WIN dedup: it's dropped at insertion, so if it won it would take
        # its live IMDb siblings down with it and the whole title would vanish.
        # Skip excluded items here; a live copy then wins and surfaces normally.
        if it.get("excluded"):
            continue
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


# Re-upload qualifiers stripped before comparing titles, so "Carnival Of Souls
# 1962" / "...video quality upgrade" / "... 720p" all normalize to the same key.
_DUPE_QUALIFIERS = [
    "video quality upgrade", "quality upgrade", "video upgrade", "ipod video version",
    "ipod video", "full movie", "full film", "the complete film", "complete film",
    "remastered", "remaster", "restored", "restoration", "widescreen", "fullscreen",
    "colorized", "colourized", "cult film", "cult classic", "public domain",
    "hi res", "high quality", "best quality", "upgrade",
    "quality print", "widescreen print", " print", "telecine", " scan",
    "complete uncut", "uncut", "feature film",
    "1080p", "720p", "480p", "2160p", "4k", "hd ", " hd",
]

_FILM_TYPES = {"feature-film", "short-film", "silent-film", "animation",
               "documentary", "feature"}


def _dupe_title_key(title):
    t = (title or "").lower()
    for q in _DUPE_QUALIFIERS:
        t = t.replace(q, " ")
    t = re.sub(r"(?<!\d)(19|20)\d\d(?!\d)", " ", t)   # strip 4-digit years (even glued)
    t = re.sub(r"[^a-z0-9]+", " ", t).strip()
    t = re.sub(r"^(the|a|an) ", "", t)            # strip a leading article
    return t.replace(" ", "")


def _runtime_compatible(a, b):
    """True if two runtimes plausibly belong to the same film (guards the
    1959-original vs 1999-remake case where titles collide but lengths don't)."""
    ra, rb = a.get("runtimeSeconds") or 0, b.get("runtimeSeconds") or 0
    if ra <= 0 or rb <= 0:
        return True                                   # no runtime to contradict
    tol = max(0.15 * max(ra, rb), 150)                # 15% or 2.5 min, whichever larger
    return abs(ra - rb) <= tol


def _year_compatible(a, b):
    ya, yb = a.get("year"), b.get("year")
    return ya is None or yb is None or abs(ya - yb) <= 2


def _color_compatible(a, b):
    """B&W vs color is a hard version distinction — a B&W original and a color
    remake/colorization of the same title are different works. Unknown on either
    side does not contradict."""
    ca, cb = a.get("colorMode"), b.get("colorMode")
    return not (ca and cb and ca != cb)


def _color_match(a, b):
    ca, cb = a.get("colorMode"), b.get("colorMode")
    return bool(ca) and ca == cb


def _video_quality(i):
    """Higher = better playable copy. qualityScore + resolution hints from the
    filename, demoting tiny mobile derivatives (512kb/ipod/64kb)."""
    q = i.get("qualityScore") or 0
    url = (i.get("downloadURL") or "").lower()
    if any(x in url for x in ("1080", "1920", "2160", "4k")):
        q += 5
    elif "720" in url:
        q += 3
    elif "480" in url:
        q += 1
    if any(x in url for x in ("512kb", "256kb", "64kb", "ipod", "_ipod", "mobile")):
        q -= 6
    return q


def _real_art_rank(i):
    if not (i.get("hasRealArtwork") or i.get("artworkSource") not in (None, "archive")):
        return 0
    return {"tmdb": 4, "tvdb": 4, "wikidata": 3, "commons": 3,
            "generated": 2}.get(i.get("artworkSource"), 1)


def _same_film(a, b):
    """True when two same-titled copies are CONFIDENTLY the same film. Color and
    year must be compatible (B&W vs color = different version; years apart >2 =
    different film). Beyond that:
      - same imdb id  → same film;
      - imdb anchor + no-imdb copy → same film (the imdb + title + colour fix the
        identity), tolerating a CORRUPTED runtime up to 40% — runtime is the most
        error-prone field (a 1959 House on Haunted Hill copy carried a bogus 93-min
        runtime + the 1999 director, yet is plainly the same B&W film);
      - no-imdb + no-imdb → require TIGHT runtime agreement or same-year+one-runtime
        -unknown, and never two bare copies (so generic-title collisions can't
        chain-merge)."""
    ia, ib = a.get("imdbID"), b.get("imdbID")
    if ia and ib:
        return ia == ib
    if not _year_compatible(a, b) or not _color_compatible(a, b):
        return False
    ra, rb = a.get("runtimeSeconds") or 0, b.get("runtimeSeconds") or 0
    if ia or ib:                                      # imdb anchor + no-imdb copy
        if ra > 0 and rb > 0 and abs(ra - rb) > 0.40 * max(ra, rb):
            return False                              # too far off even for bad data
        return True
    ya, yb = a.get("year"), b.get("year")             # both no-imdb
    if ra > 0 and rb > 0 and abs(ra - rb) <= max(0.10 * max(ra, rb), 90):
        return True
    if ya and yb and abs(ya - yb) <= 1 and (ra == 0 or rb == 0):
        return True
    return False


def _title_quality(t):
    """Prefer a clean human title over an uploader/filename string."""
    t = (t or "").strip()
    low = t.lower()
    s = 0
    if " " in t:
        s += 2
    if any(c.islower() for c in t) and any(c.isupper() for c in t):
        s += 1
    if any(x in low for x in (".com", "http", "www", ".is", ".net", "_", "upload",
                              "y2mate", "filescn", "xvid", "divx", "x264")):
        s -= 4
    if t.isupper():
        s -= 1
    s -= max(0, len(t) - 64) // 16
    return s


def _consistent(group):
    """A merge component must name a single film: at most one imdb id, no B&W +
    colour mix, and a sane year span. Runtime span is enforced only for no-imdb-
    ONLY components — when an imdb anchors the component, its identity is fixed and
    corrupted runtimes on re-uploads are tolerated."""
    imdbs = {m.get("imdbID") for m in group if m.get("imdbID")}
    if len(imdbs) > 1:
        return False
    colors = {m.get("colorMode") for m in group if m.get("colorMode")}
    if len(colors) > 1:
        return False
    rts = [m["runtimeSeconds"] for m in group if m.get("runtimeSeconds")]
    tight = len(rts) >= 2 and (max(rts) - min(rts)) <= max(0.10 * max(rts), 90)
    if not imdbs and rts and max(rts) - min(rts) > max(0.12 * max(rts), 150):
        return False
    yrs = [m["year"] for m in group if m.get("year")]
    if yrs and max(yrs) - min(yrs) > (5 if tight else 2):
        return False
    return True


def merge_film_duplicates(items):
    """Collapse re-uploads of the SAME film — across single-imdb, multi-imdb, AND
    no-imdb cases — into ONE best card, grafting best-of-everything onto it.

    For each normalized-title cluster, build connected components via `_same_film`
    (positive imdb/year/runtime corroboration, no contradiction), then merge each
    consistent component of size >1. The survivor is the best VIDEO + captions copy;
    the cluster's best imdb/tmdb/year/director/rating, best artwork, and cleanest
    title are grafted onto it. DISTINCT films that merely share a title never merge:
    different imdb ids, year spreads >2 (Cleopatra 1917/1934/1963), and mismatched
    runtimes (House on Haunted Hill 1959 75min vs 1999 remake 93min) all break the
    edge; bare no-imdb copies attach only to an imdb anchor, so generic-title
    collisions ("Public Domain Animation" ×31 different cartoons) stay separate.
    Precision over recall (Decision 035). Runs AFTER dedupe_by_imdb."""
    clusters = {}
    for it in items:
        if it.get("contentType") in _FILM_TYPES and not it.get("excluded"):
            k = _dupe_title_key(it.get("title"))
            if len(k) >= 4:
                clusters.setdefault(k, []).append(it)

    GRAFT = ("imdbID", "tmdbID", "year", "director", "imdbRating", "imdbVotes",
             "contentRating", "language")
    drop_ids, merged = set(), 0
    for members in clusters.values():
        if len(members) < 2:
            continue
        # union-find over the cluster using _same_film edges
        parent = list(range(len(members)))

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for i in range(len(members)):
            for j in range(i + 1, len(members)):
                if _same_film(members[i], members[j]):
                    parent[find(i)] = find(j)
        comps = {}
        for i in range(len(members)):
            comps.setdefault(find(i), []).append(members[i])

        for group in comps.values():
            if len(group) < 2 or not _consistent(group):
                continue
            winner = max(group, key=lambda i: (1 if i.get("subtitleHLS") else 0,
                                               _video_quality(i), _real_art_rank(i),
                                               i.get("imdbVotes") or 0))
            donor = next((m for m in group if m.get("imdbID")), None)  # canonical metadata
            for f in GRAFT:
                if not winner.get(f):
                    src = donor if (donor and donor.get(f)) else \
                        next((m for m in group if m.get(f)), None)
                    if src:
                        winner[f] = src[f]
            best_art = max(group, key=_real_art_rank)
            if _real_art_rank(best_art) > _real_art_rank(winner):
                for f in ("posterURL", "artworkSource", "hasRealArtwork", "backdropURL"):
                    if best_art.get(f) is not None:
                        winner[f] = best_art[f]
            best_title = max(group, key=lambda m: _title_quality(m.get("title")))
            if _title_quality(best_title.get("title")) > _title_quality(winner.get("title")):
                winner["title"] = best_title["title"]
            for m in group:
                if m["archiveID"] != winner["archiveID"]:
                    drop_ids.add(m["archiveID"])
            merged += 1

    if drop_ids:
        print(f"[dedup] merged {len(drop_ids)} film re-uploads into "
              f"{merged} best cards (title + imdb/year/runtime corroboration)")
    return [it for it in items if it["archiveID"] not in drop_ids]


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

    -- Search index. `names` = people; `extra` = genres + series/network +
    -- synopsis, so search covers content/topic words, not just title + cast
    -- (the old index missed most of the catalog from a user's POV). The app's
    -- `items_fts MATCH ?` searches every column automatically, so broadening
    -- here needs no app change.
    CREATE VIRTUAL TABLE items_fts USING fts5(archiveID UNINDEXED, title, names, extra);
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
        for s in _shelf_ids_for(it):
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
        # Rights audit (Decision 027): items flagged excluded=true stay in
        # catalog.json (reversible) but are never inserted, so they vanish from
        # every app surface. Mirrors the isAdult gate but harder — a full skip.
        if it.get("excluded"):
            continue
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
        for s in _shelf_ids_for(it):
            shelf_rows.append((s, aid, shelf_pos.get((s, aid), 0)))
        names = " ".join([it.get("director") or ""]
                         + [c.get("name", "") for c in (it.get("cast") or [])]
                         + [it.get("producer") or ""]).strip()
        # Topic/content words: genres, series/network, country, and a synopsis
        # snippet (truncated so the index doesn't balloon). Lets users find a
        # film by what it's ABOUT, not just its title or cast.
        syn = it.get("synopsis")
        syn = (" ".join(syn) if isinstance(syn, list) else (syn or ""))
        extra = " ".join([
            " ".join(it.get("genres") or []),
            it.get("seriesName") or "", it.get("network") or "",
            " ".join(it.get("countries") or []),
            syn[:400],
        ]).strip()
        fts_rows.append((aid, it.get("title") or "", names, extra))

    db.executemany("INSERT OR IGNORE INTO items VALUES (%s)" % ",".join("?" * 25), item_rows)
    db.executemany("INSERT OR IGNORE INTO item_json VALUES (?,?)", json_rows)
    db.executemany("INSERT INTO item_genres VALUES (?,?)", genre_rows)
    db.executemany("INSERT INTO item_collections VALUES (?,?)", coll_rows)
    db.executemany("INSERT INTO item_shelves VALUES (?,?,?)", shelf_rows)
    db.executemany("INSERT INTO items_fts VALUES (?,?,?,?)", fts_rows)
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
    items = [it for it in items if not it.get("excluded")]   # rights audit (Decision 027)
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
    deduped = merge_film_duplicates(deduped)
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
