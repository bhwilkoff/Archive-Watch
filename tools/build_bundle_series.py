#!/usr/bin/env python3
"""
build_bundle_series.py — an archive.org item that holds a whole series or
serial becomes a series spine, so it works like every other show.

The TV spines (Decisions 016/045) assume one episode is one archive.org ITEM.
Some uploaders put a whole show in one item instead: `UFO.complete` holds
`UFO.01.Identified.mp4` ... `UFO.26.The Long Sleep.mp4`, Spy Smasher's twelve
chapters are `...-episode1-...` to `...-episode12-...`. Until now those items
were a single card whose "versions" were its episodes, sorted by file size,
playing whichever file was largest (2026-10-15 App Store review).

This tool finds those items and writes `series/<slug>.json` for each, in the
spine format the apps already read, with two additions:
  * the spine and every episode carry `sourceID` (the bundle's archive.org id);
  * an episode's `archiveID` is `<sourceID>@<token>` (`UFO.complete@e01`,
    `X@s2e05`). archive.org identifiers never contain `@`, so the item is
    always the part before the first `@`, and every user-state key, queue and
    list on every platform stays distinct per episode (Decision 166).
The token comes from the episode's own NUMBER, never its position, so an
uploader adding a file does not move anybody's progress.

Every number and title comes from the uploader's file names or file metadata:
nothing is written here (CLAUDE.md, "no AI-written lists or copy").

An item qualifies only when its works (one per original file) carry an
episode/chapter number that the names state: SxxEyy, NxNN, "episode N",
"chapter N", or a bare number after the name every file shares
("UFO.07.Kill Straker"). "part" and "reel" are deliberately NOT episodes —
those are pieces of one film. An item that other catalog cards also point
into (a studio's shorts, each its own card) is a compilation, not a series.

Usage:
  python tools/build_bundle_series.py --scan       # refresh sizes + metadata cache
  python tools/build_bundle_series.py --apply      # write/remove bundle spines
  python tools/build_bundle_series.py --report     # what qualifies and why not
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

import requests

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from archive_lib import ARCHIVE_META, UA, download_url, pick_video, runtime_from_file  # noqa: E402

SERIES_DIR = REPO / "series"
CATALOG = REPO / "catalog.json"
CACHE = REPO / "shared" / "editorial" / "bundle_scan.json"
SCRAPE = "https://archive.org/services/search/v1/scrape"

SEP = "@"
MIN_WORKS = 3            # fewer numbered works than this is not a series
MIN_NUMBERED = 0.75      # share of works that must carry a number
MIN_BYTES = 5_000_000    # the clients' own floor for a playable file
RECHECK_DAYS = 60
SIZE_RATIO = 3.0         # item size / default file size that makes a candidate
MIN_FILES = 45           # a three-episode item already lists ~60 (each video has thumbs)

VIDEO_EXT = (".mp4", ".m4v", ".mov", ".mkv", ".avi", ".mpg", ".mpeg", ".ogv", ".webm", ".wmv", ".flv")


def item_of(aid: str) -> str:
    """The archive.org item an id lives in: `UFO.complete@e01` -> `UFO.complete`."""
    return (aid or "").split(SEP, 1)[0]


# ── parsing ────────────────────────────────────────────────────────────────

_SXE = re.compile(r"(?<![a-z0-9])s(\d{1,2})[ ._-]*e(\d{1,3})(?![0-9])", re.I)
_NXN = re.compile(r"(?<![0-9])(\d{1,2})x(\d{2,3})(?![0-9])", re.I)
_WORD = re.compile(r"(episode|ep|chapter|chap|ch|(?<![a-z0-9])e)[ ._#-]*(\d{1,3})(?![0-9])", re.I)
_SEASON_DIR = re.compile(r"(?:season|series|s)[ ._-]*(\d{1,2})$", re.I)
_LEAD_NUM = re.compile(r"^[ ._#-]*(\d{1,3})(?![0-9])")
# what a shared name ends in when its numbers count pieces of ONE film or tape
_PIECE = re.compile(r"(?:reel|part|pt|disc|disk|cd|dvd|tape|side|vol|volume|r)[ ._#-]*$", re.I)
# a bare name that counts pieces of one film: "nosferatu-2of5", "reel1", a DVD's VTS_01_3
_PIECE_NAME = re.compile(r"(?<![0-9])\d{1,2}\s*of\s*\d{1,2}(?![0-9])|reel[ ._#-]*\d|^vts_\d+_\d+$", re.I)
# "Part 3" is a film's piece unless the item is typed television (an eight-part drama)
_PART_NAME = re.compile(r"(?:part|pt)[ ._#-]*\d", re.I)
MIN_RUN = 10             # a numbered run this long is a series however it is named
_NAMED = (_SXE, _NXN, _WORD)
# what an item's own metadata says when it is a show or a serial
_SERIES_WORDS = re.compile(r"\b(?:serials?|series|episodes?|chapters|seasons?|cliffhangers?|miniseries)\b", re.I)


def _stem(name: str) -> str:
    base = name.rsplit("/", 1)[-1]
    return re.sub(r"(\.ia)?\.[A-Za-z0-9]{2,4}$", "", base)


def _season_from_dir(name: str) -> int | None:
    if "/" not in name:
        return None
    m = _SEASON_DIR.search(name.rsplit("/", 1)[0].rsplit("/", 1)[-1].strip())
    return int(m.group(1)) if m else None


def _common_prefix(xs: list[str]) -> str:
    if not xs:
        return ""
    lo, hi = min(xs), max(xs)
    i = 0
    while i < len(lo) and i < len(hi) and lo[i] == hi[i]:
        i += 1
    p = lo[:i]
    # back off to a separator so "UFO.0" (all files 01-09) keeps the digit
    while p and p[-1].isdigit():
        p = p[:-1]
    return p


def _common_suffix(xs: list[str]) -> str:
    return _common_prefix([x[::-1] for x in xs])[::-1] if xs else ""


def _clean_words(s: str) -> str:
    s = re.sub(r"[_]+|\.(?=\S)", " ", s)
    s = re.sub(r"\s+", " ", s).strip(" .-_–:#")
    return s


def number_of(stem: str, prefix: str) -> tuple[int | None, int | None, str]:
    """(season, episode, word) a file's own name states, or (None, None, '')."""
    m = _SXE.search(stem)
    if m:
        return int(m.group(1)), int(m.group(2)), "Episode"
    m = _NXN.search(stem)
    if m:
        return int(m.group(1)), int(m.group(2)), "Episode"
    m = _WORD.search(stem)
    if m:
        w = m.group(1).lower()
        return None, int(m.group(2)), ("Chapter" if w.startswith("ch") else "Episode")
    rest = stem[len(prefix):] if prefix and stem.startswith(prefix) else None
    piece = _PIECE.search(prefix) if rest is not None else None
    if rest is not None and (not piece or _PART_NAME.match(piece.group(0) + "1")):
        m = _LEAD_NUM.match(rest)
        if m:
            # "Insurrection Part 3" counts, but only typed television may use it
            return None, int(m.group(1)), "Part" if piece else "Episode"
    return None, None, ""


