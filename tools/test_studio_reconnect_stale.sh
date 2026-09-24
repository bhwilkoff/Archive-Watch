#!/bin/bash
# §8.62 runner: its own mediamtx on a private port, then the Swift check.
#   bash tools/test_studio_reconnect_stale.sh [publisher-source]   # alt source = control
set -u
cd "$(dirname "$0")/.."
PUBSRC=${1:-ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift}
T=$(mktemp -d)
printf 'logLevel: error\nrtsp: no\nhls: no\nwebrtc: no\nsrt: no\napi: no\nmetrics: no\npprof: no\nplayback: no\nrtmpAddress: :19362\npaths:\n  all:\n    source: publisher\n' > $T/mtx.yml
mediamtx $T/mtx.yml > $T/mtx.log 2>&1 &
MTX=$!
sleep 1
S=ArchiveWatch/ArchiveWatch/Studio
xcrun swiftc -parse-as-library -O "$PUBSRC" $S/StudioEngine.swift $S/StudioRecorder.swift $S/StudioChatFilter.swift \
  $S/StudioOutputSettings.swift $S/StudioAudio.swift $S/StudioOverlayRenderer.swift $S/StudioChatTwitch.swift \
  $S/StudioChatYouTube.swift tools/harness_awdiag.swift tools/test_studio_reconnect_stale.swift -o $T/t 2> $T/build.log \
  || { echo "BUILD FAILED"; tail -5 $T/build.log; kill $MTX; exit 1; }
$T/t rtmp://127.0.0.1:19362/live/stale > $T/out.log 2>&1; rc=$?
kill $MTX 2>/dev/null
grep -vE "AWPUB (connecting|publishing)" $T/out.log
# THE STALE NEWS ITSELF is the defect, fatal or not: on a LAN the new
# handshake usually finishes first, over the internet it often does not.
stale=$(grep -c "socket closed" $T/out.log)
echo "  stale 'socket closed' reports during reconnects: $stale"
[ $rc -eq 0 ] && [ "$stale" -eq 0 ] && { echo "PASS (no stale news)"; exit 0; }
echo "FAIL"; exit 1
