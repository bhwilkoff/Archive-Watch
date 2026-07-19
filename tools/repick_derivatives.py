#!/usr/bin/env python3
"""
repick_derivatives.py — fix films whose baked downloadURL is a container AVPlayer
can't play: `.ogv` (Theora), `.mkv`, `.avi`, `.wmv`, `.flv`, `.divx`, `_mpeg2`.

CORRECTION 2026-07-19 (measured, not assumed): this docstring previously claimed
~4,240 items point at a `512Kb MPEG4` file that "iOS AVPlayer won't decode".
That is FALSE and it is a costly thing to believe — acting on it de-verified
1,205 perfectly playable titles before ffprobe settled it. archive.org's
"512Kb MPEG4" names a DERIVATIVE PRESET (bitrate), not the codec: the files are
H.264. Sampled 7 live 512kb.mp4 derivatives, 7/7 `codec_name=h264`
(`the_stranger`, `Popeye_forPresident`, `McLintock`, `superman_1941`,
`horror_express`, `Return_of_the_Kung_Fu_Dragon`, `Teaserama` — the first
reporting profile "Constrained Baseline", tag `avc1`).

The `_BAD` regex below has always been right to exclude 512kb; only this
docstring was wrong. If you doubt it again, re-run:
    ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
      -of csv=p=0 <a 512kb.mp4 URL>

Per affected item: fetch archive.org metadata, re-pick the best derivative, and
if a BETTER playable one now exists (H.264/plain MP4, different from the current
file), rewrite downloadURL (+ videoFile). Resumable via derivativeRepicked;
bounded (per-item metadata fetch). Catalog on the release (Decision 018):
fetch -> repick -> publish.
"""

from __future__ import annotations

import argparse
import json
import re
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

# downloadURL CONTAINERS AVPlayer genuinely cannot play. NOT 512kb MPEG-4 Part 2:
# owner confirmed on-device that those DO play (Gumbasia) — Apple's software decoder
# still handles Simple-Profile MP4-container files even though the spec sheet dropped
# it. Only the non-MP4 containers (Theora/Ogg, Matroska, AVI/DivX, MPEG-PS) are stuck.
_BAD = re.compile(r"\.(ogv|mkv|avi|wmv|flv|divx)$|_mpeg2", re.I)   # NOT .mov (QuickTime plays), NOT 512kb (plays)


def _is_good_pick(name: str, fmt: str) -> bool:
    """A playable target = an MP4/M4V (H.264 OR MPEG-4-in-MP4 both play on iOS).
    pick_video already ranks H.264 first, so it returns the best available."""
    return name.lower().endswith((".mp4", ".m4v"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--sleep", type=float, default=0.1)
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[repick] no catalog.json (catalog_release.py fetch first)"); return 2
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    def candidate(it):
        u = it.get("downloadURL") or ""
        return (u and not it.get("derivativeRepicked")
                and _BAD.search(u.rsplit("/", 1)[-1]))

    targets = [it for it in items if candidate(it)]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[repick] {len(targets)} items with an unplayable derivative", flush=True)
    if not targets:
        return 0

    lock = threading.Lock()
    done = upgraded = noupgrade = 0

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    def work(it):
        nonlocal done, upgraded, noupgrade
        try:
            meta = A.archive_meta(it["archiveID"], requests.Session())
        except Exception:
            return                                    # unreachable — retry next run
        best = A.pick_video(meta.get("files") or [])
        with lock:
            done += 1
            if not best:
                it["derivativeRepicked"] = True; noupgrade += 1; return
            cur = (it.get("downloadURL") or "").rsplit("/", 1)[-1]
            name, fmt = best.get("name") or "", best.get("format") or ""
            if name and name != requests.utils.unquote(cur) and _is_good_pick(name, fmt):
                it["downloadURL"] = A.download_url(it["archiveID"], name)
                if isinstance(it.get("videoFile"), dict):
                    it["videoFile"]["name"] = name
                    it["videoFile"]["format"] = fmt
                upgraded += 1
                print(f"  UPGRADE {it['archiveID'][:30]:30} -> {name} ({fmt})", flush=True)
            else:
                noupgrade += 1                        # only legacy exists — needs transcode
            it["derivativeRepicked"] = True
            if done % 50 == 0:
                flush(); print(f"  [{done}/{len(targets)}] {upgraded} upgraded", flush=True)
        time.sleep(args.sleep)

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for _ in as_completed([ex.submit(work, it) for it in targets]):
            pass
    flush()
    print(f"[repick] done: {done} checked, {upgraded} upgraded to H.264, "
          f"{noupgrade} still legacy-only (need transcode)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