def works_of(files: list[dict]) -> dict[str, list[dict]]:
    """Group video files by the work they are: a derivative belongs to its
    original, so `UFO.01.Identified.avi/.mp4/.ogv` is one work."""
    by_name = {f.get("name"): f for f in files}
    groups: dict[str, list[dict]] = {}
    for f in files:
        name = f.get("name") or ""
        if not name.lower().endswith(VIDEO_EXT) or re.search(r"(^|/)history/|\.~\d+~$", name):
            continue
        root = name
        seen = 0
        while by_name.get(root, {}).get("original") and seen < 4:
            root = by_name[root]["original"]
            seen += 1
        groups.setdefault(root, []).append(f)
    return groups


def parse_bundle(files: list[dict]) -> tuple[list[dict] | None, str]:
    """The item's episodes, or (None, why it is not a series)."""
    groups = works_of(files)
    picked = {}
    for root, fs in groups.items():
        f = pick_video(fs)
        # an episode plays everywhere a film does: an MP4 (no Ogg, no Matroska,
        # which Apple's player cannot open), as every visible film card has
        if f and int(f.get("size") or 0) >= MIN_BYTES and (f.get("name") or "").lower().endswith((".mp4", ".m4v")):
            picked[root] = f
    if len(picked) < MIN_WORKS:
        return None, f"{len(picked)} playable works"
    stems = {root: _stem(root) for root in picked}
    prefix = _common_prefix(list(stems.values()))
    suffix = _common_suffix(list(stems.values()))
    eps, extras = [], []
    for root, f in picked.items():
        st = stems[root]
        s_dir = _season_from_dir(root)
        s, e, word = number_of(st, prefix)
        if s is None:
            s = s_dir
        # The file's own title when archive.org holds one, else what is left of
        # the name once the shared series name, the number and the shared tail
        # are gone ("UFO.07.Kill Straker" -> "Kill Straker").
        t = _own_title(by_title(files, root) or "")
        if not t or _stem(t) == st:
            core = st[len(prefix):] if prefix and st.startswith(prefix) else st
            if suffix and core.endswith(suffix) and len(core) > len(suffix):
                core = core[: -len(suffix)]
            core = _SXE.sub(" ", core)
            core = _NXN.sub(" ", core)
            core = _WORD.sub(" ", core)
            core = re.sub(r"^[ ._#-]*\d{1,3}(?![0-9])", " ", core) if e is not None else core
            # a shared prefix of "S" leaves "01E01 - Beaver Gets Spelled" behind
            core = _LEFT_MARK.sub(" ", core) if e is not None else core
            t = _clean_words(html.unescape(core))
        named = any(rx.search(st) for rx in _NAMED)
        if not named and _PIECE_NAME.search(st):
            return None, f"pieces of one film ({st})"
        row = {"root": root, "file": f, "season": s, "episode": e, "word": word, "title": t or None,
               "named": named, "part": not named and (word == "Part" or bool(_PART_NAME.search(st)))}
        (eps if e is not None else extras).append(row)
    works = len(eps) + len(extras)
    if len(eps) < MIN_WORKS:
        return None, f"{len(eps)} numbered of {works}"
    if len(eps) / works < MIN_NUMBERED:
        return None, f"only {len(eps)} of {works} works numbered"
    seasons = {r["season"] for r in eps}
    if None in seasons and len(seasons) > 1:
        # some files say a season and some do not: numbers would collide
        return None, "mixed season numbering"
    keys = [(r["season"], r["episode"]) for r in eps]
    if len(set(keys)) != len(keys):
        return None, "two works share a number"
    for s in seasons:
        nums = sorted(r["episode"] for r in eps if r["season"] == s)
        # a run, not a scatter of years or resolutions read as numbers
        if nums[-1] > 2 * len(nums) + 3:
            return None, f"numbers do not form a run ({nums[0]}..{nums[-1]} over {len(nums)})"
    return sorted(eps, key=lambda r: (r["season"] or 0, r["episode"])) + \
        sorted(extras, key=lambda r: r["root"].lower()), "ok"


