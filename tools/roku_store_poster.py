#!/usr/bin/env python3
"""
roku_store_poster.py — the 540 x 405 poster the Roku Channel Store shows.

The channel already ships `roku/images/icon_focus_fhd.png` at exactly this
size, and it would pass certification: it is the photographic 1902 Méliès
still in its film-strip frame, which is THE app icon and the one thing that
must never be redrawn (memory: app_icon_photographic_only). But as a STORE
tile it carries no name, and a tile in a grid of named channels that does not
say what it is loses every time.

So this composes the same still with the wordmark, using the type and the one
accent the rest of the product already uses — Fraunces Display Black for the
name, the 96 x 7 marquee-orange rule that sits above every title on Detail,
in the social cards and on the vertical teasers (#FF5C35, CLAUDE.md), and
Inter for the line beneath. Nothing new is invented for the store.

Two rules borrowed from the rest of the system:
  * the still is never reshaped (Decision 097) — it is fitted, then panned to
    keep the moon's face out of the wordmark band;
  * the scrim is a gradient, not a slab, because a hard edge across a
    photograph reads as a mistake.

Run:
  python3 tools/roku_store_poster.py --out roku/images/store_poster_fhd.png
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
STILL = REPO / "ArchiveWatch" / "ArchiveWatch" / "Assets.xcassets" / \
    "AppIcon.appiconset" / "icon-1024.png"
FONTS = REPO / "roku" / "fonts"
ORANGE = (0xFF, 0x5C, 0x35)
W, H = 540, 405


def fit_width(text: str, path: Path, box: int, start: int, floor: int = 22):
    """The largest size at which this string fits the box.

    Measured, not chosen: at a fixed 54 px "ARCHIVE WATCH" ran off the right
    edge of a 540 px tile, which is the kind of thing that looks fine in the
    code and wrong in the store.
    """
    for size in range(start, floor - 1, -1):
        f = ImageFont.truetype(str(path), size)
        if f.getbbox(text)[2] <= box:
            return f
    return ImageFont.truetype(str(path), floor)


def compose(still: Path, w: int = W, h: int = H) -> Image.Image:
    """Banded, not layered.

    A first version laid the wordmark over the photograph with a gradient
    scrim, and the moon's face is the brightest thing in the frame — white
    type on white plaster, unreadable at tile size. The product already
    answers this everywhere else (the vertical teasers, Detail, the social
    cards): give the picture its own band and the words theirs, so neither
    covers the other and the still is never dimmed to make room for type.
    """
    band = int(h * 0.29)
    art_h = h - band

    src = Image.open(still).convert("RGB")
    scale = w / src.width
    fitted = src.resize((w, int(src.height * scale)), Image.LANCZOS)
    # Pan to keep the rocket and the face: the moon sits high in the still.
    top = max(0, int((fitted.height - art_h) * 0.42))
    im = Image.new("RGB", (w, h), (0x0A, 0x0A, 0x0C))
    im.paste(fitted.crop((0, top, w, top + art_h)), (0, 0))

    d = ImageDraw.Draw(im)
    x, box = 30, w - 60
    name = fit_width("ARCHIVE WATCH", FONTS / "Fraunces-Display-Black.ttf", box, 40)
    sub = ImageFont.truetype(str(FONTS / "Inter-Medium.ttf"), 17)
    # The marquee rule, at the proportions it has everywhere else.
    d.rectangle([x, art_h + 16, x + 96, art_h + 23], fill=ORANGE)
    d.text((x, art_h + 34), "ARCHIVE WATCH", font=name, fill=(0xF2, 0xF2, 0xF2))
    d.text((x, h - 27), "Public domain cinema, free to watch",
           font=sub, fill=(0xA6, 0xA6, 0xAE))
    return im


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--still", default=str(STILL))
    ap.add_argument("--out", default=str(REPO / "roku" / "images" / "store_poster_fhd.png"))
    ap.add_argument("--also", action="append", default=[],
                    metavar="WxH:PATH", help="an extra size, e.g. 290x218:hd.png")
    a = ap.parse_args()

    im = compose(Path(a.still))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    im.save(a.out, "PNG", optimize=True)
    print(f"[poster] {a.out}  {im.size[0]}x{im.size[1]}  "
          f"{Path(a.out).stat().st_size/1024:.0f} KB")
    for spec in a.also:
        wh, path = spec.split(":", 1)
        w, h = (int(v) for v in wh.lower().split("x"))
        compose(Path(a.still), w, h).save(path, "PNG", optimize=True)
        print(f"[poster] {path}  {w}x{h}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
