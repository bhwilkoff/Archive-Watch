#!/usr/bin/env python3
"""build_stock_index.py — the Stock-archive SHOT index (Creation Studio #6, Decision 042).

Detects REAL shot boundaries in clippable films via ffmpeg scene detection (`scdet`) and emits
`clips.sqlite` (a `shots` table) for the macOS Creation Studio stock-shot browser — replacing the
app's synthesized placeholder windows with actual cuts. Tags come from the catalog's
genres/subjects; Apple-Vision per-shot classification + MobileCLIP semantic embeddings are the
later refinement (the `shots` schema already matches `StockIndex.swift`, so the app needs no change
to consume the real index).

Runs on a Mac/CI with ffmpeg (the cover-pipeline dependency). Popularity-first, bounded per film
for speed (decode at a low fps, cap the processed seconds), resumable via the output DB.

  python3 tools/build_stock_index.py --limit 50 --max-seconds 300
"""
import argparse
import json
import re
import sqlite3
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"


def scene_cuts(url: str, max_seconds: int, fps: float) -> list[float]:
    """Scene-change timestamps (seconds) via ffmpeg `scdet`, bounded for speed."""
    cmd = ["ffmpeg", "-nostats", "-t", str(max_seconds), "-i", url,
           "-vf", f"fps={fps},scdet=threshold=10", "-f", "null", "-"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=max_seconds * 4 + 90).stderr
    except Exception:
        return []
    return sorted(float(m) for m in re.findall(r"lavfi\.scd\.time:\s*([\d.]+)", out))


def shots_from_cuts(cuts: list[float], total: float,
                    min_len: float = 1.2, max_len: float = 20.0) -> list[tuple[float, float]]:
    """Turn cut points into usable shot windows: keep [min_len, max_len], split longer takes."""
    bounds = sorted(set([0.0] + cuts + ([total] if total else [])))
    shots: list[tuple[float, float]] = []
    for a, b in zip(bounds, bounds[1:]):
        d = b - a
        if min_len <= d <= max_len:
            shots.append((a, b))
        elif d > max_len:                       # chop a long static take into chunks
            t = a
            while t + min_len < b:
                shots.append((t, min(t + max_len, b)))
                t += max_len
    return shots


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=50, help="films to add this run")
    ap.add_argument("--max-seconds", type=int, default=300, help="process up to N seconds per film")
    ap.add_argument("--fps", type=float, default=4.0, help="decode fps for scene detection (lower = faster)")
    ap.add_argument("--out", default=str(REPO / "clips.sqlite"))
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text())
    items = [it for it in cat["items"]
             if it.get("downloadURL") and not it.get("excluded")
             and it.get("contentType") not in ("tv-series",)
             and (it.get("rightsStatus") or "public_domain") in ("public_domain", "cc", "creative_commons", "")]
    items.sort(key=lambda it: it.get("popularityScore") or it.get("downloads") or 0, reverse=True)

    db = sqlite3.connect(args.out)
    db.execute("""CREATE TABLE IF NOT EXISTS shots(
        id TEXT PRIMARY KEY, archiveID TEXT, sourceURL TEXT,
        startSeconds REAL, endSeconds REAL, tags TEXT, title TEXT)""")
    seen = {r[0] for r in db.execute("SELECT DISTINCT archiveID FROM shots")}

    done = 0
    for it in items:
        if done >= args.limit:
            break
        aid = it["archiveID"]
        if aid in seen:
            continue
        url = it["downloadURL"]
        cuts = scene_cuts(url, args.max_seconds, args.fps)
        if not cuts:
            continue
        rt = it.get("runtimeSeconds") or 0
        total = min(rt, args.max_seconds) if rt else args.max_seconds
        shots = shots_from_cuts(cuts, total)
        if not shots:
            continue
        tags = " ".join((it.get("genres") or []) + (it.get("subjects") or [])[:3]) \
            .lower().replace(" ", "-")
        for i, (s, e) in enumerate(shots):
            db.execute("INSERT OR REPLACE INTO shots VALUES(?,?,?,?,?,?,?)",
                       (f"{aid}#{i}", aid, url, s, e, tags, it.get("title", "")))
        db.commit()
        done += 1
        print(f"[stock] {aid}: {len(shots)} shots", flush=True)

    n = db.execute("SELECT count(*) FROM shots").fetchone()[0]
    print(f"[stock] +{done} films this run; {n} shots total in {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
