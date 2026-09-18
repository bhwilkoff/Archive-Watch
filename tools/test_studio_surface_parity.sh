#!/bin/bash
# Every go-live surface consults the SAME gates — checked mechanically.
#
# This exists because one defect class has now recurred four times in this
# feature, and every time it was found by eye, late:
#
#   §9.ooo   the `configurationProblem == nil` proxy, on tvOS
#   §9.ttt   the SAME proxy, still in macOS and iOS, found one surface a tick
#   §9.eeee  the go-live confirmation wired into Android's phone Detail while
#            the TELEVISION's Detail kept arming straight through
#   §9.ffff  the readiness gate added to tvOS only, leaving iOS and macOS able
#            to press Go Live into a channel the platform refuses
#
# Reading the diff does not catch it: each fix is correct where it is applied.
# What catches it is asking every surface the same question at once, which is
# what this does. It is a SOURCE check, not a UI test — it cannot prove a
# screen behaves, only that no surface is missing the gate its siblings have.
#
#   bash tools/test_studio_surface_parity.sh
set -u
cd "$(dirname "$0")/.."
fail=0

# The Apple go-live surfaces. Each collects a request and has a commit control.
APPLE_SURFACES=(
  "ArchiveWatch/ArchiveWatch/Views/GoLiveTV.swift"
  "ArchiveWatch/ArchiveWatch/iOS/GoLiveSheet_iOS.swift"
  "ArchiveWatch/ArchiveWatch/macOS/GoLiveSheet_macOS.swift"
)

check() { # name, file, pattern
  if grep -q "$3" "$2"; then
    echo "  PASS  $1 — $(basename "$2")"
  else
    echo "  FAIL  $1 — $(basename "$2") does not mention /$3/"
    fail=1
  fi
}

echo "Watch Together — every go-live surface asks the same questions"
echo
echo "the platform READINESS gate (§9.zzz): a signed-in host whose channel"
echo "cannot broadcast must not reach a pressable Go Live"
for f in "${APPLE_SURFACES[@]}"; do
  check "consults readiness" "$f" "StudioPlatformAuth.readiness(for:"
  check "gates its commit on it" "$f" "blockedReason"
done

echo
echo "the SIGN-IN state (§9.ttt): a commit gated on configuration rather than"
echo "on a token switches itself on the day a client id is registered"
for f in "${APPLE_SURFACES[@]}"; do
  check "gates on signedIn, not configuration" "$f" "signedIn"
done

echo
echo "CONTROL — the check can FAIL. A pattern no surface carries must be"
echo "reported missing, or the greps above prove only that grep runs."
if grep -q "aw_this_string_is_in_no_surface" "${APPLE_SURFACES[0]}"; then
  echo "  FAIL  CONTROL matched a string that cannot exist"
  fail=1
else
  echo "  PASS  CONTROL — an absent pattern is correctly reported absent"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL SURFACES CARRY THE SAME GATES."
  exit 0
fi
echo "FAILED — a surface is missing a gate its siblings have."
exit 1
