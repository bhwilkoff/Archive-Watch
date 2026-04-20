#!/usr/bin/env python3
"""
Canonical Video Work Registry
------------------------------
Builds a federated database of video works (films, TV, shorts, documentaries,
etc.) aggregating metadata from multiple sources:

  - Internet Archive (archive.org)                     [Scrape API, no key]
  - Library of Congress loc.gov JSON API               [no key]
  - American Archive of Public Broadcasting (AAPB)     [Solr JSON API, no key]
  - Wikimedia Commons video files                      [MediaWiki API, no key]
  - Wikidata (enrichment + EFG ID via SPARQL)          [no key]

Each work is given a stable canonical ID, chosen from this hierarchy:
  1. wd:Q12345      - if Wikidata knows it
  2. imdb:tt0012345 - if IMDb knows it
  3. lic:<hash>     - locally-issued hash of normalized title+year+creator

Multiple sources for the same work merge automatically into one record with
many source rows. The "best" source is picked via quality scoring, so the
consumer app never has to choose.

Zero API keys required.

Usage:
    python registry_pipeline.py                          # default: all sources
    python registry_pipeline.py --limit 100              # test with cap
    python registry_pipeline.py --sources ia loc         # pick specific sources
    python registry_pipeline.py --skip-enrichment        # skip Wikidata pass
"""

import argparse
import hashlib
import json
import re
import sqlite3
import sys
import time
import unicodedata
from pathlib import Path
from urllib.parse import urlencode

import requests

# ---------------------------------------------------------------------------
# Shared editorial config loader
# ---------------------------------------------------------------------------
# The Archive Watch tvOS app has accumulated hard-won intelligence about
# collection identities, adult filters, silent-era directors, and the
# work_type → contentType mapping. All of that lives in `shared/editorial/`
# as JSON so the Python pipeline and the Swift app read from one source.

_EDITORIAL_DIR = Path(__file__).resolve().parent.parent / "shared" / "editorial"

def _load_editorial(name, default=None):
    """Load a JSON file from shared/editorial/. Returns `default` if missing
    so the pipeline can still run in isolation (e.g., CI without the app
    sibling)."""
    path = _EDITORIAL_DIR / f"{name}.json"
    if not path.exists():
        print(f"[editorial] missing {path}; using default", file=sys.stderr)
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[editorial] failed to load {path}: {e}", file=sys.stderr)
        return default


_COLLECTION_METADATA = _load_editorial("collection_metadata", {"collections": []})
_ADULT_COLLECTIONS   = set(
    _load_editorial("adult_collections", {"collections": []}).get("collections", [])
)
_SILENT_DIRECTORS    = _load_editorial("silent_era_directors", {"directors": []}).get("directors", [])

# Pre-compute lowercased alias → validThrough lookup for fast classification.
_SILENT_ALIAS_LOOKUP = {}
for _d in _SILENT_DIRECTORS:
    for alias in _d.get("aliases", []):
        _SILENT_ALIAS_LOOKUP[alias.lower()] = _d.get("validThrough", 1929)
    if _d.get("name"):
        _SILENT_ALIAS_LOOKUP[_d["name"].lower()] = _d.get("validThrough", 1929)

# Collections whose membership flags a work as silent-era regardless of year.
_SILENT_COLLECTIONS = {
    c["id"] for c in _COLLECTION_METADATA.get("collections", [])
    if c.get("category") == "silent-film"
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

IA_SCRAPE_ENDPOINT = "https://archive.org/services/search/v1/scrape"
LOC_API_ENDPOINT   = "https://www.loc.gov"
AAPB_API_ENDPOINT  = "https://americanarchive.org/api.json"
COMMONS_API        = "https://commons.wikimedia.org/w/api.php"
WIKIDATA_SPARQL    = "https://query.wikidata.org/sparql"

PAGE_SIZE = 1000
AAPB_PAGE_SIZE = 100      # AAPB Solr caps at 100
COMMONS_PAGE_SIZE = 50    # polite batch size for generator queries

IA_FIELDS = [
    "identifier", "title", "date", "year", "creator", "description",
    "subject", "runtime", "language", "licenseurl", "mediatype",
    "collection", "downloads", "item_size", "publicdate", "addeddate",
    "format",
    # `external-identifier` often contains urn:imdb:tt... — so we can skip
    # the Wikidata hop for items IA already knows the IMDb ID for.
    "external-identifier",
    # Engagement signals — used for popularity scoring
    "num_favorites", "avg_rating", "num_reviews", "week",
]

# Archive.org collections to harvest. These are video-bearing, mostly PD.
IA_COLLECTIONS = {
    "feature_films":        "PD feature films",
    "classic_tv":           "PD television",
    "classic_cartoons":     "PD animated shorts",
    "silent_films":         "Pre-1929 silent cinema",
    "short_films":          "Shorts of all eras",
    "sensiblecinema":       "Curated PD collection",
    "vintage_cartoons":     "Vintage animation",
    "home_movies":          "Home movies",
}

# LoC collections that contain moving images worth indexing.
# The National Screening Room is the flagship, but several other collections
# have video too. We let the API tell us what's video vs not.
LOC_COLLECTIONS = [
    "national-screening-room",
    "origins-of-american-animation",
    "early-motion-pictures-1897-to-1920",
    "spanish-american-war-in-motion-pictures",
    "inside-an-american-factory-films-of-the-westinghouse-works-1904",
    "theodore-roosevelt-his-life-and-times-on-film",
    "variety-stage-sound-recordings-and-motion-pictures",
    "last-days-of-a-president-films-of-mckinley-and-the-pan-american-exposition-1901",
]

USER_AGENT = (
    "VideoWorkRegistry/1.0 (learningischange.com) python-requests"
)

# ---------------------------------------------------------------------------
# Canonical ID system
# ---------------------------------------------------------------------------

# Articles to strip from titles when normalizing. Multi-language aware.
_ARTICLES = {
    "the", "a", "an",
    "le", "la", "les", "l",
    "el", "los", "las",
    "der", "die", "das",
    "il", "lo", "gli",
    "de", "het",
}

def normalize_title(title: str) -> str:
    """Strip articles, lowercase, remove punctuation, collapse whitespace.

    This normalizer is deliberately aggressive: the goal is that "The Kid",
    "Kid, The", "THE  KID!" and "Kid (1921)" all collapse to the same string.
    """
    if not title:
        return ""
    s = unicodedata.normalize("NFKD", title)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower()
    # Drop parenthetical year suffixes like "kid (1921)"
    s = re.sub(r"\(\d{4}\)", "", s)
    # Handle "Title, The" -> "Title"
    s = re.sub(r",\s*(the|a|an|le|la|les|el|der|die|das|il)\s*$", "", s)
    # Strip all non-alphanumeric
    s = re.sub(r"[^\w\s]", " ", s, flags=re.UNICODE)
    s = re.sub(r"\s+", " ", s).strip()
    # Drop leading article
    words = s.split()
    if words and words[0] in _ARTICLES:
        words = words[1:]
    return " ".join(words)


def normalize_creator(creator) -> str:
    """Normalize a single creator name or the first in a list."""
    if not creator:
        return ""
    if isinstance(creator, list):
        creator = creator[0] if creator else ""
    s = unicodedata.normalize("NFKD", str(creator))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", s.lower()).strip()


def compute_local_id(title: str, year, creator) -> str:
    """Deterministic hash-based ID for works not found in Wikidata/IMDb."""
    key = f"{normalize_title(title)}|{year or ''}|{normalize_creator(creator)}"
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]
    return f"lic:{h}"


def resolve_canonical_id(
    *, wikidata_qid=None, imdb_id=None, title=None, year=None, creator=None
) -> str:
    """Priority: Wikidata QID > IMDb ID > deterministic local hash."""
    if wikidata_qid:
        return f"wd:{wikidata_qid}"
    if imdb_id:
        imdb_id = imdb_id.strip()
        if not imdb_id.startswith("tt"):
            imdb_id = "tt" + imdb_id
        return f"imdb:{imdb_id}"
    return compute_local_id(title, year, creator)


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

# Archive.org collection -> work_type inference.
COLLECTION_TYPE_MAP = {
    "feature_films":    "feature_film",
    "silent_films":     "feature_film",
    "classic_tv":       "tv_episode",
    "classic_cartoons": "animated_short",
    "vintage_cartoons": "animated_short",
    "short_films":      "short_film",
    "home_movies":      "home_movie",
    "prelinger":        "industrial_film",
    "prelingerhomemovies": "home_movie",
    "opensource_movies": "short_film",  # too generic, best guess
    "newsreels":        "newsreel",
    "sports":           "sports_footage",
    "concertvideos":    "concert",
    "educationalfilms": "educational_film",
}

# PBCore asset types (from AAPB) -> our vocabulary
PBCORE_TYPE_MAP = {
    "episode":              "tv_episode",
    "program":              "tv_episode",
    "segment":              "tv_episode",
    "clip":                 "tv_episode",
    "promo":                "trailer",
    "raw footage":          "newsreel",
    "interview":            "lecture",
    "compilation":          "documentary",
}

def classify_work_type(collections, subjects, runtime_sec, title, pbcore_asset_type=None):
    """Return a single work_type from our controlled vocabulary."""
    collections = collections or []
    subjects = [s.lower() for s in (subjects or [])]
    title_l = (title or "").lower()

    # PBCore asset type (AAPB) is a strong signal
    if pbcore_asset_type:
        t = pbcore_asset_type.lower().strip()
        if t in PBCORE_TYPE_MAP:
            return PBCORE_TYPE_MAP[t]

    # Most specific collection match wins
    for coll in collections:
        if coll in COLLECTION_TYPE_MAP:
            return COLLECTION_TYPE_MAP[coll]

    # Keyword signals
    if any(w in title_l for w in ("trailer", "preview")):
        return "trailer"
    if "newsreel" in title_l or "newsreel" in subjects:
        return "newsreel"
    if "cartoon" in subjects or "animation" in subjects:
        return "animated_short"
    if "documentary" in subjects or "documentary" in title_l:
        return "documentary"
    if "home movie" in subjects:
        return "home_movie"

    # Runtime-based fallback (seconds)
    if runtime_sec:
        if runtime_sec < 40 * 60:  # under 40 min
            return "short_film"
        return "feature_film"

    return "unknown"


def classify_rights(licenseurl, source_type):
    """Best-effort rights classification from license metadata."""
    if licenseurl:
        l = licenseurl.lower()
        if "publicdomain" in l or "pdm" in l:
            return "public_domain"
        if "creativecommons" in l or "cc0" in l:
            return "creative_commons"
    # Archive.org's PD-labeled collections
    if source_type == "archive_org":
        # We trust PD-specific collection membership as a weak PD signal,
        # but still mark unknown here; promoter code can upgrade it.
        return "unknown"
    if source_type == "loc":
        # LoC downloadable items are generally PD; streaming-only are rights-restricted.
        # We'll refine this when processing each item.
        return "unknown"
    return "unknown"


# ---------------------------------------------------------------------------
# Source quality scoring
# ---------------------------------------------------------------------------

# Higher score = better source. Used for best-source selection.
SOURCE_TYPE_BASE_SCORE = {
    "loc":         90,   # authoritative, high-quality masters
    "wikimedia":   85,   # CC-licensed, well-described, direct playable URLs
    "archive_org": 70,   # variable quality, user-uploaded
    "aapb":        60,   # streaming-only, curated, mostly rights-restricted
    "efg":         55,   # metadata-only; links back to partner archive
    "youtube":     50,
}

def score_source(source_type, format_hint, downloadable, file_size):
    """Compute a 0-100 quality score for a source.

    Higher = pick me first.
    """
    score = SOURCE_TYPE_BASE_SCORE.get(source_type, 30)
    if downloadable:
        score += 10
    fmt = (format_hint or "").lower()
    if "h.264" in fmt or "h264" in fmt or "mp4" in fmt:
        score += 10
    elif "mpeg4" in fmt or "m4v" in fmt:
        score += 5
    elif "avi" in fmt or "divx" in fmt:
        score += 0
    elif "realvideo" in fmt or "rm" in fmt:
        score -= 10
    # Nudge up by file size (proxy for bitrate), capped
    if file_size:
        mb = file_size / (1024 * 1024)
        score += min(int(mb / 100), 10)  # +1 per 100MB, max +10
    return max(0, min(100, score))


