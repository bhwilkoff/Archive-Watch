#!/usr/bin/env python3
"""
classify_color.py — tag every catalog item as color or black-and-white.

Samples a few frames from the item's OWN video with ffmpeg and averages the
`signalstats` SATAVG (mean chroma saturation). The split is decisive: B&W
footage (silent OR sound) reads ~0; color reads ~15-25. Default threshold 8.
Writes `colorMode` ("color" | "bw") into ./catalog.json.

Resumable (skips already-classified items), popularity-first, concurrent.
Catalog lives on the release (Decision 018): fetch -> this -> publish.

Run (long, network-bound — wrap in `caffeinate -i` for a full pass):
  python tools/classify_color.py [--limit N] [--workers 10] [--threshold 8]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SAMPLE_POINTS = (0.2, 0.5, 0.8)        # fractions of runtime to sample
SAT_RE = re.compile(r"SATAVG=([0-9.]+)")


def video_url(it: dict):
    return it.get("downloadURL") or it.get("videoURL")


def _duration(url: str):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "quiet", "-rw_timeout", "30000000",
             "-show_entries", "format=duration", "-of", "default=nk=1:nw=1", url],
            capture_output=True, text=True, timeout=60).stdout.strip()
        d = float(out)
        return d if d > 0 else None
    except Exception:
        return None


def _sat_at(url: str, t: float):
    try:
        err = subprocess.run(
            ["ffmpeg", "-nostdin", "-rw_timeout", "30000000", "-ss", str(int(t)),
             "-i", url, "-vf", "signalstats,metadata=print",
             "-frames:v", "1", "-an", "-f", "null", "-"],
            capture_output=True, text=True, timeout=90).stderr
        m = SAT_RE.search(err)
        return float(m.group(1)) if m else None
    except Exception:
        return None


def classify(url: str, threshold: float):
    """Return ("color"|"bw", mean_saturation) or (None, None) if unreadable."""
    d = _duration(url)
    pts = [d * p for p in SAMPLE_POINTS] if d else [60, 180, 420]
    sats = [s for s in (_sat_at(url, t) for t in pts) if s is not None]
    if not sats:
        return None, None
    avg = sum(sats) / len(sats)
    return ("bw" if avg < threshold else "color"), round(avg, 2)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--threshold", type=float, default=8.0)
    ap.add_argument("--refresh", action="store_true", help="reclassify even if colorMode is set")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[color] no catalog.json (run catalog_release.py fetch first)"); return 2

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    targets = [it for it in items
               if video_url(it) and (args.refresh or not it.get("colorMode"))]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[color] {len(targets)} items to classify "
          f"(workers {args.workers}, threshold {args.threshold})")

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    done = color = bw = fail = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(classify, video_url(it), args.threshold): it for it in targets}
        for fut in as_completed(futs):
            it = futs[fut]
            mode, _avg = fut.result()
            if mode:
                it["colorMode"] = mode
                color += (mode == "color"); bw += (mode == "bw")
            else:
                fail += 1
            done += 1
            if done % 100 == 0 or done == len(targets):
                flush()
                print(f"[{done}/{len(targets)}] color {color} | bw {bw} | unreadable {fail}")
    flush()
    print(f"[color] done: color {color}, bw {bw}, unreadable {fail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
