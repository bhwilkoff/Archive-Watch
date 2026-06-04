#!/usr/bin/env python3
"""
tmdb_cast_images.py — fill cast[].profilePath (and missing character names) from
TMDb credits (#4b), so the Detail cast/crew row (#4) shows real faces instead of
initials. Enrichment only ever stored cast names; this backfills the images.

TMDb is reachable (token in Secrets.xcconfig / OMDB-style CI secret). Per-tmdbID
cache makes re-runs cheap; concurrent (no hard rate cap). REPORT by default;
--apply writes the catalog.

Usage:
    python tools/tmdb_cast_images.py --max 500     # sample (report)
    python tools/tmdb_cast_images.py --apply       # full backfill
"""
import argparse
import concurrent.futures as cf
import json
import re
import sys
import threading
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FULL = REPO / "catalog.json"
CACHE = REPO / "shared" / "editorial" / "tmdb_cast_cache.json"
SECRETS = REPO / "Secrets.xcconfig"


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--max", type=int, default=0)
    ap.add_argument("--workers", type=int, default=12)
    args = ap.parse_args()

    token = T.load_tmdb_token(SECRETS)
    if not token:
        print("[cast] no TMDB_BEARER_TOKEN — skipping.")
        return 0

    cat = json.loads(FULL.read_text(encoding="utf-8"))
    items = cat["items"]
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}

    cands = [it for it in items
             if it.get("tmdbID") and it.get("cast")
             and any(not c.get("profilePath") for c in it["cast"])]
    if args.max:
        cands = cands[:args.max]
    need = list(dict.fromkeys(str(it["tmdbID"]) for it in cands
                             if str(it["tmdbID"]) not in cache))
    print(f"[cast] {len(cands)} items need profiles; {len(need)} tmdbIDs to fetch", flush=True)

    _tl = threading.local()
    def sess():
        s = getattr(_tl, "s", None)
        if s is None:
            s = requests.Session(); _tl.s = s
        return s

    def fetch(tid):
        try:
            r = sess().get(f"{T.TMDB_API}/movie/{tid}/credits",
                           headers=T._headers(token), timeout=20)
            if not r.ok:
                return tid, None
            cast = r.json().get("cast") or []
            return tid, {norm(c.get("name")): {"p": c.get("profile_path"),
                                               "c": c.get("character")}
                         for c in cast if c.get("name")}
        except Exception:
            return tid, None

    with cf.ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
        for i, (tid, m) in enumerate(ex.map(fetch, need)):
            if m is not None:
                cache[tid] = m
            if i and i % 1000 == 0:
                print(f"[cast] fetched {i}/{len(need)}", flush=True)

    profiles = chars = 0
    samples = []
    for it in cands:
        m = cache.get(str(it["tmdbID"]))
        if not m:
            continue
        for c in it["cast"]:
            info = m.get(norm(c.get("name")))
            if not info:
                continue
            if not c.get("profilePath") and info.get("p"):
                c["profilePath"] = info["p"]; profiles += 1
                if len(samples) < 12:
                    samples.append(f"{it.get('title','')[:28]} / {c.get('name')} -> {info['p']}")
            if not c.get("character") and info.get("c"):
                c["character"] = info["c"]; chars += 1

    print(f"[cast] filled profiles={profiles} characters={chars}")
    for s in samples:
        print("   " + s)

    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
    if args.apply:
        FULL.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
        print(f"[cast] APPLIED: wrote {FULL.name}")
    else:
        print("[cast] report-only (pass --apply to write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
