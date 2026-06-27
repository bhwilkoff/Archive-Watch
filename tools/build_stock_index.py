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
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

try:
    import resource           # POSIX only (Linux CI + macOS) — used to cap ffmpeg memory
except ImportError:           # pragma: no cover
    resource = None

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

# Per-ffmpeg virtual-memory ceiling. A single poison film (a corrupt/oversized stream that
# makes the decoder attempt a huge allocation) used to OOM the whole runner — exit 143
# "runner received a shutdown signal" mid-item, the SAME shard every 6h, downscale
# notwithstanding (runs 28278175372 / 28284290545 / 28291365967). Capping ffmpeg's own
# address space means a runaway film kills ONLY its ffmpeg (scene_cuts returns []), never the
# runner. Generous (the runner has 16 GB; a 360p scdet pass uses well under 1 GB) so it never
# false-kills a normal film, only a pathological one.
FFMPEG_MEM_CAP = 6 * 1024 ** 3


def _cap_memory():
    """preexec hook: cap the child ffmpeg's address space so a runaway film can't OOM the runner."""
    if resource is not None:
        try:
            resource.setrlimit(resource.RLIMIT_AS, (FFMPEG_MEM_CAP, FFMPEG_MEM_CAP))
        except (ValueError, OSError):
            pass


def scene_cuts(url: str, max_seconds: int, fps: float) -> list[float]:
    """Scene-change timestamps (seconds) via ffmpeg `scdet`, bounded for speed AND memory."""
    # Downscale to <=360p BEFORE scene detection. Shot boundaries don't need full resolution,
    # and decoding HD/1080i frames at full res under --concurrency blew the CI runner's RAM (the
    # kernel OOM-killer SIGTERM'd whole shards right after HD items — run 28262168655). The comma
    # inside min() is single-quoted so the filtergraph parser doesn't read it as a filter break.
    cmd = ["ffmpeg", "-nostats", "-threads", "2", "-t", str(max_seconds), "-i", url,
           "-vf", f"fps={fps},scale=-2:'min(360,ih)',scdet=threshold=10", "-f", "null", "-"]
    # stderr → a TEMP FILE, not capture_output (which holds ALL of ffmpeg's stderr in RAM — a
    # corrupt stream spamming per-frame decode errors could balloon it and OOM the runner). The
    # file is read back line-by-line so the parse stays bounded too. preexec caps ffmpeg's own
    # memory (see FFMPEG_MEM_CAP). Both guard the deterministic single-shard OOM the owner hit.
    cuts: list[float] = []
    try:
        with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as errf:
            try:
                subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=errf,
                               timeout=max_seconds * 4 + 90,
                               preexec_fn=(_cap_memory if sys.platform != "win32" else None))
            except subprocess.TimeoutExpired:
                pass                      # parse whatever cuts were found before the timeout
            errf.seek(0)
            for line in errf:             # bounded: one line at a time, never the whole buffer
                m = re.search(r"lavfi\.scd\.time:\s*([\d.]+)", line)
                if m:
                    cuts.append(float(m.group(1)))
    except Exception:
        return sorted(cuts)
    return sorted(cuts)


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
    ap.add_argument("--concurrency", type=int, default=1,
                    help="films to scan in PARALLEL (ffmpeg is network-bound, so the runner's CPU "
                         "idles on one film at a time). Total concurrent archive.org streams = "
                         "shards * concurrency — keep modest so the load-balancer doesn't 503.")
    ap.add_argument("--out", default=str(REPO / "clips.sqlite"))
    # Sharding (#7): run N runners in parallel, each over a disjoint popularity-interleaved
    # slice (stride), skipping films already in the merged index from --seen-from.
    ap.add_argument("--shard-index", type=int, default=0)
    ap.add_argument("--shard-count", type=int, default=1)
    ap.add_argument("--seen-from", default="", help="existing index to skip already-done films")
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text())
    items = [it for it in cat["items"]
             if it.get("downloadURL") and not it.get("excluded")
             and it.get("contentType") not in ("tv-series",)
             and (it.get("rightsStatus") or "public_domain") in ("public_domain", "cc", "creative_commons", "")]
    items.sort(key=lambda it: it.get("popularityScore") or it.get("downloads") or 0, reverse=True)
    if args.shard_count > 1:
        items = items[args.shard_index::args.shard_count]   # disjoint stride slice

    db = sqlite3.connect(args.out)
    db.execute("""CREATE TABLE IF NOT EXISTS shots(
        id TEXT PRIMARY KEY, archiveID TEXT, sourceURL TEXT,
        startSeconds REAL, endSeconds REAL, tags TEXT, title TEXT)""")
    seen = {r[0] for r in db.execute("SELECT DISTINCT archiveID FROM shots")}
    if args.seen_from and Path(args.seen_from).exists():
        sdb = sqlite3.connect(args.seen_from)
        try:
            seen |= {r[0] for r in sdb.execute("SELECT DISTINCT archiveID FROM shots")}
        except sqlite3.OperationalError:
            pass
        sdb.close()

    def scan(it):
        """Detect a film's shots (the network-bound work; runs on a worker thread). Returns
        (it, shots) or None — NO SQLite here (writes stay single-threaded in the main loop)."""
        # Log BEFORE the scan so a runner that's OOM-killed mid-film still names the culprit in
        # its log (a successful scan logs again, with the shot count, in the main loop below).
        print(f"[stock] scanning {it['archiveID']} (rt={it.get('runtimeSeconds')})", flush=True)
        cuts = scene_cuts(it["downloadURL"], args.max_seconds, args.fps)
        if not cuts:
            return None
        rt = it.get("runtimeSeconds") or 0
        total = min(rt, args.max_seconds) if rt else args.max_seconds
        shots = shots_from_cuts(cuts, total)
        return (it, shots) if shots else None

    def write(it, shots):
        aid, url = it["archiveID"], it["downloadURL"]
        # Discrete, clean, pipe-joined tags (drop sentence-long / punctuation-y subjects) so the
        # app shows readable chips and search works — NOT one hyphen-mangled token.
        tags = "|".join(
            t.strip().lower() for t in ((it.get("genres") or []) + (it.get("subjects") or [])[:2])
            if t and len(t.strip()) <= 22 and ":" not in t and ";" not in t)[:200]
        for i, (s, e) in enumerate(shots):
            db.execute("INSERT OR REPLACE INTO shots VALUES(?,?,?,?,?,?,?)",
                       (f"{aid}#{i}", aid, url, s, e, tags, it.get("title", "")))
        db.commit()

    candidates = [it for it in items if it["archiveID"] not in seen]
    done = 0
    workers = max(1, args.concurrency)
    with ThreadPoolExecutor(max_workers=workers) as ex:
        inflight, idx = set(), 0
        while idx < len(candidates) and len(inflight) < workers:    # prime the pool
            inflight.add(ex.submit(scan, candidates[idx])); idx += 1
        while inflight and done < args.limit:
            fut = next(as_completed(inflight))
            inflight.discard(fut)
            res = fut.result()
            if res:
                it, shots = res
                write(it, shots)
                done += 1
                print(f"[stock] {it['archiveID']}: {len(shots)} shots ({done}/{args.limit})", flush=True)
            if idx < len(candidates) and done < args.limit:         # keep the pool full
                inflight.add(ex.submit(scan, candidates[idx])); idx += 1
        # Stop scanning the in-flight remainder once the quota is met (don't waste decode time).
        ex.shutdown(wait=False, cancel_futures=True)

    n = db.execute("SELECT count(*) FROM shots").fetchone()[0]
    print(f"[stock] +{done} films this run; {n} shots total in {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