# ---------------------------------------------------------------------------
# Work-level quality & popularity scoring
# ---------------------------------------------------------------------------
#
# Two separate scores at the work level:
#
# quality_score (0-100)
#   "Is this worth keeping / showing at all?"
#   Reflects how well-formed and watchable the record is. Computed once at
#   ingest and updated only if metadata changes. The default view hard-filters
#   on this (e.g. quality_score >= 40 drops obvious garbage).
#
# popularity_score (0-100)
#   "Would a typical user care about this?"
#   Reflects engagement signals and cross-source cultural footprint. Changes
#   over time; refreshed periodically by re-pulling engagement data. The
#   default view sorts on this.
#
# Both scores are intentionally cheap heuristics — they're directionally right,
# not precise, and can be tuned without losing data since we never filter at
# ingest.

import math

# Titles that look like raw filenames / junk uploads
_JUNK_TITLE_PATTERNS = [
    re.compile(r"^[A-Z0-9_\-]{6,}$"),      # ALL-CAPS identifier-like
    re.compile(r"^IMG[_\-]?\d+", re.I),     # IMG_1234 camera dumps
    re.compile(r"^DSC[_\-]?\d+", re.I),     # DSC_1234 camera dumps
    re.compile(r"^MOV[_\-]?\d+", re.I),     # MOV_1234
    re.compile(r"^VID[_\-]?\d+", re.I),
    re.compile(r"^(video|clip|movie|film)\s*\d+\s*$", re.I),  # "video 1"
    re.compile(r"^untitled", re.I),
    re.compile(r"^test\b", re.I),
]

# Work types that are intrinsically less "mainstream interesting"
_WORK_TYPE_POPULARITY_BASE = {
    "feature_film":     40,
    "documentary":      35,
    "animated_short":   30,
    "short_film":       20,
    "tv_episode":       25,
    "tv_movie":         30,
    "newsreel":         15,
    "trailer":          10,
    "educational_film": 10,
    "industrial_film":   5,
    "home_movie":        5,
    "lecture":          10,
    "concert":          20,
    "music_video":      20,
    "sports_footage":   10,
    "unknown":          15,
}


def _title_looks_like_junk(title):
    if not title:
        return True
    t = title.strip()
    if len(t) < 3:
        return True
    for pat in _JUNK_TITLE_PATTERNS:
        if pat.search(t):
            return True
    return False


def compute_quality_score(*, title, runtime_sec, file_size, description,
                          work_type, rights_status, has_year):
    """0-100 score. "Is this a real, well-formed video item?"

    Thresholds below roughly 40 indicate likely garbage (test uploads,
    corrupted files, things miscategorized as video).
    """
    score = 50  # start neutral

    # -- Title ---
    if _title_looks_like_junk(title):
        score -= 25

    # -- Runtime ---
    # Under 60 seconds is almost certainly a clip, test, or thumbnail.
    # 5+ minutes is a real video.
    if runtime_sec is None:
        score -= 5   # no runtime data, slightly suspicious
    elif runtime_sec < 60:
        score -= 30
    elif runtime_sec < 300:      # 1-5 min
        score -= 5
    elif runtime_sec >= 600:     # 10+ min
        score += 10
    if runtime_sec and runtime_sec >= 3600:  # feature-length
        score += 5

    # -- File size ---
    # Under 5 MB is typically broken or text-masquerading-as-video.
    if file_size is not None:
        if file_size < 5 * 1024 * 1024:
            score -= 20
        elif file_size >= 100 * 1024 * 1024:
            score += 5

    # -- Description quality ---
    desc_len = len(description or "")
    if desc_len == 0:
        score -= 5
    elif desc_len >= 200:
        score += 5

    # -- Basic metadata presence ---
    if not has_year:
        score -= 5

    # -- Work type sanity ---
    if work_type == "unknown":
        score -= 5

    # -- Rights status (unknown is a red flag for quality too — often means
    # metadata is missing across the board)
    if rights_status == "unknown":
        score -= 3

    return max(0, min(100, score))


def _log_normalize(value, scale=5.0):
    """Compress long-tailed counts into a 0..scale_max range via log10.

    log10(300_000) ≈ 5.48, log10(100) = 2, log10(10) = 1, log10(1) = 0.
    With scale=5, 300k downloads → 27, 1k downloads → 15, 100 → 10.
    """
    if not value or value <= 0:
        return 0
    return min(scale * math.log10(value + 1), scale * 6)


def compute_popularity_score(*, downloads=None, num_favorites=None,
                             avg_rating=None, num_reviews=None,
                             work_type=None, year=None,
                             wikipedia_article_count=0,
                             has_poster=False, has_imdb=False,
                             has_director=False, has_cast=False,
                             source_count=1):
    """0-100 score. "Would a typical user care?"

    Combines direct engagement (where available) with cross-source cultural
    footprint signals (Wikipedia, Wikidata completeness).
    """
    score = _WORK_TYPE_POPULARITY_BASE.get(work_type, 15)

    # -- Direct engagement (archive.org is our only real source here) ---
    # Downloads are heavy-tailed, so log-normalize aggressively.
    if downloads:
        score += _log_normalize(downloads, scale=3.5)   # up to ~21 for 300k dl
    if num_favorites:
        score += _log_normalize(num_favorites, scale=2.0)  # up to ~12
    if avg_rating and num_reviews and num_reviews >= 3:
        # A 5-star with 100 reviews is worth more than 5-star with 1 review
        rating_signal = (float(avg_rating) - 2.5) * 2     # -5 .. +5
        review_weight = min(num_reviews / 50.0, 1.0)
        score += rating_signal * review_weight * 3        # capped around 15

    # -- Cross-source cultural footprint ---
    # Wikipedia article in any language is a strong "someone curated this" signal
    if wikipedia_article_count >= 1:
        score += 15
    # Each additional language edition adds a small bonus (capped)
    score += min(wikipedia_article_count - 1, 8) if wikipedia_article_count > 1 else 0

    if has_poster:     score += 5
    if has_imdb:       score += 5
    if has_director:   score += 3
    if has_cast:       score += 3

    # -- Multi-source works are more likely to matter ---
    # If two or three independent archives kept this film, that means something.
    if source_count >= 2:
        score += 5
    if source_count >= 3:
        score += 3

    # -- Age & survival bonus ---
    # A pre-1940 film that's still in an archive is by definition notable.
    if year and year < 1940:
        score += 8
    elif year and year < 1960:
        score += 3

    return max(0, min(100, score))


# ---------------------------------------------------------------------------
# SQLite schema
# ---------------------------------------------------------------------------

SCHEMA = """
-- One row per canonical work. The canonical_id is our stable join key.
CREATE TABLE IF NOT EXISTS works (
    canonical_id    TEXT PRIMARY KEY,      -- wd:Qxxx | imdb:ttxxx | lic:<hash>
    id_scheme       TEXT NOT NULL,         -- 'wikidata' | 'imdb' | 'local'
    title           TEXT NOT NULL,
    title_normalized TEXT NOT NULL,        -- for fuzzy matching
    year            INTEGER,
    runtime_sec     INTEGER,
    work_type       TEXT,                  -- feature_film | short_film | tv_episode | ...
    rights_status   TEXT,                  -- public_domain | creative_commons | rights_reserved_free_stream | unknown
    description     TEXT,
    languages       TEXT,                  -- JSON array
    subjects        TEXT,                  -- JSON array (genres/tags merged)
    -- Silent-era detection is multi-signal (collection membership, director
    -- whitelist, year+type, keywords, audio-absence). Kept separate from
    -- work_type because the app's "silent-film" category crosses multiple
    -- pipeline work_types (short_film, feature_film, animated_short) and
    -- because year-alone mis-classifies transitional-era works.
    is_silent       INTEGER DEFAULT 0,     -- 0/1, authoritative for app's silent-film category
    silent_signals  TEXT,                  -- JSON array: why is_silent was flagged (for debugging)
    quality_score   INTEGER DEFAULT 50,    -- 0-100, "is this worth keeping at all?"
    popularity_score INTEGER DEFAULT 0,    -- 0-100, "would a user care?"
    popularity_updated_at TEXT,            -- ISO timestamp of last popularity refresh
    created_at      TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at      TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Enrichment from Wikidata and friends. Separate so we can refresh independently.
CREATE TABLE IF NOT EXISTS enrichment (
    canonical_id    TEXT PRIMARY KEY,
    wikidata_qid    TEXT,
    imdb_id         TEXT,
    tmdb_id         TEXT,
    wikipedia_url   TEXT,
    directors       TEXT,       -- JSON array
    cast_list       TEXT,       -- JSON array
    genres          TEXT,       -- JSON array
    countries       TEXT,       -- JSON array
    publication_date TEXT,
    poster_url      TEXT,
    FOREIGN KEY (canonical_id) REFERENCES works(canonical_id) ON DELETE CASCADE
);

-- Many sources per work. This is where federation happens.
CREATE TABLE IF NOT EXISTS sources (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    canonical_id    TEXT NOT NULL,
    source_type     TEXT NOT NULL,   -- archive_org | loc | aapb | wikimedia | efg | youtube
    source_id       TEXT NOT NULL,   -- the platform-native ID
    source_url      TEXT NOT NULL,   -- landing page on the source
    stream_url      TEXT,            -- direct playable URL if known
    format_hint     TEXT,            -- h.264, mpeg4, avi, etc.
    file_size       INTEGER,
    downloadable    INTEGER DEFAULT 0,  -- 0/1 bool
    source_quality  INTEGER NOT NULL,   -- 0-100, how good is THIS file (not the work)
    -- Fields resolved by the optional derivative pass (--resolve-derivatives).
    -- Before that pass runs, archive_org stream_urls point at the item's
    -- download FOLDER, which AVPlayer can't play. The picker walks
    -- /metadata/{id}'s files array and stores the best h.264 derivative's
    -- actual URL here. has_audio_track feeds into silent-era detection.
    derivative_name TEXT,            -- IA derivative filename (e.g. movie_512kb.mp4)
    has_audio_track INTEGER,         -- NULL=unknown, 0=silent, 1=has audio
    verified_playable INTEGER,       -- NULL=unchecked, 0=HEAD failed, 1=HEAD ok + video MIME
    verified_at     TEXT,
    raw_json        TEXT,            -- full original record
    fetched_at      TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (canonical_id) REFERENCES works(canonical_id) ON DELETE CASCADE,
    UNIQUE (source_type, source_id)
);

-- Engagement data per source. Kept separate from `sources` because it changes
-- over time; refreshing engagement should not require re-ingesting the source.
CREATE TABLE IF NOT EXISTS engagement (
    source_type     TEXT NOT NULL,
    source_id       TEXT NOT NULL,
    downloads       INTEGER,
    num_favorites   INTEGER,
    num_reviews     INTEGER,
    avg_rating      REAL,
    week_views      INTEGER,
    refreshed_at    TEXT DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (source_type, source_id)
);

CREATE INDEX IF NOT EXISTS idx_works_year        ON works(year);
CREATE INDEX IF NOT EXISTS idx_works_type        ON works(work_type);
CREATE INDEX IF NOT EXISTS idx_works_rights      ON works(rights_status);
CREATE INDEX IF NOT EXISTS idx_works_normtitle   ON works(title_normalized);
CREATE INDEX IF NOT EXISTS idx_works_quality     ON works(quality_score);
CREATE INDEX IF NOT EXISTS idx_works_popularity  ON works(popularity_score DESC);
CREATE INDEX IF NOT EXISTS idx_works_silent      ON works(is_silent);
CREATE INDEX IF NOT EXISTS idx_sources_canonical ON sources(canonical_id);
CREATE INDEX IF NOT EXISTS idx_sources_quality   ON sources(canonical_id, source_quality DESC);
CREATE INDEX IF NOT EXISTS idx_sources_verified  ON sources(verified_playable);
CREATE INDEX IF NOT EXISTS idx_enrich_wd         ON enrichment(wikidata_qid);

-- The money view: one row per work with its single best source attached.
-- The consumer app hits this and never has to choose.
CREATE VIEW IF NOT EXISTS works_with_best_source AS
SELECT
    w.*,
    e.wikidata_qid, e.imdb_id, e.tmdb_id, e.publication_date,
    e.directors, e.cast_list, e.genres,
    e.countries, e.poster_url, e.wikipedia_url,
    s.source_type        AS best_source_type,
    s.source_url         AS best_source_url,
    s.stream_url         AS best_stream_url,
    s.derivative_name    AS best_derivative,
    s.format_hint        AS best_format,
    s.file_size          AS best_file_size,
    s.source_quality     AS best_source_quality,
    s.has_audio_track    AS best_has_audio,
    s.verified_playable  AS best_verified_playable,
    (SELECT COUNT(*) FROM sources s2 WHERE s2.canonical_id = w.canonical_id) AS source_count
FROM works w
LEFT JOIN enrichment e ON e.canonical_id = w.canonical_id
LEFT JOIN sources s ON s.id = (
    -- Prefer sources we've HEAD-verified as playable; fall back to quality.
    SELECT id FROM sources
    WHERE canonical_id = w.canonical_id
    ORDER BY
        CASE WHEN verified_playable = 1 THEN 0 ELSE 1 END,
        source_quality DESC,
        id ASC
    LIMIT 1
);

-- The default "good stuff" view: the consumer app's main feed points at this.
-- Adjust thresholds by inspecting `python registry_pipeline.py --report`.
CREATE VIEW IF NOT EXISTS works_default AS
SELECT * FROM works_with_best_source
WHERE quality_score    >= 40    -- drop obvious garbage
  AND popularity_score >= 25    -- drop the long tail
ORDER BY popularity_score DESC, year DESC;
"""


