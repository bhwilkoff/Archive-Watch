#!/usr/bin/env python3
"""Generate Roku trick-play (BIF) files for the catalog and publish them to
ONE archive.org item, `archivewatch-bifs`, so each film gets a stable URL:

    https://archive.org/download/archivewatch-bifs/<archiveID>.bif

Measured before this existed (docs/ROKU-SUBMISSION.md): one 94-minute
feature = 21 s wall clock, 560 frames, 2.55 MB, streamed straight from
archive.org with `ffmpeg -skip_frame nokey` — no download. ~69 GB and ~157
network-bound machine-hours for the whole catalog; the shape of
batch_covers.py, not a programme. Verified rendering on a Streaming Stick 4K
through the player's `HDBifUrl`.

DRY RUN BY DEFAULT: prints what it would do. `--run` generates; `--upload`
also publishes (IAS3_ACCESS_KEY / IAS3_SECRET_KEY from the environment,
never committed). Resumable: manifest.jsonl records every attempt and a
resumed run skips ids already `done`. `--max-minutes` is a budget measured
from process start (Decision 091); the run stops cleanly and the manifest
is the state.

    python3 tools/batch_bifs.py --index https://archivewatch.org/catalog-index.json \
        --out build/bifs --limit 50 --run [--upload] [--max-minutes 300]
"""
from __future__ import annotations
import argparse, json, os, shutil, struct, subprocess, sys, time, urllib.request, urllib.error
from pathlib import Path

S3 = "https://s3.us.archive.org"
ITEM = "archivewatch-bifs"
INTERVAL_MS = 10000

def fnv1a_low(s: str) -> int:
    h = 0x811C9DC5
    for c in s.encode():
        h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF
    return h & 0xFF

def load_done(manifest: Path) -> dict:
    done = {}
    if manifest.exists():
        for line in manifest.read_text().splitlines():
            try:
                r = json.loads(line); done[r["id"]] = r["status"]
            except Exception:
                pass
    return done

def log(manifest: Path, rec: dict) -> None:
    with open(manifest, "a") as f:
        f.write(json.dumps(rec) + "\n")

def pack_bif(frames_dir: Path, out: Path) -> tuple[int, int]:
    frames = sorted(frames_dir.glob("*.jpg"), key=lambda p: int(p.stem))
    n = len(frames)
    hdr = bytearray(b"\x89BIF\r\n\x1a\n") + struct.pack("<III", 0, n, INTERVAL_MS) + bytes(44)
    index = bytearray(); data = bytearray()
    off = 64 + (n + 1) * 8
    for i, f in enumerate(frames):
        b = f.read_bytes()
        index += struct.pack("<II", i, off + len(data)); data += b
    index += struct.pack("<II", 0xFFFFFFFF, off + len(data))
    out.write_bytes(bytes(hdr) + bytes(index) + bytes(data))
    return n, out.stat().st_size

def make_bif(aid: str, url: str, out_dir: Path, width: int) -> dict:
    work = out_dir / "work" / aid
    if work.exists(): shutil.rmtree(work)
    work.mkdir(parents=True)
    t0 = time.time()
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-skip_frame", "nokey", "-i", url,
           "-vf", f"fps=1/{INTERVAL_MS // 1000},scale={width}:-2", "-q:v", "6",
           "-start_number", "0", str(work / "%d.jpg")]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    if r.returncode != 0:
        shutil.rmtree(work, ignore_errors=True)
        return {"status": "ffmpeg_failed", "err": r.stderr[-300:]}
    out = out_dir / f"{aid}.bif"
    n, size = pack_bif(work, out)
    shutil.rmtree(work, ignore_errors=True)
    if n < 2:
        out.unlink(missing_ok=True)
        return {"status": "too_short", "frames": n}
    return {"status": "made", "frames": n, "bytes": size, "seconds": round(time.time() - t0, 1), "path": str(out)}

