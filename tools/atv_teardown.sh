#!/bin/bash
# LEAVE NOTHING RUNNING. Terminates Archive Watch on a device and, for an
# Apple TV, powers the box back off.
#
# Written after leaving a film playing unmuted on the owner's Apple TV for an
# hour — it routed to their HomePods across the house (2026-09-17). The tvOS
# dev door starts the engine and polls until told to stop, and nothing told it
# to stop once the screenshot was taken.
#
# The lesson is the same one `atv_shot.sh` carries: a rule you intend to follow
# is not a safeguard. A harness that touches someone's living room has to clean
# up as a STEP, not as an intention.
#
#   tools/atv_teardown.sh <device-udid> [pyatv-address pyatv-id]
set -u
DEV="${1:?device udid}"
ADDR="${2:-}"
PYID="${3:-}"
BUNDLE="app.archivewatch.tvos"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
PYATV="$HOME/.pyatv-venv/bin/atvremote"

# 1. Terminate by pid — `process terminate` takes --pid, never a bundle id
#    (a wrong flag prints usage and exits 0-ish, which reads like success).
#
#    MATCH THE PATH, NOT THE BUNDLE ID. This grepped for "$BUNDLE" and
#    `devicectl device info processes` prints EXECUTABLE PATHS:
#
#      1821  /private/var/.../ArchiveWatch.app/ArchiveWatch
#
#    "app.archivewatch.tvos" appears nowhere in that line, so the grep never
#    matched, the script took the else branch, and it printed "not running"
#    while the app was running. Found 2026-09-18 after it said that twice in
#    one session about a live process (pid 1821) that was also polling Twitch.
#    A teardown that cannot see the thing it is meant to kill is worse than no
#    teardown: it reports the all-clear. Exactly the rule this file already
#    carries one paragraph up, missed one line down.
#
#    AND THE LINE IS COLUMN-PADDED. The first repair anchored the match with
#    `$`, which matched nothing either, because devicectl pads the path column
#    with trailing spaces — so the repaired script reported the all-clear about
#    a live pid 1830 exactly as the broken one had about pid 1821. Two
#    different greps, the same false verdict, found only by asking the device
#    with a looser pattern. Hence `[[:space:]]*$`, and hence the verification
#    below uses this same function rather than a second hand-written pattern.
#
#    The PlugIns path is excluded: the Top Shelf appex is launched by the
#    SYSTEM to fetch shelf content, is not part of a test run, and killing it
#    is not ours to do.
PID=$(xcrun devicectl device info processes --device "$DEV" 2>/dev/null \
      | grep -iE "ArchiveWatch\.app/ArchiveWatch[[:space:]]*$" \
      | grep -v PlugIns | awk '{print $1}' | head -1)
if [ -n "${PID:-}" ]; then
  xcrun devicectl device process terminate --device "$DEV" --pid "$PID" >/dev/null 2>&1
  sleep 3
  # ASK THE DEVICE, never the terminate's own output (memory:
  # device_teardown_must_be_verified). A signal sent is not a process gone.
  STILL=$(xcrun devicectl device info processes --device "$DEV" 2>/dev/null \
          | grep -iE "ArchiveWatch\.app/ArchiveWatch[[:space:]]*$" \
          | grep -vc PlugIns)
  if [ "$STILL" -eq 0 ]; then
    echo "terminated $BUNDLE (pid $PID) on $DEV — verified gone"
  else
    echo "FAILED to terminate $BUNDLE (pid $PID) on $DEV — STILL RUNNING"
    exit 1
  fi
else
  echo "$BUNDLE not running on $DEV"
fi

# 2. For an Apple TV, put the box back as it was found.
if [ -n "$ADDR" ] && [ -n "$PYID" ] && [ -x "$PYATV" ]; then
  "$PYATV" --address "$ADDR" --id "$PYID" --protocol companion power_state turn_off >/dev/null 2>&1
  sleep 4
  STATE=$("$PYATV" --address "$ADDR" --id "$PYID" --protocol companion power_state 2>&1 | tail -1)
  echo "power now: $STATE"
  case "$STATE" in
    *Off) ;;
    *) echo "WARNING: $ADDR did not power off — check it by hand"; exit 1 ;;
  esac
fi
