#!/usr/bin/env python3
"""
classify_color.py — tag every catalog item as color or black-and-white.

Samples a few frames from the item's OWN video with ffmpeg and averages the
`signalstats` SATAVG (mean chroma saturation) into `colorMode` + `colorSat`.

For most transfers the split IS decisive — a clean B&W scan reads 0.0 and a
healthy color print reads 15-25. But it is not decisive everywhere, and the
measurement that showed this is worth keeping: on faded or chroma-noisy prints
the two classes OVERLAP around the threshold. Measured 2026-08-18, all against
films whose real color is a matter of record:

    Lonely Wives (1931)        B&W     SATAVG 0.00   <- the clean case
    Not of This Earth (1957)   B&W     SATAVG 9.00   -> read as COLOR
    Scared to Death (1947)     COLOR   SATAVG 7.10   -> read as BW (Cinecolor)
    Eagle in a Cage (1972)     COLOR   SATAVG 7.65   -> read as BW
    Death Rides a Horse (1967) COLOR   SATAVG 8.49   (frames spanned 2.1-15.8)

A B&W film reading HIGHER than a color one is not a threshold that needs
tuning — it is two populations that overlap in this statistic. Hence `colorSat`
is now stored: consumers can tell a confident reading from a coin-flip, and
`build_sqlite.color_confident()` is where that judgement lives.

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


def _sat(args_in, frame_timeout: int = 90) -> float | None:
    """Run signalstats on one input (a URL + optional -ss seek) and read SATAVG.

    `frame_timeout` is a real measurement, not a formality. A targeted re-probe
    reported 72 of 76 items "unreadable"; the first one tried by hand answered
    SATAVG=0.53 perfectly well — after **106 seconds** to open. The 90s budget
    was killing live items and recording the verdict as a property of the film.
    A broad sweep still wants a short budget (it has thousands to get through);
    a targeted re-probe of a handful can afford to wait.
    """
    try:
        err = subprocess.run(
            ["ffmpeg", "-nostdin", "-rw_timeout", str(frame_timeout * 1_000_000),
             *args_in,
             "-vf", "signalstats,metadata=print", "-frames:v", "1", "-an",
             "-f", "null", "-"],
            capture_output=True, text=True, timeout=frame_timeout + 30).stderr
        m = SAT_RE.search(err)
        return float(m.group(1)) if m else None
    except Exception:
        return None


# Fixed sample offsets for the video path — no separate ffprobe round-trip. The
# early offset catches short items; later ones avoid title cards. We average
# whatever decodes.
VIDEO_OFFSETS = (20, 120, 420)


def classify(it: dict, threshold: float, frame_timeout: int = 90):
    """Return ("color"|"bw", mean_saturation) or (None, None) if unreadable.

    FAST PATH: if the item has a hosted cover frame, read its saturation in one
    tiny fetch. Only trust it when CONFIDENT (clear of the threshold) — an
    ambiguous single frame falls through to multi-frame video sampling."""
    cu = cover_url(it)
    if cu:
        s = _sat([*("-i", cu)], frame_timeout)
        if s is not None and (s < threshold - 3 or s > threshold + 4):
            return ("bw" if s < threshold else "color"), round(s, 2)
        # ambiguous single frame -> verify against the video below

    vu = video_url(it)
    if not vu:
        return None, None
    sats = [s for s in (_sat(["-ss", str(t), "-i", vu], frame_timeout)
                        for t in VIDEO_OFFSETS)
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
    ap.add_argument("--frame-timeout", type=int, default=90,
                    help="seconds ffmpeg may spend opening+reading ONE frame. "
                         "archive.org can take 100s+ to open a cold item; a "
                         "targeted re-probe should be patient, a full sweep "
                         "should not.")
    ap.add_argument("--refresh", action="store_true", help="reclassify even if colorMode is set")
    ap.add_argument("--ids-file", help="re-probe ONLY these archiveIDs (one per line), "
                                       "implies --refresh. Lets a disputed set be "
                                       "re-measured without sweeping the catalog.")
    # SPLIT COMPUTE FROM COMMIT. Classifying takes ~an hour; applying the result
    # takes seconds. Holding the `catalog-writers` lock for the whole hour is
    # what starves 28 workflows of a single lock and gets runs destroyed in the
    # queue (Decision 057). With --deltas-out the long half needs no lock at
    # all, and --apply-deltas takes it only to merge onto a FRESH catalog —
    # which is also safer, because a run no longer republishes a whole catalog
    # it read hours ago.
    ap.add_argument("--deltas-out", help="append results here as JSONL; do not touch the catalog")
    ap.add_argument("--apply-deltas", help="merge a deltas file into the catalog and exit")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[color] no catalog.json (run catalog_release.py fetch first)"); return 2

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    if args.apply_deltas:
        return apply_deltas(cat, items, Path(args.apply_deltas))

    only = None
    if args.ids_file:
        only = {l.strip() for l in open(args.ids_file) if l.strip()}
        print(f"[color] re-probing {len(only)} named items")
    # With --ids-file, re-probe a named item unless it ALREADY carries a
    # measurement: 111 of 248 came back unreadable on the first pass (archive.org
    # declining a hosted runner mid-sweep), so a retry should cost only the ones
    # that failed, not re-measure the ones that succeeded. --refresh overrides.
    targets = [it for it in items
               if video_url(it)
               and (only is None or it.get("archiveID") in only)
               and (args.refresh
                    or (only is not None and it.get("colorSat") is None)
                    or (only is None and not it.get("colorMode")))]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[color] {len(targets)} items to classify "
          f"(workers {args.workers}, threshold {args.threshold})")

    deltas = open(args.deltas_out, "a", encoding="utf-8") if args.deltas_out else None

    def flush():
        # In deltas mode the catalog is never rewritten — results are appended
        # as they arrive, so a kill keeps everything up to that moment instead
        # of relying on a publish step being rescued afterwards.
        if deltas:
            deltas.flush()
            return
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    done = color = bw = fail = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(classify, it, args.threshold, args.frame_timeout): it
                for it in targets}
        for fut in as_completed(futs):
            it = futs[fut]
            mode, avg = fut.result()
            if mode:
                if deltas:
                    deltas.write(json.dumps({"archiveID": it.get("archiveID"),
                                             "colorMode": mode,
                                             "colorSat": avg}) + "\n")
                else:
                    it["colorMode"] = mode
                    if avg is not None:
                        it["colorSat"] = avg
                color += (mode == "color"); bw += (mode == "bw")
            else:
                fail += 1
            done += 1
            if done % 100 == 0 or done == len(targets):
                flush()
                print(f"[{done}/{len(targets)}] color {color} | bw {bw} | unreadable {fail}")
    flush()
    if deltas: deltas.close()
    print(f"[color] done: color {color}, bw {bw}, unreadable {fail}"
          + (f" -> {args.deltas_out}" if args.deltas_out else ""))
    return 0


def apply_deltas(cat, items, path: Path) -> int:
    """Merge a deltas file into the catalog just fetched.

    The merge is onto a FRESH catalog, so whatever other writers published while
    this was computing is preserved — where republishing a whole catalog read
    hours earlier would silently revert it.
    """
    if not path.exists():
        print(f"[color] no deltas at {path} — nothing to apply"); return 0
    by_id = {it.get("archiveID"): it for it in items}
    applied = missing = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line: continue
        d = json.loads(line)
        it = by_id.get(d.get("archiveID"))
        if it is None:
            missing += 1
            continue
        it["colorMode"] = d["colorMode"]
        if d.get("colorSat") is not None:
            it["colorSat"] = d["colorSat"]
        applied += 1
    tmp = CATALOG.with_suffix(".json.tmp")
    json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
    tmp.replace(CATALOG)
    print(f"[color] applied {applied} deltas ({missing} ids no longer in the catalog)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
