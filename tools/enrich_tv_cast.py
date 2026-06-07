#!/usr/bin/env python3
"""
enrich_tv_cast.py — add cast/crew to TV series from TVmaze (free, no key).

TV had ZERO cast info (the canonical builder pulls episodes + stills but never
cast). For every series/*.json with a tvmazeID, this fetches TVmaze
/shows/{id}/cast and writes a `cast` array onto the series file in the same shape
the app's movie cast uses: {name, character, order, profilePath}. Deduped by
person (TVmaze lists recasts separately), capped, idempotent (skips files that
already have cast unless --refresh).

Series files are committed + served from Pages, so the SeriesDetailView picks the
cast up after a push. Run: python tools/enrich_tv_cast.py [--refresh] [--limit N]
"""

from __future__ import annotations

import argparse
import glob
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SERIES = REPO / "series"
CAP = 18


def tvmaze_cast(tvmaze_id: int):
    url = f"https://api.tvmaze.com/shows/{tvmaze_id}/cast"
    req = urllib.request.Request(url, headers={"User-Agent": "ArchiveWatch-tv-cast"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(2 ** attempt + 1); continue
            return None
        except (urllib.error.URLError, TimeoutError):
            time.sleep(2 ** attempt); continue
    return None


def to_cast(raw) -> list:
    """TVmaze cast -> [{name, character, order, profilePath}], deduped by person."""
    out, seen = [], set()
    for entry in raw or []:
        person = entry.get("person") or {}
        name = (person.get("name") or "").strip()
        if not name or name in seen:
            continue
        seen.add(name)
        char = ((entry.get("character") or {}).get("name") or "").strip()
        img = (person.get("image") or {})
        profile = img.get("medium") or img.get("original")
        out.append({"name": name, "character": char, "order": len(out),
                    "profilePath": profile})
        if len(out) >= CAP:
            break
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="re-fetch even if cast exists")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    files = sorted(glob.glob(str(SERIES / "*.json")))
    todo = []
    for f in files:
        d = json.load(open(f))
        if not d.get("tvmazeID"):
            continue
        if d.get("cast") and not args.refresh:
            continue
        todo.append((f, d))
    if args.limit:
        todo = todo[:args.limit]

    print(f"[tv-cast] {len(files)} series files | {len(todo)} need cast")
    filled = 0
    for i, (f, d) in enumerate(todo, 1):
        raw = tvmaze_cast(d["tvmazeID"])
        cast = to_cast(raw)
        if cast:
            d["cast"] = cast
            Path(f).write_text(json.dumps(d, ensure_ascii=False, indent=2))
            filled += 1
        if i % 25 == 0 or i == len(todo):
            print(f"[{i:>4}/{len(todo)}] filled {filled}  ({Path(f).name})")
        time.sleep(0.25)   # be polite to TVmaze
    print(f"[tv-cast] done: cast written to {filled} series files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