# ---------------------------------------------------------------------------
# Schema migration — keep old DBs compatible with new columns
# ---------------------------------------------------------------------------

def migrate_schema(conn):
    """Additive-only schema migration. Old DBs built before the app-learning
    columns existed get the new columns added. Never drops or reshapes."""
    def _cols(table):
        return {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}

    additions = [
        ("works",   "is_silent",         "ALTER TABLE works ADD COLUMN is_silent INTEGER DEFAULT 0"),
        ("works",   "silent_signals",    "ALTER TABLE works ADD COLUMN silent_signals TEXT"),
        ("sources", "derivative_name",   "ALTER TABLE sources ADD COLUMN derivative_name TEXT"),
        ("sources", "has_audio_track",   "ALTER TABLE sources ADD COLUMN has_audio_track INTEGER"),
        ("sources", "verified_playable", "ALTER TABLE sources ADD COLUMN verified_playable INTEGER"),
        ("sources", "verified_at",       "ALTER TABLE sources ADD COLUMN verified_at TEXT"),
    ]
    for table, col, sql in additions:
        if col not in _cols(table):
            conn.execute(sql)

    # The view gets dropped and recreated — views can't be ALTERed.
    conn.execute("DROP VIEW IF EXISTS works_with_best_source")
    conn.execute("DROP VIEW IF EXISTS works_default")
    conn.executescript(_VIEWS_SQL)


# Views as a separate chunk so migrate_schema can recreate them after column adds.
_VIEWS_SQL = """
CREATE VIEW IF NOT EXISTS works_with_best_source AS
SELECT
    w.*,
    e.wikidata_qid, e.imdb_id, e.tmdb_id, e.publication_date,
    e.directors, e.cast_list, e.genres,
    e.countries, e.poster_url, e.wikipedia_url,
    s.source_type        AS best_source_type,
    s.source_url         AS best_source_url,
    s.stream_url         AS best_stream_url,
    s.derivative_name    AS best_derivative,
    s.format_hint        AS best_format,
    s.file_size          AS best_file_size,
    s.source_quality     AS best_source_quality,
    s.has_audio_track    AS best_has_audio,
    s.verified_playable  AS best_verified_playable,
    (SELECT COUNT(*) FROM sources s2 WHERE s2.canonical_id = w.canonical_id) AS source_count
FROM works w
LEFT JOIN enrichment e ON e.canonical_id = w.canonical_id
LEFT JOIN sources s ON s.id = (
    SELECT id FROM sources
    WHERE canonical_id = w.canonical_id
    ORDER BY
        CASE WHEN verified_playable = 1 THEN 0 ELSE 1 END,
        source_quality DESC,
        id ASC
    LIMIT 1
);

CREATE VIEW IF NOT EXISTS works_default AS
SELECT * FROM works_with_best_source
WHERE quality_score    >= 40
  AND popularity_score >= 25
ORDER BY popularity_score DESC, year DESC;
"""


# ---------------------------------------------------------------------------
# Archive.org external-identifier extraction
# ---------------------------------------------------------------------------
# Archive.org items carry an `external-identifier` field that often contains
# `urn:imdb:tt0012345`, `urn:isbn:...`, `urn:tmdb:...`. Reading IMDb IDs
# directly from Archive is much faster and more complete than going through
# Wikidata P724 SPARQL. Learned from the tvOS app's EnrichmentService.

_EXT_ID_PATTERNS = {
    "imdb":     re.compile(r"urn:imdb:(tt\d+)", re.IGNORECASE),
    "tmdb":     re.compile(r"urn:tmdb:(\d+)",   re.IGNORECASE),
    "wikidata": re.compile(r"urn:wikidata:(Q\d+)", re.IGNORECASE),
}

def extract_external_ids(item):
    """Pull {imdb, tmdb, wikidata} IDs from an Archive.org item's
    external-identifier field. Returns dict of whatever's present."""
    raw = item.get("external-identifier") or []
    if isinstance(raw, str):
        raw = [raw]
    out = {}
    for entry in raw:
        s = str(entry)
        for kind, pat in _EXT_ID_PATTERNS.items():
            m = pat.search(s)
            if m and kind not in out:
                out[kind] = m.group(1)
    return out


# ---------------------------------------------------------------------------
# Date safety
# ---------------------------------------------------------------------------
# Archive.org's `date` field sometimes holds the upload timestamp, not the
# film's release year. If `date` is within ±1 year of `addeddate`, it's a
# false positive — prefer a year extracted from the title itself, or `year`.
# Lesson learned when the pipeline's parse_year dated every silent film as 2018.

_YEAR_IN_TITLE = re.compile(r"\((18|19|20)(\d{2})\)")

def safe_year(item):
    """IA-specific year extraction that rejects upload-date masquerading as
    film-date. Mirrors the JS builder's logic; supersedes parse_year() for IA."""
    title = item.get("title")
    if isinstance(title, list):
        title = title[0] if title else ""
    title_year = None
    if title:
        m = _YEAR_IN_TITLE.search(str(title))
        if m:
            title_year = int(m.group(1) + m.group(2))

    year_field = parse_year(item.get("year"))
    date_year  = parse_year(item.get("date"))
    added_year = parse_year(item.get("addeddate"), item.get("publicdate"))

    # If `date` looks like an upload timestamp (within ±1y of addeddate),
    # discard it so it doesn't get picked as the film year.
    safe_date_year = None
    if date_year and added_year:
        if abs(date_year - added_year) > 1:
            safe_date_year = date_year
    elif date_year and not added_year:
        safe_date_year = date_year

    # Priority: year > parenthetical title year > sanitized date
    return year_field or title_year or safe_date_year


# ---------------------------------------------------------------------------
# Silent-era detection (multi-signal, authoritative for app's silent-film category)
# ---------------------------------------------------------------------------

def classify_silent(*, collections, year, work_type, creator, director_names,
                    description, subjects, has_audio_track):
    """Return (is_silent: bool, signals: list[str]).

    Silent-era detection is a real classification problem, not a year threshold:
      • Collections like silenthalloffame / georgesmelies / silent_films are
        authoritative even when year is unknown.
      • Méliès / Griffith / Chaplin / Keaton / Lang + a validThrough check
        (from shared/editorial/silent_era_directors.json) catches works
        mis-tagged in generic collections.
      • year ≤ 1927 AND work_type in {feature_film, short_film, animated_short}
        catches silents no one bothered to tag.
      • Description / subjects containing "silent" is a soft signal.
      • has_audio_track == 0 (detected from derivative files) is authoritative.

    Returns which signals fired so downstream debugging / auditing works."""
    signals = []
    collections = collections or []
    subjects = [str(s).lower() for s in (subjects or [])]

    if has_audio_track == 0:
        signals.append("no_audio_track")

    if any(c in _SILENT_COLLECTIONS for c in collections):
        signals.append("silent_collection")

    # Director check across director_names list + creator field.
    director_blob = " ".join(str(d) for d in (director_names or []))
    if creator:
        director_blob += " " + (creator if isinstance(creator, str) else " ".join(creator))
    director_blob = director_blob.lower()
    for alias, valid_through in _SILENT_ALIAS_LOOKUP.items():
        if alias in director_blob:
            if year is None or year <= valid_through:
                signals.append(f"director:{alias}")
                break

    if (year is not None
        and year <= 1927
        and work_type in ("feature_film", "short_film", "animated_short")):
        signals.append(f"pre_sound_year:{year}")

    text_blob = ((description or "") + " " + " ".join(subjects)).lower()
    if "silent film" in text_blob or "silent cinema" in text_blob:
        signals.append("silent_keyword")

    return (len(signals) > 0), signals


# ---------------------------------------------------------------------------
# Archive.org derivative picker — resolve the real playable MP4
# ---------------------------------------------------------------------------
# IA's scrape API only gives an item's download folder URL. AVPlayer can't
# play a folder. To get a real stream URL, hit /metadata/{id}, walk the
# `files` array, and pick the best h.264 derivative by a priority ladder.
# Ported from tools/build-catalog.mjs (which mirrors the Swift DerivativePicker).

_IA_METADATA_CACHE = {}  # in-memory during a single run; keeps re-runs fast

def fetch_ia_metadata(ia_id, timeout=30):
    """Fetch /metadata/{id}, with a per-run in-memory cache."""
    if ia_id in _IA_METADATA_CACHE:
        return _IA_METADATA_CACHE[ia_id]
    url = f"https://archive.org/metadata/{ia_id}"
    try:
        r = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=timeout)
        r.raise_for_status()
        data = r.json()
    except Exception:
        data = None
    _IA_METADATA_CACHE[ia_id] = data
    return data


_VIDEO_FORMAT_RE = re.compile(
    r"(mp4|h\.?264|mpeg-?4|ogg video|matroska|quicktime|avi|webm)",
    re.IGNORECASE,
)

def _is_video(f):
    return bool(_VIDEO_FORMAT_RE.search((f.get("format") or "").lower()))

def _is_derivative(f): return (f.get("source") or "").lower() == "derivative"
def _is_original(f):   return (f.get("source") or "").lower() == "original"

def pick_ia_derivative(files):
    """Pick the best playable derivative from an Archive.org files array.
    Returns {name, format, size, tier} or None. Mirrors tools/build-catalog.mjs.

    Tiers (smaller = better):
      1. derivative + h.264
      2. derivative + mp4
      3. derivative + 512kb mpeg4
      4. derivative + mpeg-4
      5. derivative + webm/matroska/ogg
      6. original + mp4/h.264
      7. original (last resort)
    """
    if not files:
        return None
    videos = [f for f in files if _is_video(f)]
    if not videos:
        return None

    def _fmt(f): return (f.get("format") or "").lower()

    tiers = [
        lambda f: _is_derivative(f) and re.search(r"h\.?264", _fmt(f)),
        lambda f: _is_derivative(f) and "mp4" in _fmt(f),
        lambda f: _is_derivative(f) and "512kb" in _fmt(f) and re.search(r"mpeg-?4", _fmt(f)),
        lambda f: _is_derivative(f) and re.search(r"mpeg-?4", _fmt(f)),
        lambda f: _is_derivative(f) and re.search(r"(webm|matroska|ogg)", _fmt(f)),
        lambda f: _is_original(f)   and re.search(r"(mp4|h\.?264)", _fmt(f)),
        _is_original,
    ]

    def _size(f):
        try: return int(f.get("size") or 0)
        except ValueError: return 0

    for i, match in enumerate(tiers, start=1):
        candidates = [f for f in videos if match(f)]
        if candidates:
            candidates.sort(key=_size, reverse=True)
            best = candidates[0]
            return {
                "name":   best.get("name"),
                "format": best.get("format"),
                "size":   _size(best),
                "tier":   i,
            }
    return None


def detect_audio_presence(files):
    """Detect whether any h.264 derivative declares audio tracks. Returns
    0 (no audio / silent), 1 (audio present), or None (unknown).

    Archive.org's files array records codec info on some derivatives —
    when an h.264 derivative has NO audio, it's a strong signal the source
    was silent. Opportunistic: absence of metadata leaves it None."""
    if not files:
        return None
    for f in files:
        fmt = (f.get("format") or "").lower()
        if "h.264" not in fmt and "mp4" not in fmt:
            continue
        # Archive's derivatives sometimes include an audio/* codec field.
        audio = f.get("audio") or f.get("audio_codec") or f.get("audio-codec")
        if audio:
            return 1
        # Some files list a "noAudio" hint; others a duration-only metadata.
        if f.get("noAudio") or f.get("silent"):
            return 0
    return None


