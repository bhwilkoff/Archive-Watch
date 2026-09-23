#!/bin/bash
# §8.57 — a live show's film cannot change under it (launch audit A11).
#
# Every place that advances to another title must refuse while a show is live:
# tvOS advanceNow() (Play Next, and a lineup's skip-on-failure), tvOS's
# end-of-film autoplay observer, the tvOS menu (Play Next removed while live),
# and the macOS projection window's autoplayNext(). The engine is attached to
# one player once, and the next title never passed the rights gate.
#
#   bash tools/test_studio_film_locked.sh
#   AW_SOURCE_ROOT=<dir> bash tools/test_studio_film_locked.sh   # negative control
set -u
cd "$(dirname "$0")/.."
ROOT=${AW_SOURCE_ROOT:-ArchiveWatch/ArchiveWatch}
TV="$ROOT/Views/DetailView.swift"; MAC="$ROOT/macOS/PlayerWindow_macOS.swift"
fail=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
check "tvOS advanceNow refuses while live" \
  "awk '/private func advanceNow\(\)/{on=1} on&&/guard studioFilm == nil/{f=1} on&&/^    }$/{exit} END{exit !f}' '$TV'"
check "tvOS end-of-film autoplay refuses while live" \
  "grep -A4 'forName: .AVPlayerItemDidPlayToEndTime' '$TV' | grep -A4 'Task { @MainActor in' | grep -q 'guard studioFilm == nil'"
check "tvOS menu drops Play Next while live" \
  "grep -A2 'var items: \[UIMenuElement\] = studioFilm == nil' '$TV' | grep -q '\[muteToggle, watchTogether\]'"
check "macOS projection autoplay refuses while live" \
  "awk '/private func autoplayNext\(\)/{on=1} on&&/StudioSession.shared.isLive/{f=1} on&&/^    }$/{exit} END{exit !f}' '$MAC'"
[ $fail = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
