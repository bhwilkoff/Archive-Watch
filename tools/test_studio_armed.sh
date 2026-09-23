#!/bin/bash
# §8.46 — everything a host set up BEFORE the engine existed survives (D133).
#
# THE SHAPE THIS CATCHES. Going live ENDS the rehearsal and builds a second
# engine. Anything attached to the first one then reaches nothing, silently:
# the control still reads correctly, the capture still runs, and the value is
# simply absent from the broadcast. On 2026-09-22 that was the call's picture
# — a host who framed their guests during the preview would have pressed Go
# Live and dropped them without a word. `armedChat`, two lines above it in the
# same function, had already had the identical fix.
#
# So the rule is mechanical rather than remembered: every `armedX` on
# StudioSession is re-applied where the engine is built, or it is named here
# WITH THE REASON it is not.
#
#   bash tools/test_studio_armed.sh
set -u
cd "$(dirname "$0")/.."
SESS=ArchiveWatch/ArchiveWatch/Studio/StudioSession.swift
[ -f "$SESS" ] || { echo "FAIL: $SESS is missing"; exit 1; }
fail=0

# Values that deliberately do NOT belong in the attach. Each needs a reason,
# because an exemption list without reasons is where a real defect goes to
# hide.
#   armedBroadcast   — read by completeArmedBroadcast() to end the YouTube
#                      broadcast, and by the session's own audience poller
#                      (§D27); the ENGINE has no use for it.
#   armedBroadcastID — a computed read of armedBroadcast's YouTube id, not a
#                      value anyone arms.
#   armedFilmID      — consumed by the attach itself as its guard, and
#                      cleared there; re-applying it would re-arm a show.
EXEMPT="armedBroadcast armedBroadcastID armedFilmID"

armed=$(grep -oE "var armed[A-Za-z]+" "$SESS" | awk '{print $2}' | sort -u)
applied=$(awk '/public func attachIfArmed\(player/,/^    }$/' "$SESS")

missing=""
for a in $armed; do
  case " $EXEMPT " in *" $a "*) continue ;; esac
  echo "$applied" | grep -q "$a" || missing="$missing $a"
done

if [ -n "$missing" ]; then
  echo "FAIL: these are armed and never re-applied when the engine is built:"
  for m in $missing; do echo "    $m"; done
  echo
  echo "  A host who set one of these during a rehearsal would lose it the"
  echo "  moment they pressed Go Live, with no error and the control still"
  echo "  reading correctly. Apply it in attachIfArmed, or add it to EXEMPT"
  echo "  in this file with the reason it does not belong there."
  fail=1
else
  echo "  ok   every armed value is re-applied when the engine is built"
fi

# THE CALL'S PICTURE specifically, because it is not an `armedX` — the source
# is a live object, so the naming rule above cannot see it.
if echo "$applied" | grep -q "attachGuests"; then
  echo "  ok   the call's picture is re-attached too"
else
  echo "  FAIL going live would drop the guests a host set up in the preview"
  fail=1
fi

# NEGATIVE CONTROL. Both checks are greps over an awk range, and a range that
# matched nothing would pass the first (no armed values found) and fail the
# second for the wrong reason. Prove both sides were really read.
n=$(echo "$armed" | grep -c .)
if [ "$n" -ge 5 ] && [ -n "$applied" ]; then
  echo "  ok   control — $n armed values found, and the attach was read"
else
  echo "  FAIL control — found $n armed value(s); this test is searching nothing"
  fail=1
fi

# AND THE VALUES THAT ARE NOT NAMED "armed". The mix, the card and the
# lower-third lines were kept nowhere and forwarded to `engine?` — so going
# live (a second engine) broadcast a microphone the host had muted in the
# preview, and a Studio opened on Intermission broadcast no card (measured on
# the wire, 2026-09-23). The attach must hand all three to the new engine.
for want in 'e.setAudio(filmGain: mix.filmGain' 'overlay.card = card' 'lowerThirdLines.title'; do
  if echo "$applied" | grep -qF "$want"; then
    echo "  ok   the attach re-applies $want"
  else
    echo "  FAIL the attach does not re-apply $want — a new engine forgets it"
    fail=1
  fi
done

[ $fail -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $fail
