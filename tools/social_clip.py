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

* **A line beats a shot.** When the film publishes subtitles, `social_line`
  picks the most quotable line of its first act and the cut is built AROUND
  it: the scene starts a beat before the line is spoken, the words burn on
  screen (nearly everyone watches muted), and the AUDIO is kept, because a
  quotable line nobody can hear is a caption, not a teaser. Without
  subtitles — or when the line lands on a dark frame — it falls back to the
  shot-led cut, silent as before.

Run:
  python tools/social_clip.py --spec social/out/post.json \
      --index /tmp/clips.sqlite --out social/out/clip.mp4
"""

from __future__ import annotations

import sys as _sys
_sys.path.insert(0, __file__.rsplit('/', 1)[0])
from ffmpeg_limits import FFMPEG, FFPROBE  # noqa: E402

import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import textwrap
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from social_hear import hear                                   # noqa: E402
from social_line import pick_lines                             # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FONTS = REPO / "roku" / "fonts"

TITLES_END = 60.0          # before this is idents and opening titles
MIN_SHOT = 4.0
TARGET = 18.0              # a teaser, not an excerpt
MIN_LUMA = 42.0            # below this the frame reads as black on a phone
MAX_LUMA = 225.0           # above it, a blown-out fade or a title card
W, H = 1080, 1920

SUBS = "https://archivewatch.org/subs/{id}/en.vtt"
LEAD = 2.2                 # scene before the line is spoken
TAIL = 3.4                 # after it, so the clip never cuts on the word
LINE_MIN, LINE_MAX = 11.0, 22.0   # long enough to read three burned lines
QUOTE_COLS = 24            # characters per burned line, at fontsize 54
QUOTE_LINES = 3

# Reels, Shorts and TikTok draw their OWN chrome over the video: the account
# name, the caption and the action rail all sit across the bottom, and a
# header sits across the top. Measured against the published creative specs
# (Reels ~250 px top / ~420 px bottom, TikTok ~130 / ~480 on a 1080x1920
# frame), so the union is what we must clear. Everything we burn therefore
# lives in the UPPER band — the owner watched a Reel with the account name
# printed straight through our title.
TOP_SAFE = 250
BOTTOM_SAFE = 480

# The frame is BANDED, not layered. Owner: "when we are building vertical
# video, we shouldn't overlay the captions text on the square video, but
# rather we should put it above or below to not block the content."
#
# So the picture gets a box of its own and the words get theirs: title above,
# film in the middle, quote below, none of them touching. The film is fitted
# inside its box at its own aspect (Decision 097 — never reshape it), which
# means a 4:3 film is a little narrower than the frame. That is the cost of
# not covering an actor's face with a caption, and it is worth paying.
#
# Full-width was tried first and cannot work: a 4:3 film fitted to 1080 wide
# is 810 tall, so the band left under it inside the safe area is 75 px — a
# third of one line of type.
CARD_Y, CARD_H = 250, 260          # title block, under the platform header
FILM_Y, FILM_H = 530, 630          # with a quote to seat below it
FILM_Y_TALL, FILM_H_TALL = 530, 910  # without one, the picture takes the room
QUOTE_Y, QUOTE_H = 1180, 260       # ends at 1440 = H - BOTTOM_SAFE

# A line is burned on screen only when the film is HEARD saying it. Measured
# 2026-09-08 against three films with published subtitles: a correctly-timed
# track scores 0.625-1.0, and every wrong pairing — a mistimed file, and one
# item carrying An American Werewolf in London's subtitles under The Werewolf
# of Washington — scores 0.0. The gap is enormous, so the threshold is not
# finely tuned and should not be lowered to "rescue" more lines: below it, the
# words on screen are not the words being spoken, which is the defect.
HEARD_MIN = 0.5
HEAR_TRIES = 3             # candidate lines to test before giving up


def ffmpeg_has(feature: str) -> bool:
    r = subprocess.run([*FFMPEG, "-hide_banner", "-filters"],
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
        r = subprocess.run([*FFMPEG, "-y", "-nostdin", "-ss", str(at + offset),
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
    r = subprocess.run([*FFMPEG, "-y", "-nostdin", "-ss", str(at + 1.0), "-i", url,
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
    r = subprocess.run([*FFMPEG, "-nostdin", "-ss", str(at), "-i", url,
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
            [*FFMPEG, "-nostdin", "-ss", str(probe_at), "-i", url, "-t", "60",
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


def has_audio(target: str) -> bool:
    """Does this file or URL carry an audio stream?

    Asked of the SOURCE and again of the RENDER. A teaser that goes out silent
    is the defect the owner reported twice — once on YouTube, once on Bluesky —
    and it is invisible in a screenshot, so it has to be measured.
    """
    try:
        r = subprocess.run([*FFPROBE, "-v", "error", "-select_streams", "a:0",
                            "-show_entries", "stream=codec_type",
                            "-of", "csv=p=0", target],
                           capture_output=True, text=True, timeout=120)
        return "audio" in r.stdout
    except (subprocess.SubprocessError, OSError):
        return False


def fetch_vtt(archive_id: str, local: str | None = None) -> str | None:
    """The film's published English subtitles, or None.

    A 404 is the ordinary case — ~16% of the catalog carries a track — so it
    is reported at one line and never as a failure.
    """
    if local:
        return Path(local).read_text(encoding="utf-8", errors="replace")
    url = SUBS.format(id=archive_id)
    try:
        with urllib.request.urlopen(url, timeout=45) as r:
            body = r.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        print(f"[clip] no subtitles for {archive_id} ({e})")
        return None
    # Pages answers a missing path with 404.html at HTTP 200 for some routes;
    # a WebVTT file always opens WEBVTT, so ask the body, not the status.
    if not body.lstrip().upper().startswith("WEBVTT"):
        print(f"[clip] {archive_id}: /subs answered, but not with WebVTT")
        return None
    return body


def wrap_quote(text: str, cols: int = QUOTE_COLS,
               max_lines: int = QUOTE_LINES) -> list | None:
    """The line broken for burning, or None if it cannot be read on a phone.

    Wrapping is refused rather than shrunk: a quote that needs four lines at
    this size is a quote that competes with the picture it sits on.
    """
    lines = textwrap.wrap(" ".join(text.split()), width=cols,
                          break_long_words=False, break_on_hyphens=False)
    if not lines or len(lines) > max_lines:
        return None
    return lines


def line_segment(url: str, line: dict, seconds: float) -> dict | None:
    """Turn a chosen line into a cut, or None if it lands on a dark frame.

    The luma gate is the same one the shot picker uses. A dialogue scene may
    legitimately be dim, so two frames are sampled before giving up — but a
    quote burned over black is a title card with words on it.
    """
    start = max(0.0, line["start"] - LEAD)
    cap = min(LINE_MAX, seconds if seconds > 0 else LINE_MAX)
    dur = max(LINE_MIN, min(cap, (line["end"] - start) + TAIL))
    lit = False
    for probe in (line["start"] + 0.3, line["start"] + (line["end"] - line["start"]) / 2):
        lum = luma_of(url, probe)
        print(f"[clip] line frame at {probe:6.1f}s  luma {lum:5.1f}")
        if MIN_LUMA <= lum <= MAX_LUMA:
            lit = True
            break
    if not lit:
        print("[clip] the line plays over a black or blown-out frame — "
              "falling back to the shot cut", file=sys.stderr)
        return None
    return {"url": url, "start": start, "end": start + dur,
            "line": line, "tags": None}


def build_filter(title: str, year, has_text: bool, crop: str | None = None,
                 quote_file: str | None = None, quote_at: float = 0.0) -> str:
    """9:16 with the film fitted whole over a blurred fill of itself, and a
    lower third that survives muted autoplay — which is how nearly everyone
    will see it.

    A quote, when there is one, sits just above that lower third and fades in
    on the beat the line is spoken. It is read from a FILE rather than passed
    inline: drawtext's own escaping cannot be trusted with a sentence someone
    else wrote, and a stray colon or apostrophe would take the whole render
    down."""
    pre = f"{crop}," if crop else ""
    box_y, box_h = (FILM_Y, FILM_H) if quote_file else (FILM_Y_TALL, FILM_H_TALL)
    # `decrease` bounds BOTH dimensions, so the film lands inside its box
    # whatever its aspect — a 4:3 film is height-limited and sits narrower
    # than the frame, a scope film is width-limited and sits shorter. Neither
    # is cropped and neither reaches the bands.
    chain = (
        f"[0:v]{pre}split=2[a][b];"
        f"[a]scale={W}:{H}:force_original_aspect_ratio=increase,"
        f"crop={W}:{H},gblur=sigma=42,eq=brightness=-0.10[bg];"
        f"[b]scale={W}:{box_h}:force_original_aspect_ratio=decrease[fg];"
        f"[bg][fg]overlay=(W-w)/2:{box_y}+({box_h}-h)/2[v]"
    )
    if not has_text:
        return chain
    safe = (title.replace("\\", "").replace(":", "\\:")
                 .replace("'", "’").replace("%", ""))
    line2 = f"{year} · free to watch · archivewatch.org" if year else \
            "free to watch · archivewatch.org"
    f_title = str(FONTS / "Fraunces-Display-Black.ttf")
    f_meta = str(FONTS / "Inter-Regular.ttf")
    tail = "[lt]" if quote_file else "[out]"
    chain += (
        f";[v]drawbox=x=0:y={CARD_Y}:w={W}:h={CARD_H}:color=black@0.55:t=fill,"
        f"drawtext=fontfile='{f_title}':text='{safe}':fontcolor=0xEBEBEB:"
        f"fontsize=62:x=72:y={CARD_Y + 92}:line_spacing=8,"
        f"drawtext=fontfile='{f_meta}':text='{line2}':fontcolor=0x9A9AA0:"
        f"fontsize=36:x=72:y={CARD_Y + 192},"
        f"drawbox=x=72:y={CARD_Y + 60}:w=96:h=7:color=0xFF5C35@1.0:t=fill{tail}"
    )
    if quote_file:
        on = max(0.0, quote_at - 0.30)
        f_quote = str(FONTS / "Fraunces-Text-Italic.ttf")
        # Centred in its own band, on the blurred wash rather than on the
        # film. A light box only — the wash is already darkened, and a heavy
        # slab under text that covers nothing reads as a mistake.
        chain += (
            f";[lt]drawtext=fontfile='{f_quote}':textfile='{quote_file}':"
            f"fontcolor=0xF4F4F4:fontsize=54:line_spacing=14:"
            f"box=1:boxcolor=black@0.35:boxborderw=22:"
            f"x=(w-text_w)/2:y={QUOTE_Y}+({QUOTE_H}-text_h)/2:"
            f"alpha='if(lt(t,{on:.2f}),0,min(1,(t-{on:.2f})/0.45))'[out]"
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
    ap.add_argument("--vtt", default=None,
                    help="a local WebVTT file instead of the published one")
    ap.add_argument("--no-line", action="store_true",
                    help="skip the subtitle line; always cut on a shot")
    ap.add_argument("--no-hear", action="store_true",
                    help="do not check the line against the audio (testing only)")
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
    # A quotable line, when the film has one, decides the cut. It is a better
    # teaser than any frame statistic: somebody says something, and the scroll
    # stops for it.
    shot = None
    if src_url and not args.no_line:
        vtt = fetch_vtt(spec["id"], args.vtt)
        for line in (pick_lines(vtt, limit=HEAR_TRIES) if vtt else []):
            if not wrap_quote(line["text"]):
                print(f"[clip] line too long to burn: {line['text']!r}")
                continue
            print(f"[clip] line at {line['start']:.1f}s: {line['text']!r}")
            # THE GATE. A subtitle file says a line is spoken here; the film
            # is the authority on whether it is. Owner, on a teaser whose
            # caption was not the dialogue: "You need to actually check the
            # audio for the words before committing to putting the captions
            # on screen."
            if not args.no_hear:
                got = hear(src_url, line["start"], line["end"], line["text"])
                print(f"[clip] heard {got['heard'][:64]!r} — {got['why']}")
                if got["score"] is None:
                    # Could not CHECK, which is not the same as checked and
                    # passed. Burning an unverified line is the defect.
                    print("[clip] the line could not be checked against the "
                          "audio — not burning it", file=sys.stderr)
                    break
                if got["score"] < HEARD_MIN:
                    print(f"[clip] the film does not say this here "
                          f"(score {got['score']:.2f}) — trying the next line")
                    continue
            shot = line_segment(src_url, line, args.seconds)
            if shot:
                break

    if not shot:
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
    line = shot.get("line")
    if line:
        dur = shot["end"] - shot["start"]
    else:
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
    quote_file = None
    if line and has_text:
        quote_file = str(out.with_suffix(".quote.txt"))
        Path(quote_file).write_text("\n".join(wrap_quote(line["text"])) + "\n",
                                    encoding="utf-8")
    filt = build_filter(spec["title"], spec.get("year"), has_text, crop,
                        quote_file, line["start"] - shot["start"] if line else 0.0)
    target = "[out]" if has_text else "[v]"

    cmd = [*FFMPEG, "-y", "-nostdin", "-ss", str(shot["start"]), "-i", url,
           "-t", str(dur), "-filter_complex", filt, "-map", target,
           "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
           "-preset", "medium", "-crf", "23", "-r", "30",
           "-movflags", "+faststart"]
    # EVERY teaser keeps its sound, not only the line-led ones. A silent Short
    # or Reel does not read as restraint, it reads as broken — the owner
    # watched one go up with no audio. `0:a?` so a film with a genuinely
    # silent transfer still renders rather than failing the run, and loudnorm
    # because archive.org transfers range from whisper to clipping and a feed
    # autoplays them next to professionally mastered video.
    cmd += ["-map", "0:a?", "-c:a", "aac", "-b:a", "128k", "-ac", "2",
            "-af", f"loudnorm=I=-16:TP=-1.5:LRA=11,"
                   f"afade=t=in:st=0:d=0.6,"
                   f"afade=t=out:st={max(0.0, dur - 0.9):.2f}:d=0.9"]
    cmd += [str(out)]
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    if r.returncode != 0 or not out.exists():
        print(f"[clip] ffmpeg failed: {r.stderr.strip()[-400:]}", file=sys.stderr)
        return 1

    # The owner's rule: every teaser carries the film's own sound. A source
    # that is genuinely silent is fine; losing audio the source HAD is not,
    # and it cannot be seen in a frame — so measure both ends and refuse
    # rather than publish a silent teaser, which sends the cards out instead.
    src_audio = has_audio(url)
    out_audio = has_audio(str(out))
    if src_audio and not out_audio:
        print("[clip] the source has audio and the render lost it — no clip today",
              file=sys.stderr)
        out.unlink(missing_ok=True)
        return 5
    if not src_audio:
        print("[clip] this transfer carries no audio at all")

    size = out.stat().st_size
    print(f"[clip] {out}  {dur:.0f}s  {size/1024/1024:.1f} MB  "
          f"from {shot['start']:.0f}s  in {time.time()-t0:.0f}s")
    # The caption writer needs to know what the teaser actually shows. A hook
    # that quotes a line the viewer is about to hear reads as one piece; a
    # hook invented next to a silent shot reads as two.
    out.with_suffix(".json").write_text(json.dumps({
        "start": round(shot["start"], 2),
        "seconds": round(dur, 2),
        "audio": out_audio,
        "quote": line["text"] if line else None,
    }, indent=2) + "\n", encoding="utf-8")
    if line:
        print(f"[clip] quote burned: {line['text']!r}")
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
