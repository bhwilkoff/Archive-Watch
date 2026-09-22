#!/bin/bash
# §8.45 — a surface never pulls the film out from under a live show (§D12a).
#
# THE FAULT THIS PINS. `PlayerWindow_macOS.teardown()` calls
# `replaceCurrentItem(with: nil)` on the player it owns, and the engine may be
# holding that same object. The compositor is then reading a player with no
# item: the programme goes black while the FILM pane, the camera, the meters
# and the health line all stay correct. It reproduced twice in eight runs on
# 2026-09-22 and had no signature, because whether SwiftUI rebuilds that view
# during a show is a matter of timing — which is exactly the kind of defect a
# source invariant catches and a run does not.
#
# It is a SOURCE check on purpose. Reproducing it needs a view rebuild at a
# particular moment in a live show; asserting the shape needs neither.
#
#   bash tools/test_studio_playerlifetime.sh
set -u
cd "$(dirname "$0")/.."
fail=0
SURF=ArchiveWatch/ArchiveWatch/macOS/PlayerWindow_macOS.swift
SESS=ArchiveWatch/ArchiveWatch/Studio/StudioSession.swift
for f in "$SURF" "$SESS"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; exit 1; }
done

# 1. THE ASK COMES FIRST. Every destructive call in teardown must be guarded.
guarded=$(grep -n "engineIsUsing" "$SURF" | head -1)
if [ -z "$guarded" ]; then
  echo "FAIL: $SURF tears a player down without asking whether a show is using it"
  fail=1
else
  echo "  ok   the surface asks before destroying its player"
fi

# 2. NOTHING DESTRUCTIVE OUTSIDE THAT GUARD. A second unguarded
#    replaceCurrentItem would restore the fault while check 1 still passed.
# CODE ONLY. The first version of this counted a `replaceCurrentItem`
# written inside a COMMENT and reported two calls where there is one — an
# instrument reading its own documentation as evidence.
code() { grep -vE '^[[:space:]]*(//|/\*|\*)'; }
unguarded=$(awk '/private func teardown\(\)/,/^    }/' "$SURF" \
            | code | grep -c "replaceCurrentItem" | tr -d ' ')
inguard=$(awk '/if !StudioSession.shared.engineIsUsing/,/^        }/' "$SURF" \
          | code | grep -c "replaceCurrentItem" | tr -d ' ')
if [ "$unguarded" = "$inguard" ] && [ "$inguard" -ge 1 ]; then
  echo "  ok   every replaceCurrentItem in teardown is inside the guard ($inguard)"
else
  echo "  FAIL teardown has $unguarded replaceCurrentItem call(s), $inguard inside the guard"
  fail=1
fi

# 3. THE SHOW RELEASES WHAT THE SURFACE DECLINED TO. Without this the owner's
#    original complaint returns: a film that plays on with nothing to stop it.
# The whole function, not a fixed number of lines: the release sits 22
# lines down and -A14 missed it, which read as the product being wrong.
if awk '/public func end\(\) async/,/^    }/' "$SESS" | code \
     | grep -q "localPlayer?.replaceCurrentItem"; then
  echo "  ok   ending the show releases the player the surface left alone"
else
  echo "  FAIL StudioSession.end() never releases localPlayer — a film would play on"
  fail=1
fi

# 4. AND ONLY WHEN THE SURFACE IS GONE. A show that ends while the film is
#    still on screen must leave it playing.
if awk '/public func end\(\) async/,/^    }/' "$SESS" | code \
     | grep -B4 "localPlayer?.replaceCurrentItem" | grep -q "surfacePlayer !== localPlayer"; then
  echo "  ok   a show ending under a visible player leaves it alone"
else
  echo "  FAIL end() would stop a film that is still on screen"
  fail=1
fi

# 5. NEGATIVE CONTROL. Checks 2 and 4 are greps over ranges, and a range that
#    matches nothing passes for the wrong reason. Prove teardown is found.
if awk '/private func teardown\(\)/,/^    }/' "$SURF" | grep -q "forgetSurfacePlayer"; then
  echo "  ok   control — teardown is being read by this test"
else
  echo "  FAIL control — teardown not found; checks 2 and 4 proved nothing"
  fail=1
fi

[ $fail -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $fail
