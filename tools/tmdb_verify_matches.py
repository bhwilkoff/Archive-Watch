#!/usr/bin/env python3
"""
tmdb_verify_matches.py — verify each TMDb-matched catalog item against TMDb's
CANONICAL title+year for its stored tmdbID.

This is the #20b layer: it catches wrong matches that year-only remediation
(remediate_catalog.fix_wrong_external_matches) cannot — same-era LOOKALIKE films
(e.g. two different 1950 films, matched to the wrong one) where the year agrees
but the film is wrong. The new signal is the TITLE comparison.

Because title fuzziness is false-positive-prone (foreign titles, AKAs, subtitle
variants legitimately differ), this tool is REPORT-FIRST: it prints the three
signal buckets for review and, only with --apply, clears the conservative
intersection (year conflict >=5 AND title similarity <0.4 — two independent
signals agreeing). Owner reviews the CI report before applying.

TMDb is a live API (blocked in the sandbox) — this runs in CI with
TMDB_BEARER_TOKEN. Per-tmdbID cache makes re-runs cheap; concurrent (no hard cap).

Usage:
    python tools/tmdb_verify_matches.py            # report only
    python tools/tmdb_verify_matches.py --max 200  # small sample
    python tools/tmdb_verify_matches.py --apply    # clear the BOTH bucket
"""
import argparse
import concurrent.futures as cf
import difflib
import json
import re
import sys
import threading
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T            # noqa: E402
import remediate_catalog as R   # noqa: E402  (source_year + _clear_wrong_artwork)
from enrich_movies import clean_movie_title  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FULL = REPO / "catalog.json"
CACHE = REPO / "shared" / "editorial" / "tmdb_verify_cache.json"
SECRETS = REPO / "Secrets.xcconfig"

# Conservative thresholds — both must trip for an auto-clear.
YEAR_GAP = 5
SIM_FLOOR = 0.4


def _norm(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="clear the BOTH bucket (year+title disagree); default report-only")
    ap.add_argument("--max", type=int, default=0, help="cap items (testing)")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    token = T.load_tmdb_token(SECRETS)
    if not token:
        print("[tmdb-verify] no TMDB_BEARER_TOKEN — skipping.")
        return 0

    cat = json.loads(FULL.read_text(encoding="utf-8"))
    items = cat["items"]
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}

    cands = [it for it in items
             if (it.get("artworkSource") or "").lower() == "tmdb"
             and it.get("contentType") != "tv-series"
             and it.get("tmdbID")]
    if args.max:
        cands = cands[:args.max]
    print(f"[tmdb-verify] {len(cands)} tmdb-matched items to verify", flush=True)

    _tl = threading.local()
    def sess():
        s = getattr(_tl, "s", None)
        if s is None:
            s = requests.Session(); _tl.s = s
        return s

    def fetch(it):
        tid = str(it["tmdbID"])
        if tid in cache:
            return it, cache[tid]
        try:
            rec = T.movie_detail(it["tmdbID"], token, sess())
        except RuntimeError:
            return it, None
        d = {"title": rec.get("title"), "year": rec.get("year")} if rec else {"title": None, "year": None}
        return it, d

    results = []
    with cf.ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
        for it, d in ex.map(fetch, cands):
            if d is not None:
                cache[str(it["tmdbID"])] = d
                results.append((it, d))

    year_conflict = title_mismatch = both = 0
    flagged = []
    samples = []
    for it, d in results:
        canon_t, canon_y = d.get("title"), d.get("year")
        up = _norm(clean_movie_title(it.get("title")))
        sim = difflib.SequenceMatcher(None, up, _norm(canon_t)).ratio() if (canon_t and up) else 1.0
        sy = R.source_year(it)
        ref_y = sy if sy is not None else it.get("year")
        yc = (canon_y is not None and isinstance(ref_y, int) and abs(ref_y - canon_y) >= YEAR_GAP)
        tm = (sim < SIM_FLOOR)
        if yc: year_conflict += 1
        if tm: title_mismatch += 1
        if yc and tm:
            both += 1
            flagged.append((it, sy if isinstance(sy, int) else None))
            if len(samples) < 30:
                samples.append((it.get("title"), canon_t, ref_y, canon_y, round(sim, 2)))

    print(f"[tmdb-verify] checked={len(results)} "
          f"year_conflict(>={YEAR_GAP})={year_conflict} "
          f"title_mismatch(sim<{SIM_FLOOR})={title_mismatch} BOTH={both}", flush=True)
    print("[tmdb-verify] BOTH-bucket samples (uploader | canonical | refYear | canonYear | sim):")
    for t, ct, ry, cy, s in samples:
        print(f"  '{(t or '')[:34]:34}' | '{(ct or '')[:30]:30}' | {ry} | {cy} | {s}")

    if args.apply:
        for it, newy in flagged:
            R._clear_wrong_artwork(it, newy)
        FULL.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
        print(f"[tmdb-verify] APPLIED: cleared {len(flagged)} wrong matches, wrote {FULL.name}")
    else:
        print("[tmdb-verify] report-only (pass --apply to clear the BOTH bucket)")

    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
