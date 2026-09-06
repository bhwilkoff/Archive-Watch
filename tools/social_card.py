#!/usr/bin/env python3
"""
social_card.py — render a post spec as the marquee card.

The card is the app's own design language, not a generic quote-graphic: the
house faces (Fraunces Display + Inter), the canvas and marquee colours from
CLAUDE.md, and Decision 097's rule that a poster is shown WHOLE over an
ambient wash of itself — never cropped to fit a frame. Somebody who sees the
card and later opens the app should recognise it as the same place.

Sizes (docs/SOCIAL-PROGRAM.md §6):
  square   1080x1080  Threads, Facebook, Bluesky, Instagram feed
  portrait 1080x1350  Instagram feed (the taller frame it favours)
  story    1080x1920  Stories / Reels still

Run:
  python tools/social_card.py --spec social/out/post.json --size square \
                              --out social/out/card.jpg
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = Path(__file__).resolve().parent.parent
FONTS = REPO / "roku" / "fonts"
UA = "ArchiveWatch-Social/1.0 (+https://archivewatch.org)"

CANVAS = (11, 11, 12)
MARQUEE = (255, 92, 53)
TEXT_PRI = (235, 235, 235)
TEXT_SEC = (154, 154, 160)

ACCENT = {           # CLAUDE.md's per-category semantic accents
    "feature-film": (255, 92, 53), "tv-series": (45, 91, 255),
    "tv-special": (45, 91, 255), "tv-episode": (45, 91, 255),
    "silent-film": (201, 166, 107), "animation": (255, 77, 141),
    "newsreel": (138, 143, 152), "documentary": (63, 167, 150),
    "ephemeral": (124, 91, 186), "short-film": (232, 163, 23),
    "commercial": (232, 163, 23),
}

SIZES = {"square": (1080, 1080), "portrait": (1080, 1350), "story": (1080, 1920)}


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def fetch_image(url: str) -> Image.Image | None:
    if not url:
        return None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=45) as r:
            return Image.open(io.BytesIO(r.read())).convert("RGB")
    except Exception as e:  # noqa: BLE001
        print(f"[card] poster fetch failed: {e}", file=sys.stderr)
        return None


def wash(canvas: Image.Image, art: Image.Image, box: tuple) -> None:
    """Decision 097's ambient base: the art scaled to FILL, blurred hard, so the
    card carries the film's own colour without ever showing a cropped poster as
    if it were a picture."""
    w, h = box[2] - box[0], box[3] - box[1]
    ratio = max(w / art.width, h / art.height)
    big = art.resize((max(1, int(art.width * ratio)), max(1, int(art.height * ratio))),
                     Image.LANCZOS)
    left = (big.width - w) // 2
    top = (big.height - h) // 2
    crop = big.crop((left, top, left + w, top + h))
    crop = crop.filter(ImageFilter.GaussianBlur(radius=max(24, w // 18)))
    crop = Image.blend(crop, Image.new("RGB", crop.size, CANVAS), 0.52)
    canvas.paste(crop, (box[0], box[1]))


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1],
                                           radius=radius, fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out


def hard_break(draw: ImageDraw.ImageDraw, word: str, fnt, width: int) -> list:
    """Split a word that cannot fit the column at all.

    Nothing in a catalog of 26,000 archive titles guarantees a word narrower
    than the text column — a German compound or a run-on id will not fit at
    any font size the card uses. Without this it rendered straight past the
    card edge, which is the same overflow the square layout had.
    """
    out, cur = [], ""
    for ch in word:
        if draw.textlength(cur + ch, font=fnt) <= width or not cur:
            cur += ch
        else:
            out.append(cur)
            cur = ch
    if cur:
        out.append(cur)
    return out


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, width: int, max_lines: int) -> list:
    # Break the unbreakable FIRST, so the line-filling loop below only ever
    # sees words that can actually fit.
    words = []
    for w in text.split():
        if draw.textlength(w, font=fnt) > width:
            words.extend(hard_break(draw, w, fnt, width))
        else:
            words.append(w)
    lines, cur = [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=fnt) <= width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
            if len(lines) == max_lines:
                break
    if cur and len(lines) < max_lines:
        lines.append(cur)
    # Mark a cut ONLY when words were actually dropped. Comparing joined
    # LENGTHS marks a false cut on any text with double spaces — the meta line
    # ("1965  ·  Feature film") read "dir. David L. Hewitt …" with nothing
    # missing. Count the words instead.
    if len(" ".join(lines).split()) < len(words):
        # Shorten the last line to make room for the ellipsis. `rsplit(" ")` on
        # a string with NO space returns it unchanged, so the original loop
        # spun forever on any single word wider than the column — the card
        # renderer hung indefinitely on "Die Nibelungen: Siegfried" and took
        # the whole daily run with it. Stop when nothing more can come off.
        while lines and draw.textlength(lines[-1] + " …", font=fnt) > width:
            shorter = lines[-1].rsplit(" ", 1)[0]
            if shorter == lines[-1]:
                shorter = lines[-1][:-1]          # trim a character instead
            if not shorter:
                lines.pop()
                break
            lines[-1] = shorter
        if lines:
            lines[-1] += " …"
    return lines


def fit_title(draw, title: str, width: int, start: int, min_size: int) -> tuple:
    """The title takes the largest size at which it fits two lines. A marquee
    sets the title big; a fixed size either overflows or wastes the card."""
    size = start
    while size > min_size:
        f = font("Fraunces-Display-Black.ttf", size)
        lines = wrap(draw, title, f, width, 2)
        if all(draw.textlength(l, font=f) <= width for l in lines) and "…" not in "".join(lines):
            return f, lines
        size -= 4
    f = font("Fraunces-Display-Black.ttf", min_size)
    return f, wrap(draw, title, f, width, 2)


def render(spec: dict, size_name: str) -> Image.Image:
    """Layout order: MEASURE THE COPY, then give the picture what is left.

    Sizing the poster to a fixed fraction first is what left a review floating
    in dead space on the portrait card and squeezed the quote off the square
    one — the copy is variable-length, so it has to be measured before the
    frame around it is decided.
    """
    W, H = SIZES[size_name]
    img = Image.new("RGB", (W, H), CANVAS)
    draw = ImageDraw.Draw(img)
    accent = ACCENT.get(spec.get("contentType", ""), MARQUEE)
    art = fetch_image(spec.get("poster"))
    pad = 72
    foot = 108                      # the wordmark strip

    frag = {f["kind"]: f["text"] for f in spec.get("fragments", [])}
    quote, credit = frag.get("review"), frag.get("review_credit")

    f_eyebrow = font("Inter-SemiBold.ttf", 26)
    f_meta = font("Inter-Regular.ttf", 27)
    f_body = font("Inter-Regular.ttf", 30)
    f_quote = font("Fraunces-Text-Italic.ttf", 33)
    f_credit = font("Inter-Medium.ttf", 25)

    if art:
        wash(img, art, (0, 0, W, H))

    # ---- the square's picture is a FIXED column, so its geometry is known
    # before the copy is measured. Measuring against a guessed width and then
    # placing the art is what ran the quote off the right edge: 504 px
    # measured against 405 px of actual column.
    art_w = art_h = 0
    if size_name == "square":
        art_h = H - pad * 2 - foot + 40
        if art:
            art_w = int(art_h * (art.width / art.height))
            if art_w > W * 0.44:
                art_w = int(W * 0.44)
                art_h = int(art_w * (art.height / art.width))
        text_x = pad + (art_w + 56 if art else 0)
        text_w = W - text_x - pad
    else:
        text_x = pad
        text_w = W - pad * 2

    # ---- measure the copy block -----------------------------------------

    title_start = 70 if size_name == "square" else 86
    f_title, title_lines = fit_title(draw, spec.get("title", ""), text_w, title_start, 40)
    meta_lines = wrap(draw, frag["meta"], f_meta, text_w, 2) if frag.get("meta") else []

    copy_h = 44 + len(title_lines) * int(f_title.size * 1.06) + 16
    copy_h += len(meta_lines) * 38 + 20

    body_lines, body_font, body_fill, is_quote = [], f_body, TEXT_SEC, False
    if quote:
        body_lines = wrap(draw, quote, f_quote, text_w - 26, 7)
        body_font, body_fill, is_quote = f_quote, TEXT_PRI, True
        copy_h += len(body_lines) * 44 + (54 if credit else 0)
    elif frag.get("synopsis"):
        body_lines = wrap(draw, frag["synopsis"], f_body, text_w, 6)
        copy_h += len(body_lines) * 42

    # ---- place the picture ----------------------------------------------
    if size_name == "square":
        if art:
            fitted = art.resize((art_w, art_h), Image.LANCZOS)
            img.paste(rounded(fitted, 18), (pad, (H - foot - art_h) // 2),
                      rounded(fitted, 18))
        top = max(pad + 20, (H - foot - copy_h) // 2)
    else:
        # Portrait/story: the COPY is measured first and the poster takes what
        # is left, so a long review shrinks the picture instead of overflowing.
        avail = H - pad * 2 - foot - copy_h - 40
        if art:
            art_h = min(avail, int(H * 0.56))
            art_w = int(art_h * (art.width / art.height))
            if art_w > W - pad * 2:
                art_w = W - pad * 2
                art_h = int(art_w * (art.height / art.width))
            fitted = art.resize((art_w, art_h), Image.LANCZOS)
            img.paste(rounded(fitted, 18), ((W - art_w) // 2, pad),
                      rounded(fitted, 18))
        text_x = pad
        top = pad + art_h + 52

    # ---- draw it ---------------------------------------------------------
    draw.text((text_x, top), " ".join(spec.get("kind", "").upper()),
              font=f_eyebrow, fill=accent)
    top += 44
    for line in title_lines:
        draw.text((text_x, top), line, font=f_title, fill=TEXT_PRI)
        top += int(f_title.size * 1.06)
    top += 16
    for line in meta_lines:
        draw.text((text_x, top), line, font=f_meta, fill=TEXT_SEC)
        top += 38
    top += 20

    if body_lines and is_quote:
        # A viewer's words are the loudest thing on the card when we have them
        # (§2 — the program joins the conversation rather than talking over it).
        bar_top = top + 6
        bar_h = len(body_lines) * 44 - 12
        draw.rectangle([text_x, bar_top, text_x + 5, bar_top + bar_h], fill=accent)
        for line in body_lines:
            draw.text((text_x + 26, top), line, font=body_font, fill=body_fill)
            top += 44
        if credit:
            top += 10
            draw.text((text_x + 26, top), credit, font=f_credit, fill=TEXT_SEC)
    elif body_lines:
        for line in body_lines:
            draw.text((text_x, top), line, font=body_font, fill=body_fill)
            top += 42

    # ---- the footer: who we are, and that it costs nothing ---------------
    f_mark = font("Fraunces-Display-SemiBold.ttf", 34)
    f_note = font("Inter-Regular.ttf", 25)
    fy = H - pad - 46
    draw.text((pad, fy), "Archive Watch", font=f_mark, fill=TEXT_PRI)
    note = "Free to watch · public domain"
    draw.text((W - pad - draw.textlength(note, font=f_note), fy + 10),
              note, font=f_note, fill=TEXT_SEC)
    draw.rectangle([pad, fy - 26, pad + 64, fy - 20], fill=accent)
    return img


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--spec", required=True)
    ap.add_argument("--size", default="square", choices=sorted(SIZES))
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-bytes", type=int, default=950_000,
                    help="Bluesky's blob ceiling is 1,000,000 bytes; stay under it")
    args = ap.parse_args()

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    img = render(spec, args.size)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    # Step the quality down until it fits the tightest platform ceiling. A card
    # that is one byte over is a post that does not happen.
    for q in (92, 88, 84, 78, 72, 66, 60):
        img.save(out, "JPEG", quality=q, optimize=True, progressive=True)
        if out.stat().st_size <= args.max_bytes:
            break
    print(f"[card] {out}  {args.size}  {out.stat().st_size/1024:.0f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
