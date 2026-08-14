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
import math
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


# `porno?\b` matches "porn"/"porno" as a word (or suffix like "Altersporno") but
# NOT "Pornographers" (Imamura's 1966 classic) — that's why it's not "pornograph".
_ADULT_TITLE_RE = re.compile(r"(porno?\b|\bxxx\b|hentai)", re.I)


def _is_adult(it):
    # Honor the item-level flag set by remediate_catalog.py (subject/genre/
    # title keyword detection — catches adult films that aren't in an adult
    # COLLECTION, e.g. foreign sexploitation like "Carne"). Then fall back to
    # the collection markers.
    if it.get("isAdult"):
        return 1
    # High-confidence explicit title markers (catches blatant items + dupes the
    # remediate flag missed, e.g. "Altersporno (No Subtitel)"). Deliberately tight
    # — only terms that never appear in legit film titles; NOT "hardcore" (the
    # 1979 Schrader film) or "naked"/"sex" (real cult titles). Subtle foreign
    # softcore stays a curation judgment call, not a keyword.
    if _ADULT_TITLE_RE.search(it.get("title") or ""):
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
    # The film's CANONICAL presentation first: within one imdb id, most copies
    # are the original print and colorized re-releases are the odd ones out —
    # so a copy matching the group's majority colorMode outranks everything
    # below. Without this, quality-first crowned a colorized "4K" print as His
    # Girl Friday's card, displacing the B&W original that carries the film's
    # corrected subtitles (frame-measured colorMode, Decision 025, is what
    # makes the vote trustworthy).
    majority = {}
    counts = {}
    for it in items:
        k = it.get("imdbID")
        cm = it.get("colorMode")
        if k and cm and not it.get("excluded"):
            counts.setdefault(k, {}).setdefault(cm, 0)
            counts[k][cm] += 1
    for k, c in counts.items():
        majority[k] = max(c, key=c.get)

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
        # _video_quality before votes: same-imdb copies tied on the coarse `r`
        # and fell through to votes (identical per title) and then LEXICOGRAPHIC
        # archiveID — which is how a 4K .ia.mp4 lost to whatever id sorted last.
        maj = majority.get(i.get("imdbID"))
        canonical = 1 if (maj is None or i.get("colorMode") in (None, maj)) else 0
        return (canonical, 1 if i.get("subtitleHLS") else 0, r, _video_quality(i),
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
    # Bare device qualifiers: "His Girl Friday iPod" is the same 1940 film as
    # its siblings, and with no imdb id on the upload the title key was the
    # only way it could ever merge — the owner saw it as its own card.
    " ipod", " iphone", " mobile",
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
    # A trailing bare "film" is an uploader qualifier ("TILL THE CLOUDS ROLL BY
    # Film" vs "Till the Clouds Roll By" — same 1946 musical, separate cards).
    # Only when something remains: a real title that IS the word can survive.
    stripped = re.sub(r" film$", "", t).strip()
    if stripped:
        t = stripped
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
    """Higher = better playable copy, from what the URL actually says about the
    VIDEO. The legacy qualityScore is damped to a tiebreak: its 50-70 spread
    (a murky registry metric, Decision 050's caveat) used to dwarf the +5
    resolution hint, so a 2 Mbps 720p re-upload with a high legacy score beat
    a real 4K copy — the owner called the result "a significant downgrade".
    Archive's own `.ia.mp4` derivatives get a bonus: they are normalized,
    faststart, cleanly-muxed encodes — the upload class that does NOT force
    AVFoundation into the tiny-random-read pattern (Decision 072)."""
    url = (i.get("downloadURL") or "").lower()
    q = (i.get("qualityScore") or 0) / 10.0
    if any(x in url for x in ("2160", "4k")):
        q += 12
    elif any(x in url for x in ("1080", "1920")):
        q += 10
    elif "720" in url:
        q += 6
    elif "480" in url:
        q += 2
    if ".ia.mp4" in url:
        q += 4
    if any(x in url for x in ("512kb", "256kb", "64kb", "ipod", "_ipod", "mobile")):
        q -= 12
    return q


def _real_art_rank(i):
    if not (i.get("hasRealArtwork") or i.get("artworkSource") not in (None, "archive")):
        return 0
    return {"tmdb": 4, "tvdb": 4, "wikidata": 3, "commons": 3,
            "generated": 2}.get(i.get("artworkSource"), 1)


_TRAILER_RE = re.compile(r"trailer|teaser|\bclip\b|excerpt|promo|sample", re.I)


def _community_copy_score(i):
    """How much a real audience VETTED this exact upload — the strongest "canonical
    copy" signal (research §B). Raw downloads alone is a trap (a film's trailer can
    out-download the film), so weight rated+reviewed and favourited copies, log-damp
    reach, and penalise trailer/clip uploads. Degrades to 0 before signals are
    harvested, so dedup falls back to resolution/captions as before."""
    ar = i.get("avgRating") or 0
    nr = i.get("numReviews") or 0
    nf = i.get("numFavorites") or 0
    dl = i.get("downloads") or 0
    s = 3.0 * ar * math.log10(1 + nr) + 2.0 * math.log10(1 + nf) + math.log10(1 + dl)
    if _TRAILER_RE.search((i.get("title") or "") + " " + (i.get("archiveID") or "")):
        s -= 8
    return s


# University courseware (MIT OpenCourseWare lecture videos) is in the `mit_ocw`
# collection — educational lectures, not cinema. They have huge archive.org view
# counts (students), so the community-signal popularity sort floated them to the
# top of Movies; exclude the whole collection from this film catalog (a cinematheque,
# not a course catalog). Reversible (remove the collection from the set).
_COURSEWARE_COLLECTIONS = {"mit_ocw"}


def _is_courseware(it):
    return any(c in _COURSEWARE_COLLECTIONS for c in (it.get("collections") or []))


# Mega-compilations (many films crammed into ONE archive.org item — "Public Domain
# Movies", "PD Cartoon Collection", grindhouse double features) are not single films
# but rack up huge view counts, so the popularity sort floats them to the top of
# Movies. Detect by title and exclude from the film catalog. Precision: the count+
# plural pattern is 1-3 digits so a 4-digit YEAR ("Rebecca (1940 Film Noir)") never
# matches, and bare "collection"/"feature" needs a film/cartoon qualifier.
_COMPILATION_RE = re.compile(
    r"\b(public domain movies|movie pack|movie collection|cartoon collection|"
    r"cartoons? compilation|films? collection|complete collection|"
    r"(double|triple|quadruple) feature|\bcompilation\b|mega ?pack|"
    r"all[\s-]in[\s-]one|grindhouse experi)\b", re.I)
_COMPILATION_COUNT_RE = re.compile(   # NOT "episodes" — preserve movie serials
    r"\b\d{1,3}\s+(movies|films|cartoons|features|shorts)\b", re.I)


def _is_compilation(it):
    t = it.get("title") or ""
    return bool(_COMPILATION_RE.search(t) or _COMPILATION_COUNT_RE.search(t))


def _pop_score(it):
    """Catalog sort score stored in the popularityScore column. STABLE, single-scale, recognition-
    weighted (owner 2026-06-29: "popularity sort doesn't work well"). The old score put 0.45 on
    30-day views, so momentary-trending obscurities (recent Bollywood, lectures) topped Home over
    classics; and items missing both downloads + views30d fell back to the raw legacy score (0-89),
    interleaving into the MIDDLE of the signal-scored items (0-4000+) — two incompatible scales.

    Now: all-time downloads dominate, IMDb recognition (votes) lifts known films over un-IMDb'd
    curiosities, rating + favourites contribute, 30-day views are a small recency nudge (NOT the
    driver — the "Watching Now" shelf is the hot-now lens, via its own views30d query). Scored items
    get +100 so they ALWAYS sort above the legacy-only band; truly-unharvested items keep the legacy
    score (0-89) as a low floor. Dry-run-validated: the top is now His Girl Friday / House on Haunted
    Hill / The Stranger / Dr. Strangelove / Night of the Living Dead / Sunset Boulevard (was trending
    obscurities). Query layers add a deterministic (imdbVotes, archiveID) tiebreak."""
    v30 = it.get("views30d") or 0
    mo = it.get("downloadsMonth") or 0
    dl = it.get("downloads") or 0
    nf = it.get("numFavorites") or 0
    nr = it.get("numReviews") or 0
    ar = it.get("avgRating")
    votes = it.get("imdbVotes") or 0
    if dl == 0 and mo == 0 and v30 == 0 and nf == 0 and nr == 0 and ar is None and votes == 0:
        return it.get("popularityScore") or 0        # un-harvested → low band (0-89), below scored
    C, m = 3.7, 10                                    # catalog-mean rating, vote floor
    bayes = ((nr / (nr + m)) * ar + (m / (nr + m)) * C) if ar else C
    s = (0.42 * math.log10(1 + dl) + 0.12 * math.log10(1 + mo)
         + 0.13 * (bayes / 5.0) + 0.08 * math.log10(1 + nf)
         + 0.10 * math.log10(1 + v30) + 0.15 * math.log10(1 + votes))
    return 100 + int(round(s * 1000))


# --- "Hidden Gems": high craft, low traffic ------------------------------------
#
# COMPUTED HERE, not in the clients, because of exactly how this broke. The shelf
# shipped 2026-06-01 as the client predicate `qualityScore >= 60 AND
# popularityScore <= 40`, written against the popularityScore of the day, a 0-89
# band. On 2026-06-29 `_pop_score` was rescaled to a single scale where every
# SCORED item is `100 + s*1000` (~100-4500) — so `<= 40` could thereafter match
# only un-harvested items, which have no craft signal either. Intersection: ZERO.
# The Hidden Gems row was silently empty on tvOS, iOS, macOS and Android for five
# weeks, and nothing failed: the query was valid, the column existed, the app
# rendered an empty shelf.
#
# The lesson is about WHICH SCALE OWNS THE CONSTANT. `imdbRating >= 7.0` and a
# vote band are semantic and stable — IMDb's 0-10 means the same thing next year,
# and vote counts are an absolute measure of fame. `popularityScore` is OUR
# internal, unstable score. So the external signals stay literal and the internal
# one is thresholded by PERCENTILE of the live distribution, recomputed each
# build. A future rescale of `_pop_score` now moves the cut automatically instead
# of silently emptying a shelf.
#
# Items with no IMDb rating can't qualify: a "gem" is a claim about craft, and
# without a rating we would only be guessing. (qualityScore, the old signal, is a
# legacy registry field present on ~53% of the catalog with a murky definition —
# deliberately not used.)
GEM_MIN_RATING = 7.0        # comfortably above the catalog median (6.1)
GEM_MIN_VOTES = 100         # enough votes that the rating is not noise
GEM_MAX_VOTES = 5000        # ...but not famous — the famous ones are "Top Rated"
GEM_POP_PERCENTILE = 45     # "low traffic", relative to the eligible pool
GEM_MIN_EXPECTED = 25       # below this, something is wrong — say so, loudly

# archive.org's OWN suppression signals, which we had never read. `deemphasize`
# is the Archive explicitly asking that an item not be surfaced, and it is a
# strong adult/exploitation marker the metadata filter misses (the visible set
# includes "The Naked Witch", "Eveready Harton in Buried Treasure", assorted
# stripper reels). `loggedin` items need an archive.org account, so they cannot
# play for our users at all. Honored for the CURATED shelf only — the items stay
# reachable in Browse/Search, the same demote-don't-delete stance as
# deprioritizedSeries. NOT `geo_restricted`: that includes real Chaplin, which
# plays fine in most regions.
#
# `g4video-web` is a g4tv.com web-video scrape — unambiguously not film. Its
# items reach a film shelf only via a WRONG external match (one carries King
# Vidor's "The Crowd" credits and 1928 on a games-show clip), so a named
# non-film collection is the honest guard; the match itself is Decision 026's
# problem, not this shelf's.
GEM_SUPPRESSED_COLLECTIONS = {"deemphasize", "loggedin", "g4video-web"}


def _gem_suppressed(it):
    return bool(GEM_SUPPRESSED_COLLECTIONS &
                {str(c).lower() for c in (it.get("collections") or [])})


def _mark_hidden_gems(rows, col, suppressed=frozenset()):
    """Set the hiddenGem flag on `rows` (the tuples about to be inserted).

    `col` maps a column name to its index in the row tuple; `suppressed` holds
    archiveIDs the Archive itself asks us not to feature. Only catalog-wide,
    scale-dependent conditions belong in the flag; per-USER filters (the adult
    toggle, hidden content types) stay in the client queries, since the pipeline
    cannot know them.
    """
    def eligible(r):
        # The population a Home shelf actually draws from — used as the base for
        # the percentile so the cut means "low traffic among comparable films",
        # not "low traffic among 5,000 un-harvested stubs".
        return (r[col["archiveID"]] not in suppressed
                and r[col["playable"]] == 1 and r[col["hasRealArtwork"]] == 1
                and (r[col["artworkSource"]] or "") not in ("", "archive", "generated")
                and r[col["isAdult"]] == 0
                and (r[col["contentType"]] or "") not in
                    ("tv-series", "tv-special", "tv-episode", "commercial")
                and (r[col["rightsStatus"]] in ("public_domain", "creative_commons")
                     or (r[col["year"]] is not None and 1888 <= r[col["year"]] <= 1977)))

    pool = [r for r in rows if eligible(r)]
    pops = sorted(r[col["popularityScore"]] or 0 for r in pool)
    if not pops:
        print("[gems] WARNING: no eligible items — hiddenGem left unset", flush=True)
        return rows, 0
    cut = pops[min(len(pops) - 1, int(len(pops) * GEM_POP_PERCENTILE / 100))]

    n = 0
    out = []
    for r in rows:
        gem = 0
        rating, votes = r[col["imdbRating"]], r[col["imdbVotes"]] or 0
        if (eligible(r) and r[col["year"]] is not None       # a no-year row is a data artifact
                and rating is not None and rating >= GEM_MIN_RATING
                and GEM_MIN_VOTES <= votes <= GEM_MAX_VOTES
                and (r[col["popularityScore"]] or 0) <= cut):
            gem = 1
            n += 1
        out.append(r[:col["hiddenGem"]] + (gem,) + r[col["hiddenGem"] + 1:])

    print(f"[gems] {n} hidden gems (pool {len(pool)}, "
          f"P{GEM_POP_PERCENTILE} popularity cut {cut})", flush=True)
    if n < GEM_MIN_EXPECTED:
        # The alarm that did not exist in June. An empty curated shelf is invisible
        # in the app and invisible in the build log unless something says so.
        print(f"[gems] WARNING: only {n} hidden gems (expected >= {GEM_MIN_EXPECTED}). "
              f"Has _pop_score been rescaled, or enrichment regressed?", flush=True)
    return out, cut


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
    # Mostly-shouting titles ("TILL THE CLOUDS ROLL BY Film") dodge isupper()
    # via one lowercase word and tied with the clean title, so the tie kept the
    # uploader string. Judge the ratio, not the flag.
    alpha = [c for c in t if c.isalpha()]
    if alpha and sum(c.isupper() for c in alpha) / len(alpha) > 0.7:
        s -= 2
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
            # VIDEO QUALITY OUTRANKS POPULARITY. Summing them let a well-
            # downloaded 2 Mbps re-upload beat a 4K copy (community 10.3 vs
            # 3.7 swamped a 5-point quality edge); the community signal is the
            # tiebreak between comparable videos, never the reason to serve a
            # worse one.
            winner = max(group, key=lambda i: (1 if i.get("subtitleHLS") else 0,
                                               _video_quality(i),
                                               _community_copy_score(i),
                                               _real_art_rank(i), i.get("imdbVotes") or 0))
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


def _insert_many(db, table, rows, mode="INSERT OR IGNORE"):
    """Insert with the placeholder count derived from the rows, not hardcoded —
    adding a column to `items` previously meant editing two unrelated `"?" * 29`
    literals, and missing one failed the whole build at insert time. No-ops on
    an empty batch (a shard with no series has no episode rows)."""
    if not rows:
        return
    n = len(rows[0])
    db.executemany(f"{mode} INTO {table} VALUES ({','.join('?' * n)})", rows)


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
      isAdult INTEGER,
      numFavorites INTEGER, numReviews INTEGER, avgRating REAL, views30d INTEGER,
      -- Playability, promoted OUT of the item_json blob so shelf/hero/browse
      -- queries can actually gate on it. Before this, downloadURL lived only in
      -- the JSON, so NO SQL query could filter on whether a title plays -- which
      -- is how dead items reached the home screen. 1 = the bytes were verified
      -- by check_liveness's ranged probe; 0 = has a URL but is unverified.
      playable INTEGER,
      -- "Hidden Gems": high craft, low traffic. COMPUTED here (like isAdult)
      -- rather than as a client predicate -- see _mark_hidden_gems for why.
      hiddenGem INTEGER
    );
    -- Full item as JSON in a side table so the lean `items` table stays small
    -- for scalar WHERE/ORDER scans; the app JOINs this only for the handful of
    -- rows a screen actually shows and decodes them with the existing Codable.
    -- Full item as JSON; the app JOINs + decodes only the rows a screen shows.
    CREATE TABLE item_json (archiveID TEXT PRIMARY KEY, json TEXT);
    CREATE TABLE item_genres (archiveID TEXT, genre TEXT);
    CREATE TABLE item_collections (archiveID TEXT, collection TEXT);
    -- Metadata-expansion facets (Decision 046): indexed for filtering, like item_genres.
    CREATE TABLE item_keywords (archiveID TEXT, keyword TEXT);
    CREATE TABLE item_studios (archiveID TEXT, studio TEXT);
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


