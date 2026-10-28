#!/usr/bin/env python3
"""
build_canonical_tv.py — give TV a canonical series→season→episode spine.

The old TV pipeline synthesised "series" by clustering Archive items on
filename similarity. That produced: (a) 1,064 single Archive items
mislabelled as series with no episode structure, (b) real shows truncated
to a handful of episodes, and (c) episodes with no real S/E numbers,
titles, overviews, air dates, or artwork (46-66% missing).

This tool rebuilds TV around a CANONICAL spine from TVmaze (free, no key):
resolve each show to its TVmaze record, pull the authoritative episode list,
then MAP the Archive items we actually have onto canonical episodes. The
canonical record supplies numbering/titles/overviews/air dates/stills; the
Archive item supplies the playable MP4. Items we can't confidently place
stay as "extras" (we never fabricate an S/E number).

Sources:
  • TVmaze  https://api.tvmaze.com  — canonical structure (primary)
  • OMDb    (OMDB_KEY env)          — show poster/plot fallback (optional)
  • Archive metadata                — re-pick a playable MP4 derivative

Inputs (no dependency on the local video_registry.db):
  • existing series/*.json            (the 403 clustered series to re-spine)
  • catalog.json tv-series singles    (the 1,064 to resolve or reclassify)

Usage:
  python tools/build_canonical_tv.py --dry-run --limit 12 --titles "Get Smart,Bonanza"
  python tools/build_canonical_tv.py --dry-run --limit 12      # sample
  python tools/build_canonical_tv.py                           # full run

Output (non-dry-run): rewrites series/<slug>.json for matched shows, and
writes shared/editorial/tv_rebuild_report.json with the match/coverage
breakdown + the reclassification list for export_catalog to consume.
"""

import argparse
import difflib
import json
import os
import re
import sys
import time
import urllib.parse
from collections import defaultdict

import remediate_catalog as R  # the pipeline's own url encoder
import build_bundle_series as BUNDLE  # Decision 167: a whole series in one item
import audit_rights as _AR  # the film audit owns the rights rules
AR_MODERN = _AR.MODERN
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SERIES_DIR = REPO / "series"
FULL_CATALOG = REPO / "catalog.json"
REPORT = REPO / "shared" / "editorial" / "tv_rebuild_report.json"

TVMAZE = "https://api.tvmaze.com"
ARCHIVE_META = "https://archive.org/metadata/"
ARCHIVE_DL = "https://archive.org/download/"
UA = "ArchiveWatch-TV/1.0 (https://github.com/bhwilkoff/Archive-Watch; learningischange.com)"

# AVPlayer can decode H.264/HEVC in MP4/MOV/m4v + HLS. NOT Ogg/MKV/AVI/webm.
PLAYABLE_EXT = (".mp4", ".m4v", ".mov", ".m3u8")


# ---------------------------------------------------------------------------
# HTTP helpers (stdlib only; polite to TVmaze ~20 req/10s)
# ---------------------------------------------------------------------------

def _get_json(url, *, timeout=25, retries=3):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code == 429:
                time.sleep(5 * (attempt + 1))
                continue
            return None
        except Exception:
            time.sleep(2 * (attempt + 1))
    return None


def html_strip(s):
    if not s:
        return None
    s = re.sub(r"<[^>]+>", "", s)
    s = (s.replace("&amp;", "&").replace("&quot;", '"').replace("&#39;", "'")
           .replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " "))
    return re.sub(r"\s+", " ", s).strip() or None


# ---------------------------------------------------------------------------
# TVmaze
# ---------------------------------------------------------------------------

def tvmaze_resolve(title, year=None):
    """Resolve a title to a canonical TVmaze show, disambiguating by year.
    Returns the show dict (with _embedded.episodes) or None."""
    # Use /search (ranked list) so we can pick by year rather than trusting
    # singlesearch's single guess.
    results = _get_json(TVMAZE + "/search/shows?q=" + urllib.parse.quote(title)) or []
    if not results:
        return None

    def score(entry):
        show = entry.get("show", {})
        s = entry.get("score", 0)
        prem = (show.get("premiered") or "")[:4]
        if year and prem.isdigit():
            # Heavily reward a close premiere year; penalise far-off matches
            # (this is what separates Shogun-1980 from Shogun-2024).
            diff = abs(int(prem) - year)
            s += max(0, 8 - diff) if diff <= 8 else -diff * 0.2
        return s

    best = max(results, key=score)["show"]
    show_id = best.get("id")
    if not show_id:
        return None
    # Name-plausibility floor (issue #7): the chosen show must share an
    # identity token with the query OR premiere within a year of the requested
    # year. Otherwise the query was too vague and TVmaze just returned its top
    # unrelated hit (e.g. "Diver Dan" -> "The Man from Snowy River"). Reject
    # rather than mis-bind — the item stays unmatched and is kept as a single.
    qtoks = _id_tokens(title)
    ntoks = _id_tokens(best.get("name"))
    prem = (best.get("premiered") or "")[:4]
    year_close = bool(year and prem.isdigit() and abs(int(prem) - year) <= 1)
    if qtoks and not (qtoks & ntoks) and not year_close:
        return None
    full = _get_json(f"{TVMAZE}/shows/{show_id}?embed=episodes")
    return full


def canonical_episodes(show):
    eps = (show.get("_embedded") or {}).get("episodes") or []
    out = []
    for e in eps:
        s, n = e.get("season"), e.get("number")
        if s is None or n is None:
            continue  # specials with no number — skip from the spine
        img = (e.get("image") or {})
        out.append({
            "season": s, "number": n,
            "title": e.get("name") or f"Episode {n}",
            "overview": html_strip(e.get("summary")),
            "airDate": e.get("airdate") or None,
            "stillURL": img.get("original") or img.get("medium"),
            "runtimeSeconds": (e.get("runtime") or 0) * 60 or None,
        })
    return out


# ---------------------------------------------------------------------------
# Archive derivative re-pick (fix .ogv / unplayable)
# ---------------------------------------------------------------------------

_meta_cache = {}

def archive_pick_mp4(iaid):
    """Return (filename, format, sizeBytes) for the best H.264 MP4 derivative
    of an Archive item, or None. Cached per id."""
    if iaid in _meta_cache:
        return _meta_cache[iaid]
    d = _get_json(ARCHIVE_META + urllib.parse.quote(iaid) + "/files")
    files = (d or {}).get("result") or []
    def fmt(f):
        return (f.get("format") or "").lower()
    def is_deriv(f):
        return (f.get("source") or "").lower() == "derivative"
    tiers = [
        lambda f: is_deriv(f) and ("h.264" in fmt(f) or "h264" in fmt(f)),
        lambda f: is_deriv(f) and "mp4" in fmt(f),
        lambda f: is_deriv(f) and "mpeg4" in fmt(f),
        lambda f: (f.get("name") or "").lower().endswith((".mp4", ".m4v")),
    ]
    pick = None
    for pred in tiers:
        cands = [f for f in files if pred(f)]
        if cands:
            pick = max(cands, key=lambda f: int(f.get("size") or 0))
            break
    result = None
    if pick:
        result = (pick["name"], pick.get("format") or "h.264",
                  int(pick.get("size") or 0))
    _meta_cache[iaid] = result
    return result