# ---------------------------------------------------------------------------
# HEAD verification — confirm a stream_url is actually playable
# ---------------------------------------------------------------------------

def head_verify_playable(url, timeout=15):
    """Issue a HEAD to the stream URL. Returns (ok: bool, reason: str)."""
    if not url:
        return False, "no_url"
    try:
        r = requests.head(url, headers={"User-Agent": USER_AGENT},
                          allow_redirects=True, timeout=timeout)
        if r.status_code >= 400:
            return False, f"http_{r.status_code}"
        ct = (r.headers.get("Content-Type") or "").lower()
        if not ct.startswith("video/") and "mpegurl" not in ct and "octet-stream" not in ct:
            return False, f"bad_content_type:{ct}"
        return True, "ok"
    except requests.RequestException as e:
        return False, f"exception:{type(e).__name__}"


# ---------------------------------------------------------------------------
# Helpers (existing)
# ---------------------------------------------------------------------------

def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    return [v]


def parse_year(*candidates):
    for v in candidates:
        if not v:
            continue
        if isinstance(v, list):
            v = v[0] if v else None
        if not v:
            continue
        s = str(v)
        for i in range(max(0, len(s) - 3)):
            chunk = s[i:i+4]
            if chunk.isdigit() and 1870 <= int(chunk) <= 2030:
                return int(chunk)
    return None


def parse_runtime_seconds(runtime):
    """Convert '1:23:45' or '85 min' or '5100' (seconds) to int seconds."""
    if not runtime:
        return None
    if isinstance(runtime, list):
        runtime = runtime[0] if runtime else None
    if not runtime:
        return None
    s = str(runtime).strip()
    # HH:MM:SS or MM:SS
    if ":" in s:
        parts = s.split(":")
        try:
            parts = [int(p) for p in parts]
            if len(parts) == 3:
                return parts[0]*3600 + parts[1]*60 + parts[2]
            if len(parts) == 2:
                return parts[0]*60 + parts[1]
        except ValueError:
            pass
    # "85 min" / "85 minutes"
    m = re.match(r"^\s*(\d+)\s*m", s, re.IGNORECASE)
    if m:
        return int(m.group(1)) * 60
    # Plain int seconds
    try:
        n = int(float(s))
        # If it's suspiciously small, probably minutes
        if n < 600:
            return n * 60
        return n
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Work upsert: the heart of federation
# ---------------------------------------------------------------------------

def upsert_work(conn, *, canonical_id, id_scheme, title, year, runtime_sec,
                work_type, rights_status, description, languages, subjects):
    """Insert or merge a work. Merging prefers non-null values."""
    cur = conn.execute(
        "SELECT title, year, runtime_sec, work_type, rights_status, description, "
        "languages, subjects FROM works WHERE canonical_id = ?",
        (canonical_id,),
    )
    existing = cur.fetchone()
    if existing:
        # Merge: prefer existing non-null, take new if existing was null
        e_title, e_year, e_runtime, e_type, e_rights, e_desc, e_langs, e_subj = existing
        merged = {
            "title":         e_title or title,
            "year":          e_year if e_year is not None else year,
            "runtime_sec":   e_runtime if e_runtime is not None else runtime_sec,
            "work_type":     work_type if (e_type in (None, "unknown") and work_type) else (e_type or work_type),
            "rights_status": _merge_rights(e_rights, rights_status),
            "description":   e_desc or description,
            "languages":     _merge_json_list(e_langs, languages),
            "subjects":      _merge_json_list(e_subj, subjects),
        }
        conn.execute(
            """UPDATE works SET title=?, title_normalized=?, year=?, runtime_sec=?,
               work_type=?, rights_status=?, description=?, languages=?, subjects=?,
               updated_at=CURRENT_TIMESTAMP WHERE canonical_id=?""",
            (merged["title"], normalize_title(merged["title"]), merged["year"],
             merged["runtime_sec"], merged["work_type"], merged["rights_status"],
             merged["description"], merged["languages"], merged["subjects"],
             canonical_id),
        )
    else:
        conn.execute(
            """INSERT INTO works (canonical_id, id_scheme, title, title_normalized,
               year, runtime_sec, work_type, rights_status, description,
               languages, subjects)
               VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
            (canonical_id, id_scheme, title, normalize_title(title), year,
             runtime_sec, work_type, rights_status, description,
             json.dumps(languages or []), json.dumps(subjects or [])),
        )


def _merge_rights(existing, new):
    """Prefer the more specific/permissive of two rights statuses."""
    rank = {"public_domain": 3, "creative_commons": 2,
            "rights_reserved_free_stream": 1, "unknown": 0, None: 0}
    return existing if rank.get(existing, 0) >= rank.get(new, 0) else new


def _merge_json_list(existing_json, new_list):
    try:
        existing = json.loads(existing_json) if existing_json else []
    except Exception:
        existing = []
    merged = list(dict.fromkeys(existing + (new_list or [])))  # dedupe, preserve order
    return json.dumps(merged)


def upsert_source(conn, *, canonical_id, source_type, source_id, source_url,
                  stream_url, format_hint, file_size, downloadable, raw_json):
    quality = score_source(source_type, format_hint, downloadable, file_size)
    conn.execute(
        """INSERT OR REPLACE INTO sources
           (canonical_id, source_type, source_id, source_url, stream_url,
            format_hint, file_size, downloadable, source_quality, raw_json)
           VALUES (?,?,?,?,?,?,?,?,?,?)""",
        (canonical_id, source_type, source_id, source_url, stream_url,
         format_hint, file_size, 1 if downloadable else 0, quality, raw_json),
    )


# ---------------------------------------------------------------------------
# Archive.org ingestion
# ---------------------------------------------------------------------------

def scrape_ia_collection(collection_id, limit=None):
    q = f"mediatype:movies AND collection:{collection_id}"
    cursor = None
    fetched = 0
    while True:
        params = {"q": q, "fields": ",".join(IA_FIELDS), "count": PAGE_SIZE}
        if cursor:
            params["cursor"] = cursor
        url = f"{IA_SCRAPE_ENDPOINT}?{urlencode(params)}"
        r = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=60)
        r.raise_for_status()
        data = r.json()
        items = data.get("items", [])
        if not items:
            break
        for item in items:
            yield item
            fetched += 1
            if limit and fetched >= limit:
                return
        cursor = data.get("cursor")
        if not cursor:
            break
        time.sleep(0.5)


def ingest_ia_item(conn, item, *, exclude_adult=True):
    ia_id = item.get("identifier")
    if not ia_id:
        return None
    title = item.get("title")
    if isinstance(title, list):
        title = title[0] if title else ia_id
    if not title:
        title = ia_id

    collections = as_list(item.get("collection"))

    # Adult filter (app Decision 012): skip ingest entirely for adult-tagged
    # collections when the flag is on. Still indexable by running without it.
    if exclude_adult and any(c in _ADULT_COLLECTIONS for c in collections):
        return None

    # Year: use the app's safe extractor that rejects upload-date masquerading.
    year = safe_year(item)
    creator = item.get("creator")
    runtime_sec = parse_runtime_seconds(item.get("runtime"))
    subjects = as_list(item.get("subject"))
    licenseurl = item.get("licenseurl")
    description = item.get("description")
    if isinstance(description, list):
        description = " ".join(str(d) for d in description)

    # Canonical ID: prefer IMDb if IA already knows it — beats waiting for
    # the Wikidata SPARQL pass, catches works Wikidata doesn't cover.
    ext_ids = extract_external_ids(item)
    if ext_ids.get("imdb"):
        canonical_id = f"imdb:{ext_ids['imdb']}"
        id_scheme = "imdb"
    else:
        canonical_id = compute_local_id(title, year, creator)
        id_scheme = "local"

    work_type = classify_work_type(collections, subjects, runtime_sec, title)
    rights_status = classify_rights(licenseurl, "archive_org")
    if rights_status == "unknown" and any(
        c in ("feature_films", "classic_cartoons", "silent_films",
              "classic_tv", "short_films", "sensiblecinema", "vintage_cartoons")
        for c in collections
    ):
        rights_status = "public_domain"

    # Silent-era multi-signal detection (ported from the tvOS app). Runs
    # before upsert so both work_type and silent flag land in the same row.
    is_silent, silent_signals = classify_silent(
        collections=collections,
        year=year,
        work_type=work_type,
        creator=creator,
        director_names=None,   # Wikidata pass will refine if available
        description=description,
        subjects=subjects,
        has_audio_track=None,  # filled in later by resolve_ia_derivatives()
    )

    upsert_work(
        conn,
        canonical_id=canonical_id, id_scheme=id_scheme,
        title=title, year=year, runtime_sec=runtime_sec,
        work_type=work_type, rights_status=rights_status,
        description=(description[:5000] if isinstance(description, str) else None),
        languages=as_list(item.get("language")),
        subjects=subjects,
    )

    # Record is_silent explicitly — upsert_work's OR-merge only handles
    # content columns, not the new signal fields.
    conn.execute(
        "UPDATE works SET is_silent = ?, silent_signals = ? WHERE canonical_id = ?",
        (1 if is_silent else 0,
         json.dumps(silent_signals) if silent_signals else None,
         canonical_id),
    )

    # Opportunistically store enrichment rows we know at ingest time.
    if ext_ids.get("imdb") or ext_ids.get("tmdb") or ext_ids.get("wikidata"):
        conn.execute(
            """INSERT OR IGNORE INTO enrichment
               (canonical_id, wikidata_qid, imdb_id, tmdb_id)
               VALUES (?, ?, ?, ?)""",
            (canonical_id, ext_ids.get("wikidata"),
             ext_ids.get("imdb"), ext_ids.get("tmdb")),
        )

    format_hint = item.get("format")
    if isinstance(format_hint, list):
        format_hint = format_hint[0] if format_hint else None

    upsert_source(
        conn,
        canonical_id=canonical_id,
        source_type="archive_org",
        source_id=ia_id,
        source_url=f"https://archive.org/details/{ia_id}",
        # Placeholder: /download/{id} is the folder. The derivative-resolution
        # pass replaces this with the real MP4 URL; until then, downstream
        # consumers should treat stream_url as unplayable for IA sources.
        stream_url=f"https://archive.org/download/{ia_id}",
        format_hint=format_hint,
        file_size=int(item.get("item_size") or 0) or None,
        downloadable=True,
        raw_json=json.dumps(item, ensure_ascii=False),
    )

    # Capture engagement signals from IA (it's the only source with them)
    conn.execute(
        """INSERT OR REPLACE INTO engagement
           (source_type, source_id, downloads, num_favorites, num_reviews,
            avg_rating, week_views, refreshed_at)
           VALUES ('archive_org', ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)""",
        (
            ia_id,
            int(item.get("downloads") or 0) or None,
            int(item.get("num_favorites") or 0) or None,
            int(item.get("num_reviews") or 0) or None,
            float(item.get("avg_rating")) if item.get("avg_rating") else None,
            int(item.get("week") or 0) or None,
        ),
    )
    return canonical_id


# ---------------------------------------------------------------------------
# Library of Congress ingestion
# ---------------------------------------------------------------------------

def scrape_loc_collection(slug, limit=None):
    """Paginate through a LoC collection, yielding only moving-image items."""
    page = 1
    fetched = 0
    while True:
        params = {"fo": "json", "c": 100, "sp": page}
        url = f"{LOC_API_ENDPOINT}/collections/{slug}/?{urlencode(params)}"
        try:
            r = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=60)
            r.raise_for_status()
        except requests.HTTPError as e:
            # LoC rate limits aggressively; back off
            if e.response.status_code == 429:
                time.sleep(30)
                continue
            raise
        data = r.json()
        results = data.get("results", [])
        if not results:
            break
        for item in results:
            # Only keep moving-image items
            original_format = item.get("original_format") or []
            if isinstance(original_format, str):
                original_format = [original_format]
            if not any("film" in f.lower() or "video" in f.lower() or "motion picture" in f.lower()
                       for f in original_format):
                # Some items in these collections are stills/paper; skip them
                continue
            yield item
            fetched += 1
            if limit and fetched >= limit:
                return
        # Paginate
        pagination = data.get("pagination", {})
        if not pagination.get("next"):
            break
        page += 1
        time.sleep(1.0)  # be polite; LoC throttles


def ingest_loc_item(conn, item):
    loc_id = item.get("id", "")
    # LoC IDs are URLs like https://www.loc.gov/item/xxxx/; extract the slug
    slug_match = re.search(r"/item/([^/]+)/?", loc_id)
    source_id = slug_match.group(1) if slug_match else loc_id
    if not source_id:
        return None

    title = item.get("title") or source_id
    # LoC 'date' can be "1915", "1915-05", ISO, or a freeform string
    year = parse_year(item.get("date"), item.get("dates"))
    creator = item.get("contributor") or item.get("creator")
    description = item.get("description") or item.get("summary")
    if isinstance(description, list):
        description = " ".join(str(d) for d in description)
    subjects = as_list(item.get("subject"))

    # LoC items don't usually expose runtime in search results; leave null
    runtime_sec = None

    # Is there a downloadable MP4? The item's resources list tells us.
    resources = item.get("resources") or []
    stream_url = None
    downloadable = False
    format_hint = None
    if resources and isinstance(resources, list):
        for res in resources:
            files = res.get("files") or []
            for f in files if isinstance(files, list) else []:
                if isinstance(f, dict):
                    url = f.get("url", "")
                    mime = f.get("mimetype", "")
                    if url.endswith(".mp4") or "video/mp4" in mime:
                        stream_url = url
                        downloadable = True
                        format_hint = "mp4"
                        break
            if stream_url:
                break

    # Rights: LoC explicitly marks public domain items; streamable-only
    # items are typically rights-restricted
    rights_field = item.get("rights") or ""
    if isinstance(rights_field, list):
        rights_field = " ".join(str(r) for r in rights_field)
    rights_l = rights_field.lower()
    if "public domain" in rights_l or "no known restrictions" in rights_l:
        rights_status = "public_domain"
    elif downloadable:
        rights_status = "public_domain"  # downloadable on LoC strongly implies PD
    else:
        rights_status = "rights_reserved_free_stream"

    work_type = classify_work_type([], subjects, runtime_sec, title)

    canonical_id = compute_local_id(title, year, creator)

    upsert_work(
        conn,
        canonical_id=canonical_id, id_scheme="local",
        title=title, year=year, runtime_sec=runtime_sec,
        work_type=work_type, rights_status=rights_status,
        description=(description[:5000] if isinstance(description, str) else None),
        languages=as_list(item.get("language")),
        subjects=subjects,
    )

    upsert_source(
        conn,
        canonical_id=canonical_id,
        source_type="loc",
        source_id=source_id,
        source_url=loc_id if loc_id.startswith("http") else f"https://www.loc.gov/item/{source_id}/",
        stream_url=stream_url,
        format_hint=format_hint,
        file_size=None,
        downloadable=downloadable,
        raw_json=json.dumps(item, ensure_ascii=False),
    )
    return canonical_id


# ---------------------------------------------------------------------------
# Wikidata enrichment + canonical ID promotion
# ---------------------------------------------------------------------------

WIKIDATA_QUERY = """
SELECT ?film ?filmLabel ?iaID ?imdbID ?tmdbID ?pubDate ?article
       (GROUP_CONCAT(DISTINCT ?directorLabel; separator="|") AS ?directors)
       (GROUP_CONCAT(DISTINCT ?castLabel;     separator="|") AS ?cast)
       (GROUP_CONCAT(DISTINCT ?genreLabel;    separator="|") AS ?genres)
       (GROUP_CONCAT(DISTINCT ?countryLabel;  separator="|") AS ?countries)
       (SAMPLE(?image) AS ?poster)
WHERE {
  ?film wdt:P31/wdt:P279* wd:Q11424 ;
        wdt:P724 ?iaID .
  OPTIONAL { ?film wdt:P345  ?imdbID }
  OPTIONAL { ?film wdt:P4947 ?tmdbID }
  OPTIONAL { ?film wdt:P577  ?pubDate }
  OPTIONAL { ?film wdt:P18   ?image }
  OPTIONAL {
    ?article schema:about ?film ;
             schema:isPartOf <https://en.wikipedia.org/> .
  }
  OPTIONAL {
    ?film wdt:P57 ?director .
    ?director rdfs:label ?directorLabel . FILTER(LANG(?directorLabel) = "en")
  }
  OPTIONAL {
    ?film wdt:P161 ?castMember .
    ?castMember rdfs:label ?castLabel . FILTER(LANG(?castLabel) = "en")
  }
  OPTIONAL {
    ?film wdt:P136 ?genre .
    ?genre rdfs:label ?genreLabel . FILTER(LANG(?genreLabel) = "en")
  }
  OPTIONAL {
    ?film wdt:P495 ?country .
    ?country rdfs:label ?countryLabel . FILTER(LANG(?countryLabel) = "en")
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
}
GROUP BY ?film ?filmLabel ?iaID ?imdbID ?tmdbID ?pubDate ?article
"""


def fetch_wikidata():
    r = requests.get(
        WIKIDATA_SPARQL,
        params={"query": WIKIDATA_QUERY, "format": "json"},
        headers={"User-Agent": USER_AGENT,
                 "Accept": "application/sparql-results+json"},
        timeout=240,
    )
    r.raise_for_status()
    return r.json()["results"]["bindings"]


def apply_wikidata(conn, bindings):
    """Promote lic: IDs to wd: IDs where Wikidata maps IA ID -> film."""
    promoted = 0
    enriched = 0
    for b in bindings:
        ia_id = b.get("iaID", {}).get("value")
        if not ia_id:
            continue
        qid = b["film"]["value"].rsplit("/", 1)[-1]
        new_canonical = f"wd:{qid}"

        # Find the existing local-ID work this IA source is currently attached to
        row = conn.execute(
            """SELECT s.canonical_id FROM sources s
               WHERE s.source_type = 'archive_org' AND s.source_id = ?""",
            (ia_id,),
        ).fetchone()
        if not row:
            continue
        old_canonical = row[0]

        if old_canonical != new_canonical:
            # Promote: merge old work into new canonical_id
            _repoint_canonical_id(conn, old_canonical, new_canonical, id_scheme="wikidata")
            promoted += 1

        # Write enrichment row against the (now) Wikidata-keyed work
        conn.execute(
            """INSERT OR REPLACE INTO enrichment
               (canonical_id, wikidata_qid, imdb_id, tmdb_id, wikipedia_url,
                directors, cast_list, genres, countries, publication_date, poster_url)
               VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
            (
                new_canonical, qid,
                b.get("imdbID",  {}).get("value"),
                b.get("tmdbID",  {}).get("value"),
                b.get("article", {}).get("value"),
                json.dumps([s for s in b.get("directors", {}).get("value", "").split("|") if s]),
                json.dumps([s for s in b.get("cast",      {}).get("value", "").split("|") if s]),
                json.dumps([s for s in b.get("genres",    {}).get("value", "").split("|") if s]),
                json.dumps([s for s in b.get("countries", {}).get("value", "").split("|") if s]),
                b.get("pubDate", {}).get("value"),
                b.get("poster",  {}).get("value"),
            ),
        )
        enriched += 1
    return promoted, enriched


def _repoint_canonical_id(conn, old_id, new_id, id_scheme):
    """Move a work from old_id to new_id, merging if new_id already exists."""
    existing_new = conn.execute(
        "SELECT 1 FROM works WHERE canonical_id = ?", (new_id,)
    ).fetchone()

    if not existing_new:
        # Simple rename
        conn.execute(
            "UPDATE works SET canonical_id = ?, id_scheme = ? WHERE canonical_id = ?",
            (new_id, id_scheme, old_id),
        )
        conn.execute(
            "UPDATE sources SET canonical_id = ? WHERE canonical_id = ?",
            (new_id, old_id),
        )
    else:
        # A work already exists under new_id (e.g. same film from LoC already keyed).
        # Move sources over and delete the old work.
        conn.execute(
            "UPDATE OR IGNORE sources SET canonical_id = ? WHERE canonical_id = ?",
            (new_id, old_id),
        )
        # Any sources that collided (same source_type+source_id) we just leave;
        # the UNIQUE constraint prevented duplicates.
        conn.execute("DELETE FROM works WHERE canonical_id = ?", (old_id,))


# ---------------------------------------------------------------------------
# AAPB (American Archive of Public Broadcasting) ingestion
# ---------------------------------------------------------------------------
#
# AAPB exposes a Solr-backed JSON API at https://americanarchive.org/api.json
# No key required. Returns PBCore-derived records. We filter to video assets
# that are viewable in the Online Reading Room (access_types:online).

# AAPB fields we want back in search results. The API returns a subset of
# flattened PBCore fields; the full PBCore XML is available per-record at
# <landing>.pbcore if we need it later.
AAPB_FIELDS = [
    "id", "title", "exact_title", "asset_type", "asset_date",
    "broadcast_date", "genres", "topics", "subjects",
    "media_type", "access_types", "organization", "description",
    "rights_summary", "duration",
]


def scrape_aapb(limit=None):
    """Yield AAPB Online Reading Room video items.

    Query: all video assets that are accessible online. AAPB's media_type
    facet distinguishes "Moving Image" (video) from "Sound" (radio).
    """
    # q=* is rejected; we use a real Solr filter query syntax
    q = "media_type:\"Moving Image\" AND access_types:online"
    start = 0
    fetched = 0
    while True:
        params = {
            "q": q,
            "rows": AAPB_PAGE_SIZE,
            "start": start,
            "fl": ",".join(AAPB_FIELDS),
        }
        url = f"{AAPB_API_ENDPOINT}?{urlencode(params)}"
        r = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=60)
        r.raise_for_status()
        data = r.json()
        response = data.get("response") or data  # Solr nests under 'response'
        docs = response.get("docs", [])
        if not docs:
            break
        for doc in docs:
            yield doc
            fetched += 1
            if limit and fetched >= limit:
                return
        num_found = response.get("numFound", 0)
        start += AAPB_PAGE_SIZE
        if start >= num_found:
            break
        time.sleep(0.5)


