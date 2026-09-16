#!/usr/bin/env python3
"""
synopsis_provenance.py — every synopsis in the catalog says where it came
from, and an API's text always beats the uploader's.

Why (owner, 2026-09-16): "I continue to find descriptions and other metadata
that are not appropriate for the films... many instances of uploader
information and reviews instead of information about the film." Measured
before this tool: 27,159 visible items carried a synopsis and 22,192 of them
carried NO source stamp — the archive.org `description`, i.e. whatever the
uploader typed ("I've been researching newly public domain films from 1929
and earlier, so I'm uploading the best copies..."). 11,229 of those had a
tmdbID, so TMDb's own overview existed and was never used: the TMDb fillers
only ever filled EMPTY synopses ("never overwrites") and did not stamp what
they wrote. The app could not tell an overview from a reviewer's opinion.

Rules:
  1. An item with a tmdbID (film types) gets TMDb's overview as its synopsis,
     `synopsisSource = "tmdb"`, REPLACING unstamped/archive text. Text already
     stamped omdb / wikipedia / tvmaze / agent-reviewed is left alone — each
     is a checked source in its own right (Decisions 007/008).
  2. Every remaining synopsis with no stamp is stamped `"archive"`: the
     uploader's description, which the clients now LABEL as such rather than
     present as the film's synopsis (see the design docs, 2026-09-16).
  3. An item whose TMDb overview is empty keeps what it had, stamped archive.

The TMDb overviews are cached in shared/editorial/tmdb_overview_cache.json
(committed, ~11k entries) so re-runs and CI need no fetch. Report-first:
--apply writes catalog.json.

Usage:
    python3 tools/synopsis_provenance.py            # fetch + report
    python3 tools/synopsis_provenance.py --apply
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
CACHE = REPO / "shared/editorial/tmdb_overview_cache.json"
FILM_TYPES = {"feature-film", "silent-film", "short-film", "animation", "documentary",
              "newsreel", "ephemeral", "commercial", "tv-special"}
CHECKED = {"tmdb", "omdb", "wikipedia", "tvmaze", "agent-reviewed"}


def syn(it) -> str:
    s = it.get("synopsis") or ""
    return (" ".join(s) if isinstance(s, list) else s).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--sleep", type=float, default=0.05)
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text())
    items = [it for it in cat["items"] if not it.get("excluded")]
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}

    targets = [it for it in items if it.get("tmdbID") and it.get("contentType") in FILM_TYPES
               and (it.get("synopsisSource") or "") not in CHECKED]
    todo = [it for it in targets if str(it["tmdbID"]) not in cache]
    if args.limit:
        todo = todo[: args.limit]
    print(f"visible {len(items)} · tmdbID film items with an unchecked synopsis {len(targets)} · to fetch {len(todo)}")

    token = T.load_tmdb_token(SECRETS)
    if todo and not token:
        sys.exit("no TMDB_BEARER_TOKEN — set Secrets.xcconfig or the env")
    # Eight in flight: movie_detail carries credits, so one call is ~1 s of
    # latency, and sequentially 11k of them is three hours. TMDb's ceiling is
    # ~50 req/s; eight workers with a short sleep stays far under it.
    from concurrent.futures import ThreadPoolExecutor, as_completed
    import threading
    local = threading.local()

    def one(it):
        if not hasattr(local, "sess"):
            local.sess = requests.Session()
        tid = str(it["tmdbID"])
        try:
            d = T.movie_detail(it["tmdbID"], token, local.sess)
            time.sleep(args.sleep)
            return tid, ((d or {}).get("plot") or "").strip(), None
        except Exception as e:  # noqa: BLE001
            return tid, None, str(e)[:100]

    errors = done = 0
    with ThreadPoolExecutor(max_workers=8) as ex:
        for tid, plot, err in (f.result() for f in as_completed([ex.submit(one, it) for it in todo])):
            done += 1
            if err:
                errors += 1
                if errors <= 5:
                    print(f"  ! {tid}: {err}")
                continue
            cache[tid] = plot
            if done % 500 == 0:
                CACHE.write_text(json.dumps(cache, ensure_ascii=False))
                print(f"  fetched {done}/{len(todo)} (errors {errors})")
    CACHE.write_text(json.dumps(cache, ensure_ascii=False))

    replaced = kept_empty = stamped_archive = 0
    examples = []
    for it in items:
        src = it.get("synopsisSource") or ""
        if src in CHECKED:
            continue
        tid = str(it.get("tmdbID") or "")
        ov = cache.get(tid, "") if it.get("contentType") in FILM_TYPES else ""
        if ov and len(ov) > 20:
            if len(examples) < 6 and syn(it) and syn(it) != ov:
                examples.append((it["archiveID"][:34], syn(it)[:70], ov[:70]))
            if args.apply:
                it["synopsis"] = ov
                it["synopsisSource"] = "tmdb"
            replaced += 1
        elif syn(it):
            if args.apply:
                it["synopsisSource"] = "archive"
            stamped_archive += 1
        else:
            kept_empty += 1
    print(f"tmdb overview adopted: {replaced} · stamped archive: {stamped_archive} · no synopsis at all: {kept_empty}")
    for a, b, c in examples:
        print(f"  {a}\n     was: {b!r}\n     now: {c!r}")
    if args.apply:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False, separators=(",", ":")))
        print("wrote catalog.json")
    else:
        print("(report only — pass --apply to write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
