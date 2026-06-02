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


def clean_extra_title(t):
    """Light cleanup for the title of an item we couldn't align to a canonical
    episode: strip bracket tags, format noise, and trailing dates so we don't
    show '...The Complete Series' / '...- MKV' as an episode name (issue #4)."""
    if not t:
        return None
    s = re.sub(r"[\[\(][^\]\)]*[\]\)]", " ", t)       # [upgrade] / (1080p)
    s = _EXTRA_TITLE_NOISE.sub(" ", s)
    s = re.sub(r"\s+[-–]\s+\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b", " ", s)  # - 10-24-62
    s = re.sub(r"[_]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip(" -–:·")
    return s or None


def map_items_to_canonical(our_eps, canon):
    """our_eps: list of dicts {archiveID, title, downloadURL, videoFile, ...}.
    canon: canonical episode list. Returns (mapped, extras) where mapped is a
    list of canonical episodes with our playable item attached, extras is our
    items that couldn't be confidently placed."""
    by_sxe = {(c["season"], c["number"]): c for c in canon}
    canon_titles = [(_norm(c["title"]), c) for c in canon]
    used = set()
    mapped = {}
    extras = []

    for it in our_eps:
        title = it.get("title") or ""
        sxe_texts = _item_sxe_texts(it)
        s, e = parse_sxe(*sxe_texts)
        target = None
        if s is not None and (s, e) in by_sxe:
            target = by_sxe[(s, e)]
        if target is None:
            # Season 1 assumption when only an episode number is present and
            # the show is single-season-ish — but only if S1En exists.
            n = parse_epnum(*sxe_texts)
            if n is not None and (1, n) in by_sxe:
                target = by_sxe[(1, n)]
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


def rebuild_show(show, our_eps, *, repick):
    """Build one canonical series from a pre-resolved TVmaze show + the pooled
    Archive items. Returns (series_dict|None, report_row)."""
    our_eps = dedup_items(our_eps)
    canon = canonical_episodes(show)
    prem0 = (show.get("premiered") or "")[:4]
    slug = slugify(show.get("name"), prem0 if prem0.isdigit() else None)
    row = {"slug": slug, "tvmazeID": show.get("id"),
           "title": show.get("name"), "matched": True,
           "canonEps": len(canon), "ourItems": len(our_eps),
           "mappedEps": 0, "extras": 0, "repicked": 0, "deadItems": 0}
    if not canon:
        return None, row

    prem_i = int(prem0) if prem0.isdigit() else None
    ended0 = (show.get("ended") or "")[:4]
    year_lo = prem_i
    year_hi = int(ended0) if ended0.isdigit() else None

    mapped, extras = map_items_to_canonical(our_eps, canon)
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
        if repick:
            dl, vf, changed, ok = ensure_playable(item.get("archiveID"), dl, vf)
            if changed:
                row["repicked"] += 1
        if not ok or not dl:
            row["deadItems"] += 1
            continue
        ep = {
            "archiveID": item.get("archiveID"),
            "seasonNumber": s, "episodeNumber": n,
            "title": cep["title"],
            "overview": cep["overview"],
            "stillURL": cep["stillURL"] or item.get("stillURL"),
            "airDate": cep["airDate"],
            "year": (int(cep["airDate"][:4]) if cep.get("airDate") else item.get("year")),
            "runtimeSeconds": cep["runtimeSeconds"] or item.get("runtimeSeconds"),
            "videoFile": vf,
            "downloadURL": dl,
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
            if repick:
                dl, vf, changed, ok = ensure_playable(item.get("archiveID"), dl, vf)
                if changed:
                    row["repicked"] += 1
            if not ok or not dl:
                row["deadItems"] += 1
                continue
            sxe_texts = _item_sxe_texts(item)
            s2, e2 = parse_sxe(*sxe_texts)
            ep = {
                "archiveID": item.get("archiveID"),
                "seasonNumber": s2,
                "episodeNumber": e2 or parse_epnum(*sxe_texts),
                "title": clean_extra_title(item.get("title")) or "Untitled",
                "overview": item.get("overview"),
                "stillURL": item.get("stillURL"),
                "airDate": None,
                "year": _clamp_year(item.get("year"), year_lo, year_hi),
                "runtimeSeconds": item.get("runtimeSeconds"),
                "videoFile": vf,
                "downloadURL": dl,
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
    }
    row["availableEps"] = avail
    return series, row


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

_SUFFIX_RE = re.compile(
    r"\b(tv\s*show|tv\s*series|the\s+complete\s+series|complete\s+series|"
    r"complete|mini[\s-]?series|tv)\b", re.I)

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


def gather_raw_targets(titles_filter):
    """Return raw (rawTitle, year, items[], kind) tuples — existing clustered
    series + misclassified singles — before canonical resolution."""
    targets = []
    for f in sorted(SERIES_DIR.glob("*.json")):
        d = json.loads(f.read_text())
        # ref = the existing on-disk slug, so the reconcile step can delete
        # superseded files once their content is folded into a canonical one.
        targets.append((d.get("title"), d.get("yearStart"),
                        collect_our_episodes_from_series(d), "series", f.stem))
    cat = json.loads(FULL_CATALOG.read_text())
    for it in cat["items"]:
        if it.get("contentType") == "tv-series" and not it.get("seriesID"):
            ep = {"archiveID": it["archiveID"], "title": it.get("title"),
                  "downloadURL": it.get("downloadURL"), "videoFile": it.get("videoFile"),
                  "stillURL": it.get("posterURL"), "year": it.get("year"),
                  "runtimeSeconds": it.get("runtimeSeconds")}
            targets.append((it.get("title"), it.get("year"), [ep], "single", it["archiveID"]))
    # Freshly-discovered TV items (discover_tv_shows.py) — new shows not yet in
    # the catalog. downloadURL is None; the mapper re-picks the MP4 by id.
    disc = REPO / "shared" / "editorial" / "tv_discovery.json"
    have_targets = {t[4] for t in targets}
    if disc.exists():
        for it in json.loads(disc.read_text()).get("items", []):
            aid = it.get("archiveID")
            if not aid or aid in have_targets:
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
    args = ap.parse_args()

    raw = gather_raw_targets(args.titles)
    print(f"[tv] {len(raw)} raw targets; resolving + pooling by canonical show…",
          flush=True)
    shows, unmatched = resolve_and_pool(raw, args.limit, args.throttle)
    print(f"[tv] {len(shows)} unique canonical shows, {len(unmatched)} unmatched "
          f"({'DRY-RUN' if args.dry_run else 'WRITING'})", flush=True)

    rows = []
    written = 0
    reclassify = []     # archiveIDs to drop from tv-series (singles w/ no map)
    seen_slugs = set()
    for sid, slot in sorted(shows.items(), key=lambda kv: -len(kv[1]["items"])):
        series, row = rebuild_show(slot["show"], slot["items"],
                                   repick=not args.no_repick)
        row["kinds"] = sorted(slot["kinds"])
        row["mergedFrom"] = len(slot["sourceTitles"])
        row["consumedRefs"] = slot["refs"]   # old slugs / single archiveIDs folded in
        rows.append(row)
        avail = row.get("availableEps", 0)
        merged = f" merged={row['mergedFrom']}" if row["mergedFrom"] > 1 else ""
        print(f"  {row['title']!r:40} canon={row['canonEps']:3} "
              f"pooled={row['ourItems']:3} mapped={row['mappedEps']:3} "
              f"avail={avail:3} repick={row['repicked']:2} extras={row['extras']:2}{merged}",
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
            # Matched a show but couldn't place any item (whole-show singles):
            # flag the single items for reclassification out of tv-series.
            for it in slot["items"]:
                reclassify.append(it.get("archiveID"))

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
            "unmatched": [{"title": t, "year": y, "items": n, "kind": k, "ref": r}
                          for t, y, n, k, r in unmatched],
        }, ensure_ascii=False, indent=1))
        print(f"[tv] report -> {REPORT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
