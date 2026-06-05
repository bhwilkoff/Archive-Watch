#!/usr/bin/env python3
"""
frame_cover.py — generate a poster cover from a video's own frames (#86 / #13b).

Last-resort artwork for items no third-party source covers — chiefly the vintage
commercials (contentType 'commercial'), which have no TMDb/Commons/Wikidata
poster. Samples frames across the middle of the video with ffmpeg, scores them
(reject black/blank/blurry; bonus for a detected face + sharpness), picks the
best, and crops to a poster aspect. Pure measurement — no hallucinated art.

Requires ffmpeg + ffprobe on PATH and opencv-python (cv2). Runs on a Linux CI
runner (ubuntu + `apt-get install ffmpeg`, `pip install opencv-python-headless`).

Usage:
    python tools/frame_cover.py --id LuckyStr1948_2 --out /tmp/cover.png
    python tools/frame_cover.py --url https://archive.org/download/ID/file.mp4 --out cover.png --aspect 2:3
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2  # type: ignore


def ffprobe_duration(url: str) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", url],
        capture_output=True, text=True, timeout=60)
    try:
        return float(out.stdout.strip())
    except ValueError:
        return 0.0


def grab_frame(url: str, t: float, dst: Path) -> bool:
    # -ss before -i = fast seek; one frame, scaled to a working size.
    r = subprocess.run(
        ["ffmpeg", "-y", "-ss", str(t), "-i", url, "-frames:v", "1",
         "-vf", "scale=640:-1", "-q:v", "3", str(dst)],
        capture_output=True, timeout=120)
    return r.returncode == 0 and dst.exists() and dst.stat().st_size > 0


def score(path: Path, face_cascade) -> float:
    img = cv2.imread(str(path))
    if img is None:
        return -1
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    mean = gray.mean()
    # Reject near-black / blown-out frames (titles, fades, flashes).
    if mean < 18 or mean > 238:
        return -1
    # Sharpness = variance of the Laplacian (blurry/motion frames score low).
    sharp = cv2.Laplacian(gray, cv2.CV_64F).var()
    # Tonal range — flat frames (solid cards) score low.
    spread = float(gray.std())
    s = sharp * 0.05 + spread
    # Face bonus — a clear face makes a far better cover.
    faces = face_cascade.detectMultiScale(gray, 1.2, 5, minSize=(60, 60))
    if len(faces):
        s += 400
    return s


def crop_aspect(src: Path, dst: Path, aspect: str):
    img = cv2.imread(str(src))
    h, w = img.shape[:2]
    aw, ah = (int(x) for x in aspect.split(":"))
    target = aw / ah
    cur = w / h
    if cur > target:                      # too wide → crop width
        nw = int(h * target); x0 = (w - nw) // 2
        img = img[:, x0:x0 + nw]
    else:                                 # too tall → crop height
        nh = int(w / target); y0 = (h - nh) // 2
        img = img[y0:y0 + nh, :]
    # Upscale to a poster-ish width.
    out_w = 600
    out_h = int(out_w / target)
    img = cv2.resize(img, (out_w, out_h), interpolation=cv2.INTER_LANCZOS4)
    cv2.imwrite(str(dst), img, [cv2.IMWRITE_PNG_COMPRESSION, 6])


def archive_video_url(iaid: str) -> str | None:
    import json
    import urllib.request
    req = urllib.request.Request(f"https://archive.org/metadata/{iaid}",
                                 headers={"User-Agent": "ArchiveWatch-covers"})
    meta = json.load(urllib.request.urlopen(req, timeout=45))
    files = meta.get("files", [])
    # Prefer a small MP4 derivative for speed.
    mp4s = [f for f in files if f.get("name", "").lower().endswith(".mp4")]
    mp4s.sort(key=lambda f: int(f.get("size") or 0))  # smallest first
    if not mp4s:
        return None
    return f"https://archive.org/download/{iaid}/{mp4s[0]['name']}"


def generate(url: str, out: Path, aspect: str, samples: int = 9) -> bool:
    dur = ffprobe_duration(url)
    if dur <= 0:
        print("[cover] could not read duration", file=sys.stderr)
        return False
    # Sample across the middle 15%–85% (skip titles/credits).
    lo, hi = dur * 0.15, dur * 0.85
    times = [lo + (hi - lo) * i / (samples - 1) for i in range(samples)]
    fc = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    best, best_score = None, -1.0
    with tempfile.TemporaryDirectory() as td:
        for i, t in enumerate(times):
            f = Path(td) / f"f{i}.jpg"
            if not grab_frame(url, t, f):
                continue
            s = score(f, fc)
            if s > best_score:
                best_score, best = s, Path(td) / f"best{i}.png"
                f.replace(best)
        if best is None or best_score < 0:
            print("[cover] no usable frame found", file=sys.stderr)
            return False
        out.parent.mkdir(parents=True, exist_ok=True)
        crop_aspect(best, out, aspect)
    print(f"[cover] wrote {out} (score {best_score:.0f})")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", help="archive.org identifier (resolves a small MP4)")
    ap.add_argument("--url", help="explicit video URL (overrides --id)")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--aspect", default="2:3", help="poster aspect, e.g. 2:3 or 16:9")
    ap.add_argument("--samples", type=int, default=9)
    args = ap.parse_args()

    url = args.url or (archive_video_url(args.id) if args.id else None)
    if not url:
        print("[cover] need --url or a resolvable --id", file=sys.stderr)
        return 2
    return 0 if generate(url, args.out, args.aspect, args.samples) else 1


if __name__ == "__main__":
    sys.exit(main())