def ensure_playable(archive_id, download_url, video_file):
    """Pick the best playable MP4 for an item. Returns
    (download_url, video_file, changed:bool, ok:bool).

    Issue #6: prefer Archive's auto-generated faststart derivative
    (source=derivative, `.ia.mp4` h.264) over the uploader's original *even
    when the current URL already ends in .mp4*. Uploader originals are often
    non-faststart (moov atom at EOF) → slow/no start; the derivative streams
    immediately. archive_pick_mp4 ranks derivatives above originals, so if it
    returns a DIFFERENT file than we currently point at, swap to it. Only when
    no better derivative exists do we keep an existing .mp4 as-is."""
    url = download_url or ""
    base = _basename(url).lower()
    cur_is_mp4 = url.lower().split("?")[0].endswith(PLAYABLE_EXT)
    # Already on Archive's faststart derivative — nothing better exists, so
    # skip the metadata fetch entirely (keeps the full rebuild from hammering
    # Archive for every already-good item).
    if cur_is_mp4 and base.endswith(".ia.mp4"):
        return download_url, video_file, False, True
    picked = archive_pick_mp4(archive_id)
    if picked:
        name, fmt, size = picked
        if name and name != _basename(url):
            new_url = ARCHIVE_DL + urllib.parse.quote(archive_id) + "/" + urllib.parse.quote(name)
            new_vf = {"name": name, "format": fmt, "sizeBytes": size, "tier": 1}
            return new_url, new_vf, True, True
    # No better derivative than what we have.
    if cur_is_mp4:
        return download_url, video_file, False, True
    return download_url, video_file, False, False


# ---------------------------------------------------------------------------
# Mapping Archive items -> canonical episodes
# ---------------------------------------------------------------------------

SXE_RE = re.compile(r"s(\d{1,2})\s*[._x-]?\s*e(\d{1,3})", re.I)
EPNUM_RE = re.compile(r"(?:\bep(?:isode)?\.?\s*|\bpart\s*|\b#)(\d{1,3})", re.I)


def parse_sxe(*texts):
    for t in texts:
        if not t:
            continue
        m = SXE_RE.search(t)
        if m:
            return int(m.group(1)), int(m.group(2))
    return None, None


NXN_RE = re.compile(r"(?<![\w.])(\d{1,2})x(\d{2,3})(?!\d)", re.I)
SEASON_EP_RE = re.compile(r"season[\s_.-]*(\d{1,2})[\s_.,-]*(?:episode|ep)s?[\s_.-]*(\d{1,3})", re.I)
_PROMO_RE = re.compile(r"\b(?:promos?|trailers?|preview|teaser|next week)\b", re.I)
_MARKS_RE = re.compile(r"\b(?:s\d{1,2}\s*e\d{1,3}|\d{1,2}x\d{2,3}|season|episodes?|ep|part|\d+[a-z]{0,2})\b")
_FILE_JUNK = {"mp4", "mkv", "avi", "ogv", "ia", "hd", "sd", "web", "dl", "dvdrip", "rip", "x264",
              "h264", "aac", "colorized", "restored", "airing", "aired", "guest", "classic",
              "sitcom", "vintage", "full", "uncut", "remastered", "pilot", "unaired", "tv"}


def _own_texts(it):
    """The upload's OWN words for itself: its file name and its archive.org id.
    Not `title` — an episode re-pooled from a spine carries the canonical title
    of the slot it already holds, so a misplacement would confirm itself."""
    vf = it.get("videoFile") or {}
    stem = re.sub(r"\.[a-z0-9]{2,4}$", "", vf.get("name") or _basename(it.get("downloadURL")) or "", flags=re.I)
    stem = re.sub(r"\.ia$", "", stem, flags=re.I)
    return [re.sub(r"[_.]+", " ", re.sub(r"([a-z])([A-Z])", r"\1 \2", t)).strip()
            for t in (stem, it.get("archiveID") or "") if t]


def _own_sxe(texts):
    """A season and episode the upload states, in any of the forms uploaders use
    (S04E03, 4x03, "Season 4, Episode 3")."""
    for t in texts:
        for rx in (SXE_RE, NXN_RE, SEASON_EP_RE):
            m = rx.search(t)
            if m:
                return int(m.group(1)), int(m.group(2))
    return None, None


_ARTICLE = re.compile(r"^(?:the|a|an)\s+")


def _own_title_target(variants, canon_titles):
    """_title_target for a single upload's own words: an exact match first with
    leading articles dropped on both sides ("Bonanza - The Blood Line" is TVmaze's
    "The Blood Line", not the closer-spelled "Blood Tie"), and no fuzzy guess
    among episodes that differ only by a part number ("Beyond the Curtain of
    Space (1)/(2)/(3)")."""
    bare = [(_ARTICLE.sub("", t), c) for t, c in canon_titles]
    for v in variants:
        hit = [c for t, c in bare if t == _ARTICLE.sub("", v)]
        if hit:
            return hit[0]
    target = _title_target(variants, canon_titles)
    if target is not None:
        theirs = set(re.findall(r"\b(?:19|20)\d{2}\b", target["title"] or ""))
        mine = {y for v in variants for y in re.findall(r"\b(?:19|20)\d{2}\b", v)}
        if theirs and mine and not theirs & mine:   # "1 November 1959" is not "November 2, 1956"
            return None
        stem = re.sub(r"\d+", "", _norm(target["title"])).strip()
        if sum(1 for t, _ in canon_titles if re.sub(r"\d+", "", t).strip() == stem) > 1:
            return None
    return target


def _after_marker(texts):
    """What follows the last episode marker ("... TV 1954 colorized s01e04 At
    Night All Cats Are Gray"), which is where uploaders write the episode."""
    out = []
    for t in texts:
        m = list(re.finditer(r"s\d{1,2}\s*-?\s*e\d{1,3}|(?<![\w.])\d{1,2}x\d{2,3}(?!\d)", t, re.I))
        if m and t[m[-1].end():].strip(" -–:."):
            out.append(t[m[-1].end():].strip(" -–:."))
    return out


_GENERIC_EP = re.compile(r"^\s*(?:episode|part|chapter|program(?:me)?)\b", re.I)


def _words_meet(a, b):
    """Two titles share a word, allowing a stem ("Recruits"/"Recruit") and a
    translation's cognate ("Universo"/"Universe")."""
    return any(x == y or (len(x) >= 5 and len(y) >= 5 and x[:5] == y[:5]) for x in a for y in b)


def _title_words(t, show_tokens=frozenset()):
    t = re.sub(r"(?<=[a-z])(?=\d)|(?<=\d)(?=[a-z])", " ", _norm(t))
    words = _MARKS_RE.sub(" ", t).split()
    return {w for w in words if len(w) >= 3 and w not in show_tokens
            and w not in _TOKEN_STOP and w not in _FILE_JUNK}


