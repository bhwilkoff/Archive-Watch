#!/bin/bash
# §8.54 — Go Live ends the preview BEFORE it arms the new broadcast.
#
# THE FAULT (audit, 2026-09-23): the macOS Studio's goLive() armed the new
# broadcast and its chat, then ended the rehearsal. end() completes the armed
# broadcast, and a YouTube broadcast still in `ready` is deleted as an orphan —
# so Preview then Go Live, the path the UI recommends, deleted the broadcast it
# had just created and dropped the Twitch channel with it. Every real-platform
# proof went through a door that never previewed first.
#
#   bash tools/test_studio_golive_order.sh
#   AW_SOURCE_FILE=<file> bash tools/test_studio_golive_order.sh   # negative control
set -u
cd "$(dirname "$0")/.."
F=${AW_SOURCE_FILE:-ArchiveWatch/ArchiveWatch/macOS/StudioWindow_macOS.swift}
body=$(awk '/private func goLive\(\)/{on=1} on{print NR": "$0} on && /^    }$/{exit}' "$F")
[ -n "$body" ] || { echo "FAIL: goLive() not found in $F"; exit 1; }
# Code lines only — a comment that mentions end() must not count.
code=$(printf '%s\n' "$body" | grep -vE '^[0-9]+: *//')
endAt=$(printf '%s\n' "$code" | grep -m1 'await studio.end()' | cut -d: -f1)
armAt=$(printf '%s\n' "$code" | grep -m1 -E 'studio\.arm(Broadcast|YouTubeChat)\(' | cut -d: -f1)
if [ -z "$endAt" ] || [ -z "$armAt" ]; then
  echo "FAIL: goLive() no longer both ends a rehearsal and arms a broadcast (end=$endAt arm=$armAt)"; exit 1
fi
if [ "$endAt" -gt "$armAt" ]; then
  echo "FAIL: goLive() arms the broadcast (line $armAt) before ending the preview (line $endAt) — end() will delete it"
  exit 1
fi
echo "PASS: goLive() ends the preview (line $endAt) before arming the broadcast (line $armAt)"
