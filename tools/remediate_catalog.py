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
               "documentary", "newsreel", "ephemeral", "tv-special", "home-movie",
               "commercial"}

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
# A scraped uploader id left at the head of the title ("video52967: A Snack of
# the Show"). DELIBERATELY narrow to the literal `video<digits>:` form: a general
# "<digits>: " rule would eat "2001: A Space Odyssey", "1896: Director Unknown"
# and "911: the Road to Tyranny", which are real titles. Dry-run-checked against
# the live catalog — every hit is a g4tv.com scrape, no false positives.
_UPLOADER_ID_PREFIX = re.compile(r"^\s*video\d{3,}\s*:\s*", re.I)
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


# Unambiguous adult markers — safe to flag from title, subject, OR genre.
_ADULT_STRONG = re.compile(
    r"\b(erotic|erotica|nudie|sexploitation|soft\s?core|hard\s?core|pornograph"
    r"|porn|x-?rated|xxx|adults?\s+only|nudist|all naked and warm|strip\s?tease"
    r"|stag\s+film|skin\s?flick|blue\s+movie|girls\s+gone\s+wild)\b", re.I)
# Reliable only as SUBJECT/GENRE tags — too noisy in titles ("Lady of Burlesque"
# 1943 is a tame mystery; "The Naked Witch" a B-movie). An uploader who tags
# these means them. NOTE: bare "burlesque" is deliberately excluded (ambiguous).
_ADULT_SUBJECT = re.compile(
    r"\b(nudity|nude|topless|adult\s+film|adult\s+movie|softcore|sexploitation"
    r"|erotica|pornographic|striptease|playboy|playmate|penthouse)\b", re.I)
# Curated known-adult titles that evade the keyword tiers (extend as found).
# NOTE: a bare "playboy" title is NOT adult ("The Playboy of the Western World"),
# so the Playboy brand is caught by exact title here + the subject tier above.
_ADULT_TITLES = {
    "ubalda all naked and warm", "hysterical history",
    "from show girl to burlesque queen",
    "playboy after dark", "playboys penthouse", "playboy after dark complete",
}
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
    title = item.get("title") or ""
    subj_genre = " ".join((item.get("subjects") or []) + (item.get("genres") or []))
    # strong markers anywhere; soft markers only in subject/genre tags
    if _ADULT_STRONG.search(title) or _ADULT_STRONG.search(subj_genre):
        return True
    if _ADULT_SUBJECT.search(subj_genre):
        return True
    norm = re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", title.lower())).strip()
    return norm in _ADULT_TITLES


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
    elif it.get("colorMode") == "bw" and isinstance(y, int) and y >= 1970:
        # Color signal (Decision 025): a FRAME-VERIFIED black-and-white film whose
        # matched year is modern (>=1970) is a wrong match — B&W is a hard "old
        # film" signal, and modern B&W films are essentially absent from a PD
        # catalog. This catches the no-year-in-title / not-in-a-vintage-collection
        # cases the rules above miss, e.g. the 1946 Welles "The Stranger" (B&W)
        # pulling the 2025 TMDb film's poster + synopsis + year.
        wrong = True
    if not wrong:
        return None
    # Correct year: the confident source year when it's older than the suspect
    # stored year; else null and let enrichment re-resolve.
    new_y = sy if (sy is not None and (y is None or sy < y)) else None
    _clear_wrong_artwork(it, new_y)
    # B&W-vs-modern match: the stored modern year is definitely wrong and we have
    # no confident replacement, so drop it (better unknown than 2025 on a B&W film).
    if new_y is None and it.get("colorMode") == "bw":
        it["year"] = None
        it["decade"] = None
        it.pop("yearSource", None)      # don't leave a marker for a nulled year
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

# Canonical browse genres (the labels the app filters/shelves by — TMDb standard
# set + the subject-map vocab). Wikidata enrichment tagged thousands of items with
# "-film"-suffixed variants ("drama film", "crime film") that DON'T match these,
# silently fragmenting every genre filter. Collapse "X film"/"X films" -> "X" and
# bare-lowercase -> canonical, ONLY when X is canonical — subgenres ("comedy
# drama", "heist film", "giallo") and ambiguous labels ("musical film" vs the
# "Music" genre) are left untouched. Dedupe after, preserving order.
_CANON_GENRES = {
    "action", "adventure", "animation", "comedy", "crime", "documentary",
    "drama", "family", "fantasy", "history", "horror", "music", "mystery",
    "romance", "science fiction", "thriller", "war", "western",
}
_GENRE_FILM_SUFFIX = re.compile(r"\s+films?$", re.I)


def _canon_genre(g):
    base = _GENRE_FILM_SUFFIX.sub("", (g or "").strip()).strip().lower()
    return base.title() if base in _CANON_GENRES else g


def normalize_genres(it):
    gs = it.get("genres")
    if not gs:
        return False
    out, seen = [], set()
    for g in gs:
        ng = _canon_genre(g)
        if ng and ng not in seen:
            seen.add(ng)
            out.append(ng)
    if out != gs:
        it["genres"] = out
        return True
    return False


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

# IMDb-reference boilerplate the Tier-3 review surfaced as systematic (~280 items):
# a placeholder sentence pointing at IMDb (no plot), and a "From IMDb :" prefix
# pasted before a real plot. Drop the sentence; strip the prefix. (B6 finding.)
_BOILERPLATE_SENT = re.compile(
    r"you can find more information (regarding|about)"
    r"|you can read .*imdb page", re.I)
# "From IMDb :", "From IMDb:", "Taken from IMDB :" — a pasted-source prefix on a
# real plot (260 items measured). Strip the prefix, keep the plot.
_FROM_IMDB_PREFIX = re.compile(r"^\s*(taken\s+)?from\s+imdb\s*:?\s*", re.I)
_DISC_MARK = re.compile(r"\s*[\(\[]?\b(disc|disk|reel|tape)\s*\d+\b[\)\]]?", re.I)

# Synopsis cleaners (owner 2026-06-29: descriptions must contain ONLY the plot — no taglines, cast
# lists, release/runtime info, or source notes). Dry-run-validated on the live catalog: 550 cleaned,
# 0 real-plot false positives (the only nulls are non-plot metadata strings). Precision over recall.
_PRINT_AD_PAREN = re.compile(r"\(\s*print\s+ad\b[^)]*\)", re.I)
# A capitalized PLOT/SYNOPSIS/STORYLINE section HEADER (case-sensitive so mid-prose "the plot:" /
# "Cinderella storyline:" is never matched). Keep the text after the LAST header — that's the plot.
_PLOT_HEADER = re.compile(
    r"(?:^|\s)(?:Plot Summary|PLOT SUMMARY|Plot|PLOT|Synopsis|SYNOPSIS|Storyline|STORYLINE)\s*:\s*")
_WIKI_BODY_PREFIX = re.compile(r"\bfrom\s+wikipedia\b[^:]{0,40}:\s*", re.I)
_TAGLINE_CLAUSE = re.compile(r'\bTaglines?\s*:\s*("[^"]*"|[^|]*?(?:[.!?](?:\s|$)|\s*\||$))', re.I)
_TAGLINE_GREEDY = re.compile(r"\bTaglines?\s*:\s*.*$", re.I | re.S)
_IMDB_TAIL = re.compile(
    r"\b(here'?s the imdb page\.?|information regarding this film[^.]*imdb[^.]*\.?)\s*$", re.I)
# IMDb-prefixed trailing dumps (a SECOND tagline list, trivia, user reviews) — cut to end. Require an
# IMDb/numbered-list anchor so prose "storyline:" is never matched.
_TRAIL_CRUFT = re.compile(
    r"\s*(?:[-_]+\s*IMDb\b.*|\bIMDb\s+(?:User\s+Review|Trivia|Storylines?)\b.*"
    r"|STORYLINES?\s*:\s*0?1\).*|information regarding this film.*?imdb.*"
    r"|more information on wikipedia.*|here'?s the imdb page.*)$", re.I | re.S)
# Pipe-delimited structured field (`| Cast: ... |`) — only the table form, never prose.
_PIPE_FIELD = re.compile(
    r"\|\s*(?:cast|starring|director|directed by|writer[s]?|producer[s]?|studio|genre[s]?|runtime|"
    r"run\s*time|countr(?:y|ies)|language[s]?|release\s*date|aspect\s*ratio|format|certificate|"
    r"sound\s*mix|color)\s*:[^|]*", re.I)
