#!/bin/bash
# §8.47 — the guest tile is framed like the camera, and the two are separate.
#
# §D24 reverses §D23's "a guest tile is not framable", which was argued on the
# grounds that a call window is already a grid somebody else's app arranged.
# The owner's correction is the better reading: a call window needs cropping
# MORE than a webcam, because Zoom and Meet wrap the grid in chrome a host
# does not want to broadcast.
#
# A SOURCE CHECK, because the failure this guards is structural: the gesture
# code writing one tile's framing while the compositor reads the other's, or a
# second copy of the gesture code drifting from the first. Neither is visible
# in a single run, and both are exactly what this project keeps finding.
#
#   bash tools/test_studio_guestframing.sh
set -u
cd "$(dirname "$0")/.."
fail=0
ENG=ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift
WIN=ArchiveWatch/ArchiveWatch/macOS/StudioWindow_macOS.swift
HAN=ArchiveWatch/ArchiveWatch/macOS/StudioTileHandles_macOS.swift
SESS=ArchiveWatch/ArchiveWatch/Studio/StudioSession.swift
for f in "$ENG" "$WIN" "$HAN" "$SESS"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; exit 1; }
done
code() { grep -vE '^[[:space:]]*(//|/\*|\*)'; }

# 1. THE COMPOSITOR APPLIES IT. Both halves: the box is displaced (apply) and
#    the source is cropped into it (crop). The camera needs both; so does this.
guests=$(awk '/func drawGuests/,/^        }/' "$ENG" | code)
if echo "$guests" | grep -q "guestFraming.apply" && echo "$guests" | grep -q "guestFraming.crop"; then
  echo "  ok   the compositor both places and crops the guest tile"
else
  echo "  FAIL drawGuests does not apply guestFraming (move AND crop)"
  fail=1
fi

# 2. IT IS A SEPARATE VALUE. One framing driving both tiles would move the
#    host's face every time a host cropped their guests.
if grep -q "var guestFraming = StudioCameraFraming()" "$ENG"; then
  echo "  ok   the guest tile has its own framing on the renderer"
else
  echo "  FAIL no separate guestFraming on the renderer"; fail=1
fi

# 3. THE GESTURES NAME NO TILE. Every drag, resize, crop, zoom and pan goes
#    through one accessor; otherwise the sixth gesture is the one somebody
#    forgets to branch (Decision 133).
stray=$(grep -n "controls\.framing\b" "$HAN" | code)
if [ -n "$stray" ]; then
  echo "  FAIL the handles write a specific tile's framing:"; echo "$stray"; fail=1
else
  echo "  ok   the handles drive activeFraming and name no tile"
fi

# 4. THE HANDLES SIT ON THE COMPOSITED RECT, never a re-derivation.
if grep -q "studio.health.guestTile" "$WIN" && grep -q "health.guestTile = renderer.lastGuestRect" "$ENG"; then
  echo "  ok   the guest handles use the rect the compositor used"
else
  echo "  FAIL the guest tile's rect is not published from the compositor"; fail=1
fi

# 5. IT SURVIVES GOING LIVE, like every other armed value (§8.46).
if awk '/public func attachIfArmed\(player/,/^    }$/' "$SESS" | code | grep -q "armedGuestFraming"; then
  echo "  ok   the guests' framing is re-applied when the engine is built"
else
  echo "  FAIL going live would drop a guest crop set during the preview"; fail=1
fi

# 6. NEGATIVE CONTROL. Checks 3 and 5 are greps for absence over awk ranges,
#    and a range that matches nothing passes for the wrong reason.
if [ -n "$(awk '/func drawGuests/,/^        }/' "$ENG")" ] \
   && grep -q "activeFraming" "$HAN"; then
  echo "  ok   control — both files were really read"
else
  echo "  FAIL control — a search range matched nothing; checks above prove nothing"
  fail=1
fi

[ $fail -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $fail
