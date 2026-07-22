#!/usr/bin/env python3
"""
resource_posters_tmdb.py — re-source DURABLE professional posters from TMDb for
films whose current artwork ROTTED (posterDead) or is a frame-still fallback
(generated), but that already carry an authoritative imdbID/tmdbID.

WHY: two poster-quality problems converge on the same fixable population:
  * validate_posters.py (Decision 044) demotes a dead poster (404 on a rotting
    host — omdb/commons/tvdb/…) to the archive.org services/img thumbnail and
    marks `posterDead=True`. That leaves a real-but-plain frame, never a
    designed poster.
  * batch_covers.py (Decision 023) fills poster-less items with a frame still
    (`artworkSource="generated"`) — the FALLBACK, not designed marketing art.
Both classes are LOW RISK to upgrade when the item already has an imdbID/tmdbID,
because TMDb can be resolved by that authoritative key with NO fuzzy title match
(Decision 026 — trust the Archive imdbID). image.tmdb.org is the durable CDN
validate_posters TRUSTS (skips it from decay checks), so a re-sourced TMDb poster
is the highest-leverage, lowest-risk win in the poster-quality loop.

WHAT (per candidate, popularity-first, resumable):
  1. Resolve the TMDb movie — prefer the stored tmdbID (/movie/{id}); else
     /find/{imdbID}?external_source=imdb_id (movie_results).
  2. CORROBORATE even if a stored id is wrong (defense over Decision 026):
     - if BOTH the item year and the TMDb release year exist and |Δ| > 2 →
       DO NOT source; mark `posterMismatch` + `tmdbPosterCheckedAt` and skip.
     - if the item is colorMode=="bw" and the TMDb release year >= 1970 →
       skip (Decision 025 old→modern guard; a B&W film is not a modern release).
  3. If TMDb has a poster_path → set posterURL = image.tmdb.org/t/p/w780{path},
     artworkSource="tmdb", hasRealArtwork=True, CLEAR posterDead/posterDeadURL,
     fill backdropURL if missing, store tmdbID if newly resolved.
  4. If TMDb has NO poster for this id → leave the film UNCHANGED (keep its
     generated frame / archive thumb — NEVER delete a generated cover), just
     mark `tmdbPosterCheckedAt` so it isn't re-queried every run.

SAFE over exhaustive: any doubt (no id, year mismatch, bw→modern, ambiguous) →
skip, never source a wrong poster. Additive, idempotent, reversible.

Run: python tools/resource_posters_tmdb.py [--limit N] [--dry-run]
                                           [--reprobe-days 30] [--workers 6]
Catalog I/O via the local catalog.json (catalog_release.py fetch first in CI).
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import datetime as dt
import json
import sys
import threading
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T       # noqa: E402
import omdb_lib as O       # noqa: E402  (apply_rich — shared, consistent setters)

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"

# FILMS only — TV + commercials are out of scope (different pipelines / rights).
FILM_TYPES = {
    "feature-film", "silent-film", "short-film", "animation", "newsreel",
    "ephemeral", "home-movie", "documentary", "trailer",
}
# Artwork we consider NON-professional and thus eligible to upgrade.
NONPRO_SOURCES = {"generated", "archive", None, ""}


def load(p):
    return json.loads(p.read_text(encoding="utf-8"))


def dump(p, d):
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)


def _now():
    return (dt.datetime.now(dt.timezone.utc)
            .isoformat(timespec="seconds").replace("+00:00", "Z"))


def _item_year(it):
    """Best available year for corroboration: the stored year, else the year of
    the Archive releaseDate (YYYY-...)."""
    y = it.get("year")
    if isinstance(y, int) and 1870 <= y <= 2100:
        return y
    rd = it.get("releaseDate") or ""
    if len(rd) >= 4 and rd[:4].isdigit():
        return int(rd[:4])
    return None


def _pop(it):
    """Popularity-first ordering — homepage-leading items get posters first."""
    return (it.get("popularityScore") or 0,
            it.get("views30d") or 0,
            it.get("downloads") or 0)


def is_target(it):
    if it.get("contentType") not in FILM_TYPES:
        return False
    if it.get("excluded"):
        return False
    if not (it.get("imdbID") or it.get("tmdbID")):
        return False
    # Eligible iff the CURRENT artwork is non-professional: a demoted-dead poster
    # OR a generated/archive/empty source. (A live professional poster is left.)
    if it.get("posterDead") is True:
        return True
    return it.get("artworkSource") in NONPRO_SOURCES


def _recently_probed(it, reprobe_days):
    """Skip items probed within `reprobe_days` (resumable across runs). A hit
    clears the marker implicitly by moving the item out of the target set."""
    if reprobe_days <= 0:
        return False
    ts = it.get("tmdbPosterCheckedAt")
    if not ts:
        return False
    try:
        when = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return False
    age = dt.datetime.now(dt.timezone.utc) - when
    return age.days < reprobe_days


def apply_poster(it, rec, now):
    """Set the TMDb poster (+ backdrop) on `it` via the shared omdb_lib setters,
    then clear the posterDead markers and stamp the probe time. Returns a status
    string. Only called when rec has a poster_url."""
    # apply_rich handles posterURL/artworkSource/hasRealArtwork/backdrop with the
    # same rules the OMDb path uses. Its posterDead guard only blocks re-applying
    # the EXACT dead URL — a fresh image.tmdb.org URL never equals posterDeadURL,
    # so a live TMDb poster passes.
    was_dead = it.get("posterDead") is True
    changed = O.apply_rich(it, rec)
    if it.get("tmdbID") is None and rec.get("tmdb_id"):
        it["tmdbID"] = rec["tmdb_id"]
        changed = True
    # Clear the demotion markers now that a durable poster is in place.
    for k in ("posterDead", "posterDeadURL", "posterChecked"):
        if k in it:
            del it[k]
            changed = True
    it.pop("posterMismatch", None)
    it["tmdbPosterCheckedAt"] = now
    return "upgraded_dead" if was_dead else "upgraded_generated", changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0,
                    help="Max items to attempt this run (0 = all targets).")
    ap.add_argument("--workers", type=int, default=6,
                    help="Concurrent TMDb fetchers (TMDb ~40 req/10s; keep modest "
                         "to respect the connection-discipline memory).")
    ap.add_argument("--chunk", type=int, default=500,
                    help="Checkpoint (write catalog) after each chunk — resumable.")
    ap.add_argument("--reprobe-days", type=int, default=30,
                    help="Skip items whose tmdbPosterCheckedAt is newer than this "
                         "(so a no-poster item isn't re-queried every run).")
    ap.add_argument("--dry-run", action="store_true",
                    help="Resolve + report the distribution; write nothing.")
    args = ap.parse_args()

    token = T.load_tmdb_token(SECRETS)
    if not token:
        print("[resource-posters] no TMDB_BEARER_TOKEN — skipping (not an error).")
        return 0

    catalog = load(CATALOG)
    items = catalog["items"] if isinstance(catalog, dict) else catalog

    targets = [it for it in items if is_target(it)
               and not _recently_probed(it, args.reprobe_days)]
    targets.sort(key=_pop, reverse=True)
    total_targets = sum(1 for it in items if is_target(it))
    work = targets[:args.limit] if args.limit else targets
    print(f"[resource-posters] {len(work)} to attempt "
          f"({total_targets} total id-anchored non-pro targets, "
          f"{len(items)} catalog){' DRY-RUN' if args.dry_run else ''}", flush=True)

    _tl = threading.local()

    def sess():
        s = getattr(_tl, "s", None)
        if s is None:
            s = requests.Session()
            _tl.s = s
        return s

    def fetch(it):
        """Resolve the TMDb detail record for one item. Returns (it, rec, status).
        status 'fatal' → auth/rate-limit, stop after this chunk."""
        try:
            mid = it.get("tmdbID")
            if not mid:
                mid = T.find_by_imdb(it.get("imdbID"), token, sess())
            if not mid:
                return (it, None, "no_tmdb_id")
            rec = T.movie_detail(mid, token, sess())
            if not rec:
                return (it, None, "no_detail")
            return (it, rec, "ok")
        except RuntimeError:
            return (it, None, "fatal")

    now = _now()
    stats = {"upgraded_dead": 0, "upgraded_generated": 0,
             "skip_year_mismatch": 0, "skip_bw_modern": 0,
             "no_tmdb_poster": 0, "no_tmdb_id": 0, "no_detail": 0}
    mismatch_examples, bw_examples, upgrade_examples = [], [], []
    tried = 0
    stop = False

    def checkpoint():
        if not args.dry_run:
            dump(CATALOG, catalog)

    for start in range(0, len(work), args.chunk):
        if stop:
            break
        batch = work[start:start + args.chunk]
        with cf.ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
            results = list(ex.map(fetch, batch))
        for it, rec, status in results:
            tried += 1
            if status == "fatal":
                stop = True
                continue
            if status in ("no_tmdb_id", "no_detail"):
                stats[status] += 1
                # Can't resolve — leave unchanged, don't re-probe every run.
                it["tmdbPosterCheckedAt"] = now
                continue

            tmdb_year = rec.get("year")
            iyear = _item_year(it)
            # (2) Year corroboration — the safety net if an id was mis-assigned.
            if iyear and tmdb_year and abs(iyear - tmdb_year) > 2:
                stats["skip_year_mismatch"] += 1
                it["posterMismatch"] = f"item={iyear} tmdb={tmdb_year}"
                it["tmdbPosterCheckedAt"] = now
                if len(mismatch_examples) < 8:
                    mismatch_examples.append(
                        (it.get("title"), iyear, tmdb_year, it.get("archiveID")))
                continue
            # (2b) B&W film matched to a modern release → wrong (Decision 025).
            if it.get("colorMode") == "bw" and tmdb_year and tmdb_year >= 1970:
                stats["skip_bw_modern"] += 1
                it["posterMismatch"] = f"bw item={iyear} tmdb={tmdb_year}"
                it["tmdbPosterCheckedAt"] = now
                if len(bw_examples) < 8:
                    bw_examples.append(
                        (it.get("title"), iyear, tmdb_year, it.get("archiveID")))
                continue

            if not rec.get("poster_url"):
                # (4) No poster on TMDb — keep the generated/archive art untouched.
                stats["no_tmdb_poster"] += 1
                it["tmdbPosterCheckedAt"] = now
                continue

            # (3) Durable poster available — upgrade.
            was_dead = it.get("posterDead") is True
            old_url = it.get("posterURL")
            if args.dry_run:
                key = "upgraded_dead" if was_dead else "upgraded_generated"
                stats[key] += 1
                if len(upgrade_examples) < 12:
                    upgrade_examples.append(
                        (it.get("title"), _item_year(it), rec.get("year"),
                         was_dead, old_url, rec.get("poster_url"),
                         it.get("archiveID")))
                continue
            key, _changed = apply_poster(it, rec, now)
            stats[key] += 1
            if len(upgrade_examples) < 12:
                upgrade_examples.append(
                    (it.get("title"), _item_year(it), rec.get("year"),
                     was_dead, old_url, it.get("posterURL"), it.get("archiveID")))
        checkpoint()
        done = min(start + args.chunk, len(work))
        print(f"[resource-posters] {min(done, tried)}/{len(work)} tried · "
              f"up(dead)={stats['upgraded_dead']} up(gen)={stats['upgraded_generated']} · "
              f"skip(yr)={stats['skip_year_mismatch']} skip(bw)={stats['skip_bw_modern']} · "
              f"noPoster={stats['no_tmdb_poster']}"
              f"{' · STOPPING (auth/quota)' if stop else ''}", flush=True)

    # -------- report --------
    print("\n[resource-posters] === distribution ===", flush=True)
    for k in ("upgraded_dead", "upgraded_generated", "skip_year_mismatch",
              "skip_bw_modern", "no_tmdb_poster", "no_tmdb_id", "no_detail"):
        print(f"  {k:22s} {stats[k]}", flush=True)
    up_total = stats["upgraded_dead"] + stats["upgraded_generated"]
    print(f"  {'UPGRADED total':22s} {up_total}", flush=True)

    if upgrade_examples:
        print("\n[resource-posters] example upgrades (title · itemYr→tmdbYr · "
              "wasDead · old → new):", flush=True)
        for t, iy, ty, dead, old, new, aid in upgrade_examples:
            print(f"  • {t!r} ({iy}→{ty}) dead={dead} [{aid}]\n"
                  f"      OLD: {old}\n      NEW: {new}", flush=True)
    if mismatch_examples:
        print("\n[resource-posters] example YEAR-mismatch skips "
              "(title · itemYr vs tmdbYr):", flush=True)
        for t, iy, ty, aid in mismatch_examples:
            print(f"  • {t!r}: item={iy} tmdb={ty} [{aid}] — SKIPPED", flush=True)
    if bw_examples:
        print("\n[resource-posters] example B&W→modern skips:", flush=True)
        for t, iy, ty, aid in bw_examples:
            print(f"  • {t!r}: bw, item={iy} tmdb={ty} [{aid}] — SKIPPED", flush=True)

    if not args.dry_run:
        checkpoint()
        print(f"\n[resource-posters] wrote catalog.json "
              f"({up_total} posters re-sourced)", flush=True)
    else:
        print("\n[resource-posters] dry-run — nothing written.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