# A LEADING spec dump (Runtime:/Country:/Language:/... fields before any prose).
_LEAD_SPEC = re.compile(
    r"^(?:\s*(?:runtime|run\s*time|countr(?:y|ies)|language[s]?|release\s*date|aspect\s*ratio|"
    r"format|certificate|sound\s*mix|color|genre[s]?)\s*:[^|.]*?(?:\||\s{2,}|(?=[A-Z][a-z]+\s*:)))+",
    re.I)


def _extract_plot_body(s):
    """Strip non-plot cruft from a synopsis, preferring a labeled Plot:/Wikipedia: body. Returns the
    cleaned string (caller applies the MIN_SYNOPSIS null-out). Validated for zero false positives."""
    s = _PRINT_AD_PAREN.sub(" ", s)
    extracted = False
    headers = list(_PLOT_HEADER.finditer(s))
    if headers and len(s) - headers[-1].end() >= MIN_SYNOPSIS:
        s = s[headers[-1].end():]; extracted = True
    else:
        m = _WIKI_BODY_PREFIX.search(s)
        if m and len(s) - m.end() >= MIN_SYNOPSIS:
            s = s[m.end():]; extracted = True
    s = _TRAIL_CRUFT.sub("", s)
    s = _PIPE_FIELD.sub(" ", s)
    if not extracted:
        s2 = _LEAD_SPEC.sub("", s)
        if len(s2) >= MIN_SYNOPSIS:
            s = s2
        s = _TAGLINE_GREEDY.sub(" ", s)   # promotional tagline runs to end when no labeled plot follows
        s = _IMDB_TAIL.sub("", s)
    return re.sub(r"\s*\|\s*", " ", s)

# Slash-delimited format dump (the ptp_ collection's title style):
#   "The Love Nest / Blu-ray / / MKV / / Remux / Buster Keaton"
#   "Anna Christie / John Griffith Wray / Thomas H. Ince / DVD"
# The real title is the FIRST " / "-segment; the rest are format/source/credit
# annotations. Only collapse to the first segment when a LATER segment is a
# known format/container token (or empty) — so a legit "A / B" title that has
# no format token is never touched. 520 titles measured.
_FMT_TOKEN = re.compile(
    r"^(blu-?ray|dvd\d?|vhs|avi|mkv|mp4|mov|m4v|ogv|remux|web-?rip|br-?rip|"
    r"hdtv|x26[45]|h\.?26[45]|hevc|xvid|divx|aac|ac3|\d{3,4}x\d{3,4}|"
    r"\d{3,4}p|2160p|4k|hd)$", re.I)


# Trailing quality/format annotation on an otherwise-good title:
#   "The General (1926) HD with Score" / "The Stranger ( HD)" / "Last Man on
#   Earth-hd" / "Frankenstein (1931) English FULL HD".
# Strips trailing format/quality tokens ONLY — deliberately NOT colorized /
# restored / remastered (those are meaningful version markers a viewer chooses
# between). Word-boundaried; only runs when a token actually matched; never
# strips trailing periods/closers (so "Steamboat Bill, Jr." / "Crime, Inc." are
# untouched). 98 titles measured, 0 false positives.
_QUAL_TOK = (r"\b(full\s*hd|hi-?def|hd|blu-?ray|dvd-?rip|dvd|vhs-?rip|vhs|"
             r"web-?rip|br-?rip|hdtv|widescreen|1080p|720p|480p|2160p|4k|"
             r"with\s+(?:new\s+)?score)\b")
_QUAL_TAIL = re.compile(
    r"(?:\s*[-–—|.(\[]\s*" + _QUAL_TOK + r"\s*[)\]]?|\s+" + _QUAL_TOK +
    r"\s*[)\]]?)+\s*$", re.I)
_QUAL_DANGLE = re.compile(r"\s*[-–—|(\[]\s*$")  # opener/sep left behind, not periods/closers


def _strip_quality_tail(t):
    nt = _QUAL_TAIL.sub("", t)
    if nt == t:
        return t
    return _QUAL_DANGLE.sub("", nt).rstrip()


# Owner directive (2026-07-20): a title must be ONLY the film title — nothing about
# video quality, version, or "full movie" packaging. This REVERSES the earlier
# choice to keep colorized/restored/remastered as "version markers" (_QUAL_TAIL
# above): those ARE quality metadata and are now stripped. Matches a trailing RUN
# of version/packaging tokens, bare or separator-joined ("Stagecoach colorized",
# "… widescreen & quality upgrade.", "… - Film Noir Full Movie", "… - mp4 version").
# Trailing-only ($) + known tokens + _keep_if_lettered guard = a real title whose
# last word merely resembles one of these is never emptied; dry-run-checked for FPs.
_VERSION_TOK = (
    r"\b(?:colou?ri[sz]ed|colou?ri[sz]ation|restored|restoration|remastered|remaster|"
    r"uncut|uncensored|unedited|upscaled|ai[\s-]?upscaled|upscale|enhanced|"
    r"(?:video|image|picture|sound|audio|hd|full[\s-]?hd)[\s-]?quality(?:[\s-]?upgrades?)?|"
    r"high[\s-]?quality|hq[\s-]?version|quality[\s-]?upgrades?|new[\s-]?transfer|"
    r"new[\s-]?scan|new[\s-]?restoration|full[\s-]?movie|full[\s-]?film|"
    r"full[\s-]?length|feature[\s-]?length|complete[\s-]?film|complete[\s-]?version|"
    r"mp4[\s-]?version|digitally[\s-]?remastered|ipod[\s-]?version|"
    r"widescreen[\s-]?version|english[\s-]?sub(?:s|title|titles)?|vose|vosi|"
    r"subtitulad[oa])\b")
_VERSION_TAIL = re.compile(
    r"(?:\s*[-–—|,&/]+\s*" + _VERSION_TOK + r"|\s+" + _VERSION_TOK + r")+\s*\.?\s*$",
    re.I)
_VERSION_DANGLE = re.compile(r"\s*[-–—|,&/(\[]\s*$")
# A trailing parenthetical/bracket whose FIRST token is a version/quality word —
# "Notorious (restored)", "(Widescreen 1954)", "(colorized, uncut)". The _VERSION_TAIL
# separator class deliberately excludes '(' (so a mid-title paren is safe); this catches
# the paren case explicitly, only when the paren LEADS with a version word (extra words
# like a year inside are swept with it). Behind _keep_if_lettered.
_VERSION_PAREN = re.compile(
    r"\s*[\(\[]\s*(?:colou?ri[sz]ed|restored|remastered|remaster|widescreen|uncut|"
    r"uncensored|hd|hq|full\s*hd|1080p|720p|480p|4k|english\s+sub\w*|vose|"
    r"digitally\s+remastered|quality\s+upgrade|video\s+quality)\b[^)\]]*[\)\]]\s*$",
    re.I)


def _strip_version_tail(t):
    # Iterate: stripping one trailing version token can expose another that was not
    # trailing before ("… widescreen & quality upgrade" -> "… widescreen" -> "…"),
    # interleaving the existing format/quality tail (_QUAL_TAIL: widescreen/hd/dvd…).
    for _ in range(6):
        nt = _VERSION_PAREN.sub("", t).rstrip()
        nt = _VERSION_DANGLE.sub("", _VERSION_TAIL.sub("", nt)).rstrip()
        nt = _strip_quality_tail(nt)
        if nt == t:
            break
        t = nt
    return t


# Uploader cruft: site tags / handles / file extensions an uploader stamped onto
# the title ("Romance (1983) Musical Love Story { Brego}", "...HEVCBay.com",
# "FAASLE 1985@malikjee", "Tapasya 1976 ... .avi"). Conservative + per-pattern:
#   - curly-brace tokens ONLY when they contain a handle/URL ('{ Brego}',
#     '{www.desibbrg.com}') — NOT meaningful braces like '{The Whistler}' (series)
#   - explicit site/handle tokens (.com/.net/.org domains, @handles, the known
#     desi-upload signatures) — deliberately NOT '.in' (collides with the word "in")
#   - trailing file extensions
# Only cleans dangling separators when something was removed; never strips
# trailing periods/closers (abbreviations) and never nukes a title to empty.
_JUNK_BRACE = re.compile(
    r"\s*\{[^}]*(brego|www\.|https?://|\.com|\.net|desibbrg|xclusives)[^}]*\}", re.I)