def ingest_aapb_item(conn, item):
    aapb_id = item.get("id")
    if not aapb_id:
        return None

    # AAPB's id is the GUID like "cpb-aacip_37-95j9krh1"; landing page pattern:
    landing = f"https://americanarchive.org/catalog/{aapb_id}"

    title = item.get("exact_title") or item.get("title") or aapb_id
    if isinstance(title, list):
        title = title[0] if title else aapb_id

    year = parse_year(item.get("asset_date"), item.get("broadcast_date"))

    # Duration: AAPB reports it as float seconds or "HH:MM:SS"
    runtime_sec = parse_runtime_seconds(item.get("duration"))

    # AAPB has structured genres/topics/subjects; merge them
    subjects = []
    for key in ("genres", "topics", "subjects"):
        v = item.get(key)
        if v:
            subjects.extend(as_list(v))

    asset_type = item.get("asset_type")
    if isinstance(asset_type, list):
        asset_type = asset_type[0] if asset_type else None

    work_type = classify_work_type(
        [], subjects, runtime_sec, title, pbcore_asset_type=asset_type
    )

    # Rights: AAPB content is almost always rights-restricted (stations retain
    # rights) but free to stream in the Online Reading Room. Some is PD.
    rights_summary = item.get("rights_summary") or ""
    if isinstance(rights_summary, list):
        rights_summary = " ".join(str(r) for r in rights_summary)
    rsum = rights_summary.lower()
    if "public domain" in rsum:
        rights_status = "public_domain"
    elif "creative commons" in rsum:
        rights_status = "creative_commons"
    else:
        rights_status = "rights_reserved_free_stream"

    description = item.get("description")
    if isinstance(description, list):
        description = " ".join(str(d) for d in description)

    org = item.get("organization")
    # Use organization as a creator-ish field for local ID hashing
    creator_for_id = org[0] if isinstance(org, list) and org else org

    canonical_id = compute_local_id(title, year, creator_for_id)

    upsert_work(
        conn,
        canonical_id=canonical_id, id_scheme="local",
        title=title, year=year, runtime_sec=runtime_sec,
        work_type=work_type, rights_status=rights_status,
        description=(description[:5000] if isinstance(description, str) else None),
        languages=[],  # AAPB doesn't expose language in standard fields reliably
        subjects=subjects,
    )

    upsert_source(
        conn,
        canonical_id=canonical_id,
        source_type="aapb",
        source_id=aapb_id,
        source_url=landing,
        stream_url=landing,       # streaming happens on the landing page
        format_hint=None,
        file_size=None,
        downloadable=False,
        raw_json=json.dumps(item, ensure_ascii=False),
    )
    return canonical_id


# ---------------------------------------------------------------------------
# Wikimedia Commons ingestion
# ---------------------------------------------------------------------------
#
# Commons hosts ~135k video files (webm, ogv). The MediaWiki API is at
# https://commons.wikimedia.org/w/api.php. No key required.
# We use generator=allimages with a MIME filter to paginate through video.