def parse_epnum(*texts):
    for t in texts:
        if not t:
            continue
        m = EPNUM_RE.search(t)
        if m:
            return int(m.group(1))
    return None


def _norm(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def _safe_url(u):
    """Percent-encode an archive.org download url. ONE line of real work,
    delegating to the encoder the film pipeline has always used.

    Measured 2026-09-06: 2,264 of the 4,702 episodes in the spines — 48% —
    carried a raw filename with spaces ("S01E05 - Pie in the Sky - Hot Rodney
    - Space Dogs.ia.mp4"). A url with a space is not a url: Python refuses it
    and Roku's Video node cannot open it, so the episode looked present and
    would not play. ZERO film urls had the problem, because
    `remediate_catalog.encode_download_urls` has always run over catalog.json
    — and episodes are not catalog items, so it never saw one.

    Do not write a second encoder here. The first draft of this fix did, and
    got it wrong twice before matching what that function already handled:
    sub-directories with spaces ("Dragnet/Season 7/..."), and a literal `#` in
    a filename, which urlsplit reads as a fragment marker. `safe="/%"` also
    preserves existing escapes, so re-running cannot turn %20 into %2520.
    """
    if not u:
        return u
    items = [{"downloadURL": u}]
    R.encode_download_urls(items, defaultdict(int))
    return items[0]["downloadURL"]


def _basename(url):
    """Last path component of a download URL, percent-decoded."""
    if not url:
        return ""
    return urllib.parse.unquote(url.rstrip("/").split("/")[-1])


def _item_sxe_texts(it):
    """All strings that might carry an SxE / episode number for an item.
    Crucially includes the video FILENAME — Archive items frequently encode
    `S01E18` only in the file, not the title or id (issue #3)."""
    vf = it.get("videoFile") or {}
    return (it.get("title"), it.get("archiveID"),
            vf.get("name"), _basename(it.get("downloadURL")))


# Stopwords that carry no show-identity signal — excluded from the
# mismap-detection token overlap.
_TOKEN_STOP = {
    "the", "a", "an", "and", "of", "in", "on", "at", "to", "tv", "show",
    "shows", "series", "episode", "episodes", "ep", "season", "complete",
    "mkv", "mp4", "ia", "part", "vol", "volume", "full", "hd", "remastered",
    "upgrade", "edition", "feat", "with",
}


def _id_tokens(s):
    """Tokenize an identifier (archiveID / filename / title) for show-identity
    comparison: split camelCase and letter/digit runs, lowercase, drop pure
    numbers, tiny tokens, and stopwords."""
    if not s:
        return set()
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)      # camelCase -> camel Case
    s = re.sub(r"([A-Za-z])(\d)", r"\1 \2", s)       # Line24 -> Line 24
    s = re.sub(r"(\d)([A-Za-z])", r"\1 \2", s)       # 24January -> 24 January
    s = re.sub(r"[^A-Za-z0-9]+", " ", s).lower()
    out = set()
    for t in s.split():
        if t.isdigit() or len(t) <= 2 or t in _TOKEN_STOP:
            continue
        out.add(t)
    return out


def _item_identity_tokens(it):
    """Identity tokens for a single item (archiveID + filename, not the
    curated title — the canonical pipeline overwrites titles, but the Archive
    id/filename always reflect the real source)."""
    return (_id_tokens(it.get("archiveID"))
            | _id_tokens(_basename(it.get("downloadURL")))
            | _id_tokens((it.get("videoFile") or {}).get("name")))


def _items_identity_tokens(items):
    """Union of identity tokens across all items."""
    toks = set()
    for it in items:
        toks |= _item_identity_tokens(it)
    return toks


def _common_identity_tokens(items, frac=0.5):
    """Tokens that appear in at least `frac` of the items — the de-facto show
    name as written in the filenames. A single stray token (e.g. one item
    mislabelled 'what') won't qualify, so this is a sharper mismap signal than
    a plain union overlap."""
    if not items:
        return set()
    counts = {}
    for it in items:
        for t in _item_identity_tokens(it):
            counts[t] = counts.get(t, 0) + 1
    need = max(2, int(len(items) * frac + 0.999))
    return {t for t, c in counts.items() if c >= need}


def _clamp_year(y, lo, hi):
    """Drop a year that falls outside the show's broadcast run (±1) — guards
    against Archive UPLOAD dates leaking in as the episode year (issue #1)."""
    if not y:
        return None
    if lo and y < lo - 1:
        return None
    if hi and y > hi + 1:
        return None
    return y


_EXTRA_TITLE_NOISE = re.compile(
    r"\b(the\s+complete\s+series|complete\s+series|complete|"
    r"season\s+\d+\s+of\s+\d+|s\d+\s+of\s+\d+|mkv|tv[\s-]?show|"
    r"blu[\s-]?ray(\s+extras)?|x264|x265|h\.?264|web[\s-]?dl)\b", re.I)


