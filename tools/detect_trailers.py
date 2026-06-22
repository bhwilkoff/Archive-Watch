#!/usr/bin/env python3
"""
detect_trailers.py — find items that are TRAILERS/CLIPS posing as the full film and
reclassify them so they never headline Home or sit in the Movies grid as the feature.

The tell: the archive.org video file's ACTUAL duration is a small fraction of the
runtime the catalog matched from TMDb/IMDb. e.g. "One Flew Over the Cuckoo's Nest
(1975)" matched the real 133-min film (runtimeSeconds 7980) but the actual file is
161 s — a trailer (and a copyrighted studio film to boot).

Action per detected trailer (owner rule: trailers available, but NOT on Home and NOT
posing as full films):
  contentType -> "trailer"   (drops out of feature-film grids + Home shelves, which
                              all filter on the film content-types; still searchable
                              and playable)
  isTrailer = true, trueRuntimeSeconds = <actual>   (additive markers)
A trailer of a MODERN (>=1978) film is additionally `excluded` (we don't host modern
copyrighted promo material).

Bounded + resumable (trailerChecked marker). Fetches archive.org metadata per item,
so it runs popularity-first and in capped batches like the other audit tools.
Catalog lives on the release (Decision 018): fetch -> detect -> publish.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
FILM_TYPES = {"feature-film", "tv-special", "feature"}   # things that can pose as a film
MODERN_YEAR = 1978


def actual_duration(iaid, session):
    """Longest video file's length (seconds) from archive.org metadata, or None."""
    try:
        m = A.archive_meta(iaid, session)
    except Exception:
        return None
    best = 0.0
    for f in m.get("files") or []:
        n = (f.get("name") or "").lower()
        if n.endswith((".mp4", ".m4v", ".mkv", ".ogv", ".webm", ".avi")):
            try:
                best = max(best, float(f.get("length") or 0))
            except (TypeError, ValueError):
                pass
    return best or None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--min-runtime", type=int, default=1800,
                    help="only check items whose matched runtime is at least this (s)")
    ap.add_argument("--frac", type=float, default=0.45,
                    help="actual/runtime below this AND actual<max-clip => trailer")
    ap.add_argument("--max-clip", type=int, default=900, help="trailers are under this (s)")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[trailer] no catalog.json (catalog_release.py fetch first)"); return 2
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    def candidate(it):
        return (it.get("downloadURL") and not it.get("excluded")
                and not it.get("trailerChecked")
                and it.get("contentType") in FILM_TYPES
                and (it.get("runtimeSeconds") or 0) >= args.min_runtime)

    targets = [it for it in items if candidate(it)]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[trailer] checking {len(targets)} long-runtime film items", flush=True)
    if not targets:
        return 0

    lock = threading.Lock()
    done = flagged = excluded = 0

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    def work(it):
        dur = actual_duration(it["archiveID"], requests.Session())
        nonlocal done, flagged, excluded
        with lock:
            done += 1
            if dur is None:                       # couldn't read — retry next run
                return
            it["trailerChecked"] = True
            rt = it.get("runtimeSeconds") or 0
            if dur < args.max_clip and rt and dur < args.frac * rt:
                it["contentType"] = "trailer"
                it["isTrailer"] = True
                it["trueRuntimeSeconds"] = int(dur)
                flagged += 1
                # A trailer of a MODERN film, or of a clearly-recognized major
                # studio film (high IMDb vote count = copyrighted, e.g. One Flew
                # Over the Cuckoo's Nest), is copyrighted promo — don't host it.
                if (it.get("year") or 0) >= MODERN_YEAR or (it.get("imdbVotes") or 0) >= 50000:
                    it["excluded"] = True
                    it["rightsAudit"] = "copyrighted_trailer"
                    excluded += 1
                print(f"  TRAILER {it['archiveID'][:34]:34} {int(dur)}s vs {rt}s runtime"
                      f"{' [EXCLUDED modern]' if it.get('excluded') else ''}", flush=True)
            if done % 50 == 0:
                flush()

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for _ in as_completed([ex.submit(work, it) for it in targets]):
            pass
    flush()
    print(f"[trailer] done: {done} checked, {flagged} reclassified trailers, "
          f"{excluded} modern excluded", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
