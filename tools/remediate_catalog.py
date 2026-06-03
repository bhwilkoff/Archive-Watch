#!/usr/bin/env python3
"""
remediate_catalog.py — one-shot, RE-RUNNABLE data-quality pass over the existing
catalog.json, fixing the high-confidence movie metadata bugs found in the
2026-06 audit without risky guesswork:

  1. YEAR: when the title/archiveID carries an explicit year and the stored year
     is implausible (in the future, or off by >1 from a confident title year, or
     a silent film dated after 1930), trust the title year. Years beyond the
     current year, or silent-era films dated >1930 with no title year, are
     nulled (better unknown than a 2026 on a black-and-white film).
  2. SILENT vs SOUND: year < 1928 features become silent-film; silent-film items
     dated >=1930 are demoted to feature-film (false silents like the 1930
     "Abraham Lincoln" / 1932 "Speak Easily").
  3. ANIMATION: items with a hard animation signal (genre "Animation", or an
     explicit "cartoon"/"animation" subject) that aren't already animation.
  4. ADULT: title/subject/genre adult markers set isAdult so the default filter
     hides them (the collection-only filter misses these).

Deliberately does NOT reclassify by runtime (audit found runtime data
unreliable — many real features report 1 min). Conservative on purpose.

Operates on catalog.json (root). Idempotent. `--dry-run` to preview.
"""

import argparse
import json
import re
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
CURRENT_YEAR = 2026  # passed-in epoch is fixed; bump when re-running in a later year

MOVIE_TYPES = {"feature-film", "silent-film", "animation", "short-film",
               "documentary", "newsreel", "ephemeral", "tv-special", "home-movie"}

# Sound era begins ~1927 (The Jazz Singer); be generous and treat <1928 as silent.
SILENT_CUTOFF = 1928
SILENT_MAX = 1930  # a "silent-film" dated after this is almost certainly mislabeled

_PAREN_YEAR = re.compile(r"\((1[89]\d\d|20[0-2]\d)\)")
_BARE_YEAR = re.compile(r"\b(18[7-9]\d|19\d\d|20[0-2]\d)\b")
# Resolution/junk tokens that look like years — never read these as a year.
_NOT_YEAR_CTX = re.compile(r"(?:720|1080|2160|480|240)p?", re.I)

# Personal-upload junk: archiveID carries an email-provider token + digits
# (e.g. dipwad2_zoho_507, mary59_gmx_919) and the title is just a number.
# These are camera-roll/test uploads with garbage auto-enriched metadata.
_JUNK_ID = re.compile(r"_(zoho|gmx|gmail|yahoo|hotmail|outlook|aol|mail|qq|protonmail|icloud|web|live|msn)_?\d", re.I)
_NUMERIC_TITLE = re.compile(r"^[\d\W]{1,6}$")
# Year-only "public domain animation" compilation reels (1941publicdomainanimation
# titled just "1941") — legit content, useless title.
_PD_ANIM = re.compile(r"^(\d{4})publicdomainanimation", re.I)

_ADULT = re.compile(
    r"\b(erotic|nudie|sexploitation|softcore|hardcore|porn|x-?rated|"
    r"adults?\s+only|burlesque\s+nude|nudist)\b", re.I)
_CARTOON = re.compile(r"\b(cartoon|animation|animated)\b", re.I)


def title_year(item):
    """Confident release year from the title/archiveID, or None. Parenthesised
    years win; otherwise a single unambiguous bare year. Resolution tokens
    (720/1080) are stripped first so they can't masquerade as years."""
    for text in (item.get("title") or "", item.get("archiveID") or ""):
        m = _PAREN_YEAR.search(text)
        if m:
            return int(m.group(1))
    for text in (item.get("title") or "", item.get("archiveID") or ""):
        cleaned = _NOT_YEAR_CTX.sub(" ", text)
        yrs = [int(y) for y in _BARE_YEAR.findall(cleaned)]
        yrs = [y for y in yrs if 1878 <= y <= CURRENT_YEAR]
        if len(set(yrs)) == 1:
            return yrs[0]
    return None