COMMONS_VIDEO_MIMES = ["video/webm", "video/ogg", "video/mp4", "application/ogg"]


def scrape_commons(limit=None):
    """Yield video file records from Wikimedia Commons."""
    # Commons' allimages generator can filter by MIME. We iterate each MIME
    # separately because the API only accepts one at a time.
    fetched = 0
    for mime in COMMONS_VIDEO_MIMES:
        aicontinue = None
        while True:
            params = {
                "action": "query",
                "format": "json",
                "generator": "allimages",
                "gaisort": "name",
                "gaimime": mime,
                "gailimit": COMMONS_PAGE_SIZE,
                "prop": "imageinfo|categories",
                "iiprop": "url|size|mime|metadata|extmetadata|mediatype",
                "cllimit": 50,
            }
            if aicontinue:
                params["gaicontinue"] = aicontinue
            r = requests.get(
                COMMONS_API, params=params,
                headers={"User-Agent": USER_AGENT}, timeout=60,
            )
            r.raise_for_status()
            data = r.json()
            pages = (data.get("query") or {}).get("pages", {})
            if not pages:
                break
            for page in pages.values():
                yield page
                fetched += 1
                if limit and fetched >= limit:
                    return
            cont = data.get("continue", {})
            aicontinue = cont.get("gaicontinue")
            if not aicontinue:
                break
            time.sleep(0.5)


def ingest_commons_item(conn, page):
    # The 'File:...' title is the natural Commons identifier
    pagetitle = page.get("title", "")
    if not pagetitle.startswith("File:"):
        return None
    filename = pagetitle[5:]  # strip "File:" prefix
    if not filename:
        return None

    imageinfo = (page.get("imageinfo") or [{}])[0]
    url = imageinfo.get("url")
    mime = imageinfo.get("mime")
    size = imageinfo.get("size")

    # Display title: strip extension and underscores for readability
    title_clean = re.sub(r"\.[^.]+$", "", filename).replace("_", " ").strip()

    # Extract useful metadata from extmetadata block (Wikimedia's curated layer)
    ext = imageinfo.get("extmetadata") or {}

    def _ext(key):
        v = ext.get(key, {})
        if isinstance(v, dict):
            return v.get("value")
        return None

    description_html = _ext("ImageDescription") or ""
    description = re.sub(r"<[^>]+>", "", description_html).strip() if description_html else None
    date_time_original = _ext("DateTimeOriginal") or _ext("DateTime")
    year = parse_year(date_time_original)
    author_html = _ext("Artist") or ""
    creator = re.sub(r"<[^>]+>", "", author_html).strip() if author_html else None
    license_name = (_ext("LicenseShortName") or "").lower()
    license_url = _ext("LicenseUrl")

    # Commons license -> rights_status
    if "public domain" in license_name or "pd" == license_name.strip():
        rights_status = "public_domain"
    elif "cc" in license_name or (license_url and "creativecommons" in license_url.lower()):
        rights_status = "creative_commons"
    else:
        rights_status = "unknown"

    # Use categories as subjects (lightweight genre signal)
    cats = page.get("categories") or []
    subjects = [c.get("title", "").replace("Category:", "") for c in cats if c.get("title")]

    # Commons video files are usually short clips, educational, or nature
    # footage. Without better hints, default classification leans on runtime
    # (which we don't get from a simple API call) — so we fall back to short_film.
    work_type = classify_work_type([], subjects, None, title_clean)
    if work_type == "unknown":
        work_type = "short_film"

    canonical_id = compute_local_id(title_clean, year, creator)

    upsert_work(
        conn,
        canonical_id=canonical_id, id_scheme="local",
        title=title_clean, year=year, runtime_sec=None,
        work_type=work_type, rights_status=rights_status,
        description=(description[:5000] if description else None),
        languages=[],
        subjects=subjects,
    )

    fmt = None
    if mime:
        if "webm" in mime: fmt = "webm"
        elif "ogg" in mime: fmt = "ogv"
        elif "mp4" in mime: fmt = "mp4"

    upsert_source(
        conn,
        canonical_id=canonical_id,
        source_type="wikimedia",
        source_id=filename,
        source_url=f"https://commons.wikimedia.org/wiki/{pagetitle.replace(' ', '_')}",
        stream_url=url,
        format_hint=fmt,
        file_size=int(size) if size else None,
        downloadable=True,
        raw_json=json.dumps(page, ensure_ascii=False),
    )
    return canonical_id


# ---------------------------------------------------------------------------
# European Film Gateway via Wikidata (no Europeana API key needed)
# ---------------------------------------------------------------------------
#
# Wikidata property P2484 holds the EFG film ID. We query for every film that
# has one, along with enrichment data. Each result becomes (a) a potential
# source row pointing at the EFG landing page, and (b) enrichment for any
# work we can match via P724 (IA ID) or title+year.

EFG_WIKIDATA_QUERY = """
SELECT ?film ?filmLabel ?efgID ?iaID ?imdbID ?pubDate
       (GROUP_CONCAT(DISTINCT ?directorLabel; separator="|") AS ?directors)
       (GROUP_CONCAT(DISTINCT ?countryLabel;  separator="|") AS ?countries)
       (SAMPLE(?image) AS ?poster)
WHERE {
  ?film wdt:P31/wdt:P279* wd:Q11424 ;
        wdt:P2484 ?efgID .
  OPTIONAL { ?film wdt:P724  ?iaID }
  OPTIONAL { ?film wdt:P345  ?imdbID }
  OPTIONAL { ?film wdt:P577  ?pubDate }
  OPTIONAL { ?film wdt:P18   ?image }
  OPTIONAL {
    ?film wdt:P57 ?director .
    ?director rdfs:label ?directorLabel . FILTER(LANG(?directorLabel) = "en")
  }
  OPTIONAL {
    ?film wdt:P495 ?country .
    ?country rdfs:label ?countryLabel . FILTER(LANG(?countryLabel) = "en")
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
}
GROUP BY ?film ?filmLabel ?efgID ?iaID ?imdbID ?pubDate
"""


def fetch_efg_from_wikidata():
    r = requests.get(
        WIKIDATA_SPARQL,
        params={"query": EFG_WIKIDATA_QUERY, "format": "json"},
        headers={"User-Agent": USER_AGENT,
                 "Accept": "application/sparql-results+json"},
        timeout=240,
    )
    r.raise_for_status()
    return r.json()["results"]["bindings"]


def apply_efg_sources(conn, bindings):
    """For each EFG-linked film, either add a source to an existing work or
    create a new Wikidata-keyed work."""
    added_sources = 0
    new_works = 0
    for b in bindings:
        efg_id = b["efgID"]["value"]
        qid = b["film"]["value"].rsplit("/", 1)[-1]
        new_canonical = f"wd:{qid}"
        title = b.get("filmLabel", {}).get("value") or qid
        year = parse_year(b.get("pubDate", {}).get("value"))

        # Does a work already exist for this QID?
        existing = conn.execute(
            "SELECT 1 FROM works WHERE canonical_id = ?", (new_canonical,)
        ).fetchone()

        if not existing:
            # Also check: maybe we have it under a local ID that matches by IA ID
            ia_id = b.get("iaID", {}).get("value")
            if ia_id:
                row = conn.execute(
                    """SELECT canonical_id FROM sources
                       WHERE source_type='archive_org' AND source_id=?""",
                    (ia_id,),
                ).fetchone()
                if row:
                    _repoint_canonical_id(conn, row[0], new_canonical, "wikidata")
                    existing = True
            if not existing:
                # Create a minimal work so we have something to attach the EFG source to
                upsert_work(
                    conn,
                    canonical_id=new_canonical, id_scheme="wikidata",
                    title=title, year=year, runtime_sec=None,
                    work_type="feature_film",  # EFG-linked are usually features
                    rights_status="unknown",
                    description=None,
                    languages=[],
                    subjects=[],
                )
                new_works += 1

        # EFG landing page. The EFG URL scheme accepts the raw ID as a URL slug.
        efg_url = f"https://www.europeanfilmgateway.eu/node/{efg_id}"
        upsert_source(
            conn,
            canonical_id=new_canonical,
            source_type="efg",
            source_id=efg_id,
            source_url=efg_url,
            stream_url=None,        # EFG usually deep-links to a partner archive
            format_hint=None,
            file_size=None,
            downloadable=False,
            raw_json=json.dumps(b, ensure_ascii=False),
        )
        added_sources += 1
    return new_works, added_sources


# ---------------------------------------------------------------------------
# Scoring pass
# ---------------------------------------------------------------------------
#
# After all sources are ingested and enrichment applied, we compute each
# work's quality_score and popularity_score in one pass. This is cheap
# (a SQLite scan) and can be re-run any time without re-scraping.

def _work_for_scoring(conn, canonical_id):
    """Gather everything needed to score one work. Returns a dict."""
    row = conn.execute(
        """SELECT title, year, runtime_sec, work_type, rights_status,
                  description, quality_score, popularity_score
             FROM works WHERE canonical_id = ?""",
        (canonical_id,),
    ).fetchone()
    if not row:
        return None
    title, year, runtime_sec, work_type, rights_status, description, q, p = row

    # Source count + best file_size (for quality heuristic)
    src_rows = conn.execute(
        """SELECT source_type, source_id, file_size FROM sources
           WHERE canonical_id = ?""",
        (canonical_id,),
    ).fetchall()
    source_count = len(src_rows)
    best_file_size = None
    for _, _, sz in src_rows:
        if sz and (best_file_size is None or sz > best_file_size):
            best_file_size = sz

    # Aggregate engagement across all sources
    downloads = num_favorites = num_reviews = 0
    avg_rating_sum = 0.0
    avg_rating_n = 0
    for stype, sid, _ in src_rows:
        eng = conn.execute(
            """SELECT downloads, num_favorites, num_reviews, avg_rating
                 FROM engagement WHERE source_type = ? AND source_id = ?""",
            (stype, sid),
        ).fetchone()
        if not eng:
            continue
        d, f, r, a = eng
        if d: downloads += d
        if f: num_favorites += f
        if r: num_reviews += r
        if a:
            avg_rating_sum += a
            avg_rating_n += 1
    avg_rating = (avg_rating_sum / avg_rating_n) if avg_rating_n else None

    # Enrichment signals
    enr = conn.execute(
        """SELECT imdb_id, directors, cast_list, poster_url, wikipedia_url
             FROM enrichment WHERE canonical_id = ?""",
        (canonical_id,),
    ).fetchone()
    has_imdb = has_director = has_cast = has_poster = False
    wikipedia_article_count = 0
    if enr:
        imdb_id, directors_json, cast_json, poster, wiki_url = enr
        has_imdb = bool(imdb_id)
        has_poster = bool(poster)
        try:
            has_director = bool(json.loads(directors_json or "[]"))
            has_cast = bool(json.loads(cast_json or "[]"))
        except Exception:
            pass
        # Wikipedia presence: count URLs. Our enrichment currently stores only
        # the English article; a future pass could pull sitelinks count from
        # Wikidata for a richer signal. For now: 1 if we have any article.
        wikipedia_article_count = 1 if wiki_url else 0

    return {
        "title": title,
        "year": year,
        "runtime_sec": runtime_sec,
        "work_type": work_type,
        "rights_status": rights_status,
        "description": description,
        "file_size": best_file_size,
        "downloads": downloads or None,
        "num_favorites": num_favorites or None,
        "num_reviews": num_reviews or None,
        "avg_rating": avg_rating,
        "source_count": source_count,
        "has_imdb": has_imdb,
        "has_director": has_director,
        "has_cast": has_cast,
        "has_poster": has_poster,
        "wikipedia_article_count": wikipedia_article_count,
    }


def score_all_works(conn):
    """Compute and write quality_score and popularity_score for every work."""
    cur = conn.execute("SELECT canonical_id FROM works")
    ids = [r[0] for r in cur.fetchall()]
    updated = 0
    for cid in ids:
        ctx = _work_for_scoring(conn, cid)
        if not ctx:
            continue

        q = compute_quality_score(
            title=ctx["title"],
            runtime_sec=ctx["runtime_sec"],
            file_size=ctx["file_size"],
            description=ctx["description"],
            work_type=ctx["work_type"],
            rights_status=ctx["rights_status"],
            has_year=ctx["year"] is not None,
        )
        p = compute_popularity_score(
            downloads=ctx["downloads"],
            num_favorites=ctx["num_favorites"],
            avg_rating=ctx["avg_rating"],
            num_reviews=ctx["num_reviews"],
            work_type=ctx["work_type"],
            year=ctx["year"],
            wikipedia_article_count=ctx["wikipedia_article_count"],
            has_poster=ctx["has_poster"],
            has_imdb=ctx["has_imdb"],
            has_director=ctx["has_director"],
            has_cast=ctx["has_cast"],
            source_count=ctx["source_count"],
        )
        conn.execute(
            """UPDATE works SET quality_score = ?, popularity_score = ?,
                   popularity_updated_at = CURRENT_TIMESTAMP
                 WHERE canonical_id = ?""",
            (int(q), int(p), cid),
        )
        updated += 1
    return updated