def clean_extra_title(t, show_title=None):
    """Light cleanup for the title of an item we couldn't align to a canonical
    episode: strip bracket tags, format noise, and trailing dates so we don't
    show '...The Complete Series' / '...- MKV' as an episode name (issue #4),
    and the show's own name in front ("'Mack and Myer for Hire'- Wacky
    Wizardry"), which the series page already says."""
    if not t:
        return None
    s = re.sub(r"[\[\(][^\]\)]*[\]\)]", " ", t)       # [upgrade] / (1080p)
    words = [w for w in re.findall(r"[a-z0-9]+", (show_title or "").lower()) if w != "the"]
    if words:
        lead = re.compile(r"^\W*(?:the\W+)?" + r"\W+".join(map(re.escape, words)) + r"(?![a-z0-9])[\W_]*", re.I)
        rest = lead.sub("", s)
        if re.search(r"[a-z0-9]{2}", rest, re.I):
            s = rest
    s = s.replace("''", " ").strip(" '\"")
    s = re.sub(r"^(?:s\d{1,2}\s*e\d{1,3}|\d{1,2}x\d{2,3})\s*[-–:.]?\s+(?=\w)", "", s, flags=re.I)
    s = _EXTRA_TITLE_NOISE.sub(" ", s)
    s = re.sub(r"\s+[-–]\s+\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b", " ", s)  # - 10-24-62
    s = re.sub(r"[_]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip(" -–:·")
    return s or None


_BUNDLE_CACHE = None


def _wrong_show_bundles(our_eps):
    """Items whose files mostly name episodes this show does not have: a whole
    series matched onto the wrong show (The Invisible Man of 1958 under the 1975
    one). Mapping their files would fill the show with another show's episodes."""
    total, placed = defaultdict(int), defaultdict(int)
    for e in our_eps:
        if e.get("sourceID") and e.get("bundleTitle"):
            total[e["sourceID"]] += 1
            placed[e["sourceID"]] += bool(e.get("_named"))
    return {src for src, n in total.items() if n >= 4 and placed[src] < 0.25 * n}


_NOT_FILMS = None


def _not_films():
    global _NOT_FILMS
    if _NOT_FILMS is None:
        p = REPO / "shared" / "editorial" / "not_films.json"
        _NOT_FILMS = ({k for k in json.loads(p.read_text()) if not k.startswith("_")}
                      if p.exists() else set())
    return _NOT_FILMS


_TV_RIGHTS_REMOVED = None


def _tv_rights_removed():
    """archiveIDs audit_tv_rights removed (shared/editorial/tv_rights_removed.csv).
    The audit re-removes them after this build, but a spine written here and
    committed before the audit ran (or when it failed) served them again, so
    the build drops them itself. Same reading rule as audit_tv_rights.manifest_ids:
    the archiveID is the third field from the END (old rows have six fields,
    newer ones seven)."""
    global _TV_RIGHTS_REMOVED
    if _TV_RIGHTS_REMOVED is None:
        import csv
        p = REPO / "shared" / "editorial" / "tv_rights_removed.csv"
        out = set()
        if p.exists():
            with p.open(newline="", encoding="utf-8") as fh:
                for r in list(csv.reader(fh))[1:]:
                    if len(r) >= 6 and r[-3]:
                        out.add(r[-3])
        _TV_RIGHTS_REMOVED = out
    return _TV_RIGHTS_REMOVED


_EPISODE_REJECTS = None


def _episode_rejects():
    """{archiveID: {notIn, why}}: an upload a person found is not an episode of
    the show it was filed under (2002 Twilight Zone revival rips in the 1959
    series, 2021 Family Feud in The Smith Family)."""
    global _EPISODE_REJECTS
    if _EPISODE_REJECTS is None:
        p = REPO / "shared" / "editorial" / "episode_rejects.json"
        _EPISODE_REJECTS = ({k: v for k, v in json.loads(p.read_text()).items() if not k.startswith("_")}
                            if p.exists() else {})
    return _EPISODE_REJECTS


def expand_bundles(our_eps, keep=frozenset()):
    """Decision 167: an item whose files are the whole show (`FireballXL5.complete`,
    39 files) was pooled as ONE episode of it. Replace it — and any episodes a
    previous run already expanded from it — with one row per file, read from
    build_bundle_series's cache (the build needs no network for them). An item
    whose files no longer parse keeps what it had. Returns (eps, n_expanded)."""
    global _BUNDLE_CACHE
    if _BUNDLE_CACHE is None:
        _BUNDLE_CACHE = BUNDLE.load_cache()
    by_src, rest = {}, []
    for e in our_eps:
        src = e.get("sourceID") or BUNDLE.item_of(e.get("archiveID") or "")
        if src and src not in keep and (_BUNDLE_CACHE.get(src) or {}).get("verdict") == "bundle":
            by_src.setdefault(src, []).append(e)
        else:
            rest.append(e)
    expanded = 0
    for src, olds in by_src.items():
        rows = BUNDLE.tv_episodes(src, _BUNDLE_CACHE[src])
        if rows:
            rest.extend(rows)
            expanded += 1
        else:
            rest.extend(olds)
    return rest, expanded


def _unexpanded(our_eps, srcs):
    """`our_eps` with the items in `srcs` as they were before any expansion: the
    item itself, never a file of it a previous run placed."""
    out, seen = [], set()
    for e in our_eps:
        src = e.get("sourceID") or BUNDLE.item_of(e.get("archiveID") or "")
        if src in srcs:
            if src not in seen and not e.get("sourceID"):
                out.append(e)
                seen.add(src)
            elif src not in seen and e.get("sourceID"):
                out.append({"archiveID": src, "title": src, "downloadURL": None, "videoFile": None})
                seen.add(src)
            continue
        out.append(e)
    return out


def _bundle_order(our_eps):
    """Items that are one episode each place first, as before; files of
    whole-series items after them, the fullest upload first and a colorized one
    last (Decision 158: a colorization is never the default copy)."""
    singles = sorted((e for e in our_eps if not e.get("sourceID")),
                     key=lambda e: BUNDLE.is_colorized(" ".join(_own_texts(e))))
    files = [e for e in our_eps if e.get("sourceID")]
    size = defaultdict(int)
    for e in files:
        size[e["sourceID"]] += 1
    files.sort(key=lambda e: (BUNDLE.is_colorized(e["sourceID"]), -size[e["sourceID"]], e["sourceID"]))
    return singles + files


_LEAD_MARK = re.compile(r"^(?:s\d{1,2}\s*e\d{1,3}|\d{1,2}x\d{2,3}|e?p?\d{1,3}|episode\s+\d{1,3})\s+")


def _title_variants(title, show_tokens):
    """The ways an upload's title may name its episode: as written, without the
    show's own name in front ("Prisoner. Arrival", "1999 The Exiles"), and
    without an episode marker ("Fireball XL5 - 1x01 - Planet 46")."""
    out = []
    t = _norm(title)
    for _ in range(3):
        if t and t not in out:
            out.append(t)
        words = t.split()
        while words and words[0] in show_tokens:
            words.pop(0)
        t = _LEAD_MARK.sub("", " ".join(words))
    if t and t not in out:
        out.append(t)
    return [v for v in out if len(v) >= 3]


def _title_target(variants, canon_titles):
    names = [t for t, _ in canon_titles]
    for v in variants:
        hit = [c for t, c in canon_titles if t == v]
        if hit:
            return hit[0]
    for v in variants:
        best = difflib.get_close_matches(v, names, n=1, cutoff=0.82)
        if best:
            return next(c for t, c in canon_titles if t == best[0])
    for v in variants:
        # a file name cut short ("Happy Birthday Gra") or a title the canonical
        # list shortens ("Mother Lurch Visits"): one canonical name only
        hit = [c for t, c in canon_titles
               if min(len(t), len(v)) >= 10 and (t.startswith(v) or v.startswith(t))]
        if len(hit) == 1:
            return hit[0]
    return None


def _map_bundle_row(it, by_sxe, canon_titles, show_tokens=frozenset()):
    """A file of a whole-series item is placed by its own TITLE first: uploaders
    number by production order as often as by broadcast (FireballXL5.complete's
    "08. Space Immigrants" is TVmaze's 1x03). Only a file that states no title is
    placed by its number."""
    if it.get("bundleTitle"):
        return _title_target(_title_variants(it["bundleTitle"], show_tokens), canon_titles)
    n = it.get("episodeNumber")
    if n is None:
        return None
    if it.get("seasonNumber") is not None:
        return by_sxe.get((it["seasonNumber"], n))
    # a file that names no season counts the whole run ("spectreman@e22")
    order = sorted(by_sxe)
    return by_sxe[order[n - 1]] if 0 < n <= len(order) else None


def map_items_to_canonical(our_eps, canon, show_title=None):
    """our_eps: list of dicts {archiveID, title, downloadURL, videoFile, ...}.
    canon: canonical episode list. Returns (mapped, extras) where mapped is a
    list of canonical episodes with our playable item attached, extras is our
    items that couldn't be confidently placed."""
    by_sxe = {(c["season"], c["number"]): c for c in canon}
    canon_titles = [(_norm(c["title"]), c) for c in canon]
    used = set()
    mapped = {}
    extras = []
    extra_titles = set()
    show_tokens = set(_norm(show_title).split()) | {"the"}

    for it in _bundle_order(our_eps):
        if it.get("sourceID"):
            target = _map_bundle_row(it, by_sxe, canon_titles, show_tokens)
            it["_named"] = bool(target)   # names an episode of this show, placed or not
            if target:
                key = (target["season"], target["number"])
                rt, crt = it.get("runtimeSeconds"), target.get("runtimeSeconds")
                if key not in used and not (rt and crt and rt < 0.4 * crt):
                    used.add(key)
                    mapped[key] = (target, it)
                # else: another copy already plays this episode, or this file is
                # a fragment of it — a second entry would only repeat it
                continue
            nt = _norm(it.get("title"))
            if nt not in extra_titles:   # five uploads of one show add one extra each, not five
                extra_titles.add(nt)
                extras.append(it)
            continue
        title = it.get("title") or ""
        own = _own_texts(it)
        # A promo, trailer or "next week" reel names the episode it advertises
        # ("Twilight Zone promo (S2E25 The Silence)"); it is not that episode.
        if any(_PROMO_RE.search(t) for t in own):
            ps, pe = _own_sxe(own)
            advert = by_sxe.get((ps, pe)) if ps is not None else None
            it["title"] = f"Promo: {advert['title']}" if advert else (own[0] if own else title)
            it["_promo"] = True
            it["_notThis"] = True
            extras.append(it)
            continue
        sxe_texts = _item_sxe_texts(it)
        s, e = parse_sxe(*sxe_texts)
        if s is None:
            s, e = _own_sxe(own)
        target = None
        if s is not None and (s, e) in by_sxe:
            target = by_sxe[(s, e)]
        if target is None and s is None:
            # Season 1 assumption when only an episode number is present and
            # the show is single-season-ish — but only if S1En exists, and
            # never when the upload names another season ("Season4Episode3").
            n = parse_epnum(*sxe_texts)
            if n is not None and (1, n) in by_sxe:
                target = by_sxe[(1, n)]
        # The upload's own title outranks its number (as for a whole-series
        # item's files, Decision 167): "s01e01.The.Speckled.Band" is not
        # TVmaze's 1x01. A title that names another episode moves it there;
        # one that names none and shares no word with its numbered slot is not
        # that slot.
        words = _title_words(own[0], show_tokens) if own else set()
        agrees = target is not None and _words_meet(words, _title_words(target["title"], show_tokens))
        named = _own_title_target([v for t in own[:1] + _after_marker(own[:1])
                                   for v in _title_variants(t, show_tokens)], canon_titles) \
            if words and not agrees else None
        if named is not None:
            target = named
        elif (target is not None and len(words) >= 2 and not agrees
                and not _GENERIC_EP.match(target["title"] or "")):
            it["title"] = own[0]
            it["_notThis"] = True   # its own title says another episode: no number, no second pass
            target = None
            extras.append(it)
            continue
        if target is None:
            # Fuzzy title match against canonical episode names.
            nt = _norm(title)
            if nt:
                best = difflib.get_close_matches(
                    nt, [t for t, _ in canon_titles], n=1, cutoff=0.82)
                if best:
                    target = next(c for t, c in canon_titles if t == best[0])
        key = (target["season"], target["number"]) if target else None
        if target and key not in used:
            used.add(key)
            mapped[key] = (target, it)
        else:
            extras.append(it)

    # An item that is one episode but named in a way the passes above cannot read
    # ("Fireball XL5 - 1x01 - Planet 46") is placed by its title when a file of a
    # whole-series item would otherwise hold its slot: items place first.
    if any(it.get("sourceID") for _, it in mapped.values()):
        still = []
        for it in extras:
            # A promo or an upload whose own title named another episode was
            # judged already: "Promo: Person or Persons Unknown" must not match
            # the episode it advertises here (2026-10-27).
            target = None if it.get("sourceID") or it.get("_notThis") else \
                _title_target(_title_variants(it.get("title"), show_tokens), canon_titles)
            key = (target["season"], target["number"]) if target else None
            if key and (key not in used or mapped[key][1].get("sourceID")):
                used.add(key)
                mapped[key] = (target, it)
            else:
                still.append(it)
        extras = still

    return mapped, extras


# ---------------------------------------------------------------------------
# Per-show rebuild
# ---------------------------------------------------------------------------

def collect_our_episodes_from_series(series_json):
    out = []
    for s in series_json.get("seasons", []):
        for e in s.get("episodes", []):
            out.append(e)
    return out


def rebuild_show(show, our_eps, *, repick, deadline=None):
    """Build one canonical series from a pre-resolved TVmaze show + the pooled
    Archive items. Returns (series_dict|None, report_row)."""
    pooled = dedup_items(our_eps)
    our_eps, n_bundles = expand_bundles(pooled)
    # A person named the item not a film, never to be served (not_films.json):
    # that binds its episodes too. LTT101, a Looney Tunes rip from Tubi, came
    # back as some 260 episodes of the Looney Tunes spine through Decision 167.
    nf = _not_films()
    our_eps = dedup_items([e for e in our_eps
                           if (e.get("sourceID") or BUNDLE.item_of(e.get("archiveID") or "")) not in nf])
    canon = canonical_episodes(show)
    prem0 = (show.get("premiered") or "")[:4]
    slug = slugify(show.get("name"), prem0 if prem0.isdigit() else None)
    rej = _episode_rejects()
    gone = _tv_rights_removed()
    our_eps = [e for e in our_eps
               if (rej.get(e.get("archiveID")) or {}).get("notIn") not in ("*", slug)
               and e.get("archiveID") not in gone]
    row = {"slug": slug, "tvmazeID": show.get("id"),
           "title": show.get("name"), "matched": True,
           "canonEps": len(canon), "ourItems": len(our_eps),
           "mappedEps": 0, "extras": 0, "repicked": 0, "deadItems": 0,
           "repickSkipped": 0, "bundles": n_bundles}
    if not canon:
        return None, row

    def _may_repick() -> bool:
        """Whether to spend a network round trip verifying this episode's MP4.

        The budget used to be checked only BETWEEN shows, so a single large
        show ran unbounded and blew the job's 180-minute step timeout — the
        exact failure the workflow comment warns about, and the reason the
        weekly rebuild has been red since 2026-08-16.

        Past the deadline we degrade to --no-repick for the REMAINING episodes:
        each one keeps the downloadURL it already had. That costs freshness for
        the tail of one show. Stopping mid-show instead would cost EPISODES,
        and this spine is what every client reads for TV — a partial rebuild
        would silently delete content (Decisions 016/036).
        """
        if not repick:
            return False
        if deadline is not None and time.monotonic() > deadline:
            row["repickSkipped"] += 1
            return False
        return True

    prem_i = int(prem0) if prem0.isdigit() else None
    ended0 = (show.get("ended") or "")[:4]
    year_lo = prem_i
    year_hi = int(ended0) if ended0.isdigit() else None

    mapped, extras = map_items_to_canonical(our_eps, canon, show.get("name"))
    wrong = _wrong_show_bundles(our_eps)
    if wrong:
        our_eps = dedup_items(expand_bundles(_unexpanded(pooled, wrong), keep=wrong)[0])
        mapped, extras = map_items_to_canonical(our_eps, canon, show.get("name"))
        n_bundles -= len(wrong)
        row["bundles"] = n_bundles
        row["wrongShowBundles"] = sorted(wrong)
    row["mappedEps"] = len(mapped)
    row["extras"] = len(extras)

    # Mismap guard (issue #7): if NOT ONE item aligned to a canonical episode
    # AND the pooled items' identifiers share zero identity tokens with the
    # resolved show's name, this is almost certainly the wrong show (e.g.
    # What's-My-Line items resolved onto "Now What?"). Reject — leave the items
    # unmatched so reconcile reclassifies them, rather than mis-binding.
    if len(mapped) == 0:
        name_toks = _id_tokens(show.get("name"))
        common_toks = _common_identity_tokens(our_eps)
        if name_toks and common_toks and not (name_toks & common_toks):
            row["rejectedMismap"] = True
            return None, row

    # Build seasons from the canonical episodes we actually have a playable
    # item for. (v1: only-available; missing episodes are omitted, not greyed.)
    seasons = {}
    for (s, n), (cep, item) in sorted(mapped.items()):
        dl = item.get("downloadURL")
        vf = item.get("videoFile")
        ok = True
        # a file of a whole-series item was picked from the item's own file list;
        # a re-pick by item id would swap in the item's largest file, another episode
        if not item.get("sourceID") and _may_repick():
            dl, vf, changed, ok = ensure_playable(item.get("archiveID"), dl, vf)
            if changed:
                row["repicked"] += 1
        if not ok or not dl:
            row["deadItems"] += 1
            continue
        ep = {
            "archiveID": item.get("archiveID"),
            **({"sourceID": item["sourceID"]} if item.get("sourceID") else {}),
            "seasonNumber": s, "episodeNumber": n,
            "title": cep["title"],
            "overview": cep["overview"],
            "stillURL": cep["stillURL"] or item.get("stillURL"),
            "airDate": cep["airDate"],
            "year": (int(cep["airDate"][:4]) if cep.get("airDate") else item.get("year")),
            "runtimeSeconds": cep["runtimeSeconds"] or item.get("runtimeSeconds"),
            "videoFile": vf,
            "downloadURL": _safe_url(dl),
        }
        seasons.setdefault(s, []).append(ep)

    # Place items we couldn't align to a canonical episode as "extras" — but
    # only when this is genuinely a series (multiple items, or at least one
    # aligned). A lone unalignable file is a whole-show single → reclassify
    # (returned as None below), not a 1-episode "series".
    place_extras = len(mapped) > 0 or len(our_eps) >= 2
    if place_extras:
        for item in extras:
            dl = item.get("downloadURL")
            vf = item.get("videoFile")
            ok = True
            if not item.get("sourceID") and _may_repick():
                dl, vf, changed, ok = ensure_playable(item.get("archiveID"), dl, vf)
                if changed:
                    row["repicked"] += 1
            if not ok or not dl:
                row["deadItems"] += 1
                continue
            if item.get("sourceID"):
                s2, e2 = item.get("seasonNumber"), item.get("episodeNumber")
            elif item.get("_notThis"):
                s2, e2 = None, None   # a promo, or a file whose number names another episode
            else:
                sxe_texts = _item_sxe_texts(item)
                s2, e2 = parse_sxe(*sxe_texts)
                e2 = e2 or parse_epnum(*sxe_texts)
            ep = {
                "archiveID": item.get("archiveID"),
                **({"sourceID": item["sourceID"]} if item.get("sourceID") else {}),
                "seasonNumber": s2,
                "episodeNumber": e2,
                "title": (item.get("title") if item.get("sourceID")
                          else clean_extra_title(item.get("title"), show.get("name"))) or "Untitled",
                "overview": item.get("overview"),
                "stillURL": item.get("stillURL"),
                "airDate": None,
                "year": _clamp_year(item.get("year"), year_lo, year_hi),
                "runtimeSeconds": item.get("runtimeSeconds"),
                "videoFile": vf,
                "downloadURL": _safe_url(dl),
            }
            seasons.setdefault(s2, []).append(ep)

    # Sort seasons with None ("unassigned") last; episodes by number then title.
    def ep_key(e):
        return (e.get("episodeNumber") is None, e.get("episodeNumber") or 0,
                e.get("title") or "")
    season_list = [{"seasonNumber": s, "episodes": sorted(eps, key=ep_key)}
                   for s, eps in sorted(seasons.items(),
                                        key=lambda kv: (kv[0] is None, kv[0] or 0))]
    avail = sum(len(s["episodes"]) for s in season_list)
    if avail == 0:
        return None, row

    img = (show.get("image") or {})
    net = (show.get("network") or show.get("webChannel") or {})
    prem = (show.get("premiered") or "")[:4]
    ended = (show.get("ended") or "")[:4]
    series = {
        "version": 2,
        "seriesID": slug,
        "tvmazeID": show.get("id"),
        "title": show.get("name"),
        "yearStart": int(prem) if prem.isdigit() else None,
        "yearEnd": int(ended) if ended.isdigit() else None,
        "overview": html_strip(show.get("summary")),
        "posterURL": img.get("original") or img.get("medium"),
        "backdropURL": None,
        "genres": show.get("genres") or [],
        "networks": [net["name"]] if net.get("name") else [],
        "creator": None,
        "seasons": season_list,
        "episodesCount": avail,         # available (playable) count
        "canonicalEpisodesCount": len(canon),
        "tvmazeRating": (show.get("rating") or {}).get("average"),
    }
    row["availableEps"] = avail
    return series, row


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

_SUFFIX_RE = re.compile(
    r"\b(tv\s*show|tv\s*series|the\s+complete\s+series|complete\s+series|"
    r"complete|mini[\s-]?series|tv|colou?ri[sz]ed)\b", re.I)

def clean_title(t):
    """Normalise an Archive-derived show title for TVmaze search: drop
    parentheticals, '.'-separators, trailing years, and noise suffixes
    ('TV Show', '(Complete Series)', 'miniseries')."""
    if not t:
        return ""
    s = re.sub(r"\([^)]*\)", " ", t)          # drop (miniseries) etc.
    s = s.replace(".", " ")                     # ken.-burns -> ken burns
    s = re.sub(r"[_\-]+", " ", s)
    s = _SUFFIX_RE.sub(" ", s)
    s = re.sub(r"\b(19|20)\d{2}\b", " ", s)    # trailing/embedded year
    s = re.sub(r"\s+", " ", s).strip(" -:–")
    return s


def slugify(title, year):
    base = re.sub(r"[^a-z0-9]+", "-", (title or "").lower()).strip("-")
    return f"{base}-{year}" if year else base


_SEASON_EP_RE = re.compile(r"season\s*\d+\s*episode\s*\d+|series\s*\d+\s*episode\s*\d+", re.I)
# where a title/slug stops being the series name and starts being episode info
_ORPHAN_CUT = re.compile(r"\s*(?:[|:]|s\d{1,2}\s*[._x-]?\s*e\d{1,3}|season\s*\d+"
                         r"|series\s*\d+|episode\s*\d+|\bep\.?\s*\d+|\d{1,2}x\d{2})", re.I)


def _orphan_is_episode(it):
    """A standalone item that is really a SPECIFIC TV episode — carries an SxE /
    NxNN marker (title/archiveID/filename) or a 'Season N Episode M' synopsis.
    Conservative: a marker is required (owner decision — episode-marked only)."""
    name = (it.get("videoFile") or {}).get("name") or ""
    blob = f"{it.get('archiveID') or ''} {it.get('title') or ''} {name}"
    syn = it.get("synopsis") if isinstance(it.get("synopsis"), str) else ""
    return bool(SXE_RE.search(blob) or re.search(r"\d{1,2}x\d{2}", blob)
                or _SEASON_EP_RE.search(syn))


def _orphan_series_name(it):
    """Best-guess SERIES name for an orphan episode, from the item's OWN naming
    (not a buried cross-reference): synopsis prefix before the first colon
    (handles 'One Step Beyond: <ep> ...' where the title is just the episode),
    then the title up to its episode marker, then the archiveID slug. Returns a
    clean_title()'d name of >=2 words, else ''."""
    syn = it.get("synopsis") if isinstance(it.get("synopsis"), str) else ""
    cands = []
    if ":" in syn[:50]:
        pre = syn.split(":", 1)[0]
        if 2 <= len(pre.split()) <= 6:
            cands.append(pre)
    cands.append(_ORPHAN_CUT.split(it.get("title") or "")[0])
    cands.append(_ORPHAN_CUT.split(re.sub(r"[_-]", " ", it.get("archiveID") or ""))[0])
    for c in cands:
        cleaned = clean_title(c)
        if len(cleaned.split()) >= 2:
            return cleaned
    return ""


def gather_raw_targets(titles_filter):
    """Return raw (rawTitle, year, items[], kind) tuples — existing clustered
    series + misclassified singles + episode-marked orphans — before canonical
    resolution."""
    targets = []
    bundled = set()
    for f in sorted(SERIES_DIR.glob("*.json")):
        d = json.loads(f.read_text())
        if d.get("sourceID"):
            bundled.add(d["sourceID"])
            continue   # a bundle spine is built from its item's files (Decision 166)
        # an item expanded into this spine's episodes (Decision 167) is served by
        # them; as a catalog card it would be pooled again as one more episode
        bundled.update(e["sourceID"] for se in d.get("seasons", [])
                       for e in se.get("episodes", []) if e.get("sourceID"))
        # ref = the existing on-disk slug, so the reconcile step can delete
        # superseded files once their content is folded into a canonical one.
        targets.append((d.get("title"), d.get("yearStart"),
                        collect_our_episodes_from_series(d), "series", f.stem))
    cat = json.loads(FULL_CATALOG.read_text())
    for it in cat["items"]:
        if it.get("archiveID") in bundled:
            continue
        # A catalog item the rights audit HID must not be re-served through a
        # spine. Only the orphan branch below carried this check, so an
        # excluded tv-series single walked straight back in — "the gate said
        # hide, the spine served it anyway".
        if (it.get("contentType") == "tv-series" and not it.get("seriesID")
                and not it.get("excluded")):
            ep = {"archiveID": it["archiveID"], "title": it.get("title"),
                  "downloadURL": _safe_url(it.get("downloadURL")), "videoFile": it.get("videoFile"),
                  "stillURL": it.get("posterURL"), "year": it.get("year"),
                  "runtimeSeconds": it.get("runtimeSeconds")}
            targets.append((it.get("title"), it.get("year"), [ep], "single", it["archiveID"]))
        # Episode-marked ORPHANS: items typed tv-special/feature with no seriesID
        # that are really a TV episode. They were invisible to this builder (only
        # tv-series + discovery were pooled), so they floated as standalone
        # "films". Pool them under their SERIES name (resolution) while keeping
        # the EPISODE title in the item (so the mapper's SxE/fuzzy match slots
        # them). The mismap guard + audit_series_episodes still gate inclusion;
        # excluded items (rights / confirmed duplicates) are skipped.
        elif (it.get("contentType") in ("tv-special", "feature-film")
                and not it.get("seriesID") and not it.get("excluded")
                and _orphan_is_episode(it)):
            sname = _orphan_series_name(it)
            if not sname:
                continue
            ep = {"archiveID": it["archiveID"], "title": it.get("title"),
                  "downloadURL": _safe_url(it.get("downloadURL")), "videoFile": it.get("videoFile"),
                  "stillURL": it.get("posterURL"), "year": it.get("year"),
                  "runtimeSeconds": it.get("runtimeSeconds")}
            targets.append((sname, it.get("year"), [ep], "orphan-episode", it["archiveID"]))
    # Freshly-discovered TV items (discover_tv_shows.py) — new shows not yet in
    # the catalog. downloadURL is None; the mapper re-picks the MP4 by id.
    disc = REPO / "shared" / "editorial" / "tv_discovery.json"
    have_targets = {t[4] for t in targets}
    if disc.exists():
        for it in json.loads(disc.read_text()).get("items", []):
            aid = it.get("archiveID")
            if not aid or aid in have_targets or aid in bundled:
                continue
            # Discovery items have never been near catalog.json, so the rights
            # audit has never seen them either. Judge on the year we have;
            # backfill_tv_episodes.rights_ok does the licence-aware check when
            # the episodes themselves are fetched.
            y = it.get("year")
            if isinstance(y, int) and y >= AR_MODERN:
                continue
            ep = {"archiveID": aid, "title": it.get("title"),
                  "downloadURL": None, "videoFile": None,
                  "stillURL": None, "year": it.get("year"), "runtimeSeconds": None}
            targets.append((it.get("title"), it.get("year"), [ep], "single", aid))
    if titles_filter:
        wanted = {t.strip().lower() for t in titles_filter.split(",")}
        targets = [t for t in targets if (t[0] or "").lower() in wanted]
    return targets


def resolve_and_pool(raw_targets, limit, throttle):
    """Resolve every raw target to a canonical TVmaze show and POOL all
    Archive items that land on the same show id. Returns:
      shows:   {show_id: {"show": record, "items": [...], "kinds": set,
                          "sourceTitles": set}}
      unmatched: [(title, year, n_items, kind), ...]
    Resolution is cached by cleaned-title so duplicate clusters share one call.
    """
    shows = {}
    unmatched = []
    title_cache = {}       # cleaned title -> show record (or None)
    count = 0
    for raw_title, year, items, kind, ref in raw_targets:
        if limit and count >= limit:
            break
        count += 1
        q = clean_title(raw_title)
        key = q.lower()
        if key in title_cache:
            show = title_cache[key]
        else:
            show = tvmaze_resolve(q, year) if q else None
            title_cache[key] = show
            time.sleep(throttle)
        if not show:
            unmatched.append((raw_title, year, len(items), kind, ref))
            continue
        sid = show.get("id")
        slot = shows.setdefault(sid, {"show": show, "items": [], "kinds": set(),
                                      "sourceTitles": set(), "refs": []})
        slot["items"].extend(items)
        slot["kinds"].add(kind)
        slot["sourceTitles"].add(raw_title)
        slot["refs"].append({"kind": kind, "ref": ref})
    return shows, unmatched


def dedup_items(items):
    seen = set()
    out = []
    for it in items:
        a = it.get("archiveID")
        if a and a not in seen:
            seen.add(a)
            out.append(it)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--titles", default=None, help="comma-separated exact titles to run")
    ap.add_argument("--no-repick", action="store_true",
                    help="skip Archive MP4 re-pick (faster, for structure-only tests)")
    ap.add_argument("--throttle", type=float, default=0.35)
    ap.add_argument("--max-minutes", type=float, default=0,
                    help="stop building new shows after this long and fall "
                         "through to the write. This step consumed the whole "
                         "360-minute job timeout on three consecutive runs, so "
                         "EVERY step after it was skipped — including the commit "
                         "and the catalog publish. The workflow produced nothing.")
    args = ap.parse_args()

    # The budget is TOTAL WALL CLOCK for this tool, measured from here — not
    # from the start of the rebuild loop. resolve_and_pool below is network
    # bound and unbounded: measured on 2026-08-20 it spent 54m22s resolving
    # 4,124 raw targets against TVmaze at the 0.3s throttle, while the loop
    # itself honoured its 5-minute budget exactly. With the production default
    # that is 54m + 150m = 204m against the workflow's 180-minute step timeout,
    # which is precisely why the weekly rebuild died on 2026-08-16 — the budget
    # was real, it just started counting after the expensive half was over.
    started = time.monotonic()

    raw = gather_raw_targets(args.titles)
    print(f"[tv] {len(raw)} raw targets; resolving + pooling by canonical show…",
          flush=True)
    shows, unmatched = resolve_and_pool(raw, args.limit, args.throttle)
    print(f"[tv] {len(shows)} unique canonical shows, {len(unmatched)} unmatched "
          f"({'DRY-RUN' if args.dry_run else 'WRITING'})", flush=True)

    rows = []
    written = 0
    reclassify = []     # archiveIDs to drop from tv-series (singles w/ no map)
    orphan_series = []  # existing series-file slugs whose show was rejected
    seen_slugs = set()
    deadline = (started + args.max_minutes * 60) if args.max_minutes else None
    if deadline is not None and time.monotonic() > deadline:
        # Resolution alone outlasted the whole budget. Every show defers, which
        # is SAFE (deferred spines are never deleted — reconcile globs series/
        # and consumed_old covers only PROCESSED shows; verified 485 -> 485 on
        # run 32373160578) but means this run rebuilds nothing. Say so loudly
        # rather than reporting a quiet success.
        print(f"[tv] WARNING: resolve+pool alone used the entire "
              f"{args.max_minutes:g}-minute budget "
              f"({(time.monotonic() - started) / 60:.0f}m). No show will be "
              f"rebuilt this run. Raise --max-minutes or lower --limit.",
              flush=True)
    stopped_early = 0
    for sid, slot in sorted(shows.items(), key=lambda kv: -len(kv[1]["items"])):
        if deadline and time.monotonic() > deadline:
            stopped_early += 1
            continue
        series, row = rebuild_show(slot["show"], slot["items"],
                                   repick=not args.no_repick, deadline=deadline)
        row["kinds"] = sorted(slot["kinds"])
        row["mergedFrom"] = len(slot["sourceTitles"])
        row["consumedRefs"] = slot["refs"]   # old slugs / single archiveIDs folded in
        rows.append(row)
        avail = row.get("availableEps", 0)
        merged = f" merged={row['mergedFrom']}" if row["mergedFrom"] > 1 else ""
        print(f"  {row['title']!r:40} canon={row['canonEps']:3} "
              f"pooled={row['ourItems']:3} mapped={row['mappedEps']:3} "
              f"avail={avail:3} repick={row['repicked']:2} extras={row['extras']:2}{merged}"
              f"{' bundles=%d' % row['bundles'] if row.get('bundles') else ''}",
              flush=True)
        if series and not args.dry_run:
            slug = series["seriesID"]
            if slug in seen_slugs:        # extremely rare slug collision guard
                slug = f"{slug}-{sid}"
                series["seriesID"] = slug
            seen_slugs.add(slug)
            (SERIES_DIR / f"{slug}.json").write_text(
                json.dumps(series, ensure_ascii=False, indent=1), encoding="utf-8")
            written += 1
        elif not series:
            # Matched a show but produced no series — either a whole-show
            # single (avail=0) or a rejected mismap (issue #7). Flag the items
            # for reclassification, and mark any EXISTING series file folded in
            # here as an orphan so reconcile deletes it instead of re-carding
            # the stale/mismapped show (e.g. now-what-2002.json).
            for it in slot["items"]:
                reclassify.append(it.get("archiveID"))
            for ref in slot["refs"]:
                if ref["kind"] == "series":
                    orphan_series.append(ref["ref"])

    # Unmatched singles also need reclassification (they aren't series at all).
    placeable = sum(1 for r in rows if r.get("availableEps", 0) > 0)
    print(f"\n[tv] canonical series with >=1 playable episode: {placeable}; "
          f"unmatched targets: {len(unmatched)}; "
          f"items to reclassify out of tv-series: {len(reclassify)}; "
          f"{'(dry-run, nothing written)' if args.dry_run else f'wrote {written} series'}")

    if not args.dry_run:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(json.dumps({
            "shows": rows,
            "reclassifyArchiveIDs": reclassify,
            "orphanSeriesSlugs": orphan_series,
            "unmatched": [{"title": t, "year": y, "items": n, "kind": k, "ref": r}
                          for t, y, n, k, r in unmatched],
        }, ensure_ascii=False, indent=1))
        print(f"[tv] report -> {REPORT}")
    skipped_repicks = sum(r.get("repickSkipped", 0) for r in rows)
    if skipped_repicks:
        print(f"[tv] budget reached mid-show: {skipped_repicks} episode(s) kept their "
              f"existing video URL instead of being re-verified. Episodes are NEVER "
              f"dropped for the budget — only the re-pick is skipped.")
    if stopped_early:
        print(f"[tv] STOPPED EARLY at the {args.max_minutes:g}-minute budget: "
              f"{stopped_early} shows deferred to the next run. Everything built "
              f"before the budget IS written and published.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
