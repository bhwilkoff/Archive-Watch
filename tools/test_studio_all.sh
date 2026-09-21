#!/bin/bash
# Every Watch Together Studio test, in one command (WATCH-TOGETHER §8).
#
# The tests existed and there was no way to run them together, which in
# practice means they do not get run. Each harness had its own swiftc
# invocation to remember, its own server to start, and its own prerequisites.
#
# THE ONE RULE THIS SCRIPT ENFORCES: a SKIP is not a PASS. Four of the Kotlin
# cases skip silently without a local mediamtx, and they were skipping for a
# whole session before anyone noticed (§6.2n). Skips are counted and printed
# separately, and `--strict` turns them into failures.
#
#   tools/test_studio_all.sh [--strict] [--soak]
#
# --soak adds the ten-minute §8.3 soak, which is excluded by default because
# it is ten minutes.
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"
STRICT=0; SOAK=0
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    --soak) SOAK=1 ;;
    *) echo "unknown flag: $a"; exit 2 ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SCRATCH="${TMPDIR:-/tmp}/aw-studio-suite"
mkdir -p "$SCRATCH"
MTX=$(command -v mediamtx || echo /opt/homebrew/bin/mediamtx)
FFMPEG=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
CLIP="${AW_THERMAL_CLIP:-$SCRATCH/awnoise.mp4}"

PASS=0; FAIL=0; SKIP=0
declare -a ROWS=()

row() { ROWS+=("$1|$2|$3"); }

cleanup() {
  pkill -f "$SCRATCH/mtx.yml" >/dev/null 2>&1
  # Harness-started servers too: a Swift exit(0) skips `defer`, so two
  # of them outlived a completed run.
  pkill -f 'aw-mtx' >/dev/null 2>&1
  pkill -f 'aw-mediamtx' >/dev/null 2>&1
  pkill -f rtmp_throttle_proxy.py >/dev/null 2>&1
  pkill -f rtmp_sever_proxy.py >/dev/null 2>&1
}
trap cleanup EXIT

# ---- the server every transport test needs, started ONCE
if [ ! -x "$MTX" ]; then
  echo "!! mediamtx not found — every server-facing test will SKIP, which is not a pass."
else
  cat > "$SCRATCH/mtx.yml" <<YML
rtmp: yes
rtmpAddress: :19351
api: yes
apiAddress: :9997
hls: no
webrtc: no
rtsp: no
srt: no
moq: no
playback: no
metrics: no
pprof: no
logLevel: info
# NOT recording. Every harness that needs a recording starts its own
# server and configures it; this one only has to answer. Recording here wrote
# every case's stream to disk for no reader, and during the ten-minute soak
# that is hundreds of megabytes on top of a 1080p encode.
record: no
paths:
  all:
    source: publisher
YML
  pkill -f "$SCRATCH/mtx.yml" >/dev/null 2>&1
  sleep 1
  "$MTX" "$SCRATCH/mtx.yml" > "$SCRATCH/mtx.log" 2>&1 &
  for _ in $(seq 1 20); do
    curl -s --max-time 1 http://127.0.0.1:9997/v3/paths/list >/dev/null 2>&1 && break
    sleep 0.5
  done
  echo "mediamtx up on :19351 (api :9997)"
fi

# ---- the saturating clip the bitrate tests need (a ceiling, not a floor)
if [ ! -f "$CLIP" ] && [ -x "$FFMPEG" ]; then
  echo "… generating the saturating clip once ($CLIP)"
  "$FFMPEG" -y -loglevel error -f lavfi -i "testsrc2=s=1280x720:r=30:d=30" \
    -f lavfi -i "nullsrc=s=1280x720:r=30:d=30,geq=random(1)*255:128:128" \
    -filter_complex "[0:v][1:v]blend=all_mode=average" \
    -c:v libx264 -preset veryfast -b:v 20M -maxrate 20M -bufsize 40M \
    -pix_fmt yuv420p "$CLIP" >/dev/null 2>&1 || true