def decade_of(y):
    return (y // 10 * 10) if y else None


def has_animation_signal(item):
    if any((g or "").strip().lower() == "animation" for g in (item.get("genres") or [])):
        return True
    for s in (item.get("subjects") or []):
        if _CARTOON.search(s or ""):
            return True
    return False


def is_adult_signal(item):
    hay = " ".join([
        item.get("title") or "",
        " ".join(item.get("subjects") or []),
        " ".join(item.get("genres") or []),
    ])
    return bool(_ADULT.search(hay))


def is_junk(it):
    """Personal-upload garbage: junk-uploader archiveID + a numeric/short
    title. Conservative — needs BOTH so real films (e.g. titled "1917") and
    series are never dropped."""
    if it.get("contentType") == "tv-series":
        return False
    aid = it.get("archiveID") or ""
    if not _JUNK_ID.search(aid):
        return False
    return bool(_NUMERIC_TITLE.match((it.get("title") or "").strip()))


def remediate(items):
    stats = Counter()
    for it in items:
        ct = it.get("contentType")
        if ct == "tv-series" or ct not in MOVIE_TYPES:
            continue

        # Retitle year-only PD-animation compilation reels (#7).
        m = _PD_ANIM.match(it.get("archiveID") or "")
        if m and _NUMERIC_TITLE.match((it.get("title") or "").strip()):
            yr = int(m.group(1))
            it["title"] = f"Public Domain Animation ({yr})"
            it["year"] = yr
            it["decade"] = decade_of(yr)
            it["contentType"] = "animation"
            if "Animation" not in (it.get("genres") or []):
                it.setdefault("genres", []).append("Animation")
            stats["pd_anim_retitled"] += 1
            continue
        y = it.get("year")
        ty = title_year(it)

        # 1) YEAR — only OVERRIDE when the stored year is implausible (the
        # upload-date leak: missing, in the future, or a 2020+ value on an item
        # whose title carries a pre-2020 release year). Deliberately do NOT
        # "correct" merely-disagreeing years — a film TITLED with a year
        # ("2001: A Space Odyssey", "1917") would be wrecked by that.
        new_y = y
        if ty is not None and (y is None or y > CURRENT_YEAR or
                               (y > 2019 and ty <= 2019)):
            new_y = ty
            stats["year_from_title"] += 1
        elif y is not None and y > CURRENT_YEAR:
            new_y = None
            stats["year_nulled_future"] += 1
        elif ct == "silent-film" and y is not None and y > SILENT_MAX and ty is None:
            new_y = None
            stats["year_nulled_silent"] += 1
        if new_y != y:
            it["year"] = new_y
            it["decade"] = decade_of(new_y)
            it["isSilentFilm"] = bool(new_y and new_y < SILENT_CUTOFF)
            y = new_y

        # 2) SILENT vs SOUND (by corrected year)
        if y is not None:
            if y < SILENT_CUTOFF and ct in ("feature-film", "short-film"):
                it["contentType"] = "silent-film"; it["isSilentFilm"] = True
                stats["to_silent"] += 1
            elif ct == "silent-film" and y >= SILENT_MAX:
                it["contentType"] = "feature-film"; it["isSilentFilm"] = False
                stats["silent_demoted"] += 1

        # 3) ANIMATION (hard signal only)
        if it.get("contentType") in ("feature-film", "silent-film", "short-film") \
                and has_animation_signal(it):
            it["contentType"] = "animation"
            stats["to_animation"] += 1

        # 4) ADULT
        if not it.get("isAdult") and is_adult_signal(it):
            it["isAdult"] = True
            stats["adult_flagged"] += 1
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    # Drop personal-upload junk (#7) before remediating the rest.
    before = len(cat["items"])
    cat["items"] = [it for it in cat["items"] if not is_junk(it)]
    junk_removed = before - len(cat["items"])
    if isinstance(cat.get("stats"), dict):
        cat["stats"]["totalItems"] = len(cat["items"])
    stats = remediate(cat["items"])
    stats["junk_removed"] = junk_removed
    print("[remediate] " + (", ".join(f"{k}={v}" for k, v in sorted(stats.items())) or "no changes"))
    if not args.dry_run:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
        print(f"[remediate] wrote {CATALOG.name}")
    else:
        print("[remediate] dry-run, nothing written")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
