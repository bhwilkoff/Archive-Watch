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
  5. GENRES: fill empty genres from subjects via the shared keyword map.
  6. RIGHTS: prove public_domain for US-gov collections + PD-by-age (<1929) so
     the Home rights gate stops excluding legitimate PD titles (e.g. NASA).
  7. WRONG EXTERNAL MATCH: a modern TMDb/OMDb poster+year landed on a vintage
     title (e.g. "CInderella" -> 2015 Disney; "The Pink Panther ~ 1963" -> 2006).
     Clear the bad artwork (-> ProceduralPoster) + correct/null the year.

Deliberately does NOT reclassify by runtime (audit found runtime data
unreliable — many real features report 1 min). Conservative on purpose.

Operates on catalog.json (root). Idempotent. `--dry-run` to preview.
"""

import argparse
import html as _html
import json
import re
import sys as _sys
from collections import Counter
from pathlib import Path

# Share the auditor's detectors so "what we detect is what we clean" (Tier 1).
_sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_metadata as _audit  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
CURRENT_YEAR = 2026  # passed-in epoch is fixed; bump when re-running in a later year

# Subject-keyword -> genre fallback (Track B enrichment): fills genres for items
# OMDb/TMDb never reached, using subjects/title already in the catalog — no
# network. Map lives in the shared taxonomy so Swift + JS agree.
def _load_subject_genres():
    try:
        m = json.loads((REPO / "docs/taxonomy/collections.json").read_text())
        raw = m.get("subjectKeywordMap") or {}
    except Exception:
        raw = {}
    disp = {"sci-fi": "Sci-Fi"}
    return [(re.compile(r"\b" + re.escape(k.lower()) + r"\b"),
             disp.get(v, v.title())) for k, v in raw.items()]

_SUBJECT_GENRES = _load_subject_genres()


def genres_from_subjects(it):
    """Derive up to 3 genres from an item's subjects + title via the keyword map."""
    hay = (" ".join(it.get("subjects") or []) + " " + (it.get("title") or "")).lower()
    out = []
    for rx, genre in _SUBJECT_GENRES:
        if genre not in out and rx.search(hay):
            out.append(genre)
    return out[:3]

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

# Year-keyed compilation reels ("1941publicdomainanimation" titled "Public
# Domain Animation (1941)") are collections of many shorts, NOT a single film —
# so any TMDb/OMDb poster on them is a wrong match (the "foreign film with a year
# on it" posters the user saw). Detect by archiveID regardless of current title.
_PD_ANIM_ANY = re.compile(r"publicdomainanimation", re.I)

# #18: a single catalog item that is really a TV EPISODE — a hard SxE marker
# (S1E11, S01E05, s02.e18) in the title or the video filename. High-confidence:
# theatrical films don't carry season/episode numbers. (Looser "Part N / Episode
# N" is deliberately excluded — too many film "Part 1/2" and reel volumes.)
_SXE = re.compile(r"(?<![a-z])s(\d{1,2})\s*[._x -]?\s*e(\d{1,3})(?![a-z])", re.I)
_MOVIE_TYPES_FOR_TV = {"feature-film", "short-film", "silent-film", "animation"}


def looks_like_episode(it):
    name = (it.get("videoFile") or {}).get("name") or ""
    return bool(_SXE.search(it.get("title") or "") or _SXE.search(name))


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


def _years_from(text):
    """(paren_years, bare_years) from a string, with resolution tokens removed so
    '1920x1080' / '720p' can't masquerade as a release year."""
    if not text:
        return [], []
    t = re.sub(r"\b\d{3,4}\s*[xX×]\s*\d{3,4}\b", " ", text)   # WxH resolution
    t = _NOT_YEAR_CTX.sub(" ", t)
    paren = [int(m) for m in _PAREN_YEAR.findall(t)]
    bare = [int(y) for y in _BARE_YEAR.findall(t) if 1878 <= int(y) <= CURRENT_YEAR]
    return paren, bare


def source_year(item):
    """Confident release year pooled from the title, archiveID, AND the video
    filename. A parenthesised year anywhere wins; else a single distinct bare year
    across all sources; None when ambiguous/absent. Broader than title_year (which
    ignores the filename) — uploads are usually scene-named with the year, e.g.
    'The.Ten.Commandments.1923.720p.mp4'. This is the #20 wrong-match year signal."""
    parens, bares = [], []
    for s in (item.get("title"), item.get("archiveID"),
              (item.get("videoFile") or {}).get("name")):
        p, b = _years_from(s)
        parens += p
        bares += b
    if parens and len(set(parens)) == 1:
        return parens[0]
    if len(set(bares)) == 1:
        return bares[0]
    return None


