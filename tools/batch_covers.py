#!/usr/bin/env python3
"""
batch_covers.py — the mac-based cover-generation protocol (#86 / #13b).

Reads the full catalog, finds items with no real designed artwork, grabs the
best frame from each item's own video (via frame_cover.py — ffmpeg + opencv
face/sharpness scoring), and writes a poster + a resumable manifest. Pure
measurement: every cover is a real still from the film, never hallucinated art.

This is the GENERATE half. It is host-agnostic — it only writes local files +
a manifest. The PUBLISH half (upload + wire posterURL into the catalog) is
`tools/apply_covers.py`, which depends on the chosen host.

Designed to run locally on a Mac (ffmpeg + opencv-python installed) as an
overnight batch. Resumable: re-running skips items already done in the manifest
or whose output file already exists. Concurrent (ffmpeg/opencv release the GIL,
so threads are enough).

Usage:
    # validate on a small popularity-ordered sample
    python tools/batch_covers.py --content-type commercial --limit 12 --workers 4

    # full run for one type
    python tools/batch_covers.py --content-type commercial --workers 4

    # everything missing real art, most-popular first
    python tools/batch_covers.py --workers 6

Outputs (default under tools/covers_out/):
    posters/<slug>.jpg       one cover per successful item
    manifest.jsonl           one JSON line per attempt (resume + audit + wiring)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

import frame_cover  # same dir; reuse its ffmpeg/opencv pipeline

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
DEFAULT_OUT = Path(__file__).resolve().parent / "covers_out"

_slug_re = re.compile(r"[^A-Za-z0-9._-]+")


def slug_for(archive_id: str) -> str:
    """Filesystem-safe, collision-free file stem for an archive identifier."""
    base = _slug_re.sub("_", archive_id).strip("_")[:80] or "item"
    h = hashlib.sha1(archive_id.encode()).hexdigest()[:8]
    return f"{base}.{h}"


def needs_cover(it: dict) -> bool:
    if it.get("posterURL") and it.get("hasRealArtwork") is True:
        return False
    if it.get("hasRealArtwork") is True:
        return False
    # artworkSource other than archive/none implies a real third-party poster
    src = it.get("artworkSource")
    if it.get("posterURL") and src not in (None, "", "archive", "none", "generated"):
        return False
    return True


def video_url(it: dict) -> str | None:
    """The exact playable derivative the app streams (Decision 021 source)."""
    url = it.get("downloadURL")
    if url:
        return url
    vf = it.get("videoFile") or {}
    name = vf.get("name")
    aid = it.get("archiveID")
    if name and aid:
        return f"https://archive.org/download/{aid}/{name}"
    return None


def load_done(manifest: Path) -> dict[str, str]:
    """archiveID -> last status, so a resumed run skips finished work."""
    done: dict[str, str] = {}
    if not manifest.exists():
        return done
    with open(manifest) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            done[rec["archiveID"]] = rec.get("status", "")
    return done


def select_items(items: list[dict], content_type: str | None, retry_failed: bool,
                 done: dict[str, str]) -> list[dict]:
    out = []
    for it in items:
        if not needs_cover(it):
            continue
        if content_type and it.get("contentType") != content_type:
            continue
        if not video_url(it):
            continue
        prev = done.get(it.get("archiveID"))
        if prev == "ok":
            continue
        if prev in ("failed", "no_frame", "no_duration", "error") and not retry_failed:
            continue
        out.append(it)
    out.sort(key=lambda i: (i.get("popularityScore") or 0), reverse=True)
    return out


def process(it: dict, posters: Path, aspect: str, samples: int, keep_top: int = 1) -> dict:
    aid = it["archiveID"]
    slug = slug_for(aid)
    out = posters / f"{slug}.jpg"
    rec = {
        "archiveID": aid,
        "slug": slug,
        "file": f"{slug}.jpg",
        "contentType": it.get("contentType"),
        "popularityScore": it.get("popularityScore"),
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    if out.exists() and out.stat().st_size > 0:
        rec["status"] = "ok"
        rec["note"] = "preexisting"
        return rec
    url = video_url(it)
    if not url:
        rec["status"] = "no_url"
        return rec
    try:
        if keep_top > 1:
            # Keep the top-N heuristic candidates so a later visual best-of-N pass
            # can pick the winner without re-grabbing frames (the costly part).
            cdir = posters.parent / "candidates" / slug
            cands = frame_cover.generate_candidates(url, cdir, aspect, samples, keep_top)
            if cands:
                shutil.copyfile(cands[0][2], out)  # rank-0 = default cover until re-ranked
                rec["status"] = "ok"
                rec["score"] = cands[0][1]
                rec["candidates"] = len(cands)
            else:
                rec["status"] = "no_frame"
        else:
            sc = frame_cover.generate(url, out, aspect, samples)
            rec["status"] = "ok" if sc > 0 else "no_frame"
            rec["score"] = round(sc, 1)
    except Exception as e:  # noqa: BLE001 - record + continue the batch
        rec["status"] = "error"
        rec["error"] = str(e)[:200]
    return rec


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", type=Path, default=CATALOG)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--content-type", help="limit to one contentType (e.g. commercial)")
    ap.add_argument("--limit", type=int, default=0, help="cap items this run (0 = all)")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--aspect", default="2:3")
    ap.add_argument("--samples", type=int, default=16,
                    help="frames sampled per item; a wider pool = better best-of")
    ap.add_argument("--keep-top", type=int, default=1,
                    help="keep the top-N candidates per item for a later visual re-rank")
    ap.add_argument("--retry-failed", action="store_true",
                    help="reattempt items that previously failed")
    ap.add_argument("--dry-run", action="store_true",
                    help="report the work-list size and exit")
    args = ap.parse_args()

    if not args.catalog.exists():
        print(f"[batch] {args.catalog} not found — run "
              f"`python tools/catalog_release.py fetch` first", file=sys.stderr)
        return 2

    cat = json.load(open(args.catalog))
    items = cat["items"] if isinstance(cat, dict) else cat

    posters = args.out / "posters"
    posters.mkdir(parents=True, exist_ok=True)
    manifest = args.out / "manifest.jsonl"
    done = load_done(manifest)

    work = select_items(items, args.content_type, args.retry_failed, done)
    total_missing = sum(1 for it in items if needs_cover(it))
    if args.limit:
        work = work[:args.limit]

    print(f"[batch] catalog {len(items):,} items | missing real art {total_missing:,} "
          f"| already done {sum(1 for v in done.values() if v=='ok'):,}")
    print(f"[batch] this run: {len(work):,} items "
          f"(type={args.content_type or 'any'}, workers={args.workers}, limit={args.limit or 'none'})")
    if args.dry_run or not work:
        return 0

    lock = threading.Lock()
    counts = {"ok": 0, "fail": 0}
    started = time.time()

    with open(manifest, "a") as mf, \
            ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(process, it, posters, args.aspect, args.samples, args.keep_top): it
                for it in work}
        for i, fut in enumerate(as_completed(futs), 1):
            rec = fut.result()
            with lock:
                mf.write(json.dumps(rec) + "\n")
                mf.flush()
            ok = rec["status"] == "ok"
            counts["ok" if ok else "fail"] += 1
            rate = i / max(time.time() - started, 1e-6)
            eta = (len(work) - i) / max(rate, 1e-6)
            mark = "OK " if ok else "-- "
            print(f"[{i:>5}/{len(work)}] {mark}{rec['status']:9} "
                  f"{rec['archiveID'][:46]:46} | {rate*60:.1f}/min eta {eta/60:.0f}m")

    dt = time.time() - started
    print(f"[batch] done: {counts['ok']} ok, {counts['fail']} fail in {dt/60:.1f}m")
    print(f"[batch] posters -> {posters}")
    print(f"[batch] manifest -> {manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
