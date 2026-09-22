#!/bin/bash
# §8.44 — the screen source's privacy rules, checked mechanically (§D23).
#
# WHY A SOURCE CHECK. Asking macOS what can be captured returns the host's
# whole working day, and on 2026-09-22 our own probe printed a Slack DM naming
# a colleague into a log. The capture itself is measured on the product path
# (start=true, 82 frames in 4 s); what a test can hold is the part that went
# wrong, which was never the capture.
#
#   bash tools/test_studio_screensource.sh
set -u
cd "$(dirname "$0")/.."
fail=0
SRC=ArchiveWatch/ArchiveWatch/macOS/StudioScreenSource_macOS.swift
ROOT=ArchiveWatch/ArchiveWatch/macOS/RootView_macOS.swift
[ -f "$SRC" ] || { echo "FAIL: $SRC is missing"; exit 1; }

# 1. NEVER OURSELVES. A Studio that captures the Studio composites its own
#    preview into the program, and the preview draws the program.
if grep -q "bundleIdentifier != mine" "$SRC"; then
  echo "  ok   the window list excludes our own application"
else
  echo "  FAIL $SRC does not exclude our own windows"; fail=1
fi

# 2. NO AUDIO. capturesAudio is app-level even behind a window filter, so it
#    would deliver the call twice — once here, once from the process tap.
if grep -q "capturesAudio = false" "$SRC"; then
  echo "  ok   ScreenCaptureKit captures no audio; the process tap owns sound"
else
  echo "  FAIL $SRC does not explicitly disable SCK audio capture"; fail=1
fi

# 3. NO TITLES IN DIAGNOSTICS. The rule our own harness broke first.
titles=$(grep -n "awdiag" "$ROOT" | grep "AWSCREEN" | grep -E "\.label|\.title")
if [ -n "$titles" ]; then
  echo "  FAIL a window TITLE is written to diagnostics:"
  echo "$titles"
  fail=1
else
  echo "  ok   no window title reaches a log"
fi

# 4. NO GUESSING. A substring match took the owner's real browser instead of
#    the isolated test instance beside it.
if grep -n "AWSCREEN" -A6 "$ROOT" | grep -q "localizedCaseInsensitiveContains"; then
  echo "  FAIL the screen door still picks a window by substring"; fail=1
else
  echo "  ok   a window is matched exactly, never by substring"
fi

# 5. A STOPPED CAPTURE STOPS DRAWING. Without this the sink keeps handing out
#    the last picture and the broadcast shows a frozen still of people who
#    have left — which looks live. A comment claimed this already happened
#    before it did.
stopclear=$(awk '/func stream\(_ stream: SCStream, didStopWithError/,/^    }/' "$SRC" \
            | grep -c "sink.clear()")
if [ "$stopclear" -ge 1 ]; then
  echo "  ok   a capture that stops drops its last frame"
else
  echo "  FAIL didStopWithError leaves the last frame in the sink — the tile"
  echo "       would freeze on air instead of disappearing"
  fail=1
fi
if awk '/public func stop\(\)/,/^    }/' "$SRC" | grep -q "sink.clear()"; then
  echo "  ok   stopping on purpose drops it too"
else
  echo "  FAIL stop() leaves the last frame in the sink"; fail=1
fi

# 6. THE NEGATIVE CONTROL. Checks 3 and 4 are greps for ABSENCE, and a grep
#    over a file that moved passes for the wrong reason. Prove the probe is
#    still there and still being read.
if grep -q "AWSCREEN" "$ROOT"; then
  echo "  ok   control — the screen probe is present in the file being searched"
else
  echo "  FAIL control — no AWSCREEN probe found; checks 3 and 4 proved nothing"
  fail=1
fi

[ $fail -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $fail
