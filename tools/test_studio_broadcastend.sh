#!/bin/bash
# §8.49 — every platform ends its YouTube broadcast BEFORE its publisher stops.
#
# THE FAULT THIS PINS. YouTube accepts `liveBroadcasts.transition
# broadcastStatus=complete` only from `live`. `StudioSession.end()` called it
# AFTER `engine.stop()` had closed the RTMP publisher, and every End answered
# 403 `invalidTransition`, leaving an unlisted broadcast in the host's "Live
# now". And iOS and tvOS, which run their own engines (Decision 133), armed
# the broadcast id on the shared session and never called it at all.
#
# A SOURCE check, because proving it on the product path creates a real
# broadcast on the owner's channel. Each end path must call
# `completeArmedBroadcast()` on a line BEFORE its engine's `stop()`.
#
#   bash tools/test_studio_broadcastend.sh
#   AW_SOURCE_ROOT=<dir> bash tools/test_studio_broadcastend.sh   # negative control
set -u
cd "$(dirname "$0")/.."
ROOT=${AW_SOURCE_ROOT:-ArchiveWatch/ArchiveWatch}
fail=0
code() { grep -vE '^[[:space:]]*(//|/\*|\*)'; }

# file | awk range start | awk range end | stop call
check() {
  local f="$ROOT/$1" start="$2" end="$3" stop="$4" label="$5"
  [ -f "$f" ] || { echo "  FAIL $label: $f is missing"; fail=1; return; }
  local body; body=$(awk "$start,$end" "$f" | code)
  local c s
  c=$(printf '%s\n' "$body" | grep -n "completeArmedBroadcast()" | head -1 | cut -d: -f1)
  s=$(printf '%s\n' "$body" | grep -nF "$stop" | head -1 | cut -d: -f1)
  if [ -z "$c" ]; then
    echo "  FAIL $label never ends the YouTube broadcast"; fail=1
  elif [ -z "$s" ]; then
    echo "  FAIL $label: could not find '$stop' — the instrument is stale"; fail=1
  elif [ "$c" -lt "$s" ]; then
    echo "  ok   $label completes the broadcast before the publisher stops"
  else
    echo "  FAIL $label completes the broadcast AFTER the publisher stops"; fail=1
  fi
}

check Studio/StudioSession.swift '/public func end\(\) async \{/' '/^    }/' \
      "await engine.stop()" "macOS (StudioSession.end)"
check iOS/StudioPlayerContainer_iOS.swift '/private func end\(\) async \{/' '/^    }/' \
      "await engine?.stop()" "iOS (StudioPlayerContainer_iOS.end)"
check Views/DetailView.swift '/if let why = h.endedReason/' '/continuity.lowerAudioSession\(\)/' \
      "await engine.stop()" "tvOS (DetailView studio loop)"
exit $fail
