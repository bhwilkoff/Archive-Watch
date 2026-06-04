#!/usr/bin/env python3
"""
tmdb_fill_synopsis.py — fill EMPTY synopses from TMDb for items that already
carry a tmdbID.

These items were matched to TMDb by an earlier enrichment pass (so the tmdbID
is trusted) but landed with no synopsis — the match happened before TMDb had
an overview, or the enrich step only took identity/artwork. A direct
/movie/{tmdbID} fetch recovers the overview. Measured 100% overview-present on
the empty-synopsis-with-tmdbID population (Decision 007: TMDb is the no-cap
primary text source).

SAFE by construction:
  - only writes items whose synopsis is currently empty (never overwrites)
  - only uses the trusted existing tmdbID (no new matching, no false matches)
  - skips empties TMDb also has empty (no fabrication)
  - per-tmdbID JSON cache → cheap, resumable re-runs

Run: TMDB_BEARER_TOKEN env or Secrets.xcconfig. Mutates ./catalog.json in
place (fetch via catalog_release.py first; publish after).
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
CACHE = REPO / "tools" / ".tmdb_synopsis_cache.json"


def _syn(it) -> str:
    s = it.get("synopsis") or ""
    return (" ".join(s) if isinstance(s, list) else s).strip()


def main() -> int:
    token = T.load_tmdb_token(SECRETS)
    if not token:
        print("[tmdb-synopsis] no TMDB_BEARER_TOKEN — skipping.")
        return 0

    catalog = json.loads(CATALOG.read_text())
    items = catalog["items"]
    targets = [it for it in items if not _syn(it) and it.get("tmdbID")]
    print(f"[tmdb-synopsis] {len(targets)} empty-synopsis items with a tmdbID")

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    sess = requests.Session()
    filled = empty = errors = 0

    for i, it in enumerate(targets, 1):
        tid = str(it["tmdbID"])
        if tid in cache:
            plot = cache[tid]
        else:
            try:
                d = T.movie_detail(it["tmdbID"], token, sess)
                plot = (d or {}).get("plot") or ""
                cache[tid] = plot
                time.sleep(0.18)  # ~40 req / 10s ceiling, comfortably under
            except Exception as e:  # noqa: BLE001
                errors += 1
                if errors <= 5:
                    print(f"  ! {tid}: {e}")
                continue
        if plot and len(plot.strip()) > 20:
            it["synopsis"] = plot.strip()
            filled += 1
        else:
            empty += 1
        if i % 200 == 0:
            print(f"  ... {i}/{len(targets)} (filled {filled})")
            CACHE.write_text(json.dumps(cache))

    CACHE.write_text(json.dumps(cache))
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False))
    print(f"[tmdb-synopsis] filled {filled} | TMDb-also-empty {empty} | "
          f"errors {errors} | wrote catalog.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