_SITE_TAG = re.compile(
    r"\s*(?:@\s*\S+|\bwww\.\S+|\b\S+\.(?:com|net|org|tv|pe|me)\b|\bda\s?xclusives\b|"
    r"\bhevcbay\b|\bamaderforum\b|\bdesibbrg\b|\bbrego\b|"
    r"\b(?:rarbg|yify|yts|ettv|eztv|galaxyrg|ntg)\b)", re.I)
_TITLE_EXT = re.compile(r"\.(avi|wmv|flv|mpg|mpeg|mov|m4v|mp4|mkv|ogv|mxf)\s*$", re.I)
# A trailing timecode / frame-count run an uploader left in the title ("… 01 00 45 10",
# "… 18 20 31") — 3+ space/underscore-separated two-digit groups at the end. Real titles never
# end this way; _keep_if_lettered guards it so a result without letters is rejected.
_TIMECODE_TAIL = re.compile(r"[ _]\d{2}(?:[ _]\d{2}){2,}\s*$")
# A QID ("Q3992547") or bare imdb id ("tt0403058") that leaked in as the whole title — never a real
# title (Decision 046 unresolved). Replaced with a slug derived from the archiveID.
_RAW_ID_TITLE = re.compile(r"^(?:Q\d+|tt\d+)$", re.I)


def _title_from_archiveid(aid):
    """A human-ish title slug from an archiveID for QID/junk-titled items: drop a leading reel/
    sequence number + a trailing timecode run, words from underscores/dashes."""
    s = re.sub(r"[._-]+", " ", aid or "").strip()
    s = re.sub(r"^\d{2,5}\s+", "", s)              # leading reel/sequence number
    s = _TIMECODE_TAIL.sub("", s)                  # trailing timecode run
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _strip_uploader_cruft(t):
    nt = _JUNK_BRACE.sub("", t)
    nt = _SITE_TAG.sub("", nt)
    nt = _TITLE_EXT.sub("", nt)
    if nt == t:
        return t
    nt = re.sub(r"\s+", " ", nt)
    nt = re.sub(r"[\s~\-–—|,]+$", "", nt)       # dangling sep, not '.'/')'
    nt = re.sub(r"^[\s~\-–—|,.]+", "", nt).strip()
    return nt if len(nt) >= 2 else t


# Filename-style title: underscores as word separators with NO spaces present
# ("St_Martins_Lane" -> "St Martins Lane", "Sita_Sings_the_Blues" ->
# "Sita Sings the Blues"). Only fires on pure-filename titles (no spaces, an
# underscore between word chars) so a title that already reads normally is never
# touched. Also un-inverts a trailing sort-article suffix ("Rawhide_Terror_The"
# -> "The Rawhide Terror").
def _underscore_filename(t):
    if " " in t or "_" not in t or not re.search(r"\w_\w", t):
        return t
    s = re.sub(r"_+", " ", t).strip()
    m = re.match(r"^(.*\S)\s+(The|A|An)$", s)
    if m:
        s = m.group(2) + " " + m.group(1)
    return s


# Sort-title comma inversion ("Little Princess, The" -> "The Little Princess",
# "Farewell to Arms, A" -> "A Farewell to Arms"). The trailing ", The/A/An" is an
# unambiguous library sort convention; require non-empty body so it can't empty a
# title. 126 measured.
_SORT_ART = re.compile(r"^(.+?)\s*,\s*(the|a|an)\s*$", re.I)


def _invert_sort_article(t):
    m = _SORT_ART.match(t)
    if m and m.group(1).strip():
        return m.group(2).capitalize() + " " + m.group(1).strip()
    return t


def _strip_format_dump(t):
    if " / " not in t:
        return t
    segs = [s.strip() for s in t.split(" / ")]
    if len(segs) < 2 or not segs[0]:
        return t
    if any((not s) or _FMT_TOKEN.match(s) for s in segs[1:]):
        return segs[0]
    return t


# Source/transfer specs the uploader appended to the title that _strip_format_dump
# (which only handles " / "-delimited dumps) misses (#3, 275 measured):
#   - a trailing parenthetical that contains a pixel RESOLUTION — the whole paren is
#     transfer metadata (runtime + WxH + subtitle/colour note):
#       "1941 - Stukas (1h 31m, 512x384, CZ Untertitel)" -> "1941 - Stukas"
#   - a bare trailing resolution: "The White Sister 716x480" -> "The White Sister"
#   - a trailing run of container/codec/quality tokens (incl. containers the
#     quality-tail rule omits): "The First Auto (1927) DVD MKV" -> "The First Auto (1927)"
# Only touches trailing punctuation when a format token was actually removed, so
# titles without source cruft are never altered.
_RES_PAREN = re.compile(r"\s*[\(\[][^)\]]*\b\d{2,4}x\d{2,4}\b[^)\]]*[\)\]]\s*$")
_RES_BARE  = re.compile(r"\s*\b\d{2,4}x\d{2,4}\b\s*$")
_CONTAINER_TAIL = re.compile(
    r"(?:\s*[-–—|,]?\s*\b(?:dvd|vhs|mkv|mp4|avi|m4v|ogv|x26[45]|h\.?26[45]|hevc|xvid|divx|"
    r"bluray|blu-?ray|web-?rip|br-?rip|hdtv|dvd-?rip|720p|1080p|480p|576p|2160p|4k)\b[\s,)\]]*)+$",
    re.I)


def _strip_source_specs(t):
    nt = _RES_PAREN.sub("", t)
    nt = _RES_BARE.sub("", nt)
    nt = _CONTAINER_TAIL.sub("", nt)
    if nt == t:
        return t
    nt = re.sub(r"\s+", " ", nt).strip()
    nt = re.sub(r"[\s\-–—|,]+$", "", nt)
    return nt if len(nt) >= 2 else t


# --- Broader artifact strips (year / runtime / size / language / uploader note) ---
# The audit found MANY titles still carrying the YEAR and other file metadata that a
# viewer reads as part of the title. The app shows the year as its OWN field on Detail
# and in lists, so a parenthesised/leading year in the title is redundant noise — strip
# it. Every strip keeps letters in the result (never empties a title) and only fires when
# it actually changed something (titles without the artifact are untouched).

# Leading "1937 - " upload prefix (common on foreign scene rips:
# "1937 - You Only Live Once - ... - Fritz Lang - VOSE").
_LEAD_YEAR = re.compile(r"^\s*(?:19|20)\d{2}\s*[-–—.]\s+")
# Trailing parenthesised/bracketed year: "Carnival of Souls (1962)" -> "Carnival of Souls".
_TRAIL_YEAR = re.compile(r"\s*[\(\[]\s*(?:19|20)\d{2}\s*[\)\]]\s*$")
# A parenthetical that LEADS with a 4-digit year — a release-year stamp, often carrying uploader
# genre/credit junk ("(1940 Film Noir, Thriller, Hitchcock)") — stripped wherever it sits, not just
# as a bare trailing "(year)". Safe: a real title doesn't open a paren with its own release year.
# ("Westfront 1918 (1930)" -> "Westfront 1918"; the bare in-title 1918 is left alone.)
_PAREN_LEADING_YEAR = re.compile(r"\s*[\(\[]\s*(?:18[7-9]\d|19\d\d|20[0-2]\d)\b[^)\]]*[\)\]]")
# Same, but UNCLOSED to end-of-string — uploaders routinely drop the close paren ("Owd Bob (1995 UK",
# "… (1945, Dir: Fritz Lang, noir"). Trailing-only + year-led so a bare in-title year is never hit.
_TRAIL_OPEN_YEAR = re.compile(r"\s*[\(\[]\s*(?:18[7-9]\d|19\d\d|20[0-2]\d)\b[^)\]]*$")
# A parenthetical that is purely a language / subtitle / dub tag: "(ENG sub)", "(VOSE)".
_LANG_PAREN = re.compile(
    r"\s*[\(\[]\s*(?:eng(?:lish)?|fre(?:nch)?|spa(?:nish)?|ita(?:lian)?|ger(?:man)?|por|rus)?\s*"
    r"(?:sub(?:title)?s?|dub(?:bed)?|vose|legendado|subtitulad[oa])\b[^)\]]*[\)\]]", re.I)
