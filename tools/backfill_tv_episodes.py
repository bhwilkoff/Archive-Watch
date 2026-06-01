#!/usr/bin/env python3
"""
backfill_tv_episodes.py — grow under-populated TV series from Archive.

The committed series/*.json files were clustered from whatever episodes
happened to be in the local registry DB, so many real shows ended up with
only a handful of episodes — and Archive's inconsistent upload naming
(e.g. "the-lone-ranger-1949-s-01-e-01", "the-lone-ranger-tv-1950-s01e38",
"the-lone-ranger-tv-1955-s04e45") splits one show across several thin
"series". This tool fixes both:

  For each series file, it searches Archive (advancedsearch by the show's
  core title, within TV collections), finds every item whose title parses
  to a season/episode, validates each has a playable video derivative, and
  merges the new ones into the series file (deduped by archiveID). It then
  updates episodesCount + seasonsCount in the file and in the catalog's
  series card.

Daily-capped (--max-series) so it runs unattended in CI under a polite
request budget. Idempotent: an episode already in the file is never added
twice; a series that gained nothing is left byte-identical.

Usage:
    python tools/backfill_tv_episodes.py --max-series 40
    python tools/backfill_tv_episodes.py --series the-lone-ranger-tv-1950-colorized-1950
    python tools/backfill_tv_episodes.py --max-series 5 --dry-run
"""

import argparse
import datetime as dt
import json
import re
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
SERIES_DIR   = REPO / "series"
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"

ADV_SEARCH   = A.ADV_SEARCH
UA = "ArchiveWatch-TVBackfill/1.0 (https://github.com/bhwilkoff/Archive-Watch; learningischange.com)"

# Shared Archive helpers.
archive_meta = A.archive_meta
pick_video = A.pick_video
runtime_seconds = A.runtime_from_file

# Season/episode parsers, in priority order. Handles s01e02, S1 E2,
# s-01-e-02, 1x02.
SE_PATTERNS = [
    re.compile(r"[Ss](\d{1,2})\s*[\-\.\s]*[Ee](\d{1,3})"),
    re.compile(r"\b(\d{1,2})x(\d{1,3})\b"),
]
EP_ONLY = re.compile(r"\b(?:Episode|Ep)\s*#?\s*(\d{1,3})\b", re.IGNORECASE)

# Words to strip from a series title to get a robust Archive search term.
NOISE = re.compile(
    r"\b(tv|television|colorized|complete|series|the\s+complete|full|hd|"
    r"restored|remastered|season|episodes?|collection)\b",
    re.IGNORECASE,
)
STOPWORDS = {"the", "a", "an", "of", "and"}


def parse_se(title):
    for pat in SE_PATTERNS:
        m = pat.search(title)
        if m:
            return int(m.group(1)), int(m.group(2))
    m = EP_ONLY.search(title)
    if m:
        return 1, int(m.group(1))
    return None, None


def is_junk_title(title):
    """A series title that's just a number, a bare year, or 1-2 chars is a
    clustering artifact ("1949", "It", "50"), not a real show. These can't
    be searched meaningfully and shouldn't wear the series UI."""
    t = (title or "").strip()
    return (not t or len(t) <= 2
            or bool(re.fullmatch(r"\d{1,4}", t))
            or bool(re.fullmatch(r"(19|20)\d\d", t)))


def search_term(series_title, year_start):
    """Build a focused Archive search phrase from a series title: drop noise
    words + trailing year, keep the distinctive name words. Returns "" for
    a title too generic to search safely (so we never pollute it)."""
    if is_junk_title(series_title):
        return ""
    t = NOISE.sub(" ", series_title or "")
    t = re.sub(r"\b(19|20)\d\d\b", " ", t)        # strip years
    t = re.sub(r"[^\w\s]", " ", t)
    words = [w for w in t.split() if w.lower() not in STOPWORDS and len(w) > 1]
    # Need at least one distinctive word of length >= 3 — otherwise the
    # search would match half of Archive.
    if not any(len(w) >= 3 for w in words):
        return ""
    return " ".join(words[:6]).strip()


def adv_search(term, rows=400, session=None):
    # Broad series search, restricted to TV collections (keeps the noise
    # down for a generic show name).
    q = f'title:({term}) AND mediatype:movies AND (collection:classic_tv OR collection:television)'
    return adv_search_raw(q, session or requests, rows=rows)


def adv_search_raw(q, session, rows=20):
    """Raw advancedsearch — no TV-collection filter. Used by the per-want
    episode search, where a specific episode may live outside the TV
    collections."""
    r = session.get(
        ADV_SEARCH,
        params={"q": q, "fl[]": ["identifier", "title", "year"],
                "rows": rows, "output": "json"},
        headers={"User-Agent": UA}, timeout=60,
    )
    if not r.ok:
        return []
    return r.json().get("response", {}).get("docs", [])