# ---------------------------------------------------------------------------
# Editor's-Picks direct fetch
# ---------------------------------------------------------------------------
# Some curator-selected items live in niche Archive collections that the
# main ingest doesn't scrape. Rather than scraping every possible
# collection, we fetch those specific IDs by /metadata/{id} and ingest
# them one by one. Expect a small list (10s of items).

def ingest_ia_by_id(conn, ia_id, *, exclude_adult=False):
    """Fetch /metadata/{id}, construct a pseudo-scrape record, ingest it.
    Returns canonical_id on success, None on failure."""
    meta = fetch_ia_metadata(ia_id)
    if not meta:
        return None
    m = meta.get("metadata") or {}
    files = meta.get("files") or []
    if not m.get("identifier"):
        return None

    # Shape the metadata into the flat dict that ingest_ia_item expects
    # from the scrape API. Fields the scrape API normally provides:
    item = {
        "identifier":  m.get("identifier"),
        "title":       m.get("title") or m.get("identifier"),
        "date":        m.get("date"),
        "year":        m.get("year"),
        "creator":     m.get("creator"),
        "description": m.get("description"),
        "subject":     m.get("subject"),
        "runtime":     m.get("runtime"),
        "language":    m.get("language"),
        "licenseurl":  m.get("licenseurl"),
        "mediatype":   m.get("mediatype") or "movies",
        "collection":  m.get("collection") or [],
        "downloads":   m.get("downloads"),
        "item_size":   m.get("item_size"),
        "publicdate":  m.get("publicdate"),
        "addeddate":   m.get("addeddate"),
        "format":      m.get("format"),
        "external-identifier": m.get("external-identifier"),
        "num_favorites": m.get("num_favorites"),
        "avg_rating":  m.get("avg_rating"),
        "num_reviews": m.get("num_reviews"),
        "week":        m.get("week"),
    }
    cid = ingest_ia_item(conn, item, exclude_adult=exclude_adult)
    if not cid:
        return None

    # Immediately resolve the derivative too, since we already have files.
    picked = pick_ia_derivative(files)
    audio  = detect_audio_presence(files)
    if picked:
        real_url = f"https://archive.org/download/{ia_id}/{picked['name']}"
        conn.execute(
            """UPDATE sources
               SET stream_url = ?, derivative_name = ?, format_hint = ?,
                   file_size = ?, has_audio_track = ?
               WHERE source_type = 'archive_org' AND source_id = ?""",
            (real_url, picked["name"], picked["format"],
             picked["size"] or None, audio, ia_id),
        )
    return cid


def ingest_editors_picks(conn, featured_json_path, *, exclude_adult=False):
    """Read featured.json's Editor's Picks shelf, ensure every archiveID is
    in the DB by direct fetch. Returns (requested, already_in_db, fetched)."""
    with open(featured_json_path, "r", encoding="utf-8") as f:
        featured = json.load(f)
    ids = []
    for shelf in featured.get("shelves", []) or []:
        if shelf.get("id") == "editors-picks":
            for e in shelf.get("items", []) or []:
                if isinstance(e, dict) and e.get("archiveID"):
                    ids.append(e["archiveID"])
            break
    requested = len(ids)
    already = fetched = 0
    for ia_id in ids:
        row = conn.execute(
            "SELECT 1 FROM sources WHERE source_type='archive_org' AND source_id=?",
            (ia_id,),
        ).fetchone()
        if row:
            already += 1
            continue
        cid = ingest_ia_by_id(conn, ia_id, exclude_adult=exclude_adult)
        if cid:
            fetched += 1
            print(f"  [picks] fetched {ia_id} → {cid}", flush=True)
        else:
            print(f"  [picks] failed  {ia_id}", flush=True)
        time.sleep(0.15)
    conn.commit()
    return requested, already, fetched


# ---------------------------------------------------------------------------
# Archive.org derivative resolution pass
# ---------------------------------------------------------------------------
# For every archive_org source in the DB, hit /metadata/{id}, pick the best
# playable derivative via pick_ia_derivative, and overwrite stream_url with
# the real MP4 URL. Also detects audio-track presence and refreshes the
# silent flag on the parent work. Optional second-pass, per-item network
# request, so run it after ingest (or skip for a fast test build).

def resolve_ia_derivatives(conn, *, limit=None, skip_resolved=True):
    """Per-IA-source: fetch metadata, pick a derivative, write back.

    Returns (resolved, failed, silent_promoted)."""
    cur = conn.execute("""
        SELECT s.id, s.source_id, s.canonical_id, s.derivative_name,
               w.is_silent, w.silent_signals
        FROM sources s
        JOIN works w USING (canonical_id)
        WHERE s.source_type = 'archive_org'
    """)
    rows = cur.fetchall()
    if skip_resolved:
        rows = [r for r in rows if not r[3]]
    if limit:
        rows = rows[:limit]

    resolved = failed = silent_promoted = 0
    for i, (src_id, ia_id, canonical_id, _prev, was_silent, prev_signals) in enumerate(rows, start=1):
        meta = fetch_ia_metadata(ia_id)
        if not meta:
            failed += 1
            continue
        files = meta.get("files") or []
        picked = pick_ia_derivative(files)
        audio  = detect_audio_presence(files)
        if not picked:
            failed += 1
        else:
            real_url = f"https://archive.org/download/{ia_id}/{picked['name']}"
            conn.execute(
                """UPDATE sources
                   SET stream_url = ?, derivative_name = ?, format_hint = ?,
                       file_size = ?, has_audio_track = ?
                   WHERE id = ?""",
                (real_url, picked["name"], picked["format"],
                 picked["size"] or None, audio, src_id),
            )
            # Promote source_quality since we now KNOW it's a clean derivative.
            conn.execute(
                "UPDATE sources SET source_quality = MIN(100, source_quality + 5) "
                "WHERE id = ?", (src_id,),
            )
            resolved += 1

        # Re-classify silent with the newly-discovered audio signal.
        if audio == 0 and not was_silent:
            signals = json.loads(prev_signals) if prev_signals else []
            signals.append("no_audio_track")
            conn.execute(
                "UPDATE works SET is_silent = 1, silent_signals = ? WHERE canonical_id = ?",
                (json.dumps(signals), canonical_id),
            )
            silent_promoted += 1

        if i % 100 == 0:
            conn.commit()
            print(f"  [derivative] resolved {resolved}, failed {failed}, silent+{silent_promoted} ({i}/{len(rows)})")
        time.sleep(0.15)  # polite rate-limit

    conn.commit()
    return resolved, failed, silent_promoted


# ---------------------------------------------------------------------------
# HEAD-verification pass
# ---------------------------------------------------------------------------
# Issue a HEAD to every source's stream_url. Flag the ones that return 200
# with a video-ish content-type as verified_playable. The best-source view
# prefers verified sources over unverified at the same quality score.

def verify_playable_sources(conn, *, source_types=("archive_org", "loc", "wikimedia"),
                             limit=None, skip_verified=True):
    """Issue HEAD to every source's stream_url; record the result."""
    placeholders = ",".join(["?"] * len(source_types))
    cur = conn.execute(
        f"SELECT id, stream_url FROM sources WHERE source_type IN ({placeholders})",
        source_types,
    )
    rows = cur.fetchall()
    if skip_verified:
        # Skip already-verified; re-verify failures (they may be transient).
        cur2 = conn.execute(
            f"SELECT id FROM sources WHERE source_type IN ({placeholders}) "
            "AND verified_playable = 1", source_types,
        )
        done = {r[0] for r in cur2.fetchall()}
        rows = [r for r in rows if r[0] not in done]
    if limit:
        rows = rows[:limit]

    ok = fail = 0
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat()
    for i, (src_id, url) in enumerate(rows, start=1):
        passed, _ = head_verify_playable(url)
        conn.execute(
            "UPDATE sources SET verified_playable = ?, verified_at = ? WHERE id = ?",
            (1 if passed else 0, now, src_id),
        )
        ok += 1 if passed else 0
        fail += 0 if passed else 1
        if i % 200 == 0:
            conn.commit()
            print(f"  [verify] ok={ok} fail={fail} ({i}/{len(rows)})")
        time.sleep(0.08)
    conn.commit()
    return ok, fail


# ---------------------------------------------------------------------------
# Popularity refresh (re-pull engagement data for existing IA items)
# ---------------------------------------------------------------------------
#
# Engagement data ages. This function re-scrapes IA just for the engagement
# fields for items already in the DB. No metadata is re-written. Cheap and
# safe to run on a cron.

def refresh_ia_engagement(conn, batch_size=500):
    """Re-pull downloads/favorites/rating for all archive.org sources."""
    cur = conn.execute(
        "SELECT source_id FROM sources WHERE source_type = 'archive_org'"
    )
    ids = [r[0] for r in cur.fetchall()]
    if not ids:
        return 0

    fields = "identifier,downloads,num_favorites,num_reviews,avg_rating,week"
    updated = 0
    for i in range(0, len(ids), batch_size):
        batch = ids[i:i+batch_size]
        # Build an OR query of identifiers. IA's Scrape API supports this but
        # Solr has a ~1024 clause limit, so we chunk.
        q = "(" + " OR ".join(f"identifier:{id_}" for id_ in batch) + ")"
        cursor = None
        while True:
            params = {"q": q, "fields": fields, "count": 1000}
            if cursor:
                params["cursor"] = cursor
            url = f"{IA_SCRAPE_ENDPOINT}?{urlencode(params)}"
            r = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=60)
            r.raise_for_status()
            data = r.json()
            items = data.get("items", [])
            for item in items:
                sid = item.get("identifier")
                if not sid:
                    continue
                conn.execute(
                    """INSERT OR REPLACE INTO engagement
                       (source_type, source_id, downloads, num_favorites,
                        num_reviews, avg_rating, week_views, refreshed_at)
                       VALUES ('archive_org', ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)""",
                    (
                        sid,
                        int(item.get("downloads") or 0) or None,
                        int(item.get("num_favorites") or 0) or None,
                        int(item.get("num_reviews") or 0) or None,
                        float(item.get("avg_rating")) if item.get("avg_rating") else None,
                        int(item.get("week") or 0) or None,
                    ),
                )
                updated += 1
            cursor = data.get("cursor")
            if not cursor:
                break
        conn.commit()
        time.sleep(0.3)
    return updated


# ---------------------------------------------------------------------------
# Diagnostic report
# ---------------------------------------------------------------------------
#
# Prints score distributions + sample titles at various thresholds, so you
# can pick `works_default` cutoffs that match your taste instead of guessing.