fi

# ---- Swift harnesses. Each is compiled the way its own header documents.
swift_case() {
  local name="$1"; shift
  local out="$SCRATCH/$(echo "$name" | tr -cd 'a-z0-9')"
  local srcs=("$@")
  printf '\n=== %s\n' "$name"
  # A CLEAN SLATE per case. Each harness starts its own proxy and its own
  # mediamtx and tears them down on exit, but exit(0) skips a Swift `defer`,
  # so one can survive. 8.6 then talked to a STALE proxy that had already
  # finished its phases and was forwarding at full rate, and reported "video
  # never actually yielded" - a true statement about a run that had never
  # been throttled. It passes standalone. A suite that perturbs its own cases
  # is worse than no suite.
  # `|| true` on every one: pkill exits non-zero when nothing matched,
  # which is the NORMAL case, and see the errexit note below.
  pkill -f rtmp_throttle_proxy.py >/dev/null 2>&1 || true
  pkill -f rtmp_sever_proxy.py >/dev/null 2>&1 || true
  pkill -f 'aw-mtx' >/dev/null 2>&1 || true
  pkill -f 'aw-mediamtx' >/dev/null 2>&1 || true
  sleep 2
  if ! xcrun swiftc -parse-as-library -O "${srcs[@]}" -o "$out" 2> "$SCRATCH/$name.build"; then
    echo "   BUILD FAILED (see $SCRATCH/$name.build)"
    row "$name" FAIL "did not compile"; FAIL=$((FAIL+1)); return
  fi
  set +e
  AW_THERMAL_CLIP="$CLIP" "$out" 2>&1 | tail -22
  local rc=${PIPESTATUS[0]}
  # NOT `set -e` again. Re-enabling errexit here aborted the whole suite
  # on the next case's cleanup, because a pkill that matches nothing
  # exits non-zero: the run died silently in 8.4 and still reported
  # exit 0. This script is deliberately `set -u` only - it must report
  # every case, not stop at the first surprise.
  case "$rc" in
    0) row "$name" PASS ""; PASS=$((PASS+1)) ;;
    2) row "$name" SKIP "prerequisite missing"; SKIP=$((SKIP+1)) ;;
    *) row "$name" FAIL "exit $rc"; FAIL=$((FAIL+1)) ;;
  esac
}

# `awdiag` for cases that compile Studio sources without the app. Every Swift
# case gets it: on 2026-09-19 all of them failed to build with "cannot find
# 'awdiag' in scope" — two errors predating that day and six added when the
# RTMP publisher was instrumented — and nobody noticed because nobody had run
# the suite. See the file's own header.
DEC=ArchiveWatch/ArchiveWatch/Studio/FilmAudioDecoder.swift
SHIM=tools/harness_awdiag.swift
PUB=ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift
ENG=ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift
AUD=ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift
OVL=ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift
# The engine READS chat itself since the reader moved out of StudioSession
# (§6.4), so every case that compiles $ENG needs this too. Leaving it out is
# what made 8.3, 8.5 and 8.6 fail to compile for a whole session: the harness
# file lists are a second, silent copy of the module's dependency graph, and a
# source move does not update them.
CHAT=ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift
AUTH=ArchiveWatch/ArchiveWatch/Studio/StudioPlatformAuth.swift
PLAT=ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift
MEDIA=tools/StudioTestMedia.swift

