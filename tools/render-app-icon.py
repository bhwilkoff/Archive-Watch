#!/usr/bin/env python3
"""Generate the tvOS App Icon + Top Shelf assets from the public-domain 1902
Méliès "A Trip to the Moon" still, framed as a 35mm film cell (sprocket strips
left/right). Flat icon: the composition fills each imagestack's Back layer; the
Front layer is transparent (the still is a single photo, so no clean parallax
cutout). Re-run to regenerate. Source: assets/app-icon/melies-moon-1902.jpg."""
from PIL import Image, ImageDraw, ImageOps, ImageEnhance, ImageFilter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BA = REPO / "ArchiveWatch/ArchiveWatch/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
SRC = REPO / "assets/app-icon/melies-moon-1902.jpg"

def graded():
    img = Image.open(SRC).convert("RGB")
    img = ImageEnhance.Contrast(img).enhance(1.12)
    img = ImageEnhance.Brightness(img).enhance(1.04)
    sep = ImageOps.colorize(ImageOps.grayscale(img), black=(20,12,4), white=(255,244,225))
    return Image.blend(img, sep, 0.35)

BASE = graded()
BG = (8, 7, 6)

def reel(draw, x0, W, H, strip):
    draw.rectangle([x0, 0, x0+strip, H], fill=(13, 12, 11))
    hw, hh = int(strip*0.52), int(strip*0.39)
    gap = int(strip*0.30)
    n = max(1, (H + gap) // (hh + gap))
    total = n*hh + (n-1)*gap
    y = (H - total)//2
    cx = x0 + strip//2
    r = max(3, int(strip*0.09))
    for _ in range(n):
        draw.rounded_rectangle([cx-hw//2, y, cx+hw//2, y+hh], radius=r, fill=(232,225,208))
        y += hh + gap

def render(W, H, mode):
    strip = max(10, int(W*0.10)) if mode == "cover" else max(10, int(W*0.055))
    panel_w = W - 2*strip
    canvas = Image.new("RGB", (W, H), BG)
    if mode == "cover":
        panel = ImageOps.fit(BASE, (panel_w, H), method=Image.LANCZOS, centering=(0.5, 0.47))
        canvas.paste(panel, (strip, 0))
    else:  # contain — moon centered, sky fills the wide canvas
        scale = (H*0.92) / BASE.height
        mw, mh = int(BASE.width*scale), int(BASE.height*scale)
        moon = BASE.resize((mw, mh), Image.LANCZOS)
        canvas.paste(moon, (strip + (panel_w - mw)//2, (H - mh)//2))
    d = ImageDraw.Draw(canvas)
    reel(d, 0, W, H, strip)
    reel(d, W-strip, W, H, strip)
    return canvas

def write(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)

def transparent(W, H, path):
    write(Image.new("RGBA", (W, H), (0,0,0,0)), path)

AI  = BA / "App Icon.imagestack"
AS  = BA / "App Icon - App Store.imagestack"
TS  = BA / "Top Shelf Image.imageset"
TSW = BA / "Top Shelf Image Wide.imageset"

# App Icon (small): Back = composition, Front = transparent
write(render(400,240,"cover"),  AI/"Back.imagestacklayer/Content.imageset/icon.png")
write(render(800,480,"cover"),  AI/"Back.imagestacklayer/Content.imageset/icon@2x.png")
transparent(400,240, AI/"Front.imagestacklayer/Content.imageset/icon.png")
transparent(800,480, AI/"Front.imagestacklayer/Content.imageset/icon@2x.png")
# App Store: 1280x768 (1x)
write(render(1280,768,"cover"), AS/"Back.imagestacklayer/Content.imageset/icon.png")
transparent(1280,768, AS/"Front.imagestacklayer/Content.imageset/icon.png")
# Top Shelf (wide, contain)
write(render(1920,720,"contain"), TS/"topshelf.png")
write(render(3840,1440,"contain"), TS/"topshelf@2x.png")
write(render(2320,720,"contain"), TSW/"topshelf-wide.png")
write(render(4640,1440,"contain"), TSW/"topshelf-wide@2x.png")
# iOS app icon: square 1024 from the SAME 1902 Méliès still (NOT the retired
# orange SVG). The app target's [sdk=iphone*] AppIcon set points here.
IOS_ICON = REPO / "ArchiveWatch/ArchiveWatch/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
write(render(1024,1024,"cover"), IOS_ICON)
print("rendered Méliès app icon + top shelf + iOS app icon assets")
