#!/usr/bin/env bash
# Android TV focus verification — drive real surfaces with a real remote and
# assert that focus actually lands on real content.
#
# WHY THIS EXISTS
# On a TV, focus IS the interaction model, and it is INVISIBLE to a screenshot.
# During this build a screenshot showed a perfectly-rendered Channels EPG that
# could not be reached by remote at all, and separately showed a "broken"
# Surprise grid that was working fine. Compiling proves nothing here either —
# `.clickable` compiles, renders, and is simply unreachable by D-pad.
#
# So: route straight to a surface (no counting D-pad presses, which lands on the
# NEAREST item and repeatedly steered checks to the wrong screen), turn on the
# focus trace, press keys, and assert on what actually took focus.
#
#   ./tools/verify_tv_focus.sh                # all surfaces
#   ./tools/verify_tv_focus.sh home browse    # a subset
#
# Requires a booted Android TV emulator/device (see the smart-tv skill for the
# low-RAM headless recipe) and the debug build installed.

set -uo pipefail

PKG="com.archivewatch.app.debug"
ACT="app.archivewatch.android.MainActivity"
ADB="${ADB:-adb}"
SERIAL="${SERIAL:-emulator-5554}"
PASS=0
FAIL=0

key()   { $ADB -s "$SERIAL" shell input keyevent "KEYCODE_DPAD_$1" >/dev/null 2>&1; sleep "${2:-1.1}"; }
trace() { $ADB -s "$SERIAL" logcat -d -s AWFOCUS 2>/dev/null | sed 's/.*AWFOCUS *: *//' | grep -v '^$'; }

launch() { # launch <extra-flag> <value>
  $ADB -s "$SERIAL" logcat -c >/dev/null 2>&1
  $ADB -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1
  sleep 2
  $ADB -s "$SERIAL" shell am start \
    -c android.intent.category.LEANBACK_LAUNCHER -a android.intent.action.MAIN \
    -n "$PKG/$ACT" "$1" aw_start_"$2" "$3" --ez aw_focus_log true >/dev/null 2>&1
  sleep "${LAUNCH_WAIT:-24}"
}

check() { # check <label> <expected-regex>
  local label="$1" want="$2" got
  got="$(trace | tail -20)"
  if printf '%s\n' "$got" | grep -qE "$want"; then
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label — no focus matching /$want/"
    printf '%s\n' "$got" | sed 's/^/          /' | tail -6
    FAIL=$((FAIL + 1))
  fi
}

surface_tab() { # surface_tab <tab> <expected>
  echo "== tab: $1"
  launch --es tab "$1"
  key DOWN; key RIGHT; key DOWN
  check "$1 reaches content" "$2"
}

surface_route() { # surface_route <route> <expected>
  echo "== route: $1"
  launch --es route "$1"
  key DOWN; key RIGHT; key DOWN
  check "$1 reaches content" "$2"
}

WANTED=("$@")
want() { [ ${#WANTED[@]} -eq 0 ] && return 0; for w in "${WANTED[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }

echo "Android TV focus verification ($SERIAL)"
echo

want home        && surface_tab   home            "tile:|rail:"
want browse      && surface_tab   browse          "tile:"
want search      && surface_tab   search          "focusable|tile:"
want library     && surface_tab   library         "focusable|tile:"
want channels    && surface_tab   channels        "focusable"
want surprise    && surface_route surprise        "tile:"
want collections && surface_route collections     "collection:"
want decade      && surface_route "decade:1920"   "tile:"
want cartoon     && surface_route cartoon         "tile:|focusable"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