# "E02 - Beaver's House Guest", "1. The Fugitive", "Chapter 1--Cornered": the number
# is already the episode's; the title is what follows it
_TITLE_NUM = re.compile(r"^\s*(?:(?:s\d{1,2}\s*)?(?:episode|ep|chapter|e)?\s*\d{1,3})\s*[-–.:)]+\s*(?=\S)", re.I)


_LEFT_MARK = re.compile(r"^[ ._#-]*(?:\d{1,3}\s*)?(?:s\d{1,2}\s*)?e\d{1,3}(?![0-9])[ ._\-–:)]*", re.I)


def _own_title(t: str) -> str:
    t = html.unescape(t).strip()
    return _TITLE_NUM.sub("", t).strip()


def by_title(files: list[dict], root: str) -> str | None:
    for f in files:
        if f.get("name") == root:
            return f.get("title")
    return None


def token_of(row: dict) -> str:
    if row["episode"] is None:
        slug = re.sub(r"[^a-z0-9]+", "-", _stem(row["root"]).lower()).strip("-")[:32].strip("-")
        return f"x-{slug or 'extra'}"
    if row["season"] is not None:
        return f"s{row['season']}e{row['episode']:02d}"
    return f"e{row['episode']:02d}"


# ── spine ──────────────────────────────────────────────────────────────────