# A trailing uploader CREDIT clause: "… directed by X" / "… a film by Y" / "… Dir: Z" / "… starring W".
# Anchored to the END with required following text, so a bare word ("The Director") is never hit;
# _keep_if_lettered protects a title that IS a credit ("Directed by John Ford").
_CREDIT_TAIL = re.compile(
    r"\s*[-–—,]?\s*(?:directed by|a film by|dir\.?\s*(?:by|:)|director|starring|"
    r"featuring|feat\.?|with cast|cast:)\s+\S.*$", re.I)
# Uploader credits packed into the title with PIPE separators ("Title |Fritz Lang| Glenn Ford …"):
# a "|" is essentially never in a real film title, so everything from the first "|" is credits.
_PIPE_CREDITS = re.compile(r"\s*\|.*$", re.S)
# Trailing parenthetical that is a CAST/credit/alt-title/version list — a paren or bracket
# containing a comma, sitting at the very end ("Sie Und Die Drei( Hans Söhnker, Curt Vespermann)",
# "Frankenstein 1931 (Colin Clive, Boris Karloff)", "(restored, uncut)"). The comma is the tell:
# a primary film title is almost never "X (A, B)". Applied behind _keep_if_lettered, so a result
# without letters is rejected. Cast/alt-title/version notes are not the primary title — they live
# in dedicated fields (cast/year) everywhere in the app.
_CAST_PAREN = re.compile(r"\s*[\(\[]\s*[^)\]]*,[^)\]]*[\)\]]\s*$")
# Public-domain-fairy-tale KNOCK-OFF studios. These labels (in the title) only ever made cheap
# PD cartoon knock-offs, so a title-only matcher mapping them to the MAJOR studio film of the
# same name is always wrong — "Beauty En Het Beest (VHS, Bevanfield, Dutch)" got Disney's
# tt0101414/Gary Trousdale/502k-vote poster. Unambiguous studio names (never real film titles);
# "Films" required on Burbank/Golden so a generic word can't trip it.
_KNOCKOFF_LABEL = re.compile(
    r"\b(bevanfield|foxbridge|burbank films|golden films|goodtimes|"
    r"jetlag productions|dingo pictures)\b", re.I)
# Uploader title cruft that no real title contains: star ratings (★★★ / ☆) and closed-caption
# markers ("(CC)" / "[CC]" / "CC:"). Stripped anywhere, behind _keep_if_lettered.
_STAR_RATING = re.compile(r"[★✦⭐☆⭑✩✫✬✭]+")
_CC_MARK = re.compile(r"\s*(\(\s*cc\s*\)|\[\s*cc\s*\]|\bcc:)\s*", re.I)
# Trailing genre/format descriptor an uploader tacked on after a dash/comma ("Human Desire -
# Film Noir", "… , Comedy"). Only the FINAL segment and only KNOWN descriptors, so real subtitles
# ("First Blood - Part II") survive; applied behind _keep_if_lettered.
_GENRE_TAIL = re.compile(
    r"\s*[-–—,]\s*(?:film[ -]?noir|drama|comedy|romance|western|horror|sci[- ]?fi|"
    r"science fiction|thriller|mystery|documentary|adventure|musical|war film|crime|"
    r"fantasy|silent film|b[- ]?movie|classic film|full movie)\s*$", re.I)
# Trailing foreign subtitle/dub markers from scene rips ("- VOSE", "- Legendado", "ESub").
_LANG_TAIL = re.compile(
    r"(?:\s*[-–—|]\s*(?:vose|vosi|vos|vo|legendado|subtitulado|castellano|espa[nñ]ol|"
    r"latino|dublado|dubbed|sub\s*esp|esub|hq\s*line\s*audio)\b)+\s*$", re.I)
# Trailing runtime stamp: a BRACKETED time ("[1:01:37", "{HD 1:42:23}") or a bare
# full H:MM:SS ("Steamboat Willie 1:05:50"). A bare 2-part M:SS is NOT stripped — it
# can be part of a real title ("At 3:25").
_RUNTIME_STAMP = re.compile(
    r"\s*(?:[\(\[{]\s*(?:hd\s*)?\d{1,2}:\d{2}(?::\d{2})?\s*[\)\]}]?"
    r"|(?:hd\s+)?\d{1,2}:\d{2}:\d{2})\s*$", re.I)
# Trailing file size / fps paren: "(1.4GB)", "(18 FPS)", "(750 MB)".
_SIZE_FPS = re.compile(r"\s*[\(\[]\s*[\d.]+\s*(?:gb|mb|fps)\s*[\)\]]\s*$", re.I)
# Rip/scan/source words the container-tail rule omits (separators may be space/dot/dash).
_RIP_TAIL = re.compile(
    r"(?:\s*[-–—|,.]?\s*\b(?:dvd[\s.-]?rip|dvd[\s.-]?scr|bd[\s.-]?rip|br[\s.-]?rip|web[\s.-]?dl|"
    r"hd[\s.-]?rip|cam[\s.-]?rip|dvd[\s.-]?iso|dvd[\s.-]?mkv|iso|scan|remux)\b\s*)+$", re.I)
# Trailing underscore sort-article ("Colonel Blimp_The" -> "The ... Colonel Blimp")
# and uploader notes ("Spooks Run Wild_Weirdness bad Movie", "_no subtitle").
_USCORE_ARTICLE = re.compile(r"^(.+?)_(the|a|an)$", re.I)
_USCORE_NOTE = re.compile(
    r"_\s*(?:weirdness\b.*|[^_]*\bbad movie\b.*|no\s*subtitle.*|persian\b.*|"
    r"updated\b.*|[^_]*\bupgrade\b.*)$", re.I)


def _keep_if_lettered(nt, t):
    """Adopt nt only if it still has a LETTER in any script (never empty a title to
    junk). `[^\\W\\d_]` matches any Unicode letter — Latin, Greek, Cyrillic, CJK — so a
    non-Latin title (e.g. 'Η ζαβολιάρα') isn't wrongly reverted by an ASCII-only check."""
    return nt if (nt and re.search(r"[^\W\d_]", nt)) else t


def _strip_leading_year(t):
    # Strip repeatedly so a leading year RANGE ("1940 - 1945 - Eva Braun …") is fully
    # removed, not just its first year.
    nt = t.strip()
    while True:
        s = _LEAD_YEAR.sub("", nt).strip()
        if s == nt:
            break
        nt = s
    return _keep_if_lettered(nt, t)


def _strip_leading_year_field(t, year):
    # A bare leading 4-digit year (no dash separator, so _strip_leading_year misses it)
    # is stripped ONLY when it EQUALS the item's own year field — precise, never a guess,
    # so "2001 A Space Odyssey" / "1917" / "1941" are safe unless the year field actually
    # matches. ("1935 Sie Und Die Drei" with year 1935 -> "Sie Und Die Drei".)
    if not year:
        return t
    m = re.match(r"^\s*" + str(year) + r"\b[ .\-–—]+(.+)$", t)
    if m and re.search(r"[A-Za-z]", m.group(1)):
        return _keep_if_lettered(m.group(1).strip(), t)
    return t


def _strip_trailing_year(t):
    # Allow a bare alphanumeric remainder (incl. a number) — a title that IS a year,
    # e.g. "1984 (1984)" -> "1984", is real, not junk.
    nt = _TRAIL_YEAR.sub("", t).rstrip()
    return nt if (nt and re.search(r"[^\W_]", nt)) else t


def _truncate_at_year_field(t, year):
    # The item's own year as the TITLE/CRUFT BOUNDARY: 'Real Title YYYY <cruft>' -> 'Real Title'.
    # The single most common uploader pattern for unmatched films (the mid-string year is followed by
    # ratings/CC/genre/cast). Precise: only the item's OWN year, only when real title text precedes
    # it; a date-range ('… 1945 to 1946 …') is skipped so it isn't truncated mid-range. (Matched
    # films never reach here — they adopt the canonical title.)
    if not year:
        return t
    m = re.search(r"^(.+?)\s+" + str(year) + r"\b(.+)$", t)
    if not m:
        return t
    before = m.group(1).strip()
    if not re.search(r"[A-Za-z]", before):
        return t
    if re.search(r"(?:18|19|20)\d\d\s*$", before):     # 'Berlin 1945 to 1946 …' → leave it
        return t
    # When the year COMPLETES a phrase ('Amazing China in 1917 in color', 'Wonderful Berlin in
    # 1927') it's part of the descriptive title, not a boundary — the text before it ends in a
    # preposition/article/conjunction. Don't truncate those (travelogue/amateur-film naming).
    if re.search(r"(?i)\b(in|of|the|a|an|to|from|and|or|at|on|during|for|with|year|no|vol|part|chapter|by|circa|around)$", before):
        return t
    return _keep_if_lettered(before, t)


