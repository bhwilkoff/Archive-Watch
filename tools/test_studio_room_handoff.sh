#!/bin/bash
# §8.58 — a room code is taken only by the room's own film, and a player that
# goes away leaves the room (launch audit A16).
#
# The code waited as a bare string, so backing out of the room's film left it
# pending and the NEXT, unrelated film was seeked and paused by the room; and
# iOS and tvOS never left on close, so a guest kept polling and the host's
# "N friends here" stayed inflated.
#
#   bash tools/test_studio_room_handoff.sh
#   AW_SOURCE_ROOT=<dir> bash tools/test_studio_room_handoff.sh   # negative control
set -u
cd "$(dirname "$0")/.."
R=${AW_SOURCE_ROOT:-ArchiveWatch/ArchiveWatch}
fail=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
check "iOS player takes the code only for the room's film" "grep -A1 'if let code = RoomJoin_iOS.shared.pending,' '$R/iOS/PlayerView_iOS.swift' | grep -q 'pendingFilm'"
check "tvOS player takes the code only for the room's film" "grep -A1 'if let code = RoomJoinTV.shared.pending,' '$R/Views/AVPlayerScreen.swift' | grep -q 'pendingFilm'"
check "macOS player takes the code only for the room's film" "grep -A1 'if let code = RoomJoin.shared.pending,' '$R/macOS/PlayerWindow_macOS.swift' | grep -q 'pendingFilm'"
check "each join records the room's film" "grep -q 'RoomJoin_iOS.shared.pendingFilm = item.archiveID' '$R/iOS/JoinRoomSheet_iOS.swift' && grep -q 'RoomJoinTV.shared.pendingFilm = item.archiveID' '$R/Views/JoinRoomTV.swift' && grep -q 'RoomJoin.shared.pendingFilm = item.archiveID' '$R/macOS/RootView_macOS.swift'"
check "iOS player leaves the room when it goes away" "awk '/static func dismantleUIViewController/{on=1} on&&/leaveIfFollowing/{f=1} on&&/^    }$/{on=0} END{exit !f}' '$R/iOS/PlayerView_iOS.swift'"
check "tvOS player leaves the room when it goes away" "awk '/static func dismantleUIViewController\(_ vc: AVPlayerViewController,\$/{on=1} on&&/leaveIfFollowing/{f=1} on&&/^    }$/{on=0} END{exit !f}' '$R/Views/AVPlayerScreen.swift'"
[ $fail = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