def _clear_wrong_artwork(it, new_year):
    """Strip a wrong external (TMDb/OMDb) match: drop its poster/backdrop, NULL the
    wrong identity (imdbID/tmdbID — otherwise the next enrichment cron re-fetches
    the SAME wrong poster from the leftover wrong id), correct the year when we
    have a confident one, and drop the match's synopsis if it came from the same
    source. Shared by both #20 detectors + the #75 TMDb verifier."""
    it["posterURL"] = None
    it["backdropURL"] = None
    it["hasRealArtwork"] = False
    it["artworkSource"] = "archive"
    it["imdbID"] = None
    it["tmdbID"] = None
    if new_year is not None:
        it["year"] = new_year
        it["decade"] = decade_of(new_year)
        it["isSilentFilm"] = bool(new_year < SILENT_CUTOFF)
    if (it.get("synopsisSource") or "").lower() in ("tmdb", "omdb"):
        it["synopsis"] = None
        it["synopsisSource"] = None


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


# --- Rights inference (#6) -------------------------------------------------
# Collections whose contents are unambiguously public domain: US-government
# works (PD by statute, any year) and Prelinger (explicitly PD/CC). Items in
# these get rightsStatus="public_domain" when it's missing/unknown, so the
# Home rights gate (CatalogDB.homeAnd) stops wrongly excluding e.g. post-1977
# NASA films from the hero/browse-home surfaces.
_GOV_PD_COLLECTIONS = {
    "fedflix", "nasa", "nasaeclips", "jsc-pao-video-collection", "usgovfilms",
    "prelinger", "prelingerhomemovies", "nationalarchives", "dl-archive",
}
_PD_BY_AGE = 1929  # US: anything published before this is public domain by age.


def infer_rights(it):
    """Return 'public_domain' when we can prove it (gov collection or PD-by-age),
    else None. Conservative — never downgrades an existing status."""
    cur = (it.get("rightsStatus") or "").strip().lower()
    if cur in ("public_domain", "creative_commons"):
        return None
    colls = {str(c).lower() for c in (it.get("collections") or [])}
    if colls & _GOV_PD_COLLECTIONS:
        return "public_domain"
    y = it.get("year")
    if isinstance(y, int) and 1878 <= y < _PD_BY_AGE:
        return "public_domain"
    return None


# NOTE: an earlier draft also cleared any *designed* poster shared across
# differently-titled items. Measured against the real catalog it was far too
# blunt — most "collisions" are the SAME film (foreign-language titles, AKAs,
# "(1945)"/"colorized" variants, duplicate uploads, serial chapters) sharing a
# correct poster, so it would have stripped ~2,500 GOOD posters. Even an
# imdbID-conflict variant only cleanly caught a handful. Dropped: the precise
# wrong-external-match pass below covers the user's actual cases (Cinderella,
# Pink Panther) without the collateral damage.

# --- Wrong external-match detection (#3/#4) ---------------------------------
# Two signals that a TMDb/OMDb enrichment matched the WRONG film (a modern
# remake), giving a vintage Archive title a contemporary poster + year:
#   (a) a parenthesised release year in the title disagrees with the stored
#       year by >=2 (e.g. "The 50's Moments (1981)" stored 2019); or
#   (b) a modern stored year (>=1990) on an item that sits in a strictly
#       vintage collection or is a silent film (e.g. "CInderella" -> 2015
#       Disney; "The Pink Panther ~ 1963" -> 2006).
# Either way we clear the (wrong) poster so it falls back to ProceduralPoster,
# and correct the year to a confident title/archiveID year when there is one,
# else null it (better unknown than a 2015 on a 1907 film). tv-series excluded.
_STRICT_VINTAGE = {
    "silent_films", "vintage_cartoons", "classic_cartoons", "classiccartoons",
    "silenthalloffame", "georgesmelies",
}


def _is_vintage(it):
    colls = {str(c).lower() for c in (it.get("collections") or [])}
    if colls & _STRICT_VINTAGE:
        return True
    return bool(it.get("isSilentFilm")) or it.get("contentType") == "silent-film"


def fix_wrong_external_matches(it):
    """If `it` looks like a wrong TMDb/OMDb match, clear its artwork + correct
    the year. Returns a short reason string when it acted, else None."""
    if it.get("contentType") == "tv-series":
        return None
    src = (it.get("artworkSource") or "").lower()
    if src not in ("tmdb", "omdb"):
        return None
    y = it.get("year")
    sy = source_year(it)   # pooled title+archiveID+filename confident year
    wrong = False
    if sy is not None and isinstance(y, int) and (y - sy) >= 5:
        # #20: a confident source year (title/archiveID/filename) that is >=5y
        # OLDER than the matched year — the classic "2000s poster + 2000s synopsis
        # on a 1960s film". One-directional (only when the match is NEWER than the
        # source) so genuine re-releases/restorations aren't touched; the >=5y gap
        # + an independent confident year keeps false positives low (measured: 131
        # of 14,072 designed items, samples all genuine wrong matches).
        wrong = True
    elif isinstance(y, int) and y >= 1990 and _is_vintage(it):
        wrong = True
    if not wrong:
        return None
    # Correct year: the confident source year when it's older than the suspect
    # stored year; else null and let enrichment re-resolve.
    new_y = sy if (sy is not None and (y is None or sy < y)) else None
    _clear_wrong_artwork(it, new_y)
    return "yearfix" if new_y is not None else "yearnull"


