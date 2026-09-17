#!/bin/bash
# A device screenshot that CANNOT hand back stale evidence.
#
# Written after reading a PNG from an earlier attempt and reasoning about it as
# though it were current (2026-09-17). The capture had failed, the grep for its
# success line found nothing, and the old file was still on disk — so the only
# tell was the clock rendered inside the image. A verification instrument that
# can silently return old evidence is worse than none: it produces confident
# wrong conclusions.
#
# So: delete the target, capture, and REFUSE unless a new file exists.
#
#   tools/atv_shot.sh <device-udid> <destination.png>
set -u
DEV="${1:?device udid}"
OUT="${2:?destination png}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

rm -f "$OUT"
mkdir -p "$(dirname "$OUT")"
ERR=$(xcrun devicectl device capture screenshot --device "$DEV" --destination "$OUT" 2>&1)
rc=$?

if [ ! -s "$OUT" ]; then
  echo "SHOT FAILED (rc=$rc) — no file written to $OUT"
  # The reason matters: a dead screenshot service and a dead connection need
  # opposite responses (switch device vs. re-pair).
  echo "$ERR" | grep -iE "error|invalidated|canceled" | head -3
  exit 1
fi

# Freshness, belt and braces: a file that exists but predates this call is the
# exact failure this script was written for.
AGE=$(( $(date +%s) - $(stat -f %m "$OUT") ))
if [ "$AGE" -gt 60 ]; then
  echo "SHOT STALE — $OUT is ${AGE}s old; the capture did not overwrite it"
  exit 1
fi
echo "SHOT OK $OUT ($(( $(stat -f %z "$OUT") / 1024 )) KB, ${AGE}s old)"