def _strip_trailing_year_field(t, year):
    # A bare trailing 4-digit year (no parens, so _strip_trailing_year misses it) is
    # stripped ONLY when it EQUALS the item's own year field — precise, never a guess,
    # so "Blade Runner 2049" / "Space 1999" / "Class of 1984" survive unless the year
    # field actually matches. ("Bombay Talkie 1970" with year 1970 -> "Bombay Talkie".)
    if not year:
        return t
    # Capture ANY trailing 4-digit year, then keep it only if it's within ±2 of the item's own
    # year field — a real release-year stamp (uploader years often disagree with TMDb's by a
    # year, e.g. "Chhoti Si Baat 1975" with field 1976), while a number that's PART of the title
    # ("Blade Runner 2049" field 2017, "Space 1999") is far off and survives.
    m = re.match(r"^(.+?)[ .\-–—]+((?:18|19|20)\d\d)\s*$", t)
    if not m or not re.search(r"[A-Za-z]", m.group(1)):
        return t
    if abs(int(m.group(2)) - year) > 2:
        return t
    head = m.group(1).strip()
    # Don't split a date RANGE ("… 1939-1941" with year 1941 -> a dangling "… 1939")
    # or a title that genuinely ends in a 4-digit number — bail if the remainder
    # itself ends in a year.
    if re.search(r"(?:18|19|20)\d\d$", head):
        return t
    # When the year completes a PHRASE ("Class of 1984", "Summer of 1942"), it IS the title —
    # the preceding word is a preposition/article. Only strip a year that trails a COMPLETE
    # title ("Chhoti Si Baat 1975").
    if re.search(r"\b(of|the|a|an|in|to|for|from|at|on|and|or|no|year)$", head, re.I):
        return t
    return _keep_if_lettered(head, t)


def _strip_lang_tail(t):
    return _keep_if_lettered(_LANG_TAIL.sub("", t).rstrip(" -–—|"), t)


def _strip_runtime_size(t):
    nt = _SIZE_FPS.sub("", t)
    nt = _RUNTIME_STAMP.sub("", nt)
    nt = _RIP_TAIL.sub("", nt)
    if nt == t:
        return t
    nt = re.sub(r"\s+", " ", nt).rstrip(" -–—|,")
    return _keep_if_lettered(nt, t)


def _strip_uscore_suffix(t):
    if "_" not in t:
        return t
    m = _USCORE_NOTE.search(t)
    if m:
        t = _keep_if_lettered(t[:m.start()].strip(), t)
    m = _USCORE_ARTICLE.match(t)
    if m and m.group(1).strip():
        t = m.group(2).capitalize() + " " + m.group(1).strip().replace("_", " ")
    return t


def _is_human_caption(c):
    return c.get("source") != "archive-asr" and "(auto)" not in (c.get("label") or "")


def drop_asr_captions(items):
    """archive.org auto-ASR captions (label 'English (auto)', source 'archive-asr')
    are hallucinated word-salad on the catalog's old-film audio — the SAME failure
    that retired whisper (Decision 039b: auto speech-to-text is not shippable, a wrong
    subtitle is worse than none). Drop them; keep human/uploader captions (SubDL,
    SubSource, uploader .srt). Reversible: re-running enrich refills only human subs.

    ALSO clears an orphaned `subtitleHLS` (the Apple HLS subtitle track): when an item's
    auto caption was already burned into an HLS rendition, dropping the caption left the
    HLS still serving the hallucinated subtitle, which the Apple apps play. If no human
    caption remains, the HLS is stale — drop it too. Returns (captions_dropped, hls_cleared)."""
    dropped = 0
    hls_cleared = 0
    for it in items:
        caps = it.get("captions") or []
        if caps:
            kept = [c for c in caps if _is_human_caption(c)]
            if len(kept) != len(caps):
                dropped += len(caps) - len(kept)
                it["captions"] = kept or None
        # An HLS subtitle track with no surviving HUMAN caption is the orphaned auto track.
        if it.get("subtitleHLS") and not any(_is_human_caption(c) for c in (it.get("captions") or [])):
            it.pop("subtitleHLS", None)
            hls_cleared += 1
    return dropped, hls_cleared


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
    s = _extract_plot_body(s)          # drop taglines/cast/release/source cruft, prefer a labeled plot
    s = _FROM_IMDB_PREFIX.sub("", s)   # "From IMDb : <plot>" -> "<plot>" (B6)
    sents = [x for x in _SENT_SPLIT.split(s)
             if not (_audit.URL.search(x) or _audit.SOCIAL.search(x)
                     or _audit.EMAIL.search(x) or _audit.UPLOADER.search(x)
                     or _audit.TECH.search(x) or _BOILERPLATE_SENT.search(x))]
    s = re.sub(r"\s+", " ", " ".join(sents)).strip()
    if s == raw:
        return None
    if len(s) < MIN_SYNOPSIS:
        it["synopsis"] = None
        it["synopsisSource"] = None
        return "nulled"
    it["synopsis"] = s
    return "cleaned"


def _norm_words(s):
    return [w for w in re.split(r"[^0-9a-z]+", (s or "").lower()) if w]


def _canonical_clean(it):
    """The AUTHORITATIVE title (TMDb/OMDb `canonicalTitle`) to ADOPT over the uploader title — but
    only when it's clearly a clean version of what the uploader typed: every significant word of the
    canonical appears in the uploader title (the uploader title = the real title + appended cruft).
    This guards against a wrong match injecting a wrong title, and is the principled fix (Decision
    046) for long uploader titles like "The Web Ella Raines, Edmond O'Brien, …" → "The Web". Returns
    the canonical string to use, or None to fall through to regex cleaning."""
    c = (it.get("canonicalTitle") or "").strip()
    if not c:
        return None
    cn = _norm_words(c)
    un = set(_norm_words(it.get("title") or ""))
    if not cn:
        return None
    if len(cn) >= 2 and set(cn).issubset(un):   # multi-word canonical fully present → adopt
        return c
    if len(cn) == 1 and _norm_words(it.get("title") or "") == cn:   # already that single word
        return c
    return None


def _audited_clean(it):
    """An LLM-audited title (`auditedTitle`) to ADOPT for items with NO external id, where
    canonical + regex can't reach the real title (actor names glued mid-title, description-
    titles). Trusted but GUARDED against hallucination: every word of the audited title must
    appear in the uploader title — the audit may only REMOVE text (strip actors/quality/
    description), never invent or rename to an AKA. A rename would fail this and fall through."""
    a = (it.get("auditedTitle") or "").strip()
    if not a:
        return None
    an = _norm_words(a)
    if not an:
        return None
    un = set(_norm_words(it.get("title") or ""))
    if set(an).issubset(un):
        return a
    return None