_TITLE_CUT = re.compile(
    r"\s*(?:[-–:|]\s*)?(?:the\s+)?(?:complete|full)\s+(?:tv\s+)?(?:series|serial|season|show|collection)\b.*$"
    r"|\s*[:-]\s*\d+\s+(?:episodes|chapters)\b.*$"
    r"|\s*[,:-]?\s*(?:chapters?|episodes?)\s*\d+\s*(?:-|–|thru|through|to)\s*\d+.*$"
    r"|\s*\((?:complete|tv|\d{4}|restored|colori[sz]ed)[^)]*\).*$",
    re.I)


def series_title(title: str) -> str:
    t = _TITLE_CUT.sub("", title or "").strip(" .-–:|")
    t = re.sub(r"\s+", " ", t)
    return t or (title or "").strip()


def _still(files: list[dict], item: str, root: str) -> str | None:
    """A frame of THIS episode from archive.org's own thumbnails, so every row
    does not wear the same picture."""
    name = _still_name(files, item, root)
    return download_url(item, name) if name else None


def _still_name(files: list[dict], item: str, root: str) -> str | None:
    st = _stem(root)
    frames = sorted(f["name"] for f in files
                    if (f.get("name") or "").startswith(f"{item}.thumbs/{st}_")
                    and f["name"].lower().endswith(".jpg"))
    if not frames:
        return None
    return frames[min(len(frames) - 1, len(frames) // 3)]


def keep_for_spine(files: list[dict], item: str, rows: list[dict]) -> list[dict]:
    """Only what the spine reads: each episode's files and the one frame `_still`
    picks (an item lists dozens of thumbnails per video)."""
    keep = {r["root"] for r in rows} | {r["file"]["name"] for r in rows}
    out = [{k: f.get(k) for k in ("name", "format", "size", "length", "original", "title", "source")
            if f.get(k) is not None}
           for f in files if f.get("name") in keep]
    for r in rows:
        name = _still_name(files, item, r["root"])
        if name:
            out.append({"name": name})
    return out


def build_spine(it: dict, rows: list[dict], files: list[dict]) -> dict:
    src = it["archiveID"]
    title = series_title(it.get("title"))
    year = it.get("year")
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    slug = f"{slug}-{year}" if year else slug
    seasons: dict = {}
    for r in rows:
        f = r["file"]
        n = r["episode"]
        s = (r["season"] if r["season"] is not None else 1) if n is not None else None
        label = r["title"] or (f"{r['word'] or 'Episode'} {n}" if n is not None else _clean_words(_stem(r["root"])))
        seasons.setdefault(s, []).append({
            "archiveID": f"{src}{SEP}{token_of(r)}",
            "sourceID": src,
            "seasonNumber": s,
            "episodeNumber": n,
            "title": label,
            "overview": None,
            "stillURL": _still(files, src, r["root"]),
            "airDate": None,
            "year": year,
            "runtimeSeconds": runtime_from_file(f),
            "videoFile": {"name": f["name"], "format": f.get("format"),
                          "sizeBytes": int(f.get("size") or 0), "tier": 1},
            "downloadURL": download_url(src, f["name"]),
        })
    ordered = sorted(seasons.items(), key=lambda kv: (kv[0] is None, kv[0] or 0))
    n_eps = sum(len(v) for _, v in ordered)
    return {
        "version": 2,
        "seriesID": slug,
        "sourceID": src,
        "tvmazeID": it.get("tvmazeID"),
        "title": title,
        "yearStart": year,
        "yearEnd": None,
        "overview": it.get("synopsis"),
        "posterURL": it.get("posterURL"),
        "backdropURL": it.get("backdropURL"),
        "genres": it.get("genres") or [],
        "networks": [it["network"]] if it.get("network") else [],
        "creator": it.get("director"),
        "seasons": [{"seasonNumber": s, "episodes": eps} for s, eps in ordered],
        "episodesCount": n_eps,
        "canonicalEpisodesCount": None,
        "tvdbID": None,
        "artworkSource": it.get("artworkSource"),
        "cast": [{"name": c.get("name"), "character": c.get("character"),
                  "order": i, "profilePath": c.get("profilePath")}
                 for i, c in enumerate(it.get("cast") or []) if isinstance(c, dict) and c.get("name")],
    }


# ── catalog + cache ────────────────────────────────────────────────────────

def load_cache() -> dict:
    return json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}


def save_cache(c: dict) -> None:
    CACHE.write_text(json.dumps(c, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")


def spine_episode_aids(skip_bundles=True) -> set[str]:
    """Every item a TVmaze spine serves, by its ITEM: an episode expanded out of
    a whole-series item (`X@e08`) still names `X` as the item it lives in."""
    out = set()
    for f in SERIES_DIR.glob("*.json"):
        d = json.loads(f.read_text(encoding="utf-8"))
        if skip_bundles and d.get("sourceID"):
            continue
        for s in d.get("seasons", []):
            for e in s.get("episodes", []):
                if e.get("archiveID"):
                    out.add(e.get("sourceID") or item_of(e["archiveID"]))
    return out


def spine_items() -> list[dict]:
    """The items TVmaze spines serve, shaped like catalog items for the scan:
    a whole series filed in one item and matched onto a TVmaze show was served
    as ONE episode of it ("Fireball XL5.", playing one file of 39), because the
    scan only looked at catalog cards. Its size is the episode's file."""
    out = {}
    for f in SERIES_DIR.glob("*.json"):
        d = json.loads(f.read_text(encoding="utf-8"))
        if d.get("sourceID"):
            continue
        for s in d.get("seasons", []):
            for e in s.get("episodes", []):
                aid = e.get("sourceID") or item_of(e.get("archiveID") or "")
                if aid and aid not in out:
                    out[aid] = {"archiveID": aid, "title": e.get("title"), "contentType": "tv-episode",
                                "videoFile": e.get("videoFile"), "spine": d.get("seriesID") or f.stem}
    return list(out.values())


def candidates(items: list[dict]) -> tuple[list[dict], set[str]]:
    """Visible, standalone items, and the items other cards point INTO."""
    shared = {}
    for it in items:
        if it.get("excluded"):
            continue
        m = re.search(r"/download/([^/]+)/", it.get("downloadURL") or "")
        if m:
            shared.setdefault(urllib.parse.unquote(m.group(1)), set()).add(it["archiveID"])
    compilations = {k for k, v in shared.items() if len(v - {k}) > 0}
    in_spines = spine_episode_aids()
    pool = [it for it in items
            if not it.get("excluded") and it.get("archiveID")
            and not it["archiveID"].startswith("series:")
            and it.get("contentType") not in ("tv-episode", "tv-series")
            and it["archiveID"] not in in_spines]
    return pool, compilations


def scrape_sizes(ids: list[str], session) -> dict[str, tuple]:
    out = {}
    for k in range(0, len(ids), 80):
        chunk = ids[k:k + 80]
        q = "identifier:(" + " OR ".join('"%s"' % c.replace('"', "") for c in chunk) + ")"
        for attempt in range(3):
            try:
                r = session.get(SCRAPE, params={"q": q, "fields": "identifier,item_size,files_count",
                                                "count": 1000}, headers={"User-Agent": UA}, timeout=60)
                r.raise_for_status()
                for d in r.json().get("items", []):
                    out[d["identifier"]] = (d.get("item_size"), d.get("files_count"))
                break
            except Exception:  # noqa: BLE001
                time.sleep(3 * (attempt + 1))
    return out


def scan(items, cache, session, throttle=0.2, limit=None, save=None):
    pool, compilations = candidates(items)
    in_pool = {it["archiveID"] for it in pool}
    pool += [it for it in spine_items() if it["archiveID"] not in in_pool]
    sizes = scrape_sizes([it["archiveID"] for it in pool], session)
    now = datetime.now(timezone.utc)
    fetched = 0
    for it in pool:
        aid = it["archiveID"]
        isize, nfiles = sizes.get(aid, (None, None))
        vsize = int((it.get("videoFile") or {}).get("sizeBytes") or 0)
        prev = cache.get(aid) or {}
        if not isize or not vsize or isize < SIZE_RATIO * vsize or (nfiles or 0) < MIN_FILES:
            if prev:
                cache.pop(aid, None)
            continue
        if aid in compilations and not it.get("spine"):
            cache[aid] = {"isize": isize, "verdict": "compilation", "checkedAt": now.date().isoformat()}
            continue
        fresh = prev.get("isize") == isize and prev.get("checkedAt") and \
            (now - datetime.fromisoformat(prev["checkedAt"]).replace(tzinfo=timezone.utc)).days < RECHECK_DAYS
        if fresh:
            continue
        if limit is not None and fetched >= limit:
            break
        try:
            r = session.get(ARCHIVE_META + aid, headers={"User-Agent": UA}, timeout=40)
            r.raise_for_status()
            files = r.json().get("files") or []
        except Exception as e:  # noqa: BLE001
            print(f"  ! {aid}: {e}")
            continue
        fetched += 1
        rows, why = parse_bundle(files)
        entry = {"isize": isize, "checkedAt": now.date().isoformat(),
                 "verdict": "bundle" if rows else "single", "reason": why}
        if rows:
            # keep only what the spine needs, so the build needs no network
            entry["files"] = keep_for_spine(files, aid, rows)
        cache[aid] = entry
        if save and fetched % 200 == 0:
            save(cache)   # a step killed at its timeout keeps what it fetched
        time.sleep(throttle)
    return fetched


def series_evidence(it: dict, rows: list[dict]) -> str | None:
    """Why an item that parses as numbered files is a show or a serial, or None.
    Numbered files alone are also lectures, audiobooks, launch coverage and
    commercial breaks; the episode words in the names, or the item's own
    metadata, are what say television."""
    cols = [str(c) for c in it.get("collections") or []]
    # a series card is put in front of viewers, so nothing that may not be recommended
    # (Decisions 149/156) and nothing archive.org itself de-emphasizes
    if it.get("contentType") in ("commercial", "ephemeral") or it.get("mediatype") == "audio" \
            or it.get("noRecommend") or "deemphasize" in cols or any(c.startswith("audio_") for c in cols):
        return None
    eps = [r for r in rows if r["episode"] is not None]
    typed_tv = it.get("contentType") == "tv-special" or it.get("network") or it.get("tvmazeID") \
        or it.get("seriesName")
    if any(r.get("part") for r in rows) and not typed_tv:
        return None
    if sum(1 for r in eps if r.get("named")) * 2 >= len(eps):
        return "episode names"
    if typed_tv:
        return "typed television"
    titles = {(r["title"] or "").lower() for r in eps if re.search(r"[a-z]{3}", r["title"] or "", re.I)}
    if len(eps) >= 4 and len(titles) >= 0.75 * len(eps):
        return "episode titles"
    if len(eps) >= MIN_RUN:
        return "a long run"
    text = " ".join([it.get("title") or "", it.get("synopsis") or ""] + [str(x) for x in it.get("subjects") or []])
    return "metadata" if _SERIES_WORDS.search(text) else None


# ── a whole series inside a TVmaze spine ───────────────────────────────────

# "Room-222-Season-2", "thesmithfamilyseasontwo": the season an item holds when
# its files carry only an episode number
_ITEM_SEASON = re.compile(r"(?:season|series)[ ._-]*(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)(?![0-9a-z])", re.I)
_WORDS = {w: i for i, w in enumerate("one two three four five six seven eight nine ten".split(), 1)}
_COLORIZED = re.compile(r"colori[sz]ed|colou?ri[sz]ed|in[ ._-]colou?r", re.I)
MIN_EPISODE_SECONDS = 240  # a promo or a title card filed beside the episodes is not one


def item_season(aid: str, title: str | None = None) -> int | None:
    for text in (aid, title or ""):
        m = _ITEM_SEASON.search(text or "")
        if m:
            v = m.group(1).lower()
            return int(v) if v.isdigit() else _WORDS[v]
    return None


def is_colorized(aid: str, title: str | None = None) -> bool:
    return bool(_COLORIZED.search(f"{aid} {title or ''}"))


def tv_episodes(aid: str, entry: dict) -> list[dict] | None:
    """A whole-series item's files as episode rows for the TVmaze spine it was
    matched onto (Decision 167). Each row is a playable episode with the
    Decision 166 id `<item>@<token>`; `bundleTitle` is the uploader's own
    episode title (None when the file only states a number), which the spine
    builder matches against the canonical episode names before any number,
    because an uploader's numbering is often production order."""
    if (entry or {}).get("verdict") != "bundle" or not entry.get("files"):
        return None
    files = entry["files"]
    rows, _ = parse_bundle([f for f in files if not (f.get("name") or "").startswith(f"{aid}.thumbs/")])
    if not rows:
        return None
    hint = item_season(aid)
    # an episode's title is its own: words every file shares ("colorized",
    # "720p Bluray x264") are the upload's tags, so those files go by number
    seen = {}
    for r in rows:
        k = (r["title"] or "").strip().lower()
        seen[k] = seen.get(k, 0) + 1
    out = []
    for r in rows:
        f = r["file"]
        secs = runtime_from_file(f)
        if secs and secs < MIN_EPISODE_SECONDS:
            continue
        n = r["episode"]
        # "1875" and "XL5 to H2O" are titles; "07" or "Episode 7" is only a number
        title = r["title"] if r["title"] and not re.fullmatch(
            r"\W*(?:(?:episode|ep|chapter|chap|part|pt)\W*)?\d{1,3}\W*", r["title"], re.I) \
            and seen[r["title"].strip().lower()] == 1 else None
        out.append({
            "archiveID": f"{aid}{SEP}{token_of(r)}",
            "sourceID": aid,
            "seasonNumber": (r["season"] if r["season"] is not None else hint) if n is not None else None,
            "episodeNumber": n,
            "title": title or (f"{r['word'] or 'Episode'} {n}" if n is not None else _clean_words(_stem(r["root"]))),
            "bundleTitle": title,
            "stillURL": _still(files, aid, r["root"]),
            "year": None,
            "runtimeSeconds": secs,
            "videoFile": {"name": f["name"], "format": f.get("format"),
                          "sizeBytes": int(f.get("size") or 0), "tier": 1},
            "downloadURL": download_url(aid, f["name"]),
        })
    return out or None


def merge_uploads(spines: list[dict]) -> dict:
    """One show from the uploads that share its slug, fullest first. A serial
    uploaded in halves (chapters 1-5, then 6-12) has no number in common and
    becomes one show; a second copy of the same episodes adds nothing and its
    item stays a card of its own."""
    out = spines[0]
    tokens = {e["archiveID"].split(SEP, 1)[1] for s in out["seasons"] for e in s["episodes"]}
    sources = [out["sourceID"]]
    for sp in spines[1:]:
        theirs = {e["archiveID"].split(SEP, 1)[1] for s in sp["seasons"] for e in s["episodes"]}
        if theirs & tokens:
            continue
        tokens |= theirs
        sources.append(sp["sourceID"])
        by_season = {s["seasonNumber"]: s for s in out["seasons"]}
        for s in sp["seasons"]:
            if s["seasonNumber"] in by_season:
                by_season[s["seasonNumber"]]["episodes"].extend(s["episodes"])
            else:
                out["seasons"].append(s)
    if len(sources) > 1:
        for s in out["seasons"]:
            s["episodes"].sort(key=lambda e: (e["episodeNumber"] is None, e["episodeNumber"] or 0, e["archiveID"]))
        out["seasons"].sort(key=lambda s: (s["seasonNumber"] is None, s["seasonNumber"] or 0))
        out["episodesCount"] = sum(len(s["episodes"]) for s in out["seasons"])
        out["sourceIDs"] = sources
    return out


def apply(items, cache, dry_run=False):
    by_id = {it["archiveID"]: it for it in items}
    pool, compilations = candidates(items)
    eligible = {it["archiveID"] for it in pool} - compilations
    existing = {}
    for f in SERIES_DIR.glob("*.json"):
        d = json.loads(f.read_text(encoding="utf-8"))
        if d.get("sourceID"):
            for src in d.get("sourceIDs") or [d["sourceID"]]:
                existing[src] = f
    taken = {f.stem for f in SERIES_DIR.glob("*.json")} - {f.stem for f in existing.values()}
    wrote, removed = [], []
    best = {}
    for aid, e in sorted(cache.items()):
        if e.get("verdict") != "bundle" or aid not in eligible:
            continue
        files = e.get("files") or []
        rows, why = parse_bundle([f for f in files if not (f.get("name") or "").startswith(f"{aid}.thumbs/")])
        if not rows or not series_evidence(by_id[aid], rows):
            continue
        spine = build_spine(by_id[aid], rows, files)
        if spine["seriesID"] in taken:
            # a TVmaze spine of the same show owns the slug; never overwrite it
            spine["seriesID"] = f"{spine['seriesID']}-{re.sub(r'[^a-z0-9]+', '-', aid.lower()).strip('-')}"
        best.setdefault(spine["seriesID"], []).append(((spine["episodesCount"], e.get("isize") or 0, aid), spine))
    for slug, group in sorted(best.items()):
        group.sort(key=lambda g: g[0], reverse=True)
        spine = merge_uploads([sp for _, sp in group])
        aid = spine["sourceID"]
        path = SERIES_DIR / f"{spine['seriesID']}.json"
        if not dry_run:
            path.write_text(json.dumps(spine, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        wrote.append((aid, spine["seriesID"], spine["episodesCount"]))
    # A source that is hidden, gone or no longer a series takes its spine with it
    # (and a spine renamed or folded into another show leaves its old file).
    written = {SERIES_DIR / f"{slug}.json" for _, slug, _ in wrote}
    for aid, f in sorted(existing.items()):
        if f in written:
            continue
        removed.append((aid, f.stem))
        if not dry_run and f.exists():
            f.unlink()
    return wrote, removed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scan", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--throttle", type=float, default=0.2)
    ap.add_argument("--catalog", type=Path, default=CATALOG)
    args = ap.parse_args()
    items = json.loads(args.catalog.read_text(encoding="utf-8"))["items"]
    cache = load_cache()
    if args.scan:
        n = scan(items, cache, requests.Session(), args.throttle, args.limit,
                 save=None if args.dry_run else save_cache)
        if not args.dry_run:
            save_cache(cache)
        print(f"[bundles] fetched {n} item(s); cache holds "
              f"{sum(1 for e in cache.values() if e.get('verdict') == 'bundle')} bundle(s)")
    if args.apply:
        wrote, removed = apply(items, cache, args.dry_run)
        print(f"[bundles] {'would write' if args.dry_run else 'wrote'} {len(wrote)} spine(s), "
              f"removed {len(removed)}")
        for aid, slug, n in wrote:
            print(f"  + {slug}: {n} episodes  <- {aid}")
        for aid, slug in removed:
            print(f"  - {slug}  <- {aid}")
    if args.report:
        from collections import Counter
        print(Counter(e.get("verdict") for e in cache.values()))
        for aid, e in sorted(cache.items()):
            if e.get("verdict") == "single":
                print(f"  single {aid}: {e.get('reason')}")


if __name__ == "__main__":
    main()
