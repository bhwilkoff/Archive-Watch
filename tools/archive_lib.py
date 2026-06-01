#!/usr/bin/env python3
"""
archive_lib.py — shared Internet Archive helpers.

Consolidates the Archive logic that was duplicated across
ingest_candidates.py and backfill_tv_episodes.py (metadata fetch,
derivative picker), and adds the title+year resolver that lets us match a
PD title with no known Archive ID to a playable Archive item — the
highest-leverage sourcing improvement (unlocks the ~6,800 PD-flagged
Wikidata films that lack a P724 Internet Archive ID).
"""

from __future__ import annotations

import re

import requests

ADV_SEARCH   = "https://archive.org/advancedsearch.php"
ARCHIVE_META = "https://archive.org/metadata/"
ARCHIVE_DL   = "https://archive.org/download/"
UA = "ArchiveWatch-Lib/1.0 (https://github.com/bhwilkoff/Archive-Watch; learningischange.com)"

VIDEO_RE = re.compile(r"(mp4|h\.?264|mpeg-?4|matroska|webm|quicktime|512kb|ogg video)")
ADULT_MARKERS = {"pron", "adult", "erotica", "sexploitation", "nudism"}


# ---------------------------------------------------------------------------
# Metadata + derivative selection
# ---------------------------------------------------------------------------

def archive_meta(iaid, session, *, timeout=40):
    r = session.get(ARCHIVE_META + iaid, headers={"User-Agent": UA}, timeout=timeout)
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}")
    return r.json()


def pick_video(files):
    """Best playable derivative from an Archive files list. Ranking mirrors
    DerivativePicker.swift: h.264 MP4 > other MP4 > 512Kb MPEG4 > other
    MPEG4 > webm/mkv > any MP4/h264 original > anything. Within a tier,
    largest file wins (higher bitrate)."""
    vids = [f for f in files if VIDEO_RE.search((f.get("format") or "").lower())
            or (f.get("name") or "").lower().endswith((".mp4", ".m4v", ".webm", ".mkv"))]
    if not vids:
        return None

    def fmt(f):
        return (f.get("format") or "").lower()

    def deriv(f):
        return (f.get("source") or "").lower() == "derivative"

    tiers = [
        lambda f: deriv(f) and ("h.264" in fmt(f) or "h264" in fmt(f)),
        lambda f: deriv(f) and "mp4" in fmt(f),
        lambda f: deriv(f) and "512kb" in fmt(f) and "mpeg4" in fmt(f),
        lambda f: deriv(f) and ("mpeg4" in fmt(f) or "mpeg-4" in fmt(f)),
        lambda f: deriv(f) and ("webm" in fmt(f) or "matroska" in fmt(f)),
        lambda f: ("mp4" in fmt(f) or "h.264" in fmt(f)),
        lambda f: True,
    ]
    for pred in tiers:
        m = [f for f in vids if pred(f)]
        if m:
            return max(m, key=lambda f: int(f.get("size") or 0))
    return None


def download_url(iaid, filename):
    return ARCHIVE_DL + iaid + "/" + requests.utils.quote(filename)


def runtime_from_file(vf):
    """Parse a derivative's `length` (HH:MM:SS or seconds) → seconds."""
    rt = vf.get("length")
    if not rt:
        return None
    parts = str(rt).split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(float(parts[2]))
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(float(parts[1]))
        return int(float(parts[0]))
    except ValueError:
        return None


def is_adult(collections):
    cl = [c.lower() for c in (collections or [])]
    return any(any(m in c for m in ADULT_MARKERS) for c in cl)


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

def adv_search(q, session, *, rows=50, fields=("identifier", "title", "year", "downloads")):
    fl = list(fields)
    r = session.get(
        ADV_SEARCH,
        params={"q": q, "fl[]": fl, "rows": rows, "output": "json"},
        headers={"User-Agent": UA}, timeout=60,
    )
    if not r.ok:
        return []
    return r.json().get("response", {}).get("docs", [])


# ---------------------------------------------------------------------------
# Title → Archive resolver
# ---------------------------------------------------------------------------

_STOP = {"the", "a", "an", "of", "and", "or"}
_NOISE = re.compile(
    r"\b(trailer|clip|clips|excerpt|preview|sample|review|reaction|"
    r"restored|colorized|colorised|fan\s*edit|part\s*\d+|reel\s*\d+)\b",
    re.IGNORECASE,
)


def _norm(s):
    s = (s or "").lower()
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    return " ".join(w for w in s.split() if w not in _STOP)


def _year_of(doc):
    m = re.search(r"(\d{4})", str(doc.get("year") or ""))
    return int(m.group(1)) if m else None


def resolve_title(title, year, session, *, year_tol=2, min_downloads=0):
    """Find the best playable Archive item for a film title + year.

    Returns (identifier, score, doc) or (None, 0, None). Scoring rewards a
    tight title match and a close year, and penalizes clip/trailer-looking
    titles. The CALLER must still fetch metadata + pick_video to confirm
    the match is actually playable — this only narrows the field.
    """
    if not title or len(title) < 2:
        return None, 0, None
    want = _norm(title)
    if not want:
        return None, 0, None

    # Query: title words within movies. Quote the phrase loosely.
    q = f'title:({title}) AND mediatype:movies'
    docs = adv_search(q, session, rows=30,
                      fields=("identifier", "title", "year", "downloads"))
    if not docs:
        return None, 0, None

    best = None
    best_score = 0
    for d in docs:
        cand_title = d.get("title") or ""
        cand_norm = _norm(cand_title)
        if not cand_norm:
            continue
        # Title containment: the wanted title's words should mostly appear.
        want_words = set(want.split())
        cand_words = set(cand_norm.split())
        if not want_words:
            continue
        overlap = len(want_words & cand_words) / len(want_words)
        if overlap < 0.6:                      # too weak a title match
            continue
        score = overlap * 100

        # Exact-ish title bonus.
        if cand_norm == want:
            score += 40
        elif cand_norm.startswith(want) or want in cand_norm:
            score += 20

        # Year proximity.
        cy = _year_of(d)
        if year and cy:
            dy = abs(cy - year)
            if dy == 0:
                score += 40
            elif dy <= year_tol:
                score += 25 - dy * 5
            else:
                score -= min(dy, 20)           # wrong year is a real penalty
        elif year and not cy:
            score -= 5                          # unknown year, mild penalty

        # Clip/trailer penalty.
        if _NOISE.search(cand_title):
            score -= 50

        # Penalize obvious non-archival re-uploads (YouTube rips, etc.) —
        # these are often the same film but lower quality and shakier
        # provenance than a native Archive upload.
        ident = (d.get("identifier") or "").lower()
        if ident.startswith(("youtube-", "yt-", "ytdown")) or "youtube" in ident:
            score -= 30

        # Popularity tiebreak.
        try:
            dls = int(d.get("downloads") or 0)
        except (TypeError, ValueError):
            dls = 0
        if dls < min_downloads:
            continue
        score += min(dls, 50000) / 50000 * 5   # up to +5

        if score > best_score:
            best_score = score
            best = d

    # Confidence floor: an exact-ish title + a year match scores ~140+, so
    # 90 keeps solid matches while dropping fuzzy/wrong-year/clip guesses.
    if best and best_score >= 90:
        return best["identifier"], round(best_score, 1), best
    return None, 0, None