def _playable_episode_aids():
    """archiveIDs of every playable episode across the series spines — the set the
    episode-item materialization (Decision 045) will own, so populate_items can skip
    their standalone duplicates and let the canonical EPISODE win (Decision 036)."""
    aids = set()
    for f in SERIES_DIR.glob("*.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        for season in d.get("seasons", []):
            for ep in season.get("episodes", []):
                if ep.get("downloadURL") and ep.get("archiveID"):
                    aids.add(ep["archiveID"])
    return aids


def populate_items(db, items, rotate_seed="0", skip_aids=frozenset()):
    item_rows, json_rows, genre_rows, coll_rows, shelf_rows, fts_rows = [], [], [], [], [], []
    gem_suppressed = set()      # archive.org asked us not to feature these
    kw_rows, studio_rows = [], []   # metadata-expansion facets (Decision 046)
    shelf_pos = _rotated_shelf_positions(items, rotate_seed)
    for it in items:
        # Rights audit (Decision 027): items flagged excluded=true stay in
        # catalog.json (reversible) but are never inserted, so they vanish from
        # every app surface. Mirrors the isAdult gate but harder — a full skip.
        if it.get("excluded") or _is_courseware(it) or _is_compilation(it):
            continue
        aid = it["archiveID"]
        # This archive item is a canonical episode — drop the standalone duplicate so
        # the episode-item (materialized in populate_series) is the single card for it
        # (Decision 045/036). A tv-series CARD is never an episode, so never skip it.
        if aid in skip_aids and it.get("contentType") != "tv-series":
            continue
        item_rows.append((
            aid, _t(it.get("title")), it.get("year"), it.get("decade"),
            it.get("runtimeSeconds"), _t(it.get("contentType")), _t(it.get("posterURL")),
            1 if (it.get("hasRealArtwork") or it.get("artworkSource") not in (None, "archive")) else 0,
            _t(it.get("artworkSource")), _t(it.get("imdbID")), it.get("imdbRating"),
            it.get("imdbVotes"), _pop_score(it), it.get("qualityScore"),
            1 if (it.get("isSilentFilm") or it.get("contentType") == "silent-film") else 0,
            _t(it.get("rightsStatus")), _t(it.get("contentRating")), _t(it.get("language")),
            _t(it.get("network")), _t(it.get("director")), _t(it.get("seriesID")),
            it.get("yearEnd"), it.get("seasonsCount"), it.get("episodesCount"),
            _is_adult(it),
            it.get("numFavorites"), it.get("numReviews"), it.get("avgRating"),
            it.get("views30d"),
            1 if it.get("playbackVerified") is True else 0,
            0,                      # hiddenGem — filled by _mark_hidden_gems below
        ))
        if _gem_suppressed(it):
            gem_suppressed.add(aid)
        json_rows.append((aid, json.dumps(it, ensure_ascii=False, separators=(",", ":"))))
        for g in (it.get("genres") or []):
            if g:
                genre_rows.append((aid, g))
        for c in (it.get("collections") or []):
            if c and str(c) in REGISTERED_COLLECTIONS:
                coll_rows.append((aid, str(c)))
        for kw in (it.get("keywords") or []):
            if kw:
                kw_rows.append((aid, str(kw)))
        for st in (it.get("studios") or []):
            if st:
                studio_rows.append((aid, str(st)))
        for s in _shelf_ids_for(it):
            shelf_rows.append((s, aid, shelf_pos.get((s, aid), 0)))
        # `names` = searchable people: director, cast, producer, + the metadata-expansion crew
        # (writer/composer/cinematographer) so searching a writer/composer finds their films.
        names = " ".join([it.get("director") or ""]
                         + [c.get("name", "") for c in (it.get("cast") or [])]
                         + [it.get("producer") or "", it.get("writer") or "",
                            it.get("composer") or "", it.get("cinematographer") or ""]).strip()
        # Topic/content words: genres, series/network, country, and a synopsis
        # snippet (truncated so the index doesn't balloon). Lets users find a
        # film by what it's ABOUT, not just its title or cast.
        syn = it.get("synopsis")
        syn = (" ".join(syn) if isinstance(syn, list) else (syn or ""))
        # `extra` also carries metadata-expansion search text: keywords (thematic), the original +
        # alternative titles (find foreign/re-titled films by their other names) — Decision 046.
        extra = " ".join([
            " ".join(it.get("genres") or []),
            it.get("seriesName") or "", it.get("network") or "",
            " ".join(it.get("countries") or []),
            " ".join(it.get("keywords") or []),
            it.get("originalTitle") or "", " ".join(it.get("akaTitles") or []),
            syn[:400],
        ]).strip()
        fts_rows.append((aid, it.get("title") or "", names, extra))

    # Column order must match the `items` tuple built above (and the CREATE TABLE).
    _ITEM_COLS = ["archiveID", "title", "year", "decade", "runtimeSeconds", "contentType",
                  "posterURL", "hasRealArtwork", "artworkSource", "imdbID", "imdbRating",
                  "imdbVotes", "popularityScore", "qualityScore", "isSilentFilm",
                  "rightsStatus", "contentRating", "language", "network", "director",
                  "seriesID", "yearEnd", "seasonsCount", "episodesCount", "isAdult",
                  "numFavorites", "numReviews", "avgRating", "views30d", "playable",
                  "hiddenGem"]
    col = {name: i for i, name in enumerate(_ITEM_COLS)}
    assert len(item_rows) == 0 or len(item_rows[0]) == len(_ITEM_COLS), \
        f"items tuple has {len(item_rows[0])} fields, _ITEM_COLS has {len(_ITEM_COLS)}"
    item_rows, gem_cut = _mark_hidden_gems(item_rows, col, gem_suppressed)

    _insert_many(db, "items", item_rows)
    # Published so the cut is inspectable after the fact — the June regression was
    # invisible partly because nothing recorded what the threshold had become.
    db.execute("INSERT OR REPLACE INTO meta VALUES ('hiddenGemPopCut', ?)", (str(gem_cut),))
    db.executemany("INSERT OR IGNORE INTO item_json VALUES (?,?)", json_rows)
    db.executemany("INSERT INTO item_genres VALUES (?,?)", genre_rows)
    db.executemany("INSERT INTO item_collections VALUES (?,?)", coll_rows)
    db.executemany("INSERT INTO item_keywords VALUES (?,?)", kw_rows)
    db.executemany("INSERT INTO item_studios VALUES (?,?)", studio_rows)
    db.executemany("INSERT INTO item_shelves VALUES (?,?,?)", shelf_rows)
    db.executemany("INSERT INTO items_fts VALUES (?,?,?,?)", fts_rows)
    return len(item_rows)


import re as _re_ep
# An episode's display title should be the EPISODE NAME only — season/episode live in
# their own fields. Strip a leading "Show ... SxxEyy " prefix (the colorized-classic-TV
# uploads carry the show name + "TV 1954 colorized s01e01" cruft in every episode title,
# Decision 045 materializes them verbatim). Guarded: never empty a title.
_EP_TITLE_PREFIX = _re_ep.compile(r"^.*?\bs\d{1,2}\s*e\d{1,3}\b[\s:.\-]*", _re_ep.I)
# A series card title like "Annie Oakley TV 1954 colorized" -> "Annie Oakley".
_SERIES_TV_CRUFT = _re_ep.compile(r"\s+TV\s+(?:19|20)\d{2}\s+colou?ri[sz]ed\b.*$", _re_ep.I)


def _has_letter(s):
    return bool(s and _re_ep.search(r"[^\W\d_]", s))


try:
    import remediate_catalog as _remediate   # reuse the film title-cleaning chain
except Exception:
    _remediate = None


def _clean_ep_title(t, year=None):
    if not t:
        return t
    nt = _EP_TITLE_PREFIX.sub("", t).strip(" :.-")
    nt = nt if _has_letter(nt) else t
    # Episodes bypass remediate (materialized from spines), so run the SAME title
    # chain films get — strips trailing "(1989) [1080p]", version/quality/year cruft.
    if _remediate is not None:
        it = {"title": nt, "year": year}
        try:
            _remediate.sanitize_title(it)
            if _has_letter(it.get("title")):
                nt = it["title"]
        except Exception:
            pass
    return nt


def _clean_series_title(t):
    if not t:
        return t
    nt = _SERIES_TV_CRUFT.sub("", t).strip()
    return nt if _has_letter(nt) else t


def _episode_item(ep, sid, series_title, series_poster, series_backdrop):
    """A playable episode as a first-class catalog item (contentType 'tv-episode',
    Decision 045). Episodes become real items so favorite / playlist / share / Clip
    Studio / Detail / search all work through the SAME machinery as films — no
    episode-specific interactions. seriesID + season/episode + seriesTitle carry the
    linkage; the item is excluded from film browse surfaces but fully actionable."""
    aid = ep.get("archiveID")
    year = ep.get("year")
    title = _clean_ep_title(ep.get("title"), year) or aid
    still = ep.get("stillURL")
    poster = still or series_poster
    return {
        "archiveID": aid,
        "title": title,
        "year": year,
        "decade": (year // 10 * 10) if year else None,
        "runtimeSeconds": ep.get("runtimeSeconds"),
        "contentType": "tv-episode",
        "posterURL": poster,
        "backdropURL": series_backdrop,
        "hasRealArtwork": bool(poster),
        "artworkSource": "external" if still else ("series" if series_poster else None),
        "downloadURL": ep.get("downloadURL"),
        "synopsis": ep.get("overview"),
        "rightsStatus": "public_domain",   # the visible catalog is PD/CC-only (Decision 027)
        "seriesID": sid,
        "seriesTitle": series_title,
        "seasonNumber": ep.get("seasonNumber"),
        "episodeNumber": ep.get("episodeNumber"),
        "stillURL": still,
    }


def populate_series(db, materialize_episode_items=True):
    """Build the series + episodes tables. When materialize_episode_items (the full
    DB, not the lean seed), ALSO insert each playable episode as a 'tv-episode'
    catalog item so episodes are first-class everywhere (Decision 045)."""
    s_rows, e_rows = [], []
    ep_item_rows, ep_json_rows, ep_fts_rows = [], [], []
    seen_ep_aids = set()
    for f in sorted(SERIES_DIR.glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        sid = d.get("seriesID") or f.stem
        series_title = _clean_series_title(d.get("title"))
        series_poster = d.get("posterURL")
        series_backdrop = d.get("backdropURL")
        s_rows.append((
            sid, series_title, d.get("yearStart"), d.get("yearEnd"),
            d.get("overview"), series_poster, series_backdrop,
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
                aid = ep.get("archiveID")
                # Materialize ONLY playable episodes with a real id, once per id.
                if not (materialize_episode_items and ep.get("downloadURL") and aid
                        and aid not in seen_ep_aids):
                    continue
                seen_ep_aids.add(aid)
                it = _episode_item(ep, sid, series_title, series_poster, series_backdrop)
                ep_item_rows.append((
                    aid, _t(it["title"]), it["year"], it["decade"],
                    it["runtimeSeconds"], "tv-episode", _t(it["posterURL"]),
                    1 if it["hasRealArtwork"] else 0, _t(it["artworkSource"]), None, None,
                    None, 0, None,
                    0, "public_domain", None, None,
                    None, None, sid,
                    None, None, None,
                    0,
                    None, None, None, None,
                    # Episodes aren't byte-probed (check_liveness walks catalog
                    # items, not series spines); their URL comes from the spine.
                    0,
                    0,      # hiddenGem — a gem is a film claim; episodes never qualify
                ))
                ep_json_rows.append((aid, json.dumps(it, ensure_ascii=False, separators=(",", ":"))))
                # extra = series name + a synopsis snippet, so the series name finds the episode.
                extra = " ".join([series_title or "", (it["synopsis"] or "")[:200]]).strip()
                ep_fts_rows.append((aid, it["title"] or "", "", extra))
    db.executemany("INSERT OR IGNORE INTO series VALUES (%s)" % ",".join("?" * 13), s_rows)
    db.executemany("INSERT INTO episodes VALUES (%s)" % ",".join("?" * 12), e_rows)
    # OR IGNORE: a standalone item with the same id (rare post-Decision-035) keeps its row.
    _insert_many(db, "items", ep_item_rows)
    db.executemany("INSERT OR IGNORE INTO item_json VALUES (?,?)", ep_json_rows)
    db.executemany("INSERT INTO items_fts VALUES (?,?,?,?)", ep_fts_rows)
    if ep_item_rows:
        print(f"[sqlite]   materialized {len(ep_item_rows):,} tv-episode items", flush=True)
    return len(s_rows), len(e_rows)


def create_indexes(db):
    db.executescript("""
    CREATE INDEX idx_items_type     ON items(contentType);
    CREATE INDEX idx_items_decade   ON items(decade);
    CREATE INDEX idx_items_pop      ON items(popularityScore DESC);
    -- Composite: every shelf query orders by popularity and will gate on
    -- playable once coverage clears the bar (D3).
    CREATE INDEX idx_items_playable ON items(playable, popularityScore DESC);
    CREATE INDEX idx_items_series   ON items(seriesID);
    CREATE INDEX idx_genres_genre   ON item_genres(genre);
    CREATE INDEX idx_genres_item    ON item_genres(archiveID);
    CREATE INDEX idx_coll_coll      ON item_collections(collection);
    -- Only the value→items direction is indexed (that's the filter); item→keywords comes from the
    -- item_json blob, so the archiveID-direction index is omitted to save ~2 MB (Decision 046 budget).
    CREATE INDEX idx_kw_keyword     ON item_keywords(keyword);
    CREATE INDEX idx_studio_studio  ON item_studios(studio);
    CREATE INDEX idx_items_director ON items(director);
    CREATE INDEX idx_items_quality  ON items(qualityScore);
    CREATE INDEX idx_items_gem      ON items(hiddenGem, imdbRating DESC);
    CREATE INDEX idx_items_reviews  ON items(numReviews DESC);
    CREATE INDEX idx_items_favs     ON items(numFavorites DESC);
    CREATE INDEX idx_items_views30d ON items(views30d DESC);
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


def build_db_obj(cat, out_db, rotate_seed="0", materialize_episodes=True):
    """Compile an in-memory catalog dict into a SQLite DB at out_db. Returns
    (cat, n_items, n_series, n_eps). materialize_episodes=False for the lean
    bundled seed (episodes-as-items live only in the full DB — Decision 045)."""
    deduped = dedupe_by_imdb(cat["items"])
    deduped = merge_film_duplicates(deduped)
    if out_db.exists():
        out_db.unlink()
    db = sqlite3.connect(out_db)
    create_schema(db)
    episode_aids = _playable_episode_aids() if materialize_episodes else frozenset()
    n_items = populate_items(db, deduped, rotate_seed=rotate_seed, skip_aids=episode_aids)
    n_series, n_eps = populate_series(db, materialize_episode_items=materialize_episodes)
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
    return build_db_obj(seed, out_db, rotate_seed=rotate_seed, materialize_episodes=False)


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