swift_case "8.1 rtmp publish"      "$PUB" "$MEDIA" "$SHIM" tools/test_rtmp_publish.swift
swift_case "8.4 rtmp reconnect"    "$PUB" "$MEDIA" "$SHIM" tools/test_rtmp_reconnect.swift
swift_case "8.5 thermal"           "$PUB" "$ENG" "$AUD" "$OVL" "$CHAT" "$SHIM" tools/test_studio_thermal.swift
swift_case "8.6 back-pressure"     "$PUB" "$ENG" "$AUD" "$OVL" "$CHAT" "$SHIM" tools/test_studio_backpressure.swift
swift_case "8.15 audio ring FIFO"  "$PUB" "$ENG" "$AUD" "$OVL" "$CHAT" "$SHIM" tools/test_studio_ring.swift
swift_case "8.16 programme rate"   "$PUB" "$ENG" "$AUD" "$OVL" "$CHAT" "$DEC" "$SHIM" tools/test_studio_rate.swift
swift_case "8.17 tap resampler"    "$PUB" "$ENG" "$AUD" "$OVL" "$CHAT" "$SHIM" tools/test_studio_resample.swift
# The camera-placement settings, asserted against what their LABELS promise.
# Owner 2026-09-20: "I'm not sure the different settings for where your camera
# will go ... are actually working as they should." They were not: theatre was
# corner moved 64 px down, same 332x187 tile in the same corner.
swift_case "8.22 camera placement" "$PUB" "$ENG" "$AUD" "$OVL" "$CHAT" "$SHIM" tools/test_studio_layouts.swift
# The camera-stall recovery RULE, which lived inside tvOS's own view loop and
# so existed on exactly one platform while PARITY said "no recovery yet" for
# the other two. No $ENG: the rule is a pure value type on purpose.
swift_case "8.23 camera-stall recovery" ArchiveWatch/ArchiveWatch/Studio/StudioCameraStall.swift tools/test_studio_camerastall.swift
# No $SHIM: StudioVoiceProbe calls no awdiag, and adding sources a case does
# not need is how three cases stopped compiling for a session (§9.lllll).
swift_case "8.18 voice frame slices" ArchiveWatch/ArchiveWatch/Studio/StudioVoiceProbe.swift tools/test_studio_voiceframe.swift
# Apple's own Opus, which is what SHAREPLAY §5/§7 cost out. No $SHIM: the
# codec calls no awdiag.
swift_case "8.19 guest voice codec" ArchiveWatch/ArchiveWatch/Studio/StudioVoiceCodec.swift tools/test_studio_voicecodec.swift
swift_case "8.20 guest voice room" ArchiveWatch/ArchiveWatch/Studio/StudioVoiceCodec.swift ArchiveWatch/ArchiveWatch/Studio/StudioVoiceRoom.swift tools/test_studio_voiceroom.swift
# SHAREPLAY §10: the owner's own answer to the transport problem — let people
# use the call service they already have, and tap it. Plays two tones from two
# processes and requires the untapped one to be ABSENT, because a tap that
# caught the film as well would feed the broadcast back into itself.
# macOS only, and no $SHIM: this touches Core Audio and nothing of ours.
if [ "$(uname)" = "Darwin" ]; then
  swift_case "8.21 per-process audio tap" tools/test_studio_processtap.swift
fi

# The two credential-facing harnesses. Neither was in this runner, which is
# precisely the condition §9.aaa describes: a test that exists and therefore
# does not get run. Both send DELIBERATELY invalid credentials to the real
# endpoints and need no account, no server and no device — only a network.
swift_case "8.2 sign-in shapes"    "$AUTH" "$PLAT" "$SHIM" tools/test_studio_signin.swift
swift_case "8.7 live-platform shapes" "$AUTH" "$PLAT" "$SHIM" tools/test_studio_live_shapes.swift
# The REGISTERED clients. Skips (exit 2) where Secrets.xcconfig carries no
# client id, which is every machine but the owner's - and a skip is not a
# pass, so `--strict` makes it a failure once the ids exist. 8.2 proves the
# shapes with credentials that are wrong on purpose; this proves OUR
# registration accepts them, which is a defect class 8.2 cannot see.
swift_case "8.9 registered clients" "$AUTH" "$PLAT" "$SHIM" tools/test_studio_registered.swift
# §5's credential rule, guarded. Needs no network and no account: it throws a
# sentinel key at every error path the publisher can reach and asserts the
# string comes back in none of them. Its first run found a live leak.
# Every go-live surface asks the same questions. A SOURCE check, not a UI test:
# it cannot prove a screen behaves, only that no surface is missing a gate its
# siblings have — the one defect class that has recurred four times here and was
# found by eye every time (§9.ffff).
if bash tools/test_studio_surface_parity.sh >"$SCRATCH/surface-parity.log" 2>&1; then
  row "8.12 go-live surface parity" PASS ""; PASS=$((PASS+1))
