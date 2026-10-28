#!/usr/bin/env python3
"""
enrich_tv_ratings.py — IMDb's own rating for every TV series we can name on
IMDb (Decision 171).

A series card carried no IMDb rating, only TVmaze's, and TVmaze rates 48 of the
236 TVmaze shows we serve. TVmaze names the IMDb id of 200 of them
(`externals.imdb`), and OMDb answers that id with IMDb's rating and vote count.
Series with no TVmaze record carry the id build_episode_wants resolved
(`seriesImdbID`). Owner, 2026-10-27: "Please make use of the best ratings
available per content."

For every series/*.json this writes `seriesImdbID`, and `imdbRating` +
`imdbVotes` when OMDb rates an id it calls a SERIES (an id that answers as a
movie or an episode is someone else's, and is not used). It runs after
build_canonical_tv, which rewrites spines from scratch, as enrich_tv_cast
does, so it reads committed caches first and spends network only on what they
lack:

  shared/editorial/tvmaze_externals.json   {tvmazeID: {"imdb", "fetched_at"}}
  shared/editorial/omdb_series_cache.json  OMDb records in omdb_lib's shape,
                                           plus `omdb_type` and `title`, re-asked
                                           after REFRESH_DAYS because a running
                                           show's rating moves. Apart from the
                                           films' omdb_cache.json so the weekly
                                           TV build and the daily film backfill
                                           never commit the same file

A failed or refused fetch keeps the last value: a rating is never erased
because OMDb could not answer. Usage:
    python tools/enrich_tv_ratings.py [--max-calls N] [--offline]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import omdb_lib as L  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
SERIES = REPO / "series"
OMDB_CACHE = REPO / "shared" / "editorial" / "omdb_series_cache.json"
EXTERNALS = REPO / "shared" / "editorial" / "tvmaze_externals.json"
SECRETS = REPO / "Secrets.xcconfig"
REFRESH_DAYS = 30
EXTERNALS_REFRESH_DAYS = 180


def _now():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def _iso(t):
    return t.isoformat().replace("+00:00", "Z")


def _age_days(stamp, now):
    try:
        t = dt.datetime.fromisoformat(str(stamp).replace("Z", "+00:00"))
    except ValueError:
        return 10 ** 6
    return (now - t).total_seconds() / 86400


def _load(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default


def _dump(path, data, indent=2):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=indent) + "\n", encoding="utf-8")
    tmp.replace(path)


def tvmaze_imdb(tvmaze_id):
    """TVmaze's IMDb id for a show: "tt…", None when TVmaze names none.
    Raises RuntimeError when TVmaze could not be asked."""
    req = urllib.request.Request(f"https://api.tvmaze.com/shows/{tvmaze_id}",
                                 headers={"User-Agent": "ArchiveWatch-tv-ratings"})
    last = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                return ((json.load(r).get("externals") or {}).get("imdb")) or None
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code == 429:
                time.sleep(2 ** attempt + 1)
                continue
            raise RuntimeError(f"TVmaze HTTP {e.code}")
        except (urllib.error.URLError, TimeoutError) as e:
            last = e
            time.sleep(2 ** attempt)
    raise RuntimeError(f"TVmaze unreachable ({last or 'rate limited'})")


def series_rating(entry):
    """(rating, votes) from an OMDb cache entry that is a rated SERIES, else None."""
    if not entry or entry.get("error") or entry.get("omdb_type") != "series":
        return None
    r, v = entry.get("imdb_rating"), entry.get("imdb_votes")
    return (r, v) if r else None


def needs_omdb(entry, now):
    if entry is None or entry.get("error") or "omdb_type" not in entry:
        return True
    return _age_days(entry.get("fetched_at"), now) > REFRESH_DAYS


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-calls", type=int, default=300,
                    help="OMDb requests this run (the key's 1,000 a day is shared "
                         "with omdb_backfill's 600).")
    ap.add_argument("--offline", action="store_true",
                    help="apply the caches only; no network")
    ap.add_argument("--throttle", type=float, default=0.15)
    args = ap.parse_args()

    now = _now()
    cache = _load(OMDB_CACHE, {"entries": {}})
    entries = cache.setdefault("entries", {})
    externals = _load(EXTERNALS, {})
    key = None if args.offline else L.load_omdb_key(SECRETS)
    session = requests.Session()
    omdb_calls = tvmaze_calls = 0
    omdb_stopped = None
    files = sorted(SERIES.glob("*.json"))
    have_id = rated = changed = 0

    for f in files:
        spine = json.loads(f.read_text(encoding="utf-8"))
        imdb = spine.get("seriesImdbID")
        tid = spine.get("tvmazeID")
        if not imdb and tid:
            ext = externals.get(str(tid))
            stale = ext is None or _age_days(ext.get("fetched_at"), now) > EXTERNALS_REFRESH_DAYS
            if stale and not args.offline:
                try:
                    ext = {"imdb": tvmaze_imdb(tid), "fetched_at": _iso(now)}
                    externals[str(tid)] = ext
                    tvmaze_calls += 1
                    time.sleep(0.5)          # TVmaze allows 20 calls per 10 s
                except RuntimeError as e:
                    print(f"  [tv-ratings] TVmaze {tid}: {e} (kept what we had)", flush=True)
            imdb = (ext or {}).get("imdb")
        if not imdb:
            continue
        have_id += 1
        entry = entries.get(imdb)
        if needs_omdb(entry, now) and key and omdb_stopped is None and omdb_calls < args.max_calls:
            try:
                rec = L.fetch_omdb(imdb, key, session, full_plot=False)
                omdb_calls += 1
                fresh = L.cache_record(rec, _iso(now))
                fresh["omdb_type"] = (rec or {}).get("omdb_type")
                fresh["title"] = (rec or {}).get("title")
                entries[imdb] = fresh
                entry = fresh
                time.sleep(args.throttle)
            except RuntimeError as e:
                if "quota" in str(e).lower():
                    omdb_stopped = str(e)
                else:
                    print(f"  [tv-ratings] OMDb {imdb}: {e} (kept what we had)", flush=True)
        got = series_rating(entry)
        before = (spine.get("seriesImdbID"), spine.get("imdbRating"), spine.get("imdbVotes"))
        spine["seriesImdbID"] = imdb
        if got:
            spine["imdbRating"], spine["imdbVotes"] = got
            rated += 1
        elif entry is not None and not entry.get("error"):
            # OMDb answered and has no series rating for this id: say so.
            spine.pop("imdbRating", None)
            spine.pop("imdbVotes", None)
        after = (spine.get("seriesImdbID"), spine.get("imdbRating"), spine.get("imdbVotes"))
        if after != before:
            f.write_text(json.dumps(spine, ensure_ascii=False, indent=1), encoding="utf-8")
            changed += 1

    if omdb_calls:
        cache["updated_at"] = _iso(now)
        _dump(OMDB_CACHE, cache)
    if tvmaze_calls:
        _dump(EXTERNALS, dict(sorted(externals.items(), key=lambda kv: int(kv[0]))))
    print(f"[tv-ratings] {len(files)} series: {have_id} with an IMDb id, {rated} rated by "
          f"IMDb; {changed} files changed; OMDb calls {omdb_calls}, TVmaze calls "
          f"{tvmaze_calls}" + (f"; OMDb stopped: {omdb_stopped}" if omdb_stopped else ""),
          flush=True)
    if files and rated == 0:
        print("[tv-ratings] WARNING: no series carries an IMDb rating. Is OMDB_KEY set, "
              "and is the OMDb cache intact?", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
