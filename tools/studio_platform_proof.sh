#!/bin/bash
# ONE COMMAND FOR EVERY STUDIO PROOF RUN ON A REAL DEVICE — the owner's
# 2026-09-23 instruction: "You really should be able to run commands yourself
# or create structures that allow you to do fully autonomous testing."
#
# It installs the current Debug build on the TEST iPhone 12 (never the owner's
# 15 Pro), launches the Studio on the product path with the proof doors, waits
# for the show to end itself, pulls the phone's own diagnostics, terminates the
# app BY PID and confirms zero processes (a `--terminate-existing` relaunch
# over a live instance left a black screen, twice), and prints the lines that
# matter. Everything it sends is UNLISTED and ends by itself.
#
#   bash tools/studio_platform_proof.sh youtube [seconds] [film-archive-id]
#   bash tools/studio_platform_proof.sh twitch  [seconds] [film-archive-id]
#   bash tools/studio_platform_proof.sh bench   [seconds] [film-archive-id]   # local mediamtx
#   bash tools/studio_platform_proof.sh state                                 # read-only sign-in probe
set -u
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
PHONE=B4E756E2-CBFA-5F63-8CEE-21D226637AF7          # iPhone 12 — the test device
BUNDLE=app.archivewatch.tvos
MODE=${1:-}; SECS=${2:-180}
FILM=${3:-the-man-who-laughs-1928-1080p-blu-ray-x-265-ghost}
OUT=${TMPDIR:-/tmp}/aw-proof; mkdir -p "$OUT"
LOG="$OUT/diag-$MODE-$(date +%s).log"

apps() { xcrun devicectl device info processes --device $PHONE 2>/dev/null | grep -c "ArchiveWatch.app/ArchiveWatch"; }
# Up to three tries: an app still tearing down a show survived a single
# terminate + 2 s wait (2026-09-23), and the run reported it honestly.
stop_app() {
  for attempt in 1 2 3; do
    for p in $(xcrun devicectl device info processes --device $PHONE 2>/dev/null \
               | grep "ArchiveWatch.app/ArchiveWatch" | awk '{print $1}'); do
      xcrun devicectl device process terminate --device $PHONE --pid "$p" >/dev/null 2>&1
    done
    sleep 3
    [ "$(apps)" = "0" ] && return 0
  done
  echo "!! the app is still running on the phone"; return 1
}
# ONLY THIS RUN'S LINES. The phone's log survives between launches and is
# emptied only when the new instance writes its first line — so the first
# version of this script found the PREVIOUS run's "AWSTUDIOEND", decided the
# show was over, and stopped the app 15 s into a run that had not logged yet.
# Every line starts with an epoch timestamp; anything before launch is dropped.
STARTED=0
# A FAILED COPY MUST SAY SO. It used to leave the previous run's file in
# place, which the time filter then reduced to nothing — so a run whose app
# never wrote a line read as "the phone logged nothing" (2026-09-23).
PULL_FAILS=0
pull() {
  rm -f "$LOG.raw"
  if ! xcrun devicectl device copy from --device $PHONE --domain-type appDataContainer \
       --domain-identifier $BUNDLE --source Library/Caches/awdiag.log --destination "$LOG.raw" >/dev/null 2>&1; then
    PULL_FAILS=$((PULL_FAILS+1))
  fi
  awk -v t="$STARTED" '$1+0 >= t' "$LOG.raw" 2>/dev/null > "$LOG"
}
launch() {
  xcrun devicectl device process launch --device $PHONE --environment-variables "$1" $BUNDLE 2>&1 | tail -1
}

case "$MODE" in
  youtube|twitch|bench|state) ;;
  *) echo "usage: $0 youtube|twitch|bench|state [seconds] [film]"; exit 2 ;;
esac

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/ArchiveWatch-*/Build/Products/Debug-iphoneos/ArchiveWatch.app 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "!! no Debug-iphoneos build — build for the device first"; exit 1; }
stop_app || exit 1
xcrun devicectl device install app --device $PHONE "$APP" >/dev/null 2>&1 || { echo "!! install failed"; exit 1; }

if [ "$MODE" = state ]; then
  STARTED=$(date +%s)
  launch '{"AW_STUDIO_AUTH":"state","AW_DIAG_FILE":"1"}'
  sleep 20; pull; stop_app
  grep AWAUTH "$LOG"; exit 0
fi

ENV="\"AW_DIAG_FILE\":\"1\",\"AW_STUDIO_IOS_READBACK\":\"15\",\"AW_STUDIO_IOS_SHARECHAT\":\"30\",\"AW_STUDIO_IOS_END\":\"$SECS\""
if [ "$MODE" = bench ]; then
  MTXLOG="$OUT/mtx-$(date +%s).log"
  printf 'logLevel: info\nrecord: no\npaths:\n  all:\n    source: publisher\n' > "$OUT/mtx.yml"
  pkill -f "$OUT/mtx.yml" >/dev/null 2>&1; sleep 1
  mediamtx "$OUT/mtx.yml" > "$MTXLOG" 2>&1 &
  MAC=$(ipconfig getifaddr en0)
  ENV="$ENV,\"AW_STUDIO_IOS\":\"$FILM\",\"AW_STUDIO_DEST\":\"rtmp://$MAC:1935/live\",\"AW_STUDIO_KEY\":\"bench\",\"AW_STUDIO_CHAT_DEMO\":\"1\""
else
  ENV="$ENV,\"AW_START_ITEM\":\"$FILM\",\"AW_AUTOPLAY\":\"1\",\"AW_STUDIO_GOLIVE\":\"$MODE\",\"AW_STUDIO_YT_CHAT\":\"1\""
fi
echo "== $MODE proof run: $FILM, ends at $SECS s on air"
STARTED=$(date +%s)
launch "{$ENV}"

# Wait for the show to end itself (the END door), pulling the log as we go.
DEADLINE=$((SECONDS + SECS + 150))
while [ $SECONDS -lt $DEADLINE ]; do
  sleep 15; pull
  grep -q "AWSTUDIOEND\|AWDOOR ending" "$LOG" 2>/dev/null && { sleep 5; pull; break; }
done
stop_app
[ "$MODE" = bench ] && pkill -f "$OUT/mtx.yml" >/dev/null 2>&1

[ "$PULL_FAILS" -gt 0 ] && echo "!! $PULL_FAILS pull(s) of the phone's log FAILED — an empty result below is not evidence"
[ -s "$LOG" ] || echo "!! no lines from THIS run — did the app launch with its environment?"
echo "== what the phone says ($LOG)"
grep -E "AWDOOR|AWYTREAD|AWPUB|AWSTUDIOCHAT|AWCHATSHARE|AWAUDIENCE (read|probe)|AWMARKER|AWSTUDIOEND|AWMUTE|FAILED|refused" "$LOG" | cut -c1-220
grep AWSTUDIOHEALTH "$LOG" | tail -1 | cut -c1-160
echo "== phone left with $(apps) Archive Watch process(es)"