# --- Animation matched to a live-action film (#3a) -------------------------
# An `animation` item whose designed (TMDb/OMDb) poster carries strong
# live-action genres and NO "Animation" genre is matched to the wrong (usually
# live-action) film — e.g. the Popeye cartoons reel pulling the 1980 live-action
# "Popeye" (poster, 1980, 114-min runtime, genres Action/Adventure). Real
# cartoons carry "Animation" or family/comedy/musical/fantasy genres, so this is
# low-false-positive. Clear the wrong artwork + the live-action genres + the
# match's runtime/year (all from the wrong film). Language and true file length
# can't be verified from the catalog (runtime stored IS the match's, not the
# file's) — that needs a CI file probe; this catches the visible poster/genre/
# runtime mismatch.
_LIVE_ACTION_GENRES = {
    "action", "science fiction", "sci-fi", "horror", "western",
    "thriller", "war", "crime",
}


def fix_animation_liveaction_match(it):
    """Clear a live-action match wrongly applied to an animation item. Returns
    True if it acted."""
    if it.get("contentType") != "animation":
        return False
    if (it.get("artworkSource") or "").lower() not in ("tmdb", "omdb"):
        return False
    genres = [(g or "").lower() for g in (it.get("genres") or [])]
    if not genres or any(g == "animation" for g in genres):
        return False
    if not any(g in _LIVE_ACTION_GENRES for g in genres):
        return False
    it["posterURL"] = None
    it["backdropURL"] = None
    it["hasRealArtwork"] = False
    it["artworkSource"] = "archive"
    it["genres"] = []          # the live-action genres belong to the wrong film
    it["runtimeSeconds"] = None  # so does the runtime (often a feature length)
    it["year"] = None
    it["decade"] = None
    return True


# --- Tier 1: text sanitization (docs/architecture/metadata-audit.md) --------
# Deterministic cleaning of the two free-text fields users read, sharing the
# auditor's detectors. Synopsis: decode entities, strip HTML/mojibake, and drop
# whole sentences that are URL/social/email/uploader junk (keeps the plot, loses
# "Follow us on Instagram!"). If nothing meaningful survives, null it so Tier-2
# enrichment (Wikipedia/OMDb) can refill a real one. Title: strip codec/
# resolution/bracket junk + fix mojibake/ALL-CAPS, never emptying it.
_SENT_SPLIT = re.compile(r"(?<=[.!?])\s+")
_TAG = re.compile(r"<[^>]+>")
MIN_SYNOPSIS = 40


def _synopsis_text(it):
    v = it.get("synopsis")
    return (" ".join(v) if isinstance(v, list) else (v or "")).strip()


def _fix_mojibake(s):
    if not _audit.MOJIBAKE.search(s):
        return s
    try:
        return s.encode("latin-1").decode("utf-8")
    except (UnicodeDecodeError, UnicodeEncodeError):
        return s


def sanitize_synopsis(it):
    """Returns 'cleaned', 'nulled', or None."""
    raw = _synopsis_text(it)
    if not raw:
        return None
    s = _TAG.sub(" ", _fix_mojibake(_html.unescape(raw)))
    sents = [x for x in _SENT_SPLIT.split(s)
             if not (_audit.URL.search(x) or _audit.SOCIAL.search(x)
                     or _audit.EMAIL.search(x) or _audit.UPLOADER.search(x)
                     or _audit.TECH.search(x))]
    s = re.sub(r"\s+", " ", " ".join(sents)).strip()
    if s == raw:
        return None
    if len(s) < MIN_SYNOPSIS:
        it["synopsis"] = None
        it["synopsisSource"] = None
        return "nulled"
    it["synopsis"] = s
    return "cleaned"


