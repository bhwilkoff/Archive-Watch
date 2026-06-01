#!/usr/bin/env python3
"""
build_episode_wants.py — compute the per-series "missing episode" queue.

The TV backfill (backfill_tv_episodes.py) finds whatever episodes happen
to be on Archive under a show's title. But it has no idea what the show's
FULL episode list is — so it can't tell a complete series from one that's
still missing 40 episodes, and it can't search for a specific missing
episode by name.

This tool closes that loop. For each series it:
  1. Resolves the series' IMDb ID via OMDb title lookup (cached back into
     the series file so we only pay the lookup once).
  2. Pulls the canonical per-season episode list from OMDb
     (?i={seriesIMDb}&Season=N) — title + episode # + episode IMDb ID.
  3. Diffs the canonical list against the episodes we already have
     (matched by season/episode number, then by fuzzy title).
  4. Writes the gaps to shared/editorial/episode_wants.json — a queue of
     (seriesID, season, episode, title, episode IMDb) the TV backfill then
     hunts for on Archive.

No TMDb token needed — uses the OMDb key we already have. Daily-capped
(--max-series); idempotent; only re-resolves a series whose canonical
counts we haven't fetched yet (or --refresh).

Usage:
    python tools/build_episode_wants.py --max-series 40
    python tools/build_episode_wants.py --series the-lone-ranger-tv-1950-colorized-1950
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
import omdb_lib as L  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
SERIES_DIR   = REPO / "series"
WANTS_PATH   = REPO / "shared" / "editorial" / "episode_wants.json"
SECRETS_PATH = REPO / "Secrets.xcconfig"

OMDB = "https://www.omdbapi.com/"
UA = "ArchiveWatch-EpisodeWants/1.0 (learningischange.com)"


def norm_title(t):
    """Normalize an episode title for fuzzy matching: lowercase, strip the
    show name / SxxExx noise, keep alphanumerics."""
    t = (t or "").lower()
    t = re.sub(r"[Ss]\d{1,2}\s*[\-\.\s]*[Ee]\d{1,3}", " ", t)
    t = re.sub(r"\bepisode\b|\bep\b|\bseason\b", " ", t)
    t = re.sub(r"[^a-z0-9]+", " ", t)
    return " ".join(t.split())


def omdb_get(params, session):
    params = dict(params)
    r = session.get(OMDB, params=params, headers={"User-Agent": UA}, timeout=20)
    if r.status_code == 401:
        raise RuntimeError("OMDb quota exhausted (401)")
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}")
    return r.json()


def resolve_series_imdb(title, year, session):
    """Resolve a series' IMDb ID + total seasons via OMDb title search.
    Returns (imdb_id, total_seasons) or (None, None)."""
    # Strip our own noise from the title before asking OMDb.
    clean = re.sub(r"\b(tv|colorized|complete|series|full|hd|restored|"
                   r"remastered|the\s+complete)\b", " ", title or "", flags=re.I)
    clean = re.sub(r"\b(19|20)\d\d\b", " ", clean)
    clean = re.sub(r"\s+", " ", clean).strip()
    if len(clean) < 2:
        return None, None
    params = {"t": clean, "type": "series", "apikey": session.api_key}
    if year:
        params["y"] = str(year)
    d = omdb_get(params, session)
    if str(d.get("Response", "")).lower() != "true":
        # Retry without the year (Archive years are often the upload year).
        if year:
            params.pop("y")
            d = omdb_get(params, session)
        if str(d.get("Response", "")).lower() != "true":
            return None, None
    seasons = d.get("totalSeasons")
    try:
        seasons = int(seasons)
    except (TypeError, ValueError):
        seasons = None
    return d.get("imdbID"), seasons


def canonical_episodes(imdb_id, total_seasons, session, *, season_cap=30):
    """Pull the canonical episode list across all seasons. Returns a list of
    dicts: {season, episode, title, imdb}."""
    out = []
    for sn in range(1, (total_seasons or 1) + 1):
        if sn > season_cap:
            break
        try:
            d = omdb_get({"i": imdb_id, "Season": str(sn), "apikey": session.api_key}, session)
        except RuntimeError:
            break
        for e in d.get("Episodes", []) or []:
            try:
                epno = int(e.get("Episode"))
            except (TypeError, ValueError):
                continue
            out.append({
                "season": sn,
                "episode": epno,
                "title": e.get("Title"),
                "imdb": e.get("imdbID"),
            })
        time.sleep(0.1)
    return out


def have_index(series_doc):
    """Index what we already have: a set of (season, episode) tuples and a
    set of normalized episode titles."""
    se = set()
    titles = set()
    for s in series_doc.get("seasons", []):
        for e in s.get("episodes", []):
            sn, en = e.get("seasonNumber"), e.get("episodeNumber")
            if sn is not None and en is not None:
                se.add((sn, en))
            nt = norm_title(e.get("title"))
            if nt:
                titles.add(nt)
    return se, titles


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-series", type=int, default=40,
                    help="Max series to resolve this run (default 40).")
    ap.add_argument("--series", help="Only this seriesID.")
    ap.add_argument("--refresh", action="store_true",
                    help="Re-resolve even series we've already looked up.")
    ap.add_argument("--throttle", type=float, default=0.2)
    args = ap.parse_args()

    api_key = L.load_omdb_key(SECRETS_PATH)
    if not api_key:
        print("[wants] OMDB_KEY not set — cannot run", file=sys.stderr)
        return 1

    session = requests.Session()
    session.api_key = api_key  # stash for the helpers

    # Existing wants (preserve fulfilled/queued status across runs).
    wants_doc = {"schema": 1, "wants": []}
    if WANTS_PATH.exists():
        wants_doc = json.loads(WANTS_PATH.read_text(encoding="utf-8"))
    existing = {(w["seriesID"], w["season"], w["episode"]): w
                for w in wants_doc.get("wants", [])}

    files = sorted(SERIES_DIR.glob("*.json"))
    if args.series:
        files = [p for p in files if p.stem == args.series]

    # Prefer series we haven't resolved yet, smallest first (biggest gap
    # potential), unless --refresh.
    def needs_resolve(p):
        d = json.loads(p.read_text(encoding="utf-8"))
        return args.refresh or "canonicalEpisodeCount" not in d
    todo = [p for p in files if needs_resolve(p)]
    todo.sort(key=lambda p: json.loads(p.read_text(encoding="utf-8")).get("episodesCount", 0))

    print(f"[wants] {len(todo):,} series to resolve (of {len(files):,}); "
          f"processing up to {args.max_series}", flush=True)

    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    resolved = added_wants = unresolved = 0

    for path in todo[:args.max_series]:
        doc = json.loads(path.read_text(encoding="utf-8"))
        try:
            imdb, seasons = resolve_series_imdb(doc.get("title"), doc.get("yearStart"), session)
        except RuntimeError as e:
            if "quota" in str(e).lower():
                print(f"[wants] stopping: {e}", flush=True)
                break
            imdb, seasons = None, None

        if not imdb:
            doc["seriesImdbID"] = None
            doc["canonicalEpisodeCount"] = 0  # mark as resolved-but-unknown
            path.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
            unresolved += 1
            time.sleep(args.throttle)
            continue

        canon = canonical_episodes(imdb, seasons, session)
        doc["seriesImdbID"] = imdb
        doc["canonicalEpisodeCount"] = len(canon)
        doc["canonicalSeasons"] = seasons
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
        resolved += 1

        have_se, have_titles = have_index(doc)
        for ep in canon:
            key = (path.stem, ep["season"], ep["episode"])
            # Already have it (by S/E or by title)? skip.
            if (ep["season"], ep["episode"]) in have_se:
                continue
            if norm_title(ep["title"]) and norm_title(ep["title"]) in have_titles:
                continue
            if key in existing and existing[key].get("status") == "fulfilled":
                continue
            existing[key] = {
                "seriesID": path.stem,
                "seriesTitle": doc.get("title"),
                "season": ep["season"],
                "episode": ep["episode"],
                "title": ep["title"],
                "episodeImdbID": ep["imdb"],
                "status": "wanted",
                "added_at": existing.get(key, {}).get("added_at", now),
            }
            added_wants += 1
        time.sleep(args.throttle)

    # Recompute stats + write the queue.
    wants = list(existing.values())
    wanted = sum(1 for w in wants if w["status"] == "wanted")
    by_series = {}
    for w in wants:
        if w["status"] == "wanted":
            by_series[w["seriesID"]] = by_series.get(w["seriesID"], 0) + 1
    wants_doc = {
        "schema": 1,
        "updated_at": now,
        "description": "Missing-episode queue: canonical episodes (from OMDb) "
                       "that we don't yet have on Archive. Drained by "
                       "tools/backfill_tv_episodes.py.",
        "stats": {
            "total": len(wants),
            "wanted": wanted,
            "fulfilled": sum(1 for w in wants if w["status"] == "fulfilled"),
            "series_with_gaps": len(by_series),
        },
        "wants": sorted(wants, key=lambda w: (w["seriesID"], w["season"], w["episode"])),
    }
    WANTS_PATH.write_text(json.dumps(wants_doc, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"[wants] resolved {resolved} series ({unresolved} unresolved), "
          f"+{added_wants} new wants", flush=True)
    print(f"[wants] queue now: {wanted:,} wanted episodes across "
          f"{len(by_series):,} series", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
