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
PID=$(xcrun devicectl device info processes --device "$DEV" 2>/dev/null \
      | grep -F "$BUNDLE" | awk '{print $1}' | head -1)
if [ -n "${PID:-}" ]; then
  xcrun devicectl device process terminate --device "$DEV" --pid "$PID" >/dev/null 2>&1 \
    && echo "terminated $BUNDLE (pid $PID) on $DEV" \
    || echo "could not terminate pid $PID on $DEV"
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
