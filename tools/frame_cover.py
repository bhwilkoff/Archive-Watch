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
        return -1.0
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    mean = float(gray.mean())
    spread = float(gray.std())  # global contrast / tonal range
    # Hard rejects: too dark, blown out, or near-uniform. A black/fade frame or a
    # solid title card must NEVER win over the procedural fallback card.
    if mean < 32 or mean > 232 or spread < 18:
        return -1.0
    # Sharpness = variance of the Laplacian; kills motion-blur / soft frames.
    sharp = cv2.Laplacian(gray, cv2.CV_64F).var()
    if sharp < 40:
        return -1.0
    # Colorfulness (Hasler-Susstrunk): a vivid frame beats a muddy one.
    b, g, r = cv2.split(img.astype("float32"))
    rg = r - g
    yb = 0.5 * (r + g) - b
    colorful = (rg.std() ** 2 + yb.std() ** 2) ** 0.5 \
        + 0.3 * ((rg.mean() ** 2 + yb.mean() ** 2) ** 0.5)
    # Reject title cards / intertitles / documents: a near-monochrome frame whose
    # tones collapse onto one histogram bin is text on a flat field, not a scene.
    # (Measured: real B&W/colour scenes stay <=0.5; an intertitle hit 0.77.)
    hist = cv2.calcHist([gray], [0], None, [16], [0, 256]).flatten()
    if hist.max() / max(hist.sum(), 1.0) > 0.58 and colorful < 25:
        return -1.0
    # Brightness comfort: peak around mid-tone, taper toward the extremes.
    bright = max(0.0, 1.0 - abs(mean - 110) / 110)
    s = spread + sharp * 0.04 + colorful * 0.6 + bright * 25.0
    # A face is the strongest "key moment" signal; weight by how much of the
    # frame it fills, so a big promotional-style close-up beats a distant figure.
    faces = face_cascade.detectMultiScale(gray, 1.15, 5, minSize=(40, 40))
    if len(faces):
        area = max(fw * fh for (_, _, fw, fh) in faces) / float(w * h)
        s += 350 + min(area, 0.4) * 600  # up to +240 for a large, clear face
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
    if dst.suffix.lower() in (".jpg", ".jpeg"):
        cv2.imwrite(str(dst), img, [cv2.IMWRITE_JPEG_QUALITY, 88])
    else:
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


def generate(url: str, out: Path, aspect: str, samples: int = 12) -> float:
    """Pick the highest-scoring frame and write it. Returns the best score
    (> 0 on success), or -1.0 if no frame cleared the quality floor."""
    dur = ffprobe_duration(url)
    if dur <= 0:
        print("[cover] could not read duration", file=sys.stderr)
        return -1.0
    # Sample densely across the middle 15%–85% (skip titles/credits); a wider
    # candidate pool raises the odds of landing on a face / key moment.
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
        if best is None or best_score <= 0:
            print("[cover] no usable frame found", file=sys.stderr)
            return -1.0
        out.parent.mkdir(parents=True, exist_ok=True)
        crop_aspect(best, out, aspect)
    print(f"[cover] wrote {out} (score {best_score:.0f})")
    return best_score


def generate_candidates(url: str, outdir: Path, aspect: str,
                        samples: int = 16, top_n: int = 3) -> list:
    """Write the top_n highest-scoring frames to outdir/c0.jpg .. (rank 0 = best
    by the heuristic). Returns [(rank, score, path), ...]. Enables a best-of-N
    visual re-rank: the heuristic narrows the field, judgment picks the winner."""
    dur = ffprobe_duration(url)
    if dur <= 0:
        return []
    lo, hi = dur * 0.15, dur * 0.85
    times = [lo + (hi - lo) * i / (samples - 1) for i in range(samples)]
    fc = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    scored = []
    with tempfile.TemporaryDirectory() as td:
        for i, t in enumerate(times):
            f = Path(td) / f"f{i}.jpg"
            if not grab_frame(url, t, f):
                continue
            s = score(f, fc)
            if s > 0:
                keep = Path(td) / f"k{i}.png"
                f.replace(keep)
                scored.append((s, keep))
        scored.sort(key=lambda x: -x[0])
        outdir.mkdir(parents=True, exist_ok=True)
        out = []
        for rank, (s, p) in enumerate(scored[:top_n]):
            dst = outdir / f"c{rank}.jpg"
            crop_aspect(p, dst, aspect)
            out.append((rank, round(s, 1), dst))
        return out


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
    return 0 if generate(url, args.out, args.aspect, args.samples) > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