def print_score_report(conn):
    cur = conn.cursor()

    def _count(where=""):
        row = cur.execute(f"SELECT COUNT(*) FROM works {where}").fetchone()
        return row[0]

    total = _count()
    print(f"\nTotal works: {total}")
    if total == 0:
        print("(no works to analyze)")
        return

    # Quality score distribution
    print("\n=== QUALITY SCORE DISTRIBUTION ===")
    print(f"  (hard filter — 'is this worth keeping at all?')")
    buckets = [(0, 20), (20, 40), (40, 60), (60, 80), (80, 101)]
    for lo, hi in buckets:
        n = _count(f"WHERE quality_score >= {lo} AND quality_score < {hi}")
        bar = "█" * int(40 * n / total) if total else ""
        print(f"  {lo:>3}-{hi-1:<3}: {n:>6} {bar}")

    # Popularity score distribution
    print("\n=== POPULARITY SCORE DISTRIBUTION ===")
    print(f"  (sort key — 'would a typical user care?')")
    for lo, hi in buckets:
        n = _count(f"WHERE popularity_score >= {lo} AND popularity_score < {hi}")
        bar = "█" * int(40 * n / total) if total else ""
        print(f"  {lo:>3}-{hi-1:<3}: {n:>6} {bar}")

    # How many survive at various threshold combos
    print("\n=== SURVIVAL AT VARIOUS CUTOFFS ===")
    combos = [(0, 0), (20, 0), (40, 0), (40, 25), (40, 40), (60, 40), (60, 60)]
    for q, p in combos:
        n = _count(f"WHERE quality_score >= {q} AND popularity_score >= {p}")
        pct = 100.0 * n / total
        print(f"  quality >= {q:>3}  popularity >= {p:>3}  →  {n:>6} works ({pct:5.1f}%)")

    # Sample titles at different slices
    print("\n=== SAMPLE: BOTTOM 10 BY QUALITY (likely garbage) ===")
    rows = cur.execute(
        """SELECT title, year, work_type, quality_score
             FROM works ORDER BY quality_score ASC, canonical_id LIMIT 10"""
    ).fetchall()
    for title, year, wt, q in rows:
        print(f"  q={q:>3}  [{wt or '?':<14}] {(title or '')[:60]} ({year or '?'})")

    print("\n=== SAMPLE: TOP 10 BY POPULARITY ===")
    rows = cur.execute(
        """SELECT title, year, work_type, quality_score, popularity_score
             FROM works ORDER BY popularity_score DESC, canonical_id LIMIT 10"""
    ).fetchall()
    for title, year, wt, q, p in rows:
        print(f"  p={p:>3} q={q:>3}  [{wt or '?':<14}] {(title or '')[:55]} ({year or '?'})")

    print("\n=== SAMPLE: 'MEDIUM' SLICE (q 40-60, p 20-40) ===")
    print("  (these are the borderline items your cutoff decisions affect most)")
    rows = cur.execute(
        """SELECT title, year, work_type, quality_score, popularity_score
             FROM works
            WHERE quality_score BETWEEN 40 AND 59
              AND popularity_score BETWEEN 20 AND 39
            ORDER BY canonical_id LIMIT 10"""
    ).fetchall()
    for title, year, wt, q, p in rows:
        print(f"  p={p:>3} q={q:>3}  [{wt or '?':<14}] {(title or '')[:55]} ({year or '?'})")

    # By work_type
    print("\n=== MEAN POPULARITY BY WORK TYPE ===")
    rows = cur.execute(
        """SELECT work_type, COUNT(*), AVG(popularity_score), AVG(quality_score)
             FROM works GROUP BY work_type ORDER BY 3 DESC"""
    ).fetchall()
    for wt, n, ap, aq in rows:
        print(f"  {wt or '<null>':<20} n={n:>6}  p̄={ap:5.1f}  q̄={aq:5.1f}")


def main():
    ALL_SOURCES = ["ia", "loc", "aapb", "commons"]

    ap = argparse.ArgumentParser(
        description="Build a federated video work registry from multiple archives."
    )
    ap.add_argument("--db", default="video_registry.db")
    ap.add_argument("--limit", type=int, default=None,
                    help="Cap items per collection (testing)")
    ap.add_argument("--sources", nargs="+", default=ALL_SOURCES,
                    choices=ALL_SOURCES,
                    help="Which sources to ingest (default: all)")
    ap.add_argument("--skip-enrichment", action="store_true",
                    help="Skip Wikidata + EFG passes")
    ap.add_argument("--no-score", action="store_true",
                    help="Skip the work-level quality/popularity scoring pass")
    ap.add_argument("--collections", nargs="+", default=None,
                    help="Override archive.org collections list")
    ap.add_argument("--report", action="store_true",
                    help="Print the score distribution report and exit (no ingest)")
    ap.add_argument("--refresh-engagement", action="store_true",
                    help="Re-pull IA engagement data for existing items, "
                         "rescore, and exit (no ingest)")
    ap.add_argument("--resolve-derivatives", action="store_true",
                    help="For every archive_org source, hit /metadata/{id} "
                         "and resolve the real playable MP4. Also detects "
                         "audio track presence (feeds silent classification).")
    ap.add_argument("--verify-playable", action="store_true",
                    help="HEAD-verify every source stream URL and mark "
                         "verified_playable on sources. Best-source view "
                         "prefers verified sources.")
    ap.add_argument("--include-adult", action="store_true",
                    help="Don't filter out adult-tagged collections during "
                         "ingest (app filters them at read time by default).")
    ap.add_argument("--fetch-editors-picks", action="store_true",
                    help="Read featured.json and fetch every Editor's Pick "
                         "Archive ID directly via /metadata/{id}. Cheap; "
                         "ensures curated picks survive even if they're in "
                         "a collection we don't scrape.")
    ap.add_argument("--featured", default="featured.json",
                    help="Path to featured.json for --fetch-editors-picks.")
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(SCHEMA)
    # Run the additive migration AFTER the base schema so old DBs pick up
    # the new app-learning columns (is_silent, has_audio_track, etc.).
    migrate_schema(conn)
    conn.commit()

    # One-shot passes that exit after running.
    if args.resolve_derivatives:
        print("[derivative] resolving archive.org derivatives…")
        r, f, s = resolve_ia_derivatives(conn)
        print(f"[derivative] resolved {r}, failed {f}, silent-promoted {s}")
        conn.close()
        return

    if args.verify_playable:
        print("[verify] HEAD-verifying source stream URLs…")
        ok, fail = verify_playable_sources(conn)
        print(f"[verify] ok={ok} fail={fail}")
        conn.close()
        return

    if args.fetch_editors_picks:
        print("[picks] fetching Editor's Picks by Archive ID…", flush=True)
        req, already, got = ingest_editors_picks(conn, args.featured,
                                                 exclude_adult=not args.include_adult)
        print(f"[picks] requested={req}  already_in_db={already}  fetched={got}", flush=True)
        conn.close()
        return

    # --- Report mode: nothing else runs ---
    if args.report:
        print_score_report(conn)
        conn.close()
        return

    # --- Engagement-refresh mode: pull fresh IA engagement, rescore, exit ---
    if args.refresh_engagement:
        print("[refresh] pulling fresh engagement data for archive.org items…")
        try:
            n = refresh_ia_engagement(conn)
            conn.commit()
            print(f"[refresh] updated engagement for {n} items")
        except Exception as e:
            print(f"[refresh] failed: {e}", file=sys.stderr)
        print("[score] recomputing quality + popularity scores…")
        updated = score_all_works(conn)
        conn.commit()
        print(f"[score] rescored {updated} works")
        print_score_report(conn)
        conn.close()
        return

    want = set(args.sources)

    # --- Archive.org ---
    if "ia" in want:
        targets = args.collections or list(IA_COLLECTIONS.keys())
        for ti, coll in enumerate(targets, start=1):
            print(f"[ia] ({ti}/{len(targets)}) scraping collection={coll}", flush=True)
            n = 0
            try:
                for item in scrape_ia_collection(coll, limit=args.limit):
                    ingest_ia_item(conn, item, exclude_adult=not args.include_adult)
                    n += 1
                    if n % 50 == 0:
                        conn.commit()
                        print(f"  [ia:{coll}] ingested {n}", flush=True)
            except requests.HTTPError as e:
                print(f"  [warn] HTTP on {coll}: {e}", file=sys.stderr)
            conn.commit()
            print(f"  [ia] done {coll}: {n}", flush=True)

    # --- Library of Congress ---
    if "loc" in want:
        for ti, slug in enumerate(LOC_COLLECTIONS, start=1):
            print(f"[loc] ({ti}/{len(LOC_COLLECTIONS)}) scraping collection={slug}", flush=True)
            n = 0
            try:
                for item in scrape_loc_collection(slug, limit=args.limit):
                    ingest_loc_item(conn, item)
                    n += 1
                    if n % 25 == 0:
                        conn.commit()
                        print(f"  [loc:{slug}] ingested {n}", flush=True)
            except requests.HTTPError as e:
                print(f"  [warn] HTTP on {slug}: {e}", file=sys.stderr)
            except requests.RequestException as e:
                print(f"  [warn] {slug}: {e}", file=sys.stderr)
            conn.commit()
            print(f"  [loc] done {slug}: {n}", flush=True)

    # --- AAPB ---
    if "aapb" in want:
        print("[aapb] scraping Online Reading Room (video)", flush=True)
        n = 0
        try:
            for item in scrape_aapb(limit=args.limit):
                ingest_aapb_item(conn, item)
                n += 1
                if n % 50 == 0:
                    conn.commit()
                    print(f"  [aapb] ingested {n}", flush=True)
        except requests.HTTPError as e:
            print(f"  [warn] HTTP on aapb: {e}", file=sys.stderr)
        except requests.RequestException as e:
            print(f"  [warn] aapb: {e}", file=sys.stderr)
        conn.commit()
        print(f"  [aapb] done: {n}")

    # --- Wikimedia Commons ---
    if "commons" in want:
        print("[commons] scraping video files", flush=True)
        n = 0
        try:
            for item in scrape_commons(limit=args.limit):
                ingest_commons_item(conn, item)
                n += 1
                if n % 50 == 0:
                    conn.commit()
                    print(f"  [commons] ingested {n}", flush=True)
        except requests.HTTPError as e:
            print(f"  [warn] HTTP on commons: {e}", file=sys.stderr)
        except requests.RequestException as e:
            print(f"  [warn] commons: {e}", file=sys.stderr)
        conn.commit()
        print(f"  [commons] done: {n}")

    # --- Wikidata enrichment (IA IDs) + canonical ID promotion ---
    if not args.skip_enrichment:
        print("[enrich] fetching Wikidata (P724 — IA IDs)…")
        try:
            bindings = fetch_wikidata()
            print(f"[enrich] {len(bindings)} Wikidata film records with IA IDs")
            promoted, enriched = apply_wikidata(conn, bindings)
            conn.commit()
            print(f"[enrich] promoted {promoted} works to wd: IDs, enriched {enriched}")
        except Exception as e:
            print(f"[enrich] skipped: {e}", file=sys.stderr)

        print("[enrich] fetching Wikidata (P2484 — EFG IDs)…")
        try:
            efg_bindings = fetch_efg_from_wikidata()
            print(f"[enrich] {len(efg_bindings)} Wikidata films with EFG IDs")
            new_works, added_sources = apply_efg_sources(conn, efg_bindings)
            conn.commit()
            print(f"[enrich] EFG: {added_sources} sources added ({new_works} new works)")
        except Exception as e:
            print(f"[enrich] EFG skipped: {e}", file=sys.stderr)

    # --- Scoring pass (quality + popularity) ---
    if not args.no_score:
        print("[score] computing quality + popularity scores for every work…")
        updated = score_all_works(conn)
        conn.commit()
        print(f"[score] scored {updated} works")

    # --- Summary ---
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM works")
    work_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM sources")
    src_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM enrichment")
    enr_count = cur.fetchone()[0]
    cur.execute("SELECT id_scheme, COUNT(*) FROM works GROUP BY id_scheme")
    by_scheme = dict(cur.fetchall())
    cur.execute("SELECT work_type, COUNT(*) FROM works GROUP BY work_type ORDER BY 2 DESC")
    by_type = cur.fetchall()
    cur.execute("SELECT rights_status, COUNT(*) FROM works GROUP BY rights_status")
    by_rights = dict(cur.fetchall())
    cur.execute("SELECT source_type, COUNT(*) FROM sources GROUP BY source_type ORDER BY 2 DESC")
    by_source_type = cur.fetchall()
    cur.execute("""SELECT source_count, COUNT(*) FROM (
        SELECT canonical_id, COUNT(*) AS source_count FROM sources GROUP BY canonical_id
    ) GROUP BY source_count ORDER BY source_count""")
    src_dist = cur.fetchall()
    # Default-view survival count
    default_count = cur.execute(
        "SELECT COUNT(*) FROM works WHERE quality_score >= 40 AND popularity_score >= 25"
    ).fetchone()[0]

    print("\n" + "=" * 60)
    print(f"  Works:                    {work_count}")
    print(f"  Sources:                  {src_count}")
    print(f"  Enriched:                 {enr_count}")
    print(f"  In default view:          {default_count}  (quality≥40, popularity≥25)")
    print(f"  ID schemes:               {by_scheme}")
    print(f"  Rights:                   {by_rights}")
    print(f"  Sources by type:")
    for t, c in by_source_type:
        print(f"    {t or '<null>':<15} {c}")
    print(f"  Top work types:")
    for t, c in by_type[:10]:
        print(f"    {t or '<null>':<20} {c}")
    print(f"  Sources per work:         {dict(src_dist)}")
    print(f"  DB path:                  {Path(args.db).resolve()}")
    print("  Tip: run with --report to see score distributions and tune cutoffs")
    print("=" * 60)

    conn.close()


if __name__ == "__main__":
    main()
