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
  echo "BLIND: $OUT is ${sz}B (<${MIN}B) — screen asleep or app not foreground" >&2
  exit 1
fi
if [ -x /tmp/awocr ]; then
  n=$(/tmp/awocr "$OUT" 2>/dev/null | tr -cd '"' | wc -c)
  [ "$n" -lt 8 ] && { echo "BLIND: $OUT has no readable text" >&2; exit 1; }
fi
exit 0