else
  row "8.12 go-live surface parity" FAIL "a surface is missing a sibling's gate"
  FAIL=$((FAIL+1))
fi

# A Continuity CAMERA with no MICROPHONE crashed the app (§9.wwww), and the
# state is ordinary: the camera comes from discovery, the microphone only from
# the picker's AVContinuityDevice, so dismissing the picker produces it. The
# runtime proof needs a phone; this is the part that can run without one, and it
# carries its own control.
if bash tools/test_studio_continuity_guard.sh >"$SCRATCH/continuity-guard.log" 2>&1; then
  row "8.13 continuity mic guard" PASS ""; PASS=$((PASS+1))
else
  row "8.13 continuity mic guard" FAIL "a camera without a microphone is unguarded"
  FAIL=$((FAIL+1))
fi

# Two one-line platform mistakes that each blocked a real broadcast and are
# invisible in a diff review (§9.vvvv): an undeclared `part`, and a `prompt`
# that never offers Google's channel chooser.
if bash tools/test_studio_request_shapes.sh >"$SCRATCH/request-shapes.log" 2>&1; then
  row "8.14 platform request shapes" PASS ""; PASS=$((PASS+1))
else
  row "8.14 platform request shapes" FAIL "a request shape regressed"
  FAIL=$((FAIL+1))
fi

swift_case "8.10 stream-key hygiene" "$PUB" "$SHIM" tools/test_studio_key_hygiene.swift
# Where the tokens land. Writes only under a probe account and deletes it, so
# it cannot disturb a real sign-in. Reports the keychain CHOICE rather than
# judging it — an unentitled binary cannot reach the data-protection keychain,
# so that question belongs inside the signed app (§9.rrr).
swift_case "8.11 token store"       "$AUTH" "$PLAT" "$SHIM" tools/test_studio_token_store.swift
# ---- the rights tests, which need no server at all
for t in tools/test_studio_rights_parity.py tools/test_studio_rights_coverage.py; do
  name="$(basename "$t")"
  printf '\n=== %s\n' "$name"
  if python3 "$t" 2>&1 | tail -6; then
    row "$name" PASS ""; PASS=$((PASS+1))
  else
    row "$name" FAIL "non-zero exit"; FAIL=$((FAIL+1))
  fi
done

# ---- Kotlin. Its four server-facing cases SKIP without mediamtx, and a skip
# is not a pass — so the count is read out of the XML, never from "BUILD
# SUCCESSFUL".
printf '\n=== Kotlin studio suites\n'
if (cd android && ./gradlew :app:testGoogleDebugUnitTest --rerun-tasks -q > "$SCRATCH/kotlin.log" 2>&1); then
  COUNTS="$SCRATCH/kotlin-counts"
  rm -f "$COUNTS"
  python3 - "$REPO/android/app/build/test-results/testGoogleDebugUnitTest" "$COUNTS" <<'KPY'
import sys, glob, xml.etree.ElementTree as ET
p = s = f = 0
for path in glob.glob(sys.argv[1] + "/*.xml"):
    r = ET.parse(path).getroot()
    for tc in r.findall('testcase'):
        if tc.find('skipped') is not None:
            s += 1
            print("   SKIPPED", (tc.get('classname') or '').split('.')[-1] + "." + (tc.get('name') or ''))
        elif tc.find('failure') is not None or tc.find('error') is not None:
            f += 1
            print("   FAIL", tc.get('name'))
        else:
            p += 1
