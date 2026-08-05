#!/usr/bin/env bash
# Capture Android TV store screenshots from a booted TV emulator/device.
#
# Google Play and the Amazon Appstore both want 1920x1080 landscape TV shots.
# The emulator's own framebuffer is already 1080p, so `screencap` output needs
# no scaling — verify with `file` rather than assuming, since a differently
# configured AVD will silently produce the wrong size and both stores reject on
# dimensions.
#
# Screens are reached by ROUTE, never by counting D-pad presses: a press lands
# on the nearest item, not a fixed one, which has repeatedly steered automated
# runs onto the wrong screen (same reasoning as tools/verify_tv_focus.sh).
#
# Usage:
#   ./tools/tv_screenshots.sh [outdir]
#
# Requires: a booted Android TV emulator (see the smart-tv skill for the
# low-RAM headless recipe) and the debug build installed.

set -uo pipefail

PKG="com.archivewatch.app.debug"
ACT="app.archivewatch.android.MainActivity"
ADB="${ADB:-adb}"
SERIAL="${SERIAL:-emulator-5554}"
OUT="${1:-$HOME/Desktop/ArchiveWatch-TV-Screenshots}"
SETTLE="${SETTLE:-26}"     # cold start + catalog swap; shots taken too early show a seed catalog

mkdir -p "$OUT"

shot() { # shot <name> <flag> <key> <value> [extra dpad presses]
  local name="$1" flag="$2" key="$3" value="$4" presses="${5:-0}"
  echo "==> $name"
  $ADB -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1
  sleep 2
  $ADB -s "$SERIAL" shell am start \
    -c android.intent.category.LEANBACK_LAUNCHER -a android.intent.action.MAIN \
    -n "$PKG/$ACT" "$flag" "aw_start_$key" "$value" >/dev/null 2>&1
  sleep "$SETTLE"
  # A shot with nothing focused looks broken in a store listing — the focused
  # card IS the visual subject on a TV. Nudge into content first.
  local i=0
  while [ "$i" -lt "$presses" ]; do
    $ADB -s "$SERIAL" shell input keyevent KEYCODE_DPAD_DOWN >/dev/null 2>&1
    sleep 1
    i=$((i + 1))
  done
  $ADB -s "$SERIAL" exec-out screencap -p > "$OUT/$name.png"
  local size
  size=$(python3 -c "
import struct,sys
d=open('$OUT/$name.png','rb').read(33)
print('x'.join(map(str, struct.unpack('>II', d[16:24]))) if len(d)>=24 else 'unreadable')
" 2>/dev/null)
  echo "    $OUT/$name.png  ($size)"
  if [ "$size" != "1920x1080" ]; then
    echo "    !! not 1920x1080 — Play and Amazon reject on dimensions." >&2
  fi
}

echo "Android TV store screenshots -> $OUT"
echo

# Home takes NO nudge: it already claims focus on content, and a Down press
# scrolls the hero off the top, leaving a truncated synopsis where the marquee
# should be — which reads as a broken screen in a store listing.
shot 01-home        --es tab   home        0
shot 02-browse      --es tab   browse      1
# Channels claims focus on the guide itself, so no nudge either.
shot 03-channels    --es tab   channels    0
shot 04-search      --es tab   search      0
shot 05-collections --es route collections 1
shot 06-surprise    --es route surprise    1

echo
echo "Done. $(ls -1 "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') shots in $OUT"
echo
echo "Upload notes:"
echo "  Google Play : Store listing -> Android TV -> 1-8 screenshots, 1920x1080."
echo "                Also needs the TV BANNER (320x180) — that ships in the APK"
echo "                at res/drawable*/tv_banner, but Play wants a copy uploaded."
echo "  Amazon      : same PNGs; Fire TV form factor."
