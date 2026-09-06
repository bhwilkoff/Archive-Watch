#!/usr/bin/env python3
"""
social_clip.py — cut a vertical teaser from the film itself.

The card (social_card.py) is a poster; this is the picture moving. It is what
YouTube Shorts, Reels, TikTok and Bluesky video want, and it is the most
honest possible promotion of a film: an actual scene, not a claim about one.

Three decisions worth knowing:

* **Where the scene comes from.** `clips.sqlite` (the Creation Studio's stock
  index, Decision 042) holds 944,954 REAL shot boundaries detected by ffmpeg
  across 32,573 films. We cut on a real shot boundary, so the clip starts and
  ends where the film does, not mid-motion.

* **Why the first act.** That index only analyses each film's opening ~300
  seconds. Rather than pretend otherwise, the programme makes it the rule: a
  teaser draws from the FIRST ACT and never the ending. It cannot spoil a
  film it never reaches, which is the right editorial position anyway. Shots
  before 60 s are skipped — those are titles and studio idents.

* **Never reshape the picture.** Decision 097 binds here too: a 4:3 film in a
  9:16 frame is fitted whole over a blurred fill of itself. Cropping a 1933
  cartoon to a phone frame throws away half the animation.

Run:
  python tools/social_clip.py --spec social/out/post.json \
      --index /tmp/clips.sqlite --out social/out/clip.mp4
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FONTS = REPO / "roku" / "fonts"

TITLES_END = 60.0          # before this is idents and opening titles
MIN_SHOT = 4.0
TARGET = 18.0              # a teaser, not an excerpt
MIN_LUMA = 42.0            # below this the frame reads as black on a phone
MAX_LUMA = 225.0           # above it, a blown-out fade or a title card
W, H = 1080, 1920


def ffmpeg_has(feature: str) -> bool:
    r = subprocess.run(["ffmpeg", "-hide_banner", "-filters"],
                       capture_output=True, text=True)
    return feature in r.stdout


def motion_of(url: str, at: float) -> float:
    """Mean absolute frame-to-frame difference over ~2 s, 0-255.

    A shot's POSITION does not tell you what is in it: the first cut of
    Hercules Unchained past the 60 s mark is still the credit roll ("DIRECTED
    BY PIETRO FRANCISCI"), because the titles of a 1960 peplum run four
    minutes. Motion does tell you — a title card is nearly static and a scene
    is not — and it costs two frame grabs to measure.
    """
    try:
        from PIL import Image, ImageChops, ImageStat
    except ImportError:
        return 99.0                      # cannot measure; do not block the clip
    frames = []
    for offset in (0.5, 2.5):
        p = Path(f"/tmp/aw_motion_{int(at)}_{int(offset*10)}.jpg")
        r = subprocess.run(["ffmpeg", "-y", "-nostdin", "-ss", str(at + offset),
                            "-i", url, "-frames:v", "1", "-q:v", "5",
                            "-vf", "scale=192:-2", str(p)],
                           capture_output=True, text=True, timeout=180)
        if r.returncode != 0 or not p.exists():
            return 0.0
        frames.append(Image.open(p).convert("L"))
    diff = ImageChops.difference(frames[0], frames[1])
    return ImageStat.Stat(diff).mean[0]


def luma_of(url: str, at: float) -> float:
    """Mean brightness of one frame, 0-255.

    A teaser is watched on a phone, in daylight, at thumbnail size. The first
    Magic Sword cut was a dim cave interior that measured well on motion and
    read as a black rectangle in the feed — legibility is a separate property
    from movement, so it gets its own measurement.
    """
    try:
        from PIL import Image, ImageStat
    except ImportError:
        return 128.0
    p = Path(f"/tmp/aw_luma_{int(at)}.jpg")
    r = subprocess.run(["ffmpeg", "-y", "-nostdin", "-ss", str(at + 1.0), "-i", url,
                        "-frames:v", "1", "-q:v", "5", "-vf", "scale=192:-2", str(p)],
                       capture_output=True, text=True, timeout=180)
    if r.returncode != 0 or not p.exists():
        return 0.0
    return ImageStat.Stat(Image.open(p).convert("L")).mean[0]


def detect_crop(url: str, at: float) -> str | None:
    """The baked-in letterbox. Many archive transfers carry black bars INSIDE
    the frame, so fitting the file whole into 9:16 renders the picture as a
    small strip in the middle (measured on Hercules Unchained). cropdetect
    finds the real picture; without this the reframe is technically correct
    and visually useless."""
    r = subprocess.run(["ffmpeg", "-nostdin", "-ss", str(at), "-i", url,
                        "-t", "3", "-vf", "cropdetect=24:2:0", "-f", "null", "-"],
                       capture_output=True, text=True, timeout=300)
    crops = [ln.split("crop=")[-1].strip() for ln in r.stderr.splitlines()
             if "crop=" in ln]
    if not crops:
        return None
    best = max(set(crops), key=crops.count)          # the steadiest reading
    try:
        w, h, x, y = (int(v) for v in best.split(":"))
    except ValueError:
        return None
    if w < 160 or h < 120:
        return None
    return f"crop={w}:{h}:{x}:{y}"


def find_scene(url: str, runtime: float, min_motion: float = 3.0) -> dict | None:
    """Find a real cut about a third of the way into the film.

    The shot index only analyses each film's opening ~300 s, which for a
    feature is titles and the first scene — the Hercules Unchained teaser cut
    from it was the credit roll, and it passed a motion test because the ship
    behind the credits was moving. So the primary path does its own detection
    in a 60 s window at ~35% of the RUNTIME: far enough in to be the picture
    proper, far enough from the end to spoil nothing.

    One scdet pass over 60 s of a remote file costs a few seconds, because
    ffmpeg range-requests only what it decodes (measured: 1.7-3.4 s to reach
    and cut at the 250-290 s mark of four different archive.org films).
    """
    if not runtime or runtime < 240:
        return None                      # too short to have a "middle"
    # Several places to look, all in the first two-thirds. One window can be a
    # night scene or a lull; trying three costs a few seconds and is the
    # difference between a teaser and a black rectangle.
    for fraction in (0.35, 0.50, 0.25, 0.60):
        probe_at = max(TITLES_END, runtime * fraction)
        r = subprocess.run(
            ["ffmpeg", "-nostdin", "-ss", str(probe_at), "-i", url, "-t", "60",
             "-filter_complex", "select='gt(scene,0.35)',metadata=print:file=-",
             "-an", "-f", "null", "-"],
            capture_output=True, text=True, timeout=600)
        cuts = []
        for line in (r.stdout + r.stderr).splitlines():
            if "pts_time:" in line:
                try:
                    cuts.append(probe_at + float(line.split("pts_time:")[1].split()[0]))
                except (ValueError, IndexError):
                    pass
        # A cut gives a clean START. With no detected cut the window is still a
        # perfectly good scene — begin a couple of seconds in and say so.
        for start in (cuts[:2] or [probe_at + 2.0]):
            m = motion_of(url, start)
            lum = luma_of(url, start)
            ok = m >= min_motion and MIN_LUMA <= lum <= MAX_LUMA
            why = ("ok" if ok else
                   ("too dark" if lum < MIN_LUMA else
                    ("blown out" if lum > MAX_LUMA else "static")))
            print(f"[clip] probe {fraction:.0%} at {start:6.0f}s  "
                  f"motion {m:5.1f}  luma {lum:5.1f}  {why}")
            if ok:
                return {"url": url, "start": start, "end": start + TARGET,
                        "tags": "mid-film", "motion": m, "luma": lum}
    return None


def pick_shot(db_path: str, archive_id: str, min_motion: float = 3.0) -> dict | None:
    """The deepest shot in the analysed window that is actually MOVING."""
    if not Path(db_path).exists():
        return None
    db = sqlite3.connect(db_path)
    rows = db.execute(
        """SELECT sourceURL, startSeconds, endSeconds, tags FROM shots
           WHERE archiveID = ? AND startSeconds >= ? AND endSeconds - startSeconds >= ?
           ORDER BY startSeconds DESC LIMIT 14""",
        (archive_id, TITLES_END, MIN_SHOT)).fetchall()
    db.close()
    if not rows:
        return None
    # Longest first — a long take reads as a scene, a two-second one as a
    # glitch — then take the first that passes the motion test.
    for url, start, end, tags in sorted(rows, key=lambda r: -(r[2] - r[1])):
        m = motion_of(url, start)
        lum = luma_of(url, start)
        ok = m >= min_motion and MIN_LUMA <= lum <= MAX_LUMA
        print(f"[clip] candidate {start:6.1f}s  len {end-start:4.1f}s  "
              f"motion {m:5.1f}  luma {lum:5.1f}  {'ok' if ok else 'rejected'}")
        if ok:
            return {"url": url, "start": start, "end": end, "tags": tags,
                    "motion": m, "luma": lum}
    print("[clip] every analysed shot is static", file=sys.stderr)
    return None


def build_filter(title: str, year, has_text: bool, crop: str | None = None) -> str:
    """9:16 with the film fitted whole over a blurred fill of itself, and a
    lower third that survives muted autoplay — which is how nearly everyone
    will see it."""
    pre = f"{crop}," if crop else ""
    chain = (
        f"[0:v]{pre}split=2[a][b];"
        f"[a]scale={W}:{H}:force_original_aspect_ratio=increase,"
        f"crop={W}:{H},gblur=sigma=42,eq=brightness=-0.10[bg];"
        f"[b]scale={W}:-2:force_original_aspect_ratio=decrease[fg];"
        f"[bg][fg]overlay=(W-w)/2:(H-h)/2[v]"
    )
    if not has_text:
        return chain
    safe = (title.replace("\\", "").replace(":", "\\:")
                 .replace("'", "’").replace("%", ""))
    line2 = f"{year} · free to watch · archivewatch.org" if year else \
            "free to watch · archivewatch.org"
    f_title = str(FONTS / "Fraunces-Display-Black.ttf")
    f_meta = str(FONTS / "Inter-Regular.ttf")
    chain += (
        f";[v]drawbox=x=0:y={H-360}:w={W}:h=360:color=black@0.55:t=fill,"
        f"drawtext=fontfile='{f_title}':text='{safe}':fontcolor=0xEBEBEB:"
        f"fontsize=62:x=72:y={H-268}:line_spacing=8,"
        f"drawtext=fontfile='{f_meta}':text='{line2}':fontcolor=0x9A9AA0:"
        f"fontsize=36:x=72:y={H-168},"
        f"drawbox=x=72:y={H-300}:w=96:h=7:color=0xFF5C35@1.0:t=fill[out]"
    )
    return chain


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--spec", required=True)
    ap.add_argument("--index", default="/tmp/clips.sqlite",
                    help="clips.sqlite from the stock-index release")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seconds", type=float, default=TARGET)
    ap.add_argument("--source", default=None, help="override the video URL")
    args = ap.parse_args()

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    if not shutil.which("ffmpeg"):
        print("[clip] ffmpeg not installed — skipping", file=sys.stderr)
        return 4

    # Primary: our own detection a third of the way in. Fallback: the stock
    # index's opening-window shots, which are better than nothing for a short
    # film or a cartoon, where 300 s is most of the picture.
    runtime = 0.0
    for f in spec.get("fragments", []):
        if f["kind"] == "meta" and " min" in f["text"]:
            for part in f["text"].split("·"):
                if "min" in part:
                    try:
                        runtime = float(part.strip().split()[0]) * 60
                    except (ValueError, IndexError):
                        pass
    src_url = args.source
    if not src_url:
        db_shot = pick_shot(args.index, spec["id"])
        src_url = db_shot["url"] if db_shot else None
    else:
        db_shot = None
    shot = find_scene(src_url, runtime) if src_url else None
    if not shot:
        shot = db_shot
    if not shot:
        # No analysed shots for this film. Say so and skip: guessing an offset
        # into an unanalysed film is how a "teaser" turns out to be a black
        # frame or a title card.
        print(f"[clip] no analysed shot for {spec['id']} — no clip today",
              file=sys.stderr)
        return 3

    url = args.source or shot["url"]
    dur = min(args.seconds, max(MIN_SHOT, shot["end"] - shot["start"] + 6))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    has_text = ffmpeg_has("drawtext")
    if not has_text:
        print("[clip] this ffmpeg has no drawtext; clip goes out unlabelled",
              file=sys.stderr)
    crop = detect_crop(url, shot["start"])
    if crop:
        print(f"[clip] letterbox removed: {crop}")
    filt = build_filter(spec["title"], spec.get("year"), has_text, crop)
    target = "[out]" if has_text else "[v]"

    cmd = ["ffmpeg", "-y", "-nostdin", "-ss", str(shot["start"]), "-i", url,
           "-t", str(dur), "-filter_complex", filt, "-map", target,
           "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
           "-preset", "medium", "-crf", "23", "-r", "30",
           "-movflags", "+faststart", "-an", str(out)]
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    if r.returncode != 0 or not out.exists():
        print(f"[clip] ffmpeg failed: {r.stderr.strip()[-400:]}", file=sys.stderr)
        return 1

    size = out.stat().st_size
    print(f"[clip] {out}  {dur:.0f}s  {size/1024/1024:.1f} MB  "
          f"from {shot['start']:.0f}s  in {time.time()-t0:.0f}s")
    if shot.get("tags"):
        print(f"[clip] scene tags: {shot['tags'][:70]}")
    # Bluesky's ceiling is 100 MB / 3 minutes; Shorts and Reels are far more
    # generous. A teaser that breaks the tightest one is a teaser nobody sees.
    if size > 95_000_000:
        print("[clip] over Bluesky's 100 MB ceiling", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