def upload(path: Path, aid: str) -> None:
    ak, sk = os.environ.get("IAS3_ACCESS_KEY"), os.environ.get("IAS3_SECRET_KEY")
    if not ak or not sk:
        sys.exit("[bif] --upload needs IAS3_ACCESS_KEY and IAS3_SECRET_KEY in the environment")
    req = urllib.request.Request(f"{S3}/{ITEM}/{aid}.bif", data=path.read_bytes(), method="PUT")
    req.add_header("Authorization", f"LOW {ak}:{sk}")
    req.add_header("x-archive-auto-make-bucket", "1")
    req.add_header("x-archive-meta-mediatype", "data")
    req.add_header("x-archive-meta-title", "Archive Watch trick-play thumbnails")
    req.add_header("Content-Type", "application/octet-stream")
    with urllib.request.urlopen(req, timeout=600) as r:
        if r.status not in (200, 201):
            raise RuntimeError(f"upload {r.status}")

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--index", default="https://archivewatch.org/catalog-index.json")
    ap.add_argument("--details", default="https://archivewatch.org/details/{shard}.json")
    ap.add_argument("--out", default="build/bifs")
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--min-runtime", type=int, default=900, help="seconds; Roku requires BIFs over 15 min")
    ap.add_argument("--width", type=int, default=320, help="320 = HD, 240 = SD")
    ap.add_argument("--max-minutes", type=float, default=0)
    ap.add_argument("--run", action="store_true", help="actually generate (default is a dry run)")
    ap.add_argument("--upload", action="store_true", help="also publish to archive.org (implies --run)")
    a = ap.parse_args()
    if a.upload: a.run = True
    t_start = time.time()
    out_dir = Path(a.out); out_dir.mkdir(parents=True, exist_ok=True)
    manifest = out_dir / "manifest.jsonl"
    done = load_done(manifest)

    idx = json.load(urllib.request.urlopen(a.index))
    fields = idx["fields"]; F = {k: i for i, k in enumerate(fields)}
    # popularity-first: the index is already ordered that way by the pipeline
    todo = [r for r in idx["items"] if r[F["playable"]] and done.get(r[F["id"]]) != "done"]
    print(f"[bif] {len(idx['items'])} items, {len(todo)} not done, taking {a.limit}", flush=True)
    shard_cache: dict[str, dict] = {}
    made = 0
    for r in todo:
        if made >= a.limit: break
        if a.max_minutes and (time.time() - t_start) / 60 > a.max_minutes:
            print("[bif] budget reached; manifest is the state", flush=True); break
        aid = r[F["id"]]
        sh = f"{fnv1a_low(aid):02x}"
        if sh not in shard_cache:
            try: shard_cache[sh] = json.load(urllib.request.urlopen(a.details.format(shard=sh)))
            except Exception as e:
                log(manifest, {"id": aid, "status": "shard_failed", "err": str(e)[:120]}); continue
        rec = shard_cache[sh].get(aid)
        if not rec or not rec[0]:
            log(manifest, {"id": aid, "status": "no_url"}); continue
        runtime = rec[5] or 0
        if runtime and runtime < a.min_runtime:
            log(manifest, {"id": aid, "status": "short", "runtime": runtime}); continue
        if not a.run:
            print(f"[dry] {aid}  {runtime}s  {rec[0]}"); made += 1; continue
        res = make_bif(aid, rec[0], out_dir, a.width)
        if res["status"] == "made" and a.upload:
            try:
                upload(Path(res["path"]), aid); res["status"] = "done"
                res["url"] = f"https://archive.org/download/{ITEM}/{aid}.bif"
            except Exception as e:
                res["status"] = "upload_failed"; res["err"] = str(e)[:200]
        elif res["status"] == "made":
            res["status"] = "done_local"
        res["id"] = aid; log(manifest, res)
        print(f"[bif] {aid}: {res['status']} {res.get('frames','')}f {res.get('bytes','')}B {res.get('seconds','')}s", flush=True)
        made += 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