print("   kotlin: pass=%d skip=%d fail=%d" % (p, s, f))
open(sys.argv[2], "w").write("%d %d %d\n" % (p, s, f))
KPY
  # A row reading PASS over pass=0 is the false green this script exists to
  # prevent, and the first version printed exactly that: the counts file was
  # written one directory above where it was read, so 46 Kotlin cases were
  # missing from the totals as well.
  if [ -s "$COUNTS" ]; then read -r KP KS KF < "$COUNTS"; else KP=0; KS=0; KF=0; fi
  if [ "$KP" = "0" ] && [ "$KS" = "0" ] && [ "$KF" = "0" ]; then
    row "Kotlin suites" FAIL "no results parsed - counts unavailable"
    FAIL=$((FAIL+1))
  else
    PASS=$((PASS+KP)); SKIP=$((SKIP+KS)); FAIL=$((FAIL+KF))
    if [ "$KF" -gt 0 ]; then KR=FAIL; else KR=PASS; fi
    row "Kotlin suites" "$KR" "pass=$KP skip=$KS fail=$KF"
  fi
else
  echo "   gradle failed (see $SCRATCH/kotlin.log)"
  row "Kotlin suites" FAIL "gradle failed"; FAIL=$((FAIL+1))
fi

# ---- the soak runs LAST, after everything that needs the shared server.
#
# It used to run before the rights and Kotlin cases, and because it stops the
# shared mediamtx (it brings its own, and two 1080p servers got the first
# --soak run killed for memory pressure), the six server-facing Kotlin cases
# then found nothing to publish to and SKIPPED. --strict caught it; a plain
# run would have called that "PASS (with skips)". Nothing follows the soak
# now, so stopping the server before it costs nothing.
if [ "$SOAK" = "1" ]; then
  # The soak starts its OWN server, so the shared one is redundant for ten
  # minutes of 1080p encoding. Leaving both up got this run killed by the
  # system for memory pressure - not a test failure, but a suite that
  # cannot finish is a suite nobody trusts.
  pkill -f "$SCRATCH/mtx.yml" >/dev/null 2>&1 || true
  sleep 2
  swift_case "8.3 ten-minute soak" "$PUB" "$ENG" "$AUD" "$OVL" "$CHAT" tools/test_studio_soak.swift
else
  row "8.3 ten-minute soak" SKIP "not run without --soak"; SKIP=$((SKIP+1))
fi


# ---- the summary
printf '\n%s\n' "────────────────────────────────────────────────────────────"
printf '%-28s %-6s %s\n' "CASE" "RESULT" "NOTE"
for r in "${ROWS[@]}"; do
  IFS='|' read -r n s d <<< "$r"
  printf '%-28s %-6s %s\n' "$n" "$s" "$d"
done
printf '%s\n' "────────────────────────────────────────────────────────────"
echo "pass=$PASS skip=$SKIP fail=$FAIL"
if [ "$SKIP" -gt 0 ]; then
  echo "NOTE: a SKIP is not a PASS. $SKIP case(s) did not run."
fi
# THE VERDICT IS DECIDED BEFORE IT IS SPOKEN.
#
# The first version printed "PASS (with skips)" and only THEN evaluated
# --strict and exited 1 - so the spoken line contradicted the exit status on
# exactly the runs --strict exists for. That is discipline 11 inside the
# mechanism written to enforce it: the printed line exists because a caller's
# pipe eats the status, so it is the line that must be right.
RESULT=PASS
RC=0
if [ "$SKIP" -gt 0 ]; then RESULT="PASS (with skips)"; fi
if [ "$STRICT" = "1" ] && [ "$SKIP" -gt 0 ]; then
  RESULT="FAIL (--strict: $SKIP skip(s) count as failures)"
  RC=1
fi
if [ "$FAIL" -gt 0 ]; then RESULT=FAIL; RC=1; fi
echo "SUITE RESULT: $RESULT"
exit $RC