def sanitize_title(it):
    raw = (it.get("title") or "").strip()
    if not raw:
        return False
    # UNIFIED TITLE RESOLUTION (Decision 046): a matched film's title should BE its authoritative
    # canonical title, not a regex-cleaned uploader string — adopt it when it's a clean version of
    # the uploader title (guarded), else fall through to the cleaning chain below for unmatched films.
    canon = _canonical_clean(it) or _audited_clean(it)
    if canon:
        if canon != raw:
            it["title"] = canon
            return True
        return False
    # A QID / bare-imdb-id title is never real — derive a slug from the archiveID (match_unmatched
    # may later upgrade it to a canonical title; until then a readable slug beats "Q3992547").
    if _RAW_ID_TITLE.match(raw):
        slug = _title_from_archiveid(it.get("archiveID") or "")
        if len(slug) >= 3 and re.search(r"[A-Za-z]", slug):
            it["title"] = slug
            return True
        return False
    t = _fix_mojibake(_html.unescape(raw))
    t = _keep_if_lettered(_UPLOADER_ID_PREFIX.sub("", t), t)   # leading scraped "videoNNNNN:" id
    t = _keep_if_lettered(_TIMECODE_TAIL.sub("", t), t)   # trailing timecode run an uploader left in
    t = _strip_format_dump(t)
    t = _strip_source_specs(t)
    t = _strip_runtime_size(t)        # file size / fps / runtime stamp / rip words
    t = _strip_quality_tail(t)
    t = _keep_if_lettered(_strip_version_tail(t), t)   # colorized/restored/full movie/mp4 version …
    # Star ratings + closed-caption markers an uploader stuck in the title ("… ★★★ CC: …", "(CC)").
    t = _keep_if_lettered(_STAR_RATING.sub(" ", t), t)
    t = _keep_if_lettered(_CC_MARK.sub(" ", t), t)
    t = _strip_uploader_cruft(t)
    t = _strip_lang_tail(t)           # trailing foreign sub/dub marker (VOSE / Legendado …)
    # Pipe-delimited uploader credits ("Title |Director| Cast - Genre") → keep only the real title.
    t = _keep_if_lettered(_PIPE_CREDITS.sub("", t).rstrip(" -–—,|"), t)
    # Trailing genre descriptor ("… - Film Noir") an uploader appended (known descriptors only).
    t = _keep_if_lettered(_GENRE_TAIL.sub("", t).rstrip(" -–—,|"), t)
    # Trailing cast/credit/alt-title parenthetical ("Title( Actor, Actor)") — the comma is the tell.
    t = _keep_if_lettered(_CAST_PAREN.sub("", t).rstrip(" -–—,|"), t)
    # Trailing " - Director Name" on scene-rip dash dumps, but ONLY when it matches the
    # item's OWN director field — precise, never a guess. ("… - Earl McEvoy" -> "…").
    director = (it.get("director") or "").strip()
    if director and len(director) > 3 and "-" in t:
        nt = re.sub(r"\s*[-–—|]\s*" + re.escape(director) + r"\s*$", "", t, flags=re.I).rstrip(" -–—|")
        t = _keep_if_lettered(nt, t)
    # Uploader credit clause ("… directed by X" / "… starring Y") — generic, not tied to the item's
    # own director field, so it catches the "(1913) director Victor Sjöström" collection style.
    t = _keep_if_lettered(_CREDIT_TAIL.sub("", t).rstrip(" -–—,|"), t)
    # Genre/credit removal can expose a version token that was not trailing before
    # ("… - Film Noir Full Movie" -> "… - Film Noir" -> "…"): strip once more.
    t = _keep_if_lettered(_strip_version_tail(t), t)
    t = _strip_uscore_suffix(t)       # "Title_The" / "Title_Weirdness bad Movie"
    t = _underscore_filename(t)
    t = _invert_sort_article(t)
    # A title that is ENTIRELY bracketed ("[Amateur film: New Orleans Carnival]")
    # is the Prelinger amateur-film naming — UNWRAP it (blanket bracket-stripping
    # would empty it, so it was being left bracketed). Then strip inner/partial
    # bracketed junk.
    m = re.match(r"^\s*\[(.+)\]\s*$", t)
    if m:
        t = m.group(1).strip()
    t = _audit.T_BRACKET.sub(" ", t)
    t = _audit.T_RES.sub(" ", t)
    # Drop "(Disc 2)"/"Reel 5"/"(Tape 1)" volume markers when real text remains.
    disc_stripped = _DISC_MARK.sub(" ", t)
    if re.search(r"[A-Za-z]", disc_stripped):
        t = disc_stripped
    # The year is its own field everywhere in the app — strip it from the title last,
    # after quality/rip/bracket strips have peeled off whatever followed it. A paren that LEADS
    # with a year (incl. genre junk, or a year-paren followed by another paren) goes first, then
    # the bare leading/trailing year forms.
    t = _keep_if_lettered(_PAREN_LEADING_YEAR.sub(" ", t), t)
    t = _keep_if_lettered(_TRAIL_OPEN_YEAR.sub("", t), t)
    t = _keep_if_lettered(_LANG_PAREN.sub(" ", t), t)
    t = _truncate_at_year_field(t, it.get("year"))   # 'Real Title YYYY <cruft>' -> 'Real Title'
    t = _strip_leading_year(t)
    t = _strip_leading_year_field(t, it.get("year"))
    t = _strip_trailing_year(t)
    t = _strip_trailing_year_field(t, it.get("year"))
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


# --- Overt hate propaganda / CSAM-advertising uploads -----------------------
# archive.org hosts modern propaganda alongside public-domain film, and a few
# such uploads reached the catalog with contentType='feature-film' and no adult
# flag, so they were fully browsable. These are not PD films and have no place
# in a cinematheque app.
#
# WORD-BOUNDARY matching is mandatory here: a naive substring test for "pedo"
# matches TORPEDO and would have excluded eight legitimate films (Torpedo
# Flotilla Visit to Manchester, "Secret Agent X-9: Torpedo Rendezvous", the
# Dutch submarine reels...). Markers are deliberately narrow — phrases whose
# presence in a title is unambiguous — not a general content classifier.
_HATE_MARKERS = re.compile(
    r"\bholohoax\b"
    r"|\bchild\s+pornography\b"
    r"|\bwhite\s+genocide\b"
    r"|\bjewish\s+question\b",
    re.I)


def exclude_hate_propaganda(items, stats):
    """Reversibly exclude uploads whose own title advertises Holocaust denial or
    child sexual abuse material (Decision 027's `excluded` mechanism)."""
    for it in items:
        if it.get("excluded"):
            continue
        text = f"{it.get('archiveID') or ''} {it.get('title') or ''}"
        if _HATE_MARKERS.search(text):
            it["excluded"] = True
            it["excludedReason"] = "hate_propaganda"
            stats["hate_propaganda_excluded"] += 1


# --- Trailers posing as the feature -------------------------------------------
#
# Owner 2026-08-09: the Serpico TRAILER was in the app carrying the full film's
# synopsis, so it read as the feature — and Serpico (1973) is still under
# copyright. The app is for public-domain films and TV, not promos for
# copyrighted films.
#
# `tools/detect_trailers.py` already existed and could never have caught it, for
# two independent reasons:
#   1. its FILM_TYPES was {feature-film, tv-special, feature} — a trailer for a
#      feature is classified `short-film` PRECISELY BECAUSE IT IS SHORT, so the
#      detector skipped exactly the class it was meant to find; and
#   2. it gates on `runtimeSeconds >= 1800`, but by then the runtime had already
#      been corrected to the FILE's 237 s, erasing the very discrepancy it looks
#      for.
# It also only ever reclassified to contentType="trailer" — and no client
# filters that type (the app surfaces use deny-lists), so 19 already-detected
# trailers were still shipping.
#
# This rule needs NO network: the catalog already stores both numbers —
# `runtimeWasSeconds` (the matched film's canonical runtime) and
# `fileRuntimeSeconds` (what the file actually is). A recognized feature that
# runs 70-300 s is a trailer.
#
# The bounds are set from the live catalog, not guessed, and each one prevents a
# measured false positive:
#   actual <= 300 s   a real Popeye cartoon (736 s) wrongly matched to Altman's
#                     1980 "Popeye" (114 min) is a WRONG MATCH, not a trailer.
#   year >= 1930 and not silent
#                     a 4-minute silent is far more likely a surviving FRAGMENT
#                     of a lost film than a trailer — "The Case of Lena Smith"
#                     (1929) survives only as a fragment, "So This Is Paris"
#                     (Lubitsch, 1926) likewise. Those are archival treasures.
#                     The trailer as a mass-produced form belongs to the sound era.
#   canonical >= 2400 s
#                     only fragments of FEATURES qualify; a short matched to a
#                     short is just a short.
# Measured on the live catalog: 63 hidden, 30 silent-era fragments held back.
# Anything held back is still reachable by the network detector, which can read
# the archive.org metadata this rule deliberately does not fetch.
TRAILER_MAX_ACTUAL = 300        # seconds — above this it is a real short
TRAILER_MIN_CANONICAL = 2400    # the matched title must be feature-length
TRAILER_MAX_FRACTION = 0.25     # ...and the file must be a small piece of it
TRAILER_SOUND_ERA = 1930