def build_episode(iaid, doc, meta):
    md = meta.get("metadata", {})
    files = meta.get("files", [])
    title = md.get("title") or doc.get("title") or iaid
    vf = pick_video(files)
    if not vf:
        return None
    s, e = parse_se(title)
    yr = None
    for src in (md.get("year"), md.get("date"), doc.get("year")):
        if src:
            m = re.search(r"(\d{4})", str(src))
            if m:
                yr = int(m.group(1)); break
    return {
        "archiveID": iaid,
        "seasonNumber": s,
        "episodeNumber": e,
        "title": title,
        "overview": md.get("description") or None,
        "stillURL": "https://archive.org/services/img/" + iaid,
        "airDate": None,
        "year": yr,
        "runtimeSeconds": runtime_seconds(vf),
        "videoFile": {
            "name": vf["name"],
            "format": vf.get("format") or "",
            "sizeBytes": int(vf.get("size") or 0),
            "tier": 1,
        },
        "downloadURL": A.download_url(iaid, vf["name"]),
    }


def existing_archive_ids(series_doc):
    ids = set()
    for s in series_doc.get("seasons", []):
        for e in s.get("episodes", []):
            if e.get("archiveID"):
                ids.add(e["archiveID"])
    return ids


def regroup_seasons(all_eps):
    """Re-bucket a flat episode list into season groups, sorted."""
    by_season = {}
    for ep in all_eps:
        by_season.setdefault(ep.get("seasonNumber"), []).append(ep)
    seasons = []
    for sn in sorted(by_season.keys(), key=lambda x: (x is None, x or 0)):
        eps = sorted(by_season[sn], key=lambda e: (e.get("episodeNumber") is None,
                                                    e.get("episodeNumber") or 0,
                                                    e.get("title") or ""))
        seasons.append({"seasonNumber": sn, "episodes": eps})
    return seasons


def _norm_ep_title(t):
    """Normalize an episode title for matching (drop SxxExx + punctuation)."""
    t = (t or "").lower()
    t = re.sub(r"[Ss]\d{1,2}\s*[\-\.\s]*[Ee]\d{1,3}", " ", t)
    t = re.sub(r"[^a-z0-9 ]+", " ", t)
    return " ".join(t.split())


def per_want_search(doc, series_wants, have, session, *, throttle, cap):
    """Search Archive for the SPECIFIC episodes this series is missing
    (from the wants queue), validating each match against the wanted
    season/episode or episode title. Returns (episodes_to_add, filled_set).

    This is more precise than the broad series search: it targets named
    gaps and confirms the found item is actually that episode, so it can
    reach episodes the broad search misses (differently-named uploads)."""
    if not series_wants:
        return [], set()
    show = search_term(doc.get("title"), doc.get("yearStart"))
    if not show:
        return [], set()

    added = []
    filled = set()
    for w in series_wants[:cap]:
        sn, en = w["season"], w["episode"]
        ep_title = w.get("title") or ""
        # Two targeted queries: by SxxExx, and by episode title.
        queries = [
            f'title:({show}) AND title:(s0{sn}e0{en} OR s{sn}e{en} OR '
            f's-0{sn}-e-0{en} OR {sn}x{en:02d}) AND mediatype:movies',
        ]
        if ep_title and "episode #" not in ep_title.lower():
            queries.append(f'title:({show} {ep_title}) AND mediatype:movies')
        match_doc = None
        for q in queries:
            try:
                docs = adv_search_raw(q, session)
            except Exception:  # noqa: BLE001
                continue
            for d in docs[:5]:
                iaid = d.get("identifier")
                if not iaid or iaid in have:
                    continue
                dt_ = d.get("title", "")
                ds, de = parse_se(dt_)
                # Accept ONLY if the parsed S/E matches exactly, OR the
                # episode title matches strongly (>=80% of the wanted
                # title's words present) with no conflicting S/E. The
                # strict title bar avoids false-positives like a generic
                # "The Renegades" upload getting pinned to S1E8.
                se_ok = (ds == sn and de == en)
                want_words = set(_norm_ep_title(ep_title).split())
                cand_words = set(_norm_ep_title(dt_).split())
                title_ok = False
                if want_words and len(want_words) >= 2:
                    overlap = len(want_words & cand_words) / len(want_words)
                    title_ok = (overlap >= 0.8 and (ds is None or ds == sn)
                                and (de is None or de == en))
                if se_ok or title_ok:
                    match_doc = d
                    break
            if match_doc:
                break
        if not match_doc:
            time.sleep(throttle)
            continue

        iaid = match_doc["identifier"]
        try:
            meta = archive_meta(iaid, session)
        except Exception:  # noqa: BLE001
            time.sleep(throttle)
            continue
        if meta.get("metadata", {}).get("mediatype") not in (None, "movies", "video"):
            time.sleep(throttle); continue
        ep = build_episode(iaid, match_doc, meta)
        if ep:
            # Force the correct S/E from the want (the upload's own title
            # may be ambiguous, but the want came from OMDb's canonical list).
            ep["seasonNumber"] = sn
            ep["episodeNumber"] = en
            if not ep.get("title") or len(ep["title"]) < 4:
                ep["title"] = ep_title
            added.append(ep)
            have.add(iaid)
            filled.add((sn, en))
        time.sleep(throttle)
    return added, filled


