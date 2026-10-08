#!/usr/bin/env python3
"""
make_store_header.py — render the App Store product page HEADER (21:9,
3840x1646) from the 1902 "Le Voyage dans la Lune" frame.

Composed the way the apps' own hero is (Decision 097): the frame keeps its own
4:3 shape, the moon is moved to the horizontal center (Apple: keep the focal
point centered — every device crops the header differently), and the rest of
the 21:9 is an ambient wash of the same frame. No text: our copy rule, and
Apple's "a single, clear idea".

Source: `assets/app-store/melies-moon-1902-frame-1440.png`, frame 6:10 of the
public-domain Wikimedia Commons transfer "Le Voyage dans la Lune (1902).webm"
(1440x1080) — the app icon's own shot at the resolution the icon lacks.

Usage:  python3 tools/make_store_header.py [--check]
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "assets/app-store/melies-moon-1902-frame-1440.png"
OUT = REPO / "assets/app-store/header-21x9-3840x1646.jpg"

W, H = 3840, 1646
FRAME_LINE = 22          # the scan's bottom frame line, cropped away
MOON_CX = 616            # moon center in the source frame, px
FEATHER = 420            # edge blend between frame and wash, px at output scale


def render() -> Image.Image:
    src = Image.open(SRC).convert("L")
    src = src.crop((0, 0, src.width, src.height - FRAME_LINE))
    scale = H / src.height
    frame = src.resize((round(src.width * scale), H), Image.LANCZOS)
    frame = frame.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=3))

    wash = src.resize((W, round(src.height * W / src.width)), Image.LANCZOS)
    top = (wash.height - H) // 2
    wash = wash.crop((0, top, W, top + H)).filter(ImageFilter.GaussianBlur(120))
    wash = ImageEnhance.Brightness(wash).enhance(0.22)

    x = round(W / 2 - MOON_CX * scale)
    mask = Image.new("L", frame.size, 255)
    d = ImageDraw.Draw(mask)
    for i in range(FEATHER):
        a = round(255 * i / FEATHER)
        d.line([(i, 0), (i, H)], fill=a)
        d.line([(frame.width - 1 - i, 0), (frame.width - 1 - i, H)], fill=a)

    canvas = wash.copy()
    canvas.paste(frame, (x, 0), mask)
    return canvas.convert("RGB")


def main() -> int:
    img = render()
    if "--check" in sys.argv:
        old = Image.open(OUT).convert("RGB")
        same = old.size == img.size and max(
            hi for _, hi in ImageChops.difference(old, img).getextrema()) < 24
        print("header matches" if same else "header differs from a fresh render")
        return 0 if same else 1
    img.save(OUT, "JPEG", quality=92, subsampling=0)
    print(OUT, img.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