def flag_trailers(items, stats):
    """Reclassify + reversibly exclude trailers/clips posing as the feature."""
    for it in items:
        if it.get("excluded"):
            continue
        ct = it.get("contentType") or ""
        if ct in ("tv-episode", "tv-series", "commercial"):
            continue
        # NOTE: items already typed "trailer" are NOT trusted and NOT excluded
        # wholesale — they run the same measured test as everything else. The
        # previous detector used the flawed comparison described above and
        # mislabelled real films: Ozu's "Tokkan kozô" (1929, the surviving 13-min
        # fragment), a 13-min "King of the Rocket Men" SERIAL CHAPTER compared
        # against the whole 12-chapter serial, and "Häxan". Blanket-excluding
        # that bucket would have hidden them. They stay visible; the test below
        # decides, on evidence, for every item alike.
        # The file's REAL duration, from whichever pass measured it:
        # `trueRuntimeSeconds` is what detect_trailers wrote after reading
        # archive.org (for those items `runtimeSeconds` still holds the film's
        # canonical length), `fileRuntimeSeconds` is what the runtime-correction
        # pass measured, and otherwise the stored runtime is the best we have.
        canonical = max(it.get("runtimeWasSeconds") or 0,
                        it.get("runtimeSeconds") or 0 if it.get("trueRuntimeSeconds") else 0)
        actual = (it.get("trueRuntimeSeconds") or it.get("fileRuntimeSeconds")
                  or it.get("runtimeSeconds") or 0)
        year = it.get("year") or 0
        if not actual:
            continue
        if actual > TRAILER_MAX_ACTUAL:
            continue                      # long enough to be a real short
        # A silent, or an explicitly pre-1930 title, is held back — see above.
        # An item with NO year is allowed through only when it was ALREADY judged
        # a trailer, since the era guard cannot speak for it either way.
        if it.get("isSilentFilm") or (year and year < TRAILER_SOUND_ERA):
            continue
        if ct == "trailer":
            # Prior judgment PLUS a runtime no complete sound-era film has. The
            # label alone is not trusted (it mislabelled Ozu and a serial
            # chapter) — but those are 800 s and 815 s, so the length settles it.
            pass
        else:
            if not year:
                continue                  # unjudged and undateable — leave alone
            if canonical < TRAILER_MIN_CANONICAL:
                continue                  # the matched title is not a feature
            if actual >= TRAILER_MAX_FRACTION * canonical:
                continue
        it["contentType"] = "trailer"
        it["isTrailer"] = True
        it["trueRuntimeSeconds"] = int(actual)
        it["excluded"] = True
        it["excludedReason"] = "trailer"
        stats["trailer_flagged"] += 1


def restore_mistyped_trailers(items, stats):
    """Give back a real contentType to films the OLD detector mislabelled.

    `detect_trailers.py` used to overwrite contentType with "trailer" — and it
    never recorded what the type had been, so there is nothing to roll back to.
    Its comparison was wrong for a whole class of items (it measured a 13-minute
    SERIAL CHAPTER against the whole 12-chapter serial, and Ozu's surviving
    13-minute fragment against the feature it was cut from), so the label is on
    real films: "King of the Rocket Men", "Tokkan kozô", "West Virginia, the
    State Beautiful", "Häxan".

    Anything still typed "trailer" AFTER flag_trailers has had its say is, by
    construction, an item our runtime evidence does NOT consider a trailer. It is
    reclassified with `ingest_candidates.classify` — the SAME function fresh
    ingests use, so the type it gets is the type it would have been given on the
    way in — using the file's TRUE duration rather than the matched film's.

    This matters because contentType is not cosmetic: the film surfaces filter on
    it, so a mistyped item is missing from Movies, from the category grids and
    from every Home shelf even though it is in the database and plays fine.
    """
    # From the dependency-free module, NOT ingest_candidates: that one imports
    # `requests` at module level, and this step runs in CI as a bare `python
    # tools/remediate_catalog.py`, so the import failed there and this rule
    # silently did nothing on the first publish (caught only because it says so).
    try:
        _sys.path.insert(0, str(Path(__file__).resolve().parent))
        from content_type import classify               # noqa: PLC0415
    except Exception as e:                               # noqa: BLE001
        print(f"[remediate] classify() unavailable ({e}) — mistyped trailers left as-is")
        return
    for it in items:
        if it.get("contentType") != "trailer" or it.get("excluded"):
            continue
        runtime = (it.get("trueRuntimeSeconds") or it.get("fileRuntimeSeconds")
                   or it.get("runtimeSeconds") or 0)
        new = classify([str(c) for c in (it.get("collections") or [])],
                       [str(s) for s in (it.get("subjects") or [])],
                       runtime, it.get("year"))
        if new == "trailer":
            continue
        it["contentTypeWas"] = "trailer"
        it["contentType"] = new
        it.pop("isTrailer", None)
        # The runtime shown must be the FILE's, not the feature it was cut from —
        # these carry the canonical length (Häxan: 6300 s on a 490 s excerpt).
        if runtime and it.get("runtimeSeconds") != runtime:
            it["runtimeWasSeconds"] = it.get("runtimeSeconds")
            it["runtimeSeconds"] = runtime
            it["runtimeSource"] = "archive_file"
        stats[f"trailer_restored_{new}"] += 1