def backfill_one(path, session, *, dry_run, throttle, per_series_cap, series_wants=None):
    doc = json.loads(path.read_text(encoding="utf-8"))
    have = existing_archive_ids(doc)
    flat = [e for s in doc.get("seasons", []) for e in s.get("episodes", [])]

    added = []

    # Stage 1 — targeted per-want search (precise; reaches named gaps).
    if series_wants:
        want_added, _ = per_want_search(doc, series_wants, have, session,
                                        throttle=throttle, cap=per_series_cap)
        added.extend(want_added)

    # Stage 2 — broad series-title search (catches episodes not in the
    # wants queue, e.g. shows OMDb couldn't resolve).
    term = search_term(doc.get("title"), doc.get("yearStart"))
    if term:
        try:
            docs = adv_search(term, session=session)
        except Exception:  # noqa: BLE001
            docs = []
        cand = []
        for d in docs:
            iaid = d.get("identifier")
            if not iaid or iaid in have:
                continue
            s, e = parse_se(d.get("title", ""))
            if s is None and e is None:
                continue
            cand.append(d)
        for d in cand[:per_series_cap]:
            iaid = d["identifier"]
            try:
                meta = archive_meta(iaid, session)
            except Exception:  # noqa: BLE001
                time.sleep(throttle)
                continue
            if meta.get("metadata", {}).get("mediatype") not in (None, "movies", "video"):
                time.sleep(throttle); continue
            ep = build_episode(iaid, d, meta)
            if ep:
                added.append(ep)
                have.add(iaid)
            time.sleep(throttle)

    if not added:
        return 0, set()

    flat.extend(added)
    doc["seasons"] = regroup_seasons(flat)
    doc["episodesCount"] = len(flat)
    years = [e["year"] for e in flat if e.get("year")]
    if years:
        doc["yearStart"] = min(years)
        doc["yearEnd"] = max(years)

    if not dry_run:
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    # Report the (season, episode) tuples we added so the caller can mark
    # the corresponding episode-wants fulfilled.
    filled = {(e.get("seasonNumber"), e.get("episodeNumber"))
              for e in added
              if e.get("seasonNumber") is not None and e.get("episodeNumber") is not None}
    return len(added), filled


WANTS_PATH = REPO / "shared" / "editorial" / "episode_wants.json"


