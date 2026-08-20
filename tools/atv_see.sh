#!/usr/bin/env bash
# Capture the Apple TV screen and REFUSE to return a frame the OCR cannot read.
#
# A sweep that returns "row not found" is worthless if the screenshots were
# blank. That happened on 2026-08-18: twelve steps, no hits, and every frame was
# a 108 KB black screen — the device had slept. A null result from a blind
# instrument is indistinguishable from a real absence, so the instrument has to
# say when it cannot see (the same rule the audio meter follows in D075).
#
# Usage: bash tools/atv_see.sh <out.png> [min_bytes]   -> exits 1 if blank
set -uo pipefail
OUT="${1:?usage: atv_see.sh <out.png> [min_bytes]}"
MIN="${2:-400000}"
DEV="${AW_ATV:-Ben Bedroom}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}" \
  xcrun devicectl device capture screenshot --device "$DEV" --destination "$OUT" >/dev/null 2>&1
sz=$(stat -f%z "$OUT" 2>/dev/null || echo 0)
if [ "$sz" -lt "$MIN" ]; then
  # 108824 bytes EXACTLY, repeatedly, while `devicectl ... process launch`
  # reports "Launched", means the Apple TV is awake and rendering to a display
  # that is OFF — i.e. the TELEVISION is off or on another input. The Apple TV
  # cannot fix that: pyatv turn_on only sends CEC, which the set may ignore.
  # Distinguish it from a sleeping Apple TV, where the LAUNCH itself fails with
  # CoreDeviceError 10002. Launch works + capture black = go turn the TV on.
  echo "BLIND: $OUT is ${sz}B (<${MIN}B)" >&2
  echo "  if launch SUCCEEDS but capture is black, the television is off/on another input" >&2
  exit 1
fi
if [ -x /tmp/awocr ]; then
  txt=$(/tmp/awocr "$OUT" 2>/dev/null)
  n=$(printf '%s' "$txt" | tr -cd '"' | wc -c)
  [ "$n" -lt 8 ] && { echo "BLIND: $OUT has no readable text" >&2; exit 1; }
  # A READABLE frame of the WRONG APP is worse than a blank one, because it
  # survives every check and then answers questions about a screen we are not
  # testing. That happened: the app had dropped to the tvOS home screen, so a
  # sweep drove the SYSTEM UI past prime video and fubo and reported the TV
  # shelves missing. The frame was perfectly legible and completely irrelevant.
  #
  # Set AW_EXPECT to a string the app's own UI shows (default matches the tvOS
  # sidebar/Home chrome); pass AW_EXPECT=- to skip when testing another screen.
  EXPECT="${AW_EXPECT:-Home|FEATURE FILMS|Continue Watching|Movies|TV Shows|Surprise}"
  if [ "$EXPECT" != "-" ] && ! printf '%s' "$txt" | grep -qiE "$EXPECT"; then
    if printf '%s' "$txt" | grep -qiE "prime video|pluto|fubo|Apple TV\+|Select up for full screen"; then
      echo "WRONG SCREEN: $OUT is the tvOS home screen, not Archive Watch" >&2
    else
      echo "WRONG SCREEN: $OUT does not match AW_EXPECT ($EXPECT)" >&2
    fi
    exit 2
  fi
fi
exit 0
