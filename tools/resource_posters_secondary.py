#!/usr/bin/env python3
"""
resource_posters_secondary.py — re-source professional posters from SECONDARY
public sources (TheTVDB, Wikipedia film-infobox images, Wikidata P18/Commons)
for the ~6,070 feature/silent/animation FILMS still on a frame-still / dead /
no poster that TMDb does NOT cover.

WHY: resource_posters_tmdb.py (the primary re-sourcer) can only help films that
already carry an imdbID/tmdbID AND that TMDb has a poster for. That leaves a
large tail — obscure PD films with NO IMDb id, or with an id TMDb has no poster
for — permanently on a `generated` frame still or a `posterDead` archive thumb.
Those same films very often DO have a real designed poster on TheTVDB, in an
English-Wikipedia infobox, or via a Wikidata P18 Commons image. This tool reaches
that tail with the SAME abstain-over-wrong discipline as the TMDb re-sourcer:
identity is anchored (imdb/tmdb → Wikidata QID = authoritative; TVDB + title-only
QID = corroborated by year ±) and every candidate poster URL is proven LIVE before
it is adopted. Any doubt → keep the frame still.

WHY infobox-preferred over P18: measured on real films (e.g. Nosferatu 1922) the
Wikipedia film infobox `| image =` is conventionally the THEATRICAL POSTER, while
the Wikidata P18 "image" is frequently a scene/location still (Nosferatu's P18 is
a photo of Wismar market square). So 3a (infobox) is tried before 3b (P18).

WHAT (per candidate, popularity-first, resumable via `secondaryPosterCheckedAt`),
sources tried IN PRIORITY ORDER, stop at the first LIVE + safe hit:

  1. TheTVDB (item must have a year) — search /movies by title+year and adopt the
     matched poster (enrich_tvdb_movies match logic: exact title+year OR ≥0.7
     word-overlap AND ±1yr). artworkSource="tvdb".
  2. Resolve a Wikidata QID if not already stored:
       - by imdbID  (?item wdt:P345 "tt…")      → AUTHORITATIVE (it IS this film)
       - by tmdbID  (?item wdt:P4947 "…")        → AUTHORITATIVE
       - title-only (rdfs:label + P31/P279* film + P577 year within ±2) → adopted
         ONLY if EXACTLY ONE film QID matches; MUST pass the colorMode B&W×year≥1970
         guard (Decision 025) and requires a year to corroborate. Else ABSTAIN.
  3. From the QID, get a poster candidate (prefer an actual POSTER over a still):
       a. Wikipedia enwiki infobox `| image =` → imageinfo URL  (PREFERRED)
       b. Wikidata P18 → Commons imageinfo URL                  (fallback)
     Either way the durable upload.wikimedia.org URL maps to artworkSource="commons".
  4. Validate the chosen URL is LIVE (HEAD, follow redirects). 404/410 = unusable →
     try the next source. 429/5xx/timeout = transient → retry/skip, NEVER treated as
     a bad poster. Apply only a proven-live poster; else leave the item UNCHANGED and
     mark `secondaryPosterCheckedAt` (counted "no_secondary_poster" / "no_qid").

SAFE over exhaustive: never overwrite an existing professional poster (is_target
excludes them); never delete a generated cover except to UPGRADE it to a real
poster; abstain on any ambiguity. Additive, idempotent, reversible.

Run: python tools/resource_posters_secondary.py [--limit N] [--dry-run]
                                                [--reprobe-days 30] [--sleep 0.4]
Catalog I/O via the local catalog.json (catalog_release.py fetch first in CI).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import time
import urllib.parse
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tvdb_lib as TV                       # noqa: E402
from enrich_tvdb_movies import best_match   # noqa: E402  (reuse the exact match logic)

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"

UA = "ArchiveWatch-secondary-posters/1.0 (https://github.com/bhwilkoff/Archive-Watch; learningischange.com)"
SPARQL = "https://query.wikidata.org/sparql"
WD_API = "https://www.wikidata.org/w/api.php"
ENWIKI_API = "https://en.wikipedia.org/w/api.php"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"

# FILMS that plausibly had designed theatrical art (per the task scope).
FILM_TYPES = {"feature-film", "silent-film", "animation"}
# Artwork we consider NON-professional and thus eligible to upgrade.
NONPRO_SOURCES = {"generated", "archive", None, ""}
# Wikidata "instance of" film-family QIDs used to constrain a title-only resolve.
# (P31/P279* wd:Q11424 already subsumes these; kept for the explicit VALUES note.)
FILM_CLASS_QID = "Q11424"  # film (animated/short/tv-film are subclasses)


# --------------------------------------------------------------------------- #
# catalog I/O
# --------------------------------------------------------------------------- #
def load(p):
    return json.loads(p.read_text(encoding="utf-8"))


def dump(p, d):
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
    tmp.replace(p)


def _now():
    return (dt.datetime.now(dt.timezone.utc)
            .isoformat(timespec="seconds").replace("+00:00", "Z"))


def _item_year(it):
    y = it.get("year")
    if isinstance(y, int) and 1870 <= y <= 2100:
        return y
    rd = it.get("releaseDate") or ""
    if len(rd) >= 4 and rd[:4].isdigit():
        return int(rd[:4])
    return None


def _pop(it):
    return (it.get("popularityScore") or 0,
            it.get("views30d") or 0,
            it.get("downloads") or 0)


def is_target(it):
    if it.get("contentType") not in FILM_TYPES:
        return False
    if it.get("excluded"):
        return False
    if it.get("posterDead") is True:
        return True
    return it.get("artworkSource") in NONPRO_SOURCES


def _recently_probed(it, reprobe_days):
    if reprobe_days <= 0:
        return False
    ts = it.get("secondaryPosterCheckedAt")
    if not ts:
        return False
    try:
        when = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return False
    return (dt.datetime.now(dt.timezone.utc) - when).days < reprobe_days


# --------------------------------------------------------------------------- #
# HTTP helpers (serial + small sleeps — respect Wikidata/Commons/TVDB limits)
# --------------------------------------------------------------------------- #
def _get(session, url, params=None, *, timeout=45, retries=3):
    """GET with transient-retry. Returns a Response or None. 429/5xx/timeout are
    transient (retried, then None); a hard error returns None. Never raises."""
    for attempt in range(retries):
        try:
            r = session.get(url, params=params,
                            headers={"User-Agent": UA}, timeout=timeout)
            if r.status_code == 429 or 500 <= r.status_code < 600:
                time.sleep(2 ** attempt + 1)
                continue
            return r
        except (requests.Timeout, requests.ConnectionError):
            time.sleep(2 ** attempt + 1)
    return None


def poster_is_live(session, url):
    """Prove a poster URL resolves. Returns True (live), False (404/410 =
    unusable), or None (transient — could not confirm; treat as skip, never
    as a bad poster)."""
    if not url:
        return False
    for attempt in range(3):
        try:
            r = session.head(url, headers={"User-Agent": UA},
                            timeout=30, allow_redirects=True)
            # Some CDNs reject HEAD (405) — fall back to a ranged GET.
            if r.status_code == 405:
                r = session.get(url, headers={"User-Agent": UA, "Range": "bytes=0-0"},
                                timeout=30, allow_redirects=True, stream=True)
            if r.status_code in (404, 410):
                return False
            if r.status_code == 429 or 500 <= r.status_code < 600:
                time.sleep(2 ** attempt + 1)
                continue
            ok = r.status_code < 400 and \
                (r.headers.get("Content-Type", "").startswith("image/") or
                 r.status_code in (200, 206))
            return True if ok else None
        except (requests.Timeout, requests.ConnectionError):
            time.sleep(2 ** attempt + 1)
    return None


# --------------------------------------------------------------------------- #
# Wikidata QID resolution
# --------------------------------------------------------------------------- #
def _sparql(session, query):
    r = _get(session, SPARQL,
             params={"query": query, "format": "json"}, timeout=90)
    if not r or not r.ok:
        return None
    try:
        return r.json()["results"]["bindings"]
    except (ValueError, KeyError):
        return None


def _qid(uri):
    return uri.rsplit("/", 1)[-1] if uri else None


def resolve_qid(session, it):
    """Return (qid, how) — how in {stored, imdb, tmdb, title}. Authoritative
    (imdb/tmdb/stored) needs no year check; title is corroborated by year ±2 and
    must be UNAMBIGUOUS (exactly one film QID). Returns (None, reason) on failure:
    reason in {no_year, ambiguous, none}."""
    stored = it.get("wikidataQID")
    if stored:
        return stored, "stored"

    imdb = it.get("imdbID")
    if imdb and re.fullmatch(r"tt\d+", str(imdb)):
        rows = _sparql(session, f'SELECT ?item WHERE {{ ?item wdt:P345 "{imdb}" }}')
        if rows:
            qids = {_qid(b["item"]["value"]) for b in rows}
            if len(qids) == 1:
                return qids.pop(), "imdb"

    tmdb = it.get("tmdbID")
    if tmdb:
        rows = _sparql(session, f'SELECT ?item WHERE {{ ?item wdt:P4947 "{tmdb}" }}')
        if rows:
            qids = {_qid(b["item"]["value"]) for b in rows}
            if len(qids) == 1:
                return qids.pop(), "tmdb"

    # title-only — requires a year to corroborate (Decision 026).
    iyear = _item_year(it)
    title = (it.get("title") or "").strip()
    if not title:
        return None, "none"
    if not iyear:
        return None, "no_year"
    safe = title.replace("\\", "\\\\").replace('"', '\\"')
    q = (
        'SELECT DISTINCT ?item WHERE {\n'
        f'  ?item wdt:P31/wdt:P279* wd:{FILM_CLASS_QID} .\n'
        '  ?item rdfs:label ?l .\n'
        f'  FILTER(LANG(?l)="en" && LCASE(STR(?l)) = LCASE("{safe}"))\n'
        '  ?item wdt:P577 ?pub . BIND(YEAR(?pub) AS ?y)\n'
        f'  FILTER(?y >= {iyear - 2} && ?y <= {iyear + 2})\n'
        '} LIMIT 5'
    )
    rows = _sparql(session, q)
    if rows is None:
        return None, "none"
    qids = {_qid(b["item"]["value"]) for b in rows}
    if len(qids) == 1:
        return qids.pop(), "title"
    if len(qids) > 1:
        return None, "ambiguous"
    return None, "none"


# --------------------------------------------------------------------------- #
# QID → poster (Wikipedia infobox preferred, Wikidata P18 fallback)
# --------------------------------------------------------------------------- #
def qid_enwiki_and_p18(session, qid):
    """(enwiki_page_title, p18_filename) for a QID; either may be None."""
    r = _get(session, WD_API, params={
        "action": "wbgetentities", "ids": qid,
        "props": "sitelinks|claims", "format": "json"})
    if not r or not r.ok:
        return None, None
    try:
        ent = r.json()["entities"][qid]
    except (ValueError, KeyError):
        return None, None
    title = ((ent.get("sitelinks") or {}).get("enwiki") or {}).get("title")
    p18 = None
    claims = (ent.get("claims") or {}).get("P18") or []
    if claims:
        val = (claims[0].get("mainsnak", {}).get("datavalue", {}) or {}).get("value")
        if isinstance(val, str) and val:
            p18 = val
    return title, p18


_INFOBOX_IMAGE_RE = re.compile(
    r"\|\s*image\s*=\s*([^\n|}]+)", re.IGNORECASE)


def infobox_image_filename(session, page_title):
    """Extract the film infobox `| image =` filename from the lead wikitext."""
    r = _get(session, ENWIKI_API, params={
        "action": "parse", "page": page_title, "prop": "wikitext",
        "section": "0", "format": "json"})
    if not r or not r.ok:
        return None
    try:
        wt = r.json()["parse"]["wikitext"]["*"]
    except (ValueError, KeyError):
        return None
    m = _INFOBOX_IMAGE_RE.search(wt)
    if not m:
        return None
    val = m.group(1).strip()
    fm = re.search(r"(?:File|Image):\s*([^\]\|]+)", val, re.IGNORECASE)
    if fm:
        val = fm.group(1).strip()
    val = re.sub(r"^\[\[|\]\]$", "", val).strip()
    # Reject obvious non-file leftovers (templates, empty).
    if not val or val.startswith("{") or len(val) < 4 or "." not in val:
        return None
    return val


def imageinfo_url(session, api, filename, width=600):
    """Resolve File:<filename> to a real (thumb) URL via a wiki's imageinfo API.
    Handles local + Commons-transcluded files. Returns the URL or None."""
    r = _get(session, api, params={
        "action": "query", "titles": f"File:{filename}",
        "prop": "imageinfo", "iiprop": "url",
        "iiurlwidth": str(width), "format": "json"})
    if not r or not r.ok:
        return None
    try:
        pages = r.json()["query"]["pages"]
    except (ValueError, KeyError):
        return None
    for pid, pg in pages.items():
        if pid == "-1":
            return None
        ii = pg.get("imageinfo")
        if ii:
            return ii[0].get("thumburl") or ii[0].get("url")
    return None


def wikipedia_poster(session, qid):
    """Return (url, how) for a QID's best poster — infobox first, then P18.
    how in {wikipedia_infobox, wikidata_p18}. (None, None) when neither exists."""
    page_title, p18 = qid_enwiki_and_p18(session, qid)
    # 3a — Wikipedia infobox image (PREFERRED: conventionally the theatrical poster)
    if page_title:
        fn = infobox_image_filename(session, page_title)
        if fn:
            url = imageinfo_url(session, ENWIKI_API, fn) \
                or imageinfo_url(session, COMMONS_API, fn)
            if url:
                return url, "wikipedia_infobox"
    # 3b — Wikidata P18 (Commons; may be a still, accepted as professional art)
    if p18:
        url = imageinfo_url(session, COMMONS_API, p18)
        if url:
            return url, "wikidata_p18"
    return None, None


# --------------------------------------------------------------------------- #
# TheTVDB poster
# --------------------------------------------------------------------------- #
def tvdb_poster(token, it):
    """Return a TVDB poster URL for the item via the enrich_tvdb_movies match
    logic (exact title+year OR ≥0.7 overlap ±1yr), or None."""
    year = _item_year(it)
    if not year:
        return None
    results = TV.search(token, it.get("title") or "", "movie", year)
    return best_match(results, it.get("title") or "", year) or None


# --------------------------------------------------------------------------- #
# apply
# --------------------------------------------------------------------------- #
def apply_poster(it, url, src, now):
    """Adopt a proven-live secondary poster. Upgrades a generated/archive/dead
    poster; never touches an existing professional poster (is_target guards)."""
    it["posterURL"] = url
    it["artworkSource"] = src
    it["hasRealArtwork"] = True
    for k in ("posterDead", "posterDeadURL", "posterChecked"):
        it.pop(k, None)
    it.pop("posterMismatch", None)
    it["secondaryPosterCheckedAt"] = now


# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0,
                    help="Max items to attempt this run (0 = all targets).")
    ap.add_argument("--chunk", type=int, default=200,
                    help="Checkpoint (write catalog) after each chunk — resumable.")
    ap.add_argument("--reprobe-days", type=int, default=30,
                    help="Skip items whose secondaryPosterCheckedAt is newer.")
    ap.add_argument("--sleep", type=float, default=0.4,
                    help="Sleep between items (respect Wikidata/Commons/TVDB limits).")
    ap.add_argument("--max-minutes", type=float, default=75,
                    help="Stop starting new items after this long and publish what "
                         "is done (0 = no budget). Bounds how long this holds the "
                         "shared catalog-writers lock; the work is resumable, so "
                         "the next run continues where this one left off.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Resolve + report the distribution; write nothing.")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[secondary-posters] no catalog.json (fetch first)", flush=True)
        return 2

    tvdb_key = TV.load_key(SECRETS)
    tvdb_token = TV.login(tvdb_key) if tvdb_key else None
    if not tvdb_token:
        print("[secondary-posters] no/failed THETVDB_API_KEY — TVDB source "
              "disabled (Wikipedia/Wikidata still run).", flush=True)

    catalog = load(CATALOG)
    items = catalog["items"] if isinstance(catalog, dict) else catalog

    total_targets = sum(1 for it in items if is_target(it))
    targets = [it for it in items if is_target(it)
               and not _recently_probed(it, args.reprobe_days)]
    targets.sort(key=_pop, reverse=True)
    work = targets[:args.limit] if args.limit else targets
    print(f"[secondary-posters] {len(work)} to attempt "
          f"({total_targets} total feature/silent/animation non-pro targets, "
          f"{len(items)} catalog){' DRY-RUN' if args.dry_run else ''}", flush=True)

    session = requests.Session()
    now = _now()
    stats = {
        "upgraded_tvdb": 0,
        "upgraded_wikipedia_infobox": 0,
        "upgraded_wikidata_p18": 0,
        "abstain_ambiguous": 0,
        "abstain_no_year": 0,
        "abstain_bw_modern": 0,
        "no_qid": 0,
        "no_secondary_poster": 0,
        "transient_skipped": 0,
    }
    up_examples, abstain_examples = [], []

    def checkpoint():
        if not args.dry_run:
            dump(CATALOG, catalog)

    # Bound how long this holds the shared `catalog-writers` lock. 27 workflows
    # share that group and GitHub keeps only ONE pending run per group, so a
    # newer arrival CANCELS the older pending one: every hour this job runs is an
    # hour in which scheduled catalog work is destroyed rather than queued.
    # Measured 2026-08-09 — this job ran 2h45m and seven runs were lost behind it.
    # The work is resumable (reprobe markers), so stopping early costs nothing but
    # the next run's start.
    deadline = (time.monotonic() + args.max_minutes * 60) if args.max_minutes else None
    stopped_early = False

    tried = 0
    for it in work:
        if deadline and time.monotonic() > deadline:
            stopped_early = True
            print(f"[secondary-posters] time budget reached after {tried} items — "
                  "publishing and releasing the catalog-writers lock", flush=True)
            break
        tried += 1
        iyear = _item_year(it)
        anchor = None
        chosen = None      # (url, src, how)

        # ---- source 1: TheTVDB (year-corroborated) ----
        if tvdb_token:
            url = None
            try:
                url = tvdb_poster(tvdb_token, it)
            except Exception:
                url = None
            if url:
                live = poster_is_live(session, url)
                if live is True:
                    chosen = (url, "tvdb", "upgraded_tvdb")
                    anchor = f"TVDB title+year({iyear})"
                elif live is None:
                    stats["transient_skipped"] += 1

        # ---- source 2+3: Wikidata QID → Wikipedia infobox / P18 ----
        if not chosen:
            qid, how = resolve_qid(session, it)
            if not qid:
                if how == "ambiguous":
                    stats["abstain_ambiguous"] += 1
                    if len(abstain_examples) < 8:
                        abstain_examples.append(
                            (it.get("title"), iyear, "ambiguous title QID",
                             it.get("archiveID")))
                elif how == "no_year":
                    stats["abstain_no_year"] += 1
                else:
                    stats["no_qid"] += 1
                it["secondaryPosterCheckedAt"] = now
            else:
                # B&W×year≥1970 guard applies to a title-only (non-authoritative)
                # resolve (Decision 025): a B&W film claiming a modern year is a
                # mismatch tell — abstain from the title-anchored QID.
                if how == "title" and it.get("colorMode") == "bw" \
                        and iyear and iyear >= 1970:
                    stats["abstain_bw_modern"] += 1
                    if len(abstain_examples) < 8:
                        abstain_examples.append(
                            (it.get("title"), iyear, "bw + year>=1970 (title-only)",
                             it.get("archiveID")))
                    it["secondaryPosterCheckedAt"] = now
                else:
                    if not it.get("wikidataQID"):
                        it["wikidataQID"] = qid   # store the resolved QID
                    url, poster_how = wikipedia_poster(session, qid)
                    if url:
                        live = poster_is_live(session, url)
                        if live is True:
                            key = ("upgraded_wikipedia_infobox"
                                   if poster_how == "wikipedia_infobox"
                                   else "upgraded_wikidata_p18")
                            chosen = (url, "commons", key)
                            anchor = (f"{how}→QID {qid} · {poster_how}")
                        elif live is None:
                            stats["transient_skipped"] += 1
                            it["secondaryPosterCheckedAt"] = now
                        else:  # 404/410
                            stats["no_secondary_poster"] += 1
                            it["secondaryPosterCheckedAt"] = now
                    else:
                        stats["no_secondary_poster"] += 1
                        it["secondaryPosterCheckedAt"] = now

        # ---- apply / record ----
        if chosen:
            url, src, key = chosen
            stats[key] += 1
            old = it.get("posterURL")
            if not args.dry_run:
                apply_poster(it, url, src, now)
            else:
                it["secondaryPosterCheckedAt"] = now  # (not written in dry-run)
            if len(up_examples) < 14:
                up_examples.append((it.get("title"), iyear, key, anchor,
                                    old, url, it.get("archiveID")))

        if args.sleep:
            time.sleep(args.sleep)
        if tried % args.chunk == 0:
            checkpoint()
            print(f"[secondary-posters] {tried}/{len(work)} tried · "
                  f"tvdb={stats['upgraded_tvdb']} "
                  f"wp={stats['upgraded_wikipedia_infobox']} "
                  f"p18={stats['upgraded_wikidata_p18']} · "
                  f"noQID={stats['no_qid']} noPoster={stats['no_secondary_poster']} "
                  f"ambig={stats['abstain_ambiguous']}", flush=True)

    # -------- report --------
    if stopped_early:
        # Never let a bounded run read as a complete one — a silent cap is how a
        # backlog looks like coverage (no-silent-caps rule).
        print(f"\n[secondary-posters] STOPPED EARLY at the {args.max_minutes:g}-minute "
              f"budget: {tried} of {len(work)} attempted. The remaining "
              f"{len(work) - tried} are picked up by the next run.", flush=True)
    print("\n[secondary-posters] === distribution ===", flush=True)
    order = ["upgraded_tvdb", "upgraded_wikipedia_infobox", "upgraded_wikidata_p18",
             "abstain_ambiguous", "abstain_no_year", "abstain_bw_modern",
             "no_qid", "no_secondary_poster", "transient_skipped"]
    for k in order:
        print(f"  {k:28s} {stats[k]}", flush=True)
    up_total = (stats["upgraded_tvdb"] + stats["upgraded_wikipedia_infobox"]
                + stats["upgraded_wikidata_p18"])
    print(f"  {'UPGRADED total':28s} {up_total}", flush=True)

    if up_examples:
        print("\n[secondary-posters] example upgrades "
              "(title (year) · source · identity anchor · old → new):", flush=True)
        for t, iy, key, anchor, old, new, aid in up_examples:
            print(f"  • {t!r} ({iy}) [{key}] [{aid}]\n"
                  f"      anchor: {anchor}\n"
                  f"      OLD: {old}\n      NEW: {new}", flush=True)
    if abstain_examples:
        print("\n[secondary-posters] example ABSTENTIONS (title (year) · reason):",
              flush=True)
        for t, iy, reason, aid in abstain_examples:
            print(f"  • {t!r} ({iy}) — {reason} [{aid}] — SKIPPED", flush=True)

    if not args.dry_run:
        checkpoint()
        print(f"\n[secondary-posters] wrote catalog.json "
              f"({up_total} posters re-sourced)", flush=True)
    else:
        print("\n[secondary-posters] dry-run — nothing written.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
