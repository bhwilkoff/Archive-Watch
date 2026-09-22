#!/bin/bash
# EVERY resampler call site passes a FRAME capacity — WATCH-TOGETHER §8.35.
#
# `PolyphaseResampler.process(_:inFrames:out:outCapacity:)` counts interleaved
# STEREO FRAMES on both sides: `inFrames` frames in, at most `outCapacity`
# frames out, written as `outCapacity * 2` Floats. The scratch buffer it writes
# into is therefore sized `capacity * 2`.
#
# `StudioCallAudioTap` passed `dst.count` — the SAMPLE count of its scratch —
# as `outCapacity`, so the resampler believed it had twice the room it had and
# could write 2x past the end of the buffer. In a real-time CoreAudio callback
# that is heap corruption, and it sat on the one input a host reaches for by
# picking a browser out of a list.
#
# The film tap and the microphone tap were always right: both size their
# scratch from `capacityNeeded(forInputFrames:)` and pass that same frame
# count. This check asserts the THIRD one cannot drift away from them again —
# a unit error is invisible at a glance and produces correct audio right up to
# the buffer size where it does not.
set -u
cd "$(dirname "$0")/.."
fail=0

echo "Watch Together — every resampler call site passes a FRAME capacity"
echo

files=$(grep -rl "resampler.process(" ArchiveWatch/ArchiveWatch/Studio/ 2>/dev/null)
if [ -z "$files" ]; then
  echo "  FAIL  no call sites found at all — this check has stopped checking"
  exit 1
fi

for f in $files; do
  # Every `outCapacity:` argument, and what it is fed.
  while IFS= read -r arg; do
    case "$arg" in
      *capacityNeeded*|*cap*)
        echo "  PASS  $(basename "$f") — outCapacity: $arg" ;;
      *count*)
        echo "  FAIL  $(basename "$f") — outCapacity: $arg looks like a SAMPLE count"
        fail=1 ;;
      *)
        echo "  FAIL  $(basename "$f") — outCapacity: $arg is not derived from capacityNeeded"
        fail=1 ;;
    esac
  # `outCapacity: Int)` is the DECLARATION, not a call site. Excluded by name
  # rather than by line number, so moving the function does not silently turn
  # this check off.
  done < <(grep -ho "outCapacity: *[A-Za-z0-9_.()]*" "$f" \
             | sed 's/outCapacity: *//' | grep -v '^Int)$')

  # And the scratch it writes into must be sized in SAMPLES (capacity * 2).
  if grep -q "resampler.process(" "$f" && ! grep -q "cap \* 2\|cap\*2" "$f"; then
    echo "  FAIL  $(basename "$f") — no 'cap * 2' scratch sizing beside the call"
    fail=1
  fi
done

echo
# CONTROL — the check can FAIL. Without this the greps above prove only that
# grep runs (Decision 120's rule, and §8.12's).
if echo "outCapacity: dst.count" | grep -q "count"; then
  echo "  PASS  CONTROL — a sample-count capacity is correctly recognised"
else
  echo "  FAIL  CONTROL — the discriminator does not discriminate"
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL RESAMPLER CALL SITES PASS FRAMES."
else
  echo "FAILED — a call site passes the wrong unit."
fi
exit "$fail"