def sanitize_title(it):
    raw = (it.get("title") or "").strip()
    if not raw:
        return False
    t = _fix_mojibake(_html.unescape(raw))
    t = _audit.T_BRACKET.sub(" ", t)
    t = _audit.T_RES.sub(" ", t)
    t = re.sub(r"\s+", " ", t).strip(" -_|")
    if t and t.isupper() and len(t.split()) > 1:
        t = t.title()
    if t and t != raw:
        it["title"] = t
        return True
    return False


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

        # 0a) PD-ANIMATION COMPILATION posters (#4): a year-compilation reel can't
        # have a single-film poster — strip any designed artwork so it falls back
        # to its own Archive frame.
        if _PD_ANIM_ANY.search(it.get("archiveID") or "") \
                and (it.get("artworkSource") or "").lower() not in ("", "archive"):
            it["posterURL"] = None
            it["backdropURL"] = None
            it["hasRealArtwork"] = False
            it["artworkSource"] = "archive"
            stats["pd_anim_poster_cleared"] += 1

        # 0b) WRONG EXTERNAL MATCH (#3/#4): a modern TMDb/OMDb poster+year on a
        # vintage title. Clear the bad artwork + fix the year before anything
        # downstream reads it.
        wm = fix_wrong_external_matches(it)
        if wm:
            stats[f"wrong_match_{wm}"] += 1

        # 0c) ANIMATION matched to a live-action film (#3a): clear the wrong
        # poster/genres/runtime (e.g. Popeye cartoons -> 1980 live-action film).
        if fix_animation_liveaction_match(it):
            stats["anim_liveaction_cleared"] += 1

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

        # 3b) MISLABELED TV EPISODE (#18): a movie-typed item with a hard SxE
        # marker is an episode — move it off the movie shelves to tv-special so it
        # routes to the TV tab. (Full season placement is the canonical TV
        # pipeline's job — see #18b; this stops the "episode shows as a film" bug.)
        if it.get("contentType") in _MOVIE_TYPES_FOR_TV and looks_like_episode(it):
            it["contentType"] = "tv-special"
            it["isSilentFilm"] = False
            stats["episode_to_tv_special"] += 1

        # 4) ADULT
        if not it.get("isAdult") and is_adult_signal(it):
            it["isAdult"] = True
            stats["adult_flagged"] += 1

        # 5) GENRES from subjects (Track B): fill empty genres with no network.
        if not it.get("genres"):
            g = genres_from_subjects(it)
            if g:
                it["genres"] = g
                stats["genres_from_subject"] += 1

        # 6) RIGHTS: prove public-domain for gov collections / PD-by-age so the
        # Home rights gate stops excluding legitimate PD titles.
        r = infer_rights(it)
        if r:
            it["rightsStatus"] = r
            stats["rights_inferred_pd"] += 1

        # 7) TEXT SANITIZATION (Tier 1): clean the free-text fields users read.
        sy = sanitize_synopsis(it)
        if sy:
            stats[f"synopsis_{sy}"] += 1
        if sanitize_title(it):
            stats["title_cleaned"] += 1

        # 8) ARTWORK FLOOR (#13): every Archive item should show at least its
        # Archive thumbnail rather than a procedural placeholder. When no poster
        # exists (incl. titles whose wrong match was just cleared by #20/#75),
        # point at the deterministic services/img thumbnail. hasRealArtwork stays
        # false — designed art (TMDb/Commons) still wins and outranks this floor.
        # loc: items use a different host, so skip them. Frame-extracted, face-
        # scored covers (the fancy version) need a macOS+video pipeline -> #13b.
        aid = it.get("archiveID") or ""
        if not it.get("posterURL") and aid and not aid.startswith("loc:"):
            it["posterURL"] = f"https://archive.org/services/img/{aid}"
            if not it.get("artworkSource"):
                it["artworkSource"] = "archive"
            stats["archive_thumb_filled"] += 1

    return stats


def fix_tmdb_collisions(items, stats):
    """#20, year-independent: catch wrong matches that have a CORRECT stored year
    but the WRONG poster. When several designed items share one tmdbID, the group's
    dominant confident source_year is the real film's year; a member whose own
    confident source_year differs by >=5 is matched to the wrong film (e.g. a
    'Ghost Busters (1975)' episode wearing the 1925 'Phantom of the Opera' poster).
    Requires a clear majority (>=2 agreeing) so ambiguous 2-way splits are left
    untouched — keeps false positives low (measured: ~36 groups)."""
    from collections import defaultdict, Counter
    groups = defaultdict(list)
    for it in items:
        if it.get("contentType") == "tv-series":
            continue
        if (it.get("artworkSource") or "").lower() not in ("tmdb", "omdb"):
            continue
        t = it.get("tmdbID")
        if t:
            groups[t].append(it)
    for members in groups.values():
        if len(members) < 2:
            continue
        years = [source_year(it) for it in members]
        known = [s for s in years if s is not None]
        if len(known) < 2:
            continue
        dom, domn = Counter(known).most_common(1)[0]
        if domn < 2:                      # need a trustworthy majority year
            continue
        for it, sy in zip(members, years):
            if sy is not None and abs(sy - dom) >= 5:
                _clear_wrong_artwork(it, sy)   # sy is this item's own (correct) year
                stats["tmdb_collision_fixed"] = stats.get("tmdb_collision_fixed", 0) + 1


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
    fix_tmdb_collisions(cat["items"], stats)   # #20 year-independent wrong-poster pass
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
