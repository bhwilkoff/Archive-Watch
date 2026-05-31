#!/bin/bash
# Render the tvOS brand-asset PNGs from the master SVG using only the
# tools present on a stock macOS (qlmanage to rasterize the SVG, sips to
# pad to the landscape/ultra-wide canvases). No rsvg/ImageMagick needed.
#
# tvOS icons are landscape (App Icon 400x240, App Store 1280x768, Top
# Shelf 1920x720, Wide 2320x720). The master is a square emblem on a
# marquee-orange field, so we render it square then pad each target to
# size with the same orange — the emblem's own field blends in, giving a
# "film strip centered on the marquee" look.
set -euo pipefail

ORANGE="FF5C35"     # sips --padColor wants RRGGBB, no '#'
SVG="assets/app-icon/icon-1024.svg"
BASE="ArchiveWatch/ArchiveWatch/Assets.xcassets/App Icon & Top Shelf Image.brandassets"

# 1) Rasterize the SVG to a big square PNG via Quick Look.
rm -f /tmp/aw_emblem*.png
qlmanage -t -s 1440 -o /tmp "$SVG" >/dev/null 2>&1
# qlmanage names the output "<basename>.png"
mv "/tmp/$(basename "$SVG").png" /tmp/aw_emblem.png

# compose W H OUT — scale emblem to height H, pad to WxH with orange.
compose() {
  local w="$1" h="$2" out="$3"
  sips -z "$h" "$h" /tmp/aw_emblem.png --out /tmp/aw_sq.png >/dev/null
  sips -p "$h" "$w" --padColor "$ORANGE" /tmp/aw_sq.png --out "$out" >/dev/null
}

ICON="$BASE/App Icon.imagestack/Back.imagestacklayer/Content.imageset"
STORE="$BASE/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset"
TS="$BASE/Top Shelf Image.imageset"
TSW="$BASE/Top Shelf Image Wide.imageset"

compose 400  240  "$ICON/icon.png"
compose 800  480  "$ICON/icon@2x.png"
compose 1280 768  "$STORE/icon.png"
compose 1920 720  "$TS/topshelf.png"
compose 3840 1440 "$TS/topshelf@2x.png"
compose 2320 720  "$TSW/topshelf-wide.png"
compose 4640 1440 "$TSW/topshelf-wide@2x.png"

echo "Rendered PNGs:"
find "$BASE" -name '*.png' | sort