def remediate(items):
    stats = Counter()
    # A later rule can null a year this pass filled (e.g. the B&W-vs-modern
    # wrong-match check); sweep any marker left without a year at the end so
    # the catalog never carries a provenance claim for a value that is gone.
    def _drop_stale_year_markers():
        for it in items:
            if it.get("yearSource") and not isinstance(it.get("year"), int):
                it.pop("yearSource", None)
    for it in items:
        ct = it.get("contentType")
        if ct == "tv-series" or ct not in MOVIE_TYPES:
            continue

        # 0z) FILL A MISSING YEAR from the item's own naming. source_year() is
        # the vetted extractor already used to CORRECT wrong matches (paren years
        # win; resolution tokens like 720p/1920x1080 are stripped first) — it was
        # simply never applied when the year was absent rather than wrong.
        # Recovers ~450 items. Deliberately NOT sourced from the Archive `date`
        # field: that is usually the UPLOAD date, not the release year (measured:
        # 30/30 no-year items had a date, but e.g. `ThePink.Panther1963` reports
        # 2015 for a 1963 film). Stamping a modern year would corrupt decade
        # browse AND could push a PD title into the rights audit's post-1978
        # bucket, hiding it.
        if not isinstance(it.get("year"), int) or (it.get("year") or 0) <= 0:
            sy = source_year(it)
            if sy is not None and 1888 <= sy <= CURRENT_YEAR:
                it["year"] = sy
                it["decade"] = decade_of(sy)
                it["yearSource"] = "source_naming"
                stats["year_filled"] += 1

        # 0y) FORM vs RUNTIME: a "feature film" that is actually 12 minutes is
        # mis-categorised — the owner's "wrong category". Only acts on a
        # FILE-VERIFIED duration (fileRuntimeSeconds, written by check_liveness
        # from archive.org's own per-derivative length), never on a runtime that
        # came from an external match, since that is exactly the value that can
        # describe a different cut or a different film. 40 min is the Academy
        # short-film boundary. Measured on the live catalog: 520 items, e.g.
        # "Malice in the Palace" (15m Stooges short), "The Battle Of Midway"
        # (18m), "Hemp for Victory" (13m) — all typed feature-film.
        #
        # Deliberately ONE-DIRECTIONAL (feature -> short only). The reverse is
        # not safe: a short-film item whose file is long is usually a compilation
        # reel of several shorts, which is not a feature.
        if it.get("contentType") == "feature-film":
            fr = it.get("fileRuntimeSeconds")
            if isinstance(fr, int) and 60 <= fr < 2400:
                it["contentType"] = "short-film"
                it["contentTypeWas"] = "feature-film"
                it["contentTypeSource"] = "file_runtime"
                stats["contenttype_short"] += 1

        # 0x) DOCUMENTARY PRECISION (owner 2026-07-19: "fix documentary so that
        # everything that is in that category actually belongs there"). An item
        # typed `documentary` whose own genres say otherwise is mis-categorised
        # — measured: Fantasia (Animation/Family/Fantasy) and Morgan the
        # Bushranger (Western) were 2 of the 8 members. Re-type from the genres
        # the item actually carries.
        #
        # Only fires when the item HAS genres and none of them is Documentary,
        # so an unenriched item (no genres) is never re-typed on absence of
        # evidence.
        if it.get("contentType") == "documentary":
            gs = {g for g in (it.get("genres") or []) if g}
            if gs and "Documentary" not in gs:
                if "Animation" in gs:
                    it["contentType"] = "animation"
                else:
                    rt = it.get("fileRuntimeSeconds") or it.get("runtimeSeconds") or 0
                    it["contentType"] = "short-film" if 0 < rt < 2400 else "feature-film"
                it["contentTypeWas"] = "documentary"
                it["contentTypeSource"] = "genres"
                stats["documentary_retyped"] += 1

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

        # 0d) UNANCHORED EXTERNAL POSTER: a designed poster (tvdb/tmdb/omdb, or a
        # TVmaze image classified `tvmaze`/`external`) adopted by a TITLE-ONLY
        # match with zero corroboration — no imdbID, no tmdbID, AND no year — is
        # as likely wrong as right (the yearless 1979 "The Swap" pulled a modern
        # Disney film's poster; the One Step Beyond episode "The Devil's Laughter"
        # pulled a foreign film's TVmaze poster). Strip the POSTER ONLY so it
        # falls back to a real Archive frame / generated cover; keep the synopsis
        # + cast (those were often sourced correctly from elsewhere). The TVDB
        # movie enricher refuses yearless matches, so this is durable.
        if (it.get("artworkSource") or "").lower() in ("tvdb", "tmdb", "omdb", "tvmaze", "external") \
                and it.get("posterURL") \
                and not it.get("imdbID") and not it.get("tmdbID") \
                and it.get("year") is None:
            it["posterURL"] = None
            it["backdropURL"] = None
            it["hasRealArtwork"] = False
            it["artworkSource"] = "archive"
            stats["unanchored_poster_cleared"] += 1

        # 0e) DEAD POSTER RESTORED: validate_posters demotes a 404'd poster
        # (posterDead=True, hasRealArtwork=False), but an enricher run afterward
        # (omdb apply_rich keys off the cache and only refuses DESIGNED sources,
        # not the "archive" fallback) RE-APPLIES the exact dead URL with
        # hasRealArtwork=True — so 2,090 dead omdb posters were leading Home. Any
        # build, re-demote an item whose current posterURL is the known-dead one:
        # drop it so the #8 artwork floor falls back to the Archive thumbnail and
        # the designed-art Home gate skips it. (omdb_lib.apply_rich now also
        # refuses the dead URL at the source; this is the cross-tool backstop.)
        if it.get("posterDead") and it.get("posterURL") \
                and it.get("posterURL") == it.get("posterDeadURL"):
            it["posterURL"] = None
            it["backdropURL"] = None
            it["hasRealArtwork"] = False
            it["artworkSource"] = "archive"
            stats["dead_poster_redemoted"] += 1

        # 0f) KNOCK-OFF STUDIO matched to the MAJOR film of the same name: a title naming a
        # PD-cartoon knock-off label (Bevanfield, Foxbridge, Burbank/Golden Films…) can only
        # be that knock-off, never the Disney/major work a title search resolves to. Clear the
        # whole wrong external identity (ids/poster/synopsis via _clear_wrong_artwork, plus the
        # leftover director/rating/votes). Self-heals each build even if a title-matcher re-adds
        # it. Keep the Archive year (don't trust the matched film's).
        if _KNOCKOFF_LABEL.search(it.get("title") or "") \
                and (it.get("imdbID") or it.get("tmdbID")
                     or (it.get("artworkSource") or "").lower() in ("tmdb", "omdb")):
            _clear_wrong_artwork(it, None)
            it["director"] = None
            it["imdbRating"] = None
            it["imdbVotes"] = None
            stats["knockoff_match_cleared"] += 1

        # 0g) SHORT-FILM matched to a MAJOR THEATRICAL FEATURE: an Archive item classified
        # short-film but matched to a film with blockbuster vote counts is an abridged excerpt
        # of that feature, NOT the feature — it was title-matched and wrongly inherited the
        # feature's poster/identity (the 25-min educational "Twelve Angry Men" carried the
        # 981k-vote 1957 feature's art on Home). A genuine short has its OWN low-vote IMDb entry,
        # so high votes on a short = a wrong match. Clear the wrong identity → no designed poster
        # → drops off Home, but stays browsable (it may be a real PD educational short).
        # (Promotional types — trailer/clip/teaser/featurette — are HIDDEN by audit_rights
        # 'copyrighted_trailer' instead; don't clear their votes here or that vote-gated hide
        # can't fire.)
        if it.get("contentType") == "short-film" \
                and (it.get("imdbVotes") or 0) >= 150000 \
                and (it.get("imdbID") or it.get("tmdbID")):
            _clear_wrong_artwork(it, None)
            it["director"] = None
            it["imdbRating"] = None
            it["imdbVotes"] = None
            stats["short_of_feature_cleared"] += 1

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

        # 5b) GENRE VOCAB: collapse Wikidata "-film" variants to the canonical
        # browse vocabulary so genre filters/shelves stop fragmenting.
        if normalize_genres(it):
            stats["genres_normalized"] += 1

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

    # Universal ADULT pass: the loop above skips tv-series + non-movie types, but
    # a series CARD (e.g. "Playboy After Dark") must be flagged so the mature
    # filter hides it from the TV tab too. Cheap re-check of everything; items the
    # loop already flagged short-circuit on `not it.get("isAdult")`.
    for it in items:
        if not it.get("isAdult") and is_adult_signal(it):
            it["isAdult"] = True
            stats["adult_flagged"] += 1

    # Universal TITLE pass: the main loop only sanitizes MOVIE_TYPES, but every OTHER
    # display type shows its title too — tv-series / tv-special / trailer / commercial
    # ("Checkmate: The Human Touch (1961)", "One Flew Over the Cuckoo's Nest (1975)"
    # trailer). sanitize_title is conservative + idempotent, so this only cleans artifacts.
    for it in items:
        if it.get("contentType") not in MOVIE_TYPES and sanitize_title(it):
            stats["other_title_cleaned"] += 1

    _drop_stale_year_markers()
    exclude_hate_propaganda(items, stats)
    # After the year/runtime rules above have settled — flag_trailers reads both.
    flag_trailers(items, stats)
    # ...then give a real type back to whatever it did NOT judge a trailer.
    restore_mistyped_trailers(items, stats)
    encode_download_urls(items, stats)
    return stats


# --- Percent-encode downloadURLs ------------------------------------------
# archive.org filenames routinely contain spaces, parentheses, and commas
# ("Ladies in Retirement (1941, USA) - Film Noir Full Movie.mp4"). A downloadURL
# baked with those RAW characters is not a valid URL: the app's URL(string:)
# rejects it (or the request 400s), so the title "does not play" — while the
# liveness probe marked it playable because Python `requests` silently
# percent-encodes before sending, so it verified a DIFFERENT (encoded) URL than
# the one the app actually uses. Measured 2026-07-20: 9,821 items marked
# playable had raw-space URLs. Encoding the stored URL makes it exactly what the
# probe already verified, so it plays.
_UNSAFE_URL = re.compile(r"[ \"<>\\^`{|}]")  # chars that are invalid in a bare URL


_URL_HOST = re.compile(r"^(https?://[^/]+)(/.*)$", re.I)


def encode_download_urls(items, stats):
    from urllib.parse import quote
    for it in items:
        url = it.get("downloadURL")
        if not url or not _UNSAFE_URL.search(url):
            continue
        m = _URL_HOST.match(url)
        if not m:
            continue
        host, path = m.groups()
        # Encode EVERYTHING after the host as the path. `safe="/%"` keeps path
        # separators and existing %XX escapes (no double-encoding) but encodes
        # spaces, parens, commas — AND a literal `#`/`?` in the filename (the
        # DeOldify restorations have `#` in their names; urlsplit would wrongly
        # treat it as a fragment and leave the tail unencoded).
        fixed = host + quote(path, safe="/%")
        if fixed != url:
            it["downloadURL"] = fixed
            stats["download_url_encoded"] += 1


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
    asr, hls = drop_asr_captions(cat["items"])   # hallucinated archive.org ASR captions (039b)
    if asr:
        stats["asr_captions_dropped"] = asr
    if hls:
        stats["orphan_subtitleHLS_cleared"] = hls
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
