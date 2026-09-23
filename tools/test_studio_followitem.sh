#!/bin/bash
# §8.50 — the engine follows the player's ITEM, and a stopped engine does not.
#
# THE FAULT THIS PINS (item 17's second cause, measured 2026-09-23). The video
# output and the film's audio tap both live on an AVPlayerItem, and the Mac
# player swaps items under a running show. Ten seconds into a bench run on The
# Man Who Laughs it did, and the program went black — `outputOnItem=n` — while
# the FILM pane played on. With the follow in place the same run held the film
# on the wire (centre YAVG 36-60 over 45 s, read back from the server).
#
# And the half that is easy to get wrong: going live stops the rehearsal
# engine and builds a second one on the SAME player. A stale observer that
# still followed would set the item's one `audioMix` to a dead engine's tap.
#
#   bash tools/test_studio_followitem.sh
#   AW_SOURCE_ROOT=<dir> bash tools/test_studio_followitem.sh   # negative control
set -u
cd "$(dirname "$0")/.."
E=${AW_SOURCE_ROOT:-ArchiveWatch/ArchiveWatch}/Studio/StudioEngine.swift
[ -f "$E" ] || { echo "FAIL: $E is missing"; exit 1; }
fail=0
code() { grep -vE '^[[:space:]]*(//|/\*|\*)'; }
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

attach=$(awk '/public func attachFilm\(player/,/^    }$/' "$E" | code)
echo "$attach" | grep -q 'observe(\\.currentItem' \
  && ok "attachFilm observes the player's current item" \
  || bad "attachFilm does not watch for an item swap"

follow=$(awk '/private func noteFilmItemChanged/,/^    }$/' "$E" | code)
echo "$follow" | grep -q 'AVPlayerItemVideoOutput(' && echo "$follow" | grep -q 'item.add(' \
  && ok "a swap re-adds the video output to the new item" \
  || bad "a swap leaves the video output on the old item"
echo "$follow" | grep -q 'mixer.film.attach(to: item)' \
  && ok "a swap re-attaches the film's audio" \
  || bad "a swap leaves the film's audio on the old item"
echo "$follow" | grep -q 'filmItemObserver != nil' \
  && ok "a stopped engine refuses to follow" \
  || bad "a stopped engine would still follow the film"

stop=$(awk '/public func stop\(\) async/,/^    }$/' "$E" | code)
echo "$stop" | grep -q 'filmItemObserver?.invalidate()' \
  && ok "stop() releases the item observer" \
  || bad "stop() leaves the item observer running"

# AND NO SWAP TO FOLLOW, where it can be avoided. A player feeding the program
# skips Decision 067's plain-URL path (system captions never reach the
# program); measured as a `reason=stall` swap ten seconds in without this.
ROOT=${AW_SOURCE_ROOT:-ArchiveWatch/ArchiveWatch}
P=$ROOT/macOS/PlayerWindow_macOS.swift
W=$ROOT/macOS/StudioWindow_macOS.swift
if [ -f "$P" ] && [ -f "$W" ]; then
  code < "$P" | grep -A1 "else if let url = videoURL" | grep -q "!feedsProgram" \
    && ok "a program-feeding player never takes the plain-URL path" \
    || bad "a program-feeding player can start on the plain URL and stall into a swap"
  code < "$W" | grep -q "feedsProgram: true" \
    && ok "the Studio's FILM pane says it feeds the program" \
    || bad "the Studio's FILM pane does not say it feeds the program"
  code < "$P" | grep -q "feedsProgram: studio.isLive || studio.armedFilmID" \
    && ok "the projection window feeds the program when armed, not only when live" \
    || bad "the projection window only counts as feeding the program once live"
fi
exit $fail
