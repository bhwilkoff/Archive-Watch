#!/usr/bin/env python3
"""
verify_external_match.py — make each externally-matched item's metadata actually
match the video it points to, using the ARCHIVE ITEM'S OWN authoritative signals.

The wrong-match problem (e.g. the 1946 B&W Welles "The Stranger" showing the 2025
film's poster/synopsis/year) happens because enrichment matched by fuzzy TITLE
when the Archive record had no year to constrain on, and a title-only search
returns the most popular/newest film. This tool re-checks every TMDb/OMDb-matched
item against signals the matcher should have used, in priority order:

  Tier 1 — Archive external-identifier `urn:imdb:tt…` (authoritative). If the
           upload declares an IMDb id and it differs from the stored one, the
           match is wrong → RE-RESOLVE to the declared id via OMDb.
  Tier 2 — Archive `date`/`year`. If it disagrees with the matched year by >2,
           the match is wrong → re-resolve by title + the Archive year; if that
           fails, clear and keep the Archive year.
  Tier 3 — Color (Decision 025). A frame-verified B&W film matched to a modern
           (>=1970) release is wrong → clear (no reliable year to re-resolve to).

Items with no contradicting signal are left untouched (avoid false positives).
Each processed item is marked `matchVerified` so re-runs are cheap; --refresh
re-checks everything. Archive metadata is fetched per item (the bulk network),
OMDb is called only to re-resolve a wrong match.

Catalog lives on the release (Decision 018): fetch -> this -> publish.
Run: python tools/verify_external_match.py [--limit N] [--workers 12] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import omdb_lib as O            # noqa: E402
import remediate_catalog as R   # noqa: E402  (_clear_wrong_artwork, source_year)
from enrich_movies import clean_movie_title   # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
EXTERNAL = {"tmdb", "omdb"}
IMDB_RE = re.compile(r"(tt\d{6,9})")
YEAR_RE = re.compile(r"\b(18\d\d|19\d\d|20[0-2]\d)\b")



# Mirrors build_sqlite.color_confident — the band where a chroma reading is a
# coin-flip rather than evidence. Duplicated deliberately: this tool runs in a
# workflow that does not build the DB.
_SAT_CONFIDENT_BW, _SAT_CONFIDENT_COLOR = 4.0, 14.0


def _today() -> str:
    from datetime import date
    return date.today().isoformat()


def _color_confident(it) -> bool:
    sat = it.get("colorSat")
    if sat is None:
        return True
    return sat < _SAT_CONFIDENT_BW or sat > _SAT_CONFIDENT_COLOR

# OPEN GAP, measured 2026-08-18 — a wrong match this tool cannot currently see.
#
# Seen on the owner's Apple TV: a 1950s game show ("Another episode of the 50's
# Game Show 'Beat The Clock'") wearing the poster of the 2012 anime "Another".
# It IS a candidate here — only tv-series is excluded — but every tier abstains:
# no Archive imdb id (Tier 1), no Archive date and no stored year (Tier 2), and
# Tier 3 needs a year >= 1970 it does not have. The tool is behaving correctly;
# it simply holds no evidence about this item.
#
# The signal that WOULD catch it is the one nothing currently asks for: what the
# matched id actually IS. A tv-special matched to an id whose canonical type is a
# MOVIE, or whose release year is decades from the item's era, contradicts the
# match on the same footing as Tier 1's imdb disagreement.
#
# SCOPE, measured rather than assumed (2026-08-18). Of 4,377 TV items carrying
# external-match artwork:
#
#     4,159  are EPISODES inheriting their SERIES spine's art (they carry a
#            seriesID and no film id) — correct by design, not a match at all
#       165  carry a tmdbID only   <- needs a TMDb key; the anime case is here
#                                     ("Beat The Clock" -> tmdb 42589)
#        46  carry an imdbID       <- OMDb can answer TODAY via its `Type` field
#         7  carry neither and no seriesID
#
# So the suspicious population is ~211, not thousands, and the majority of it
# needs TMDb — which this workflow does not currently receive. TMDB_BEARER_TOKEN
# exists as a repo secret (appstore-build.yml consumes it); wiring it here is the
# prerequisite for the tmdb half.
#
# One caution for whoever builds it: `Type == "movie"` alone is NOT decisive. A
# tv-special can legitimately be a TV movie, which OMDb also types as "movie"
# (Kolchak: The Night Stalker, 1972). Pair the type with an era disagreement, or
# restrict to items whose own collection places them decades from the match.
#
# Do NOT reach for a cheaper proxy. "External artwork but no year" was measured
# across 6,136 TV items — 601 match it, and the sample is dominated by CORRECT
# matches (The Benny Hill Show, Newhart, The Honeymooners) whose items simply
# carry no year of their own. It is not a wrong-match signal.


def is_candidate(it: dict) -> bool:
    if it.get("contentType") == "tv-series":
        return False
    if (it.get("archiveID") or "").startswith(("series:", "loc:")):
        return False
    return ((it.get("artworkSource") or "").lower() in EXTERNAL
            or (it.get("synopsisSource") or "").lower() in EXTERNAL)


# --- Tier 0b: a TV item whose collection states its decade -------------------
_TV_KINDS = ("tv-special", "tv-episode")
_DECADE_COL = re.compile(r"classic_tv_(19\d0)s?", re.I)
_ERA_TOLERANCE = 15          # years; a decade collection is a 10-year window


def collection_decade(it):
    """The decade the ARCHIVE ITSELF files this item under, e.g. classic_tv_1950s.

    Evidence about the item that does not come from the match — which is what
    Decision 026 requires before a match may be contradicted. 194 of the 211
    suspicious TV items carry one.
    """
    for c in (it.get("collections") or []):
        m = _DECADE_COL.search(str(c))
        if m:
            return int(m.group(1))
    return None


def matched_tv_release_year(it, tmdb_token, session):
    """First-air year of the TV work this item was matched to, or None.

    ONLY the /tv endpoint, and that is the whole correctness of this function. A
    TMDb id is namespaced BY TYPE: movie 3002 and tv 3002 are unrelated works.
    A first draft tried /movie then /tv and produced garbage that looked like
    signal — The Benny Hill Show "contradicted" its 1950s collection with 1999,
    which was some unrelated film sharing the id number. Asked of /tv it answers
    1969 and agrees. Measured across 45 items, that draft flagged 12 and this
    one flags 7; the five it invented were all id collisions.

    So: never widen this to a second endpoint to "get more coverage". An id that
    404s on /tv is an id we cannot interpret, and abstaining is the answer.
    """
    tmdb = it.get("tmdbID")
    if not (tmdb and tmdb_token):
        return None
    hdr = {"Authorization": f"Bearer {tmdb_token}", "accept": "application/json"}
    try:
        r = session.get(f"https://api.themoviedb.org/3/tv/{tmdb}", headers=hdr, timeout=20)
        if r.status_code != 200:
            return None
        d = (r.json().get("first_air_date") or "")[:4]
        return int(d) if d.isdigit() else None
    except Exception:
        return None


def archive_meta(aid: str):
    """Return (archive_imdb, archive_year) from the Archive item's own metadata,
    or (None, None) on any failure."""
    try:
        with urllib.request.urlopen(f"https://archive.org/metadata/{aid}", timeout=25) as r:
            md = json.load(r).get("metadata", {})
    except Exception:
        return None, None
    ext = md.get("external-identifier")
    exts = ext if isinstance(ext, list) else ([ext] if ext else [])
    imdb = None
    for e in exts:
        m = IMDB_RE.search(str(e))
        if m and "imdb" in str(e).lower():
            imdb = m.group(1); break
    yr = None
    for key in ("date", "year"):
        m = YEAR_RE.search(str(md.get(key) or ""))
        if m:
            y = int(m.group(1))
            if 1888 <= y <= 2025:
                yr = y; break
    return imdb, yr


def adopt(item: dict, rec: dict):
    """Overwrite the item with an authoritative OMDb record (after a clear)."""
    if rec.get("poster_url"):
        item["posterURL"] = rec["poster_url"]
        item["artworkSource"] = "omdb"
        item["hasRealArtwork"] = True
    if rec.get("imdb_id"):
        item["imdbID"] = rec["imdb_id"]
    if rec.get("year"):
        item["year"] = rec["year"]
        item["decade"] = rec["year"] // 10 * 10
        item["isSilentFilm"] = bool(rec["year"] < R.SILENT_CUTOFF)
    if rec.get("plot"):
        item["synopsis"] = rec["plot"]
        item["synopsisSource"] = "omdb"
    if rec.get("director"):
        item["director"] = rec["director"]
    if rec.get("genres"):
        item["genres"] = rec["genres"]
    if rec.get("actors") and not item.get("cast"):
        item["cast"] = [{"name": n, "character": None, "order": i, "profilePath": None}
                        for i, n in enumerate(rec["actors"])]


def verify(it: dict, omdb_key, session) -> str:
    """Inspect one item; mutate in place when wrong. Return a verdict string."""
    aid = it.get("archiveID") or ""
    a_imdb, a_year = archive_meta(aid)
    stored_imdb = it.get("imdbID")
    y = it.get("year")
    title_y = None
    m = YEAR_RE.search(it.get("title") or "")
    if m:
        title_y = int(m.group(1))
    evidence_year = a_year or title_y

    # Tier 1 — authoritative IMDb id from the Archive upload.
    if a_imdb:
        if stored_imdb and stored_imdb.lower() == a_imdb.lower():
            return "verified"
        # wrong (or missing) id → re-resolve to the declared one.
        try:
            rec = O.fetch_omdb_full(a_imdb, session, imdb_id=a_imdb)
        except RuntimeError:
            return "omdb_error"
        if rec:
            R._clear_wrong_artwork(it, rec.get("year"))
            adopt(it, rec)
            return "reresolved_imdb"
        return "verified"   # couldn't fetch; don't clobber on a transient miss

    # Tier 2 — Archive date disagrees with the matched year.
    if evidence_year and isinstance(y, int) and abs(y - evidence_year) > 2:
        clean = clean_movie_title(it.get("title") or "")
        try:
            rec = O.fetch_omdb_full(None, session, title=clean, year=evidence_year)
        except RuntimeError:
            rec = None
        if rec and rec.get("year") and abs(rec["year"] - evidence_year) <= 1:
            R._clear_wrong_artwork(it, rec.get("year"))
            adopt(it, rec)
            return "reresolved_year"
        R._clear_wrong_artwork(it, evidence_year)   # keep the trustworthy Archive year
        return "cleared_year"

    # Tier 3 — color era-gate (no reliable year to re-resolve to).
    #
    # Only on a CONFIDENT B&W reading. The chroma statistic overlaps between
    # classes on faded prints — a genuine Cinecolor feature measured 7.10 and a
    # genuine B&W feature 9.00 (2026-08-18) — so a marginal `bw` is not evidence
    # that a modern match is wrong, and clearing on it would throw away a
    # correct match plus its artwork and year. 781 items are bw + year>=1970,
    # so this is not a hypothetical. `colorSat` is absent on items measured
    # before it was recorded; those keep the previous behaviour.
    if (it.get("colorMode") == "bw" and _color_confident(it)
            and isinstance(y, int) and y >= 1970):
        R._clear_wrong_artwork(it, None)
        it["year"] = None
        it["decade"] = None
        return "cleared_bw"

    return "unverifiable"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--refresh", action="store_true", help="re-check already-verified items")
    ap.add_argument("--dry-run", action="store_true", help="report verdicts; write nothing")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[verify] no catalog.json (run catalog_release.py fetch first)"); return 2

    omdb_key = O.load_omdb_key(REPO / "Secrets.xcconfig")
    if not omdb_key:
        print("[verify] no OMDB key — set OMDB_KEY"); return 0

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    targets = [it for it in items
               if is_candidate(it) and (args.refresh or not it.get("matchVerified"))]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[verify] {len(targets)} externally-matched items to check "
          f"(workers {args.workers}{' DRY-RUN' if args.dry_run else ''})")

    from collections import Counter
    tally = Counter()
    lock = threading.Lock()
    session = requests.Session()

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    def work(it):
        v = verify(it, omdb_key, session)
        if not args.dry_run and v not in ("omdb_error",):
            it["matchVerified"] = True
            # WHICH tier fired, not merely that one did. `matchVerified = True`
            # alone made this tool's blast radius uncountable: `cleared_bw`
            # deletes a match's artwork AND year on a colour reading, and a
            # colour reading is a coin-flip near the threshold (Decision 084),
            # yet nothing in the catalog said which items it had touched. A
            # verdict without its evidence cannot be audited or undone.
            it["matchVerdict"] = v
            it["matchCheckedAt"] = _today()
        return v

    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(work, it): it for it in targets}
        for fut in as_completed(futs):
            v = fut.result()
            with lock:
                tally[v] += 1; done += 1
            if done % 200 == 0 or done == len(targets):
                if not args.dry_run:
                    flush()
                fixed = sum(tally[k] for k in tally if k.startswith(("reresolved", "cleared")))
                print(f"[{done}/{len(targets)}] fixed {fixed} | {dict(tally)}")
    if not args.dry_run:
        flush()
    print(f"[verify] done: {dict(tally)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
