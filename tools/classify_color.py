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
SAT_RE = re.compile(r"SATAVG=([0-9.]+)")


def video_url(it: dict):
    return it.get("downloadURL") or it.get("videoURL")


def cover_url(it: dict):
    """A frame-extracted cover already hosted as a small JPEG on archive.org
    (the cover pipeline, Decision 023). Reading saturation from this ONE image is
    a single tiny fetch — far cheaper than streaming the video to seek frames —
    and a whole film is uniformly color or B&W, so one real frame is decisive."""
    p = it.get("posterURL") or ""
    if "archivewatch-covers" in p or (it.get("artworkSource") == "generated" and p):
        return p
    return None


def _sat(args_in) -> float | None:
    """Run signalstats on one input (a URL + optional -ss seek) and read SATAVG."""
    try:
        err = subprocess.run(
            ["ffmpeg", "-nostdin", "-rw_timeout", "30000000", *args_in,
             "-vf", "signalstats,metadata=print", "-frames:v", "1", "-an",
             "-f", "null", "-"],
            capture_output=True, text=True, timeout=90).stderr
        m = SAT_RE.search(err)
        return float(m.group(1)) if m else None
    except Exception:
        return None


# Fixed sample offsets for the video path — no separate ffprobe round-trip. The
# early offset catches short items; later ones avoid title cards. We average
# whatever decodes.
VIDEO_OFFSETS = (20, 120, 420)


def classify(it: dict, threshold: float):
    """Return ("color"|"bw", mean_saturation) or (None, None) if unreadable.

    FAST PATH: if the item has a hosted cover frame, read its saturation in one
    tiny fetch. Only trust it when CONFIDENT (clear of the threshold) — an
    ambiguous single frame falls through to multi-frame video sampling."""
    cu = cover_url(it)
    if cu:
        s = _sat([*("-i", cu)])
        if s is not None and (s < threshold - 3 or s > threshold + 4):
            return ("bw" if s < threshold else "color"), round(s, 2)
        # ambiguous single frame -> verify against the video below

    vu = video_url(it)
    if not vu:
        return None, None
    sats = [s for s in (_sat(["-ss", str(t), "-i", vu]) for t in VIDEO_OFFSETS)
            if s is not None]
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
        futs = {ex.submit(classify, it, args.threshold): it for it in targets}
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