def load_wants():
    """Load the episode-wants queue (built by build_episode_wants.py), or
    None if it doesn't exist yet."""
    if not WANTS_PATH.exists():
        return None
    try:
        return json.loads(WANTS_PATH.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return None


def mark_wants_fulfilled(wants, filled_by_series):
    """Flip matching wants to status=fulfilled. filled_by_series maps
    seriesID → set of (season, episode) tuples we just added. Returns count
    fulfilled and rewrites the queue file."""
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    n = 0
    for w in wants.get("wants", []):
        if w.get("status") != "wanted":
            continue
        got = filled_by_series.get(w["seriesID"])
        if got and (w["season"], w["episode"]) in got:
            w["status"] = "fulfilled"
            w["fulfilled_at"] = now
            n += 1
    if n:
        wants["stats"] = {
            "total": len(wants["wants"]),
            "wanted": sum(1 for x in wants["wants"] if x["status"] == "wanted"),
            "fulfilled": sum(1 for x in wants["wants"] if x["status"] == "fulfilled"),
            "series_with_gaps": len({x["seriesID"] for x in wants["wants"]
                                     if x["status"] == "wanted"}),
        }
        wants["updated_at"] = now
        WANTS_PATH.write_text(json.dumps(wants, ensure_ascii=False, indent=2), encoding="utf-8")
    return n


def prune_junk_series(dry_run=False):
    """Delete clustering-artifact series (numeric / bare-year / 1-2 char
    titles) from series/*.json AND their catalog series cards. Returns the
    list of pruned seriesIDs."""
    pruned = []
    for path in sorted(SERIES_DIR.glob("*.json")):
        d = json.loads(path.read_text(encoding="utf-8"))
        if is_junk_title(d.get("title")):
            pruned.append(d.get("seriesID") or path.stem)
            if not dry_run:
                path.unlink()
    if pruned and not dry_run:
        pruned_set = set(pruned)
        for cat_path in (FULL_CATALOG, SEED_CATALOG):
            if not cat_path.exists():
                continue
            cat = json.loads(cat_path.read_text(encoding="utf-8"))
            before = len(cat.get("items", []))
            cat["items"] = [it for it in cat.get("items", [])
                            if it.get("seriesID") not in pruned_set]
            if len(cat["items"]) != before:
                cat_path.write_text(json.dumps(cat, ensure_ascii=False, indent=2),
                                    encoding="utf-8")
    return pruned


def update_catalog_counts(series_counts):
    """Sync episodesCount on the catalog series cards. series_counts maps
    seriesID → new episode count."""
    changed_total = 0
    for cat_path in (FULL_CATALOG, SEED_CATALOG):
        if not cat_path.exists():
            continue
        cat = json.loads(cat_path.read_text(encoding="utf-8"))
        changed = 0
        for it in cat.get("items", []):
            sid = it.get("seriesID")
            if sid in series_counts and it.get("episodesCount") != series_counts[sid]:
                it["episodesCount"] = series_counts[sid]
                changed += 1
        if changed and cat_path:
            cat_path.write_text(json.dumps(cat, ensure_ascii=False, indent=2), encoding="utf-8")
            changed_total += changed
    return changed_total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-series", type=int, default=40,
                    help="Max series to backfill this run (default 40).")
    ap.add_argument("--series", help="Only this seriesID (for testing).")
    ap.add_argument("--min-episodes", type=int, default=0,
                    help="Only backfill series with <= this many episodes "
                         "(0 = all; e.g. 8 = under-populated only).")
    ap.add_argument("--per-series-cap", type=int, default=60,
                    help="Max new episodes to add per series per run.")
    ap.add_argument("--prune", action="store_true",
                    help="Remove junk-clustered series (numeric/bare-year/"
                         "1-2 char titles) before backfilling.")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--throttle", type=float, default=0.25)
    args = ap.parse_args()

    if args.prune:
        pruned = prune_junk_series(dry_run=args.dry_run)
        print(f"[tv-backfill] pruned {len(pruned)} junk series"
              f"{' (dry-run)' if args.dry_run else ''}: {', '.join(pruned[:8])}"
              f"{'…' if len(pruned) > 8 else ''}", flush=True)

    files = sorted(SERIES_DIR.glob("*.json"))
    if args.series:
        files = [p for p in files if p.stem == args.series]
    elif args.min_episodes:
        small = []
        for p in files:
            d = json.loads(p.read_text(encoding="utf-8"))
            if (d.get("episodesCount") or 0) <= args.min_episodes:
                small.append(p)
        # Smallest first — biggest relative wins.
        files = sorted(small, key=lambda p: json.loads(p.read_text())["episodesCount"])

    # If a wants queue exists, prioritise series that have known gaps —
    # those are the ones where a search is most likely to pay off.
    wants = load_wants()
    if wants and not args.series and not args.min_episodes:
        gap_series = {w["seriesID"] for w in wants.get("wants", [])
                      if w.get("status") == "wanted"}
        files.sort(key=lambda p: (p.stem not in gap_series,))

    n_wanted = sum(1 for w in wants.get("wants", []) if w.get("status") == "wanted") if wants else 0
    print(f"[tv-backfill] {len(files):,} series in scope; processing up to "
          f"{args.max_series} ({n_wanted:,} episodes wanted across queue)", flush=True)

    # Index wanted episodes by seriesID so each series gets its own gap list.
    wants_by_series = {}
    if wants:
        for w in wants.get("wants", []):
            if w.get("status") == "wanted":
                wants_by_series.setdefault(w["seriesID"], []).append(w)

    session = requests.Session()
    series_counts = {}
    filled_by_series = {}
    grown = total_added = 0

    for path in files[:args.max_series]:
        before = json.loads(path.read_text(encoding="utf-8")).get("episodesCount", 0)
        added, filled = backfill_one(path, session, dry_run=args.dry_run,
                                     throttle=args.throttle, per_series_cap=args.per_series_cap,
                                     series_wants=wants_by_series.get(path.stem))
        if added:
            grown += 1
            total_added += added
            after = before + added
            series_counts[path.stem] = after
            if filled:
                filled_by_series[path.stem] = filled
            print(f"  + {path.stem:50.50} {before} → {after} (+{added})", flush=True)

    if not args.dry_run and series_counts:
        cat_changed = update_catalog_counts(series_counts)
        print(f"[tv-backfill] updated {cat_changed} catalog series-card counts", flush=True)

    # Mark fulfilled wants.
    if wants and filled_by_series and not args.dry_run:
        n_filled = mark_wants_fulfilled(wants, filled_by_series)
        print(f"[tv-backfill] marked {n_filled} episode-wants fulfilled", flush=True)

    print(f"[tv-backfill] done: grew {grown} series, +{total_added} episodes", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
