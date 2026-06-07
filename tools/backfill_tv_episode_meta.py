#!/usr/bin/env python3
"""
backfill_tv_episode_meta.py — fill episode overviews + air dates from TVmaze.

The canonical builder captured episode stills (89%) but left most overviews
unfilled (22%) and many air dates missing (44%) — yet TVmaze's /episodes
endpoint carries summaries (~60%) and air dates (~100%) we never stored. For
each series with a tvmazeID, this fetches the full episode list and fills, by
season+episode match, any `overview`/`airDate` we're missing (HTML stripped).
Free, no key. Idempotent (only fills blanks unless --refresh).

Run: python tools/backfill_tv_episode_meta.py [--refresh] [--limit N]
"""

from __future__ import annotations

import argparse
import glob
import html
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SERIES = REPO / "series"
_TAG = re.compile(r"<[^>]+>")


def strip_html(s: str) -> str:
    return re.sub(r"\s{2,}", " ", html.unescape(_TAG.sub(" ", s or ""))).strip()


def tvmaze_episodes(tvmaze_id: int):
    url = f"https://api.tvmaze.com/shows/{tvmaze_id}/episodes?specials=1"
    req = urllib.request.Request(url, headers={"User-Agent": "ArchiveWatch-tv-eps"})
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    files = [f for f in sorted(glob.glob(str(SERIES / "*.json")))
             if json.load(open(f)).get("tvmazeID")]
    if args.limit:
        files = files[:args.limit]

    print(f"[tv-eps] {len(files)} series with a tvmazeID")
    filled_over = filled_air = touched = 0
    for i, f in enumerate(files, 1):
        d = json.load(open(f))
        eps = tvmaze_episodes(d["tvmazeID"])
        if not eps:
            continue
        # index TVmaze episodes by (season, number)
        byse = {}
        for e in eps:
            s, n = e.get("season"), e.get("number")
            if s is not None and n is not None:
                byse[(s, n)] = e
        changed = False
        for season in d.get("seasons", []):
            for ep in season.get("episodes", []):
                key = (ep.get("seasonNumber"), ep.get("episodeNumber"))
                src = byse.get(key)
                if not src:
                    continue
                if (args.refresh or not (ep.get("overview") or "").strip()):
                    ov = strip_html(src.get("summary") or "")
                    if ov:
                        ep["overview"] = ov; filled_over += 1; changed = True
                if (args.refresh or not ep.get("airDate")) and src.get("airdate"):
                    ep["airDate"] = src["airdate"]; filled_air += 1; changed = True
        if changed:
            touched += 1
            Path(f).write_text(json.dumps(d, ensure_ascii=False, indent=2))
        if i % 25 == 0 or i == len(files):
            print(f"[{i:>4}/{len(files)}] +overviews {filled_over} +airdates {filled_air} "
                  f"({touched} files)")
        time.sleep(0.25)
    print(f"[tv-eps] done: +{filled_over} overviews, +{filled_air} air dates across {touched} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
