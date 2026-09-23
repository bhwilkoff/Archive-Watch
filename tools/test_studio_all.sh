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
  # Only one we STARTED — a Worker the developer was already running is
  # theirs, and killing it would be a suite perturbing its own environment.
  [ "${TOGETHER_STARTED:-0}" = "1" ] && pkill -f "wrangler dev" >/dev/null 2>&1
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

# ---- the Worker the room tests need, started ONCE and locally.
#
# The same reasoning as the mediamtx above: a transport test that needs a
# server and does not start one becomes a SKIP, and this suite's whole point
# is that a skip is not a pass. Two cases (8.30, 8.31) were skipping the
# moment they were written, which is exactly the state §6.2n warns about.
#
# --local ALWAYS. `wrangler dev --remote` would reach the owner's Cloudflare
# account and the live archivewatch.org Worker; nothing in this suite may do
# that.
TOGETHER_BASE="${AW_TOGETHER_BASE:-http://127.0.0.1:8799}"
TOGETHER_STARTED=0
if [ -z "${AW_TOGETHER_BASE:-}" ] && [ -d worker ]; then
  if curl -s --max-time 1 "$TOGETHER_BASE/together/ABCD" >/dev/null 2>&1; then
    echo "a Worker is already answering on $TOGETHER_BASE"
  else
    echo "… starting a local Worker for the room tests"
    # NOT `( cd worker && … & )`. That subshell exits immediately and takes
    # npx's child with it often enough to be flaky — a run would print
    # "local Worker up" and then SKIP the room cases minutes later, which is
    # the worst shape of failure: a skip that looks like a configuration
    # choice. `-c` removes the need to cd at all, and backgrounding here
    # keeps the process a child of this shell.
    npx --yes wrangler d1 execute archivewatch-pulse --local \
      -c worker/wrangler.toml --file=worker/schema-rooms.sql >/dev/null 2>&1
    nohup npx --yes wrangler dev --local --port 8799 \
      -c worker/wrangler.toml > "$SCRATCH/wrangler.log" 2>&1 &
    # READY MEANS THE TABLE EXISTS, not merely that something answers.
    # `/together/ABCD` returns "no such room" as soon as the Worker is
    # routing, which is true well before `d1 execute` has finished creating
    # the table — so a run could start, find the route alive and the table
    # missing, and fail instead of skipping. Probe with a real CREATE and
    # clean it up: the only honest question is "can a room be made".
    for _ in $(seq 1 60); do
      probe=$(curl -s --max-time 2 -X POST -H 'content-type: application/json' \
              -d '{"filmID":"aw-readiness-probe"}' "$TOGETHER_BASE/together/new" 2>/dev/null)
      case "$probe" in
        *'"code"'*)
          probe_code=$(printf '%s' "$probe" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
          curl -s --max-time 2 -X POST -H 'content-type: application/json' \
               -d '{"end":true}' "$TOGETHER_BASE/together/$probe_code" >/dev/null 2>&1
          break ;;
      esac
      sleep 1
    done
    if curl -s --max-time 1 "$TOGETHER_BASE/together/ABCD" >/dev/null 2>&1; then
      TOGETHER_STARTED=1
      echo "local Worker up on $TOGETHER_BASE"
    else
      echo "!! could not start a local Worker — the room tests will SKIP, which is not a pass."
      echo "   (see $SCRATCH/wrangler.log)"
    fi
  fi
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
# The engine writes the recording itself (§D35), so every case that compiles
# $ENG needs the recorder too.
REC=ArchiveWatch/ArchiveWatch/Studio/StudioRecorder.swift
# $ENG's `Configuration.applyOutputSettings()` reads the host's §D4 choices, so
# every case that compiles $ENG needs this too — six cases failed to build the
# moment it landed, which is the same "every case that compiles $ENG needs
# this" note the chat reader already earned below.
OUT=ArchiveWatch/ArchiveWatch/Studio/StudioOutputSettings.swift
AUD=ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift
OVL=ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift
# The engine READS chat itself since the reader moved out of StudioSession
# (§6.4), so every case that compiles $ENG needs this too. Leaving it out is
# what made 8.3, 8.5 and 8.6 fail to compile for a whole session: the harness
# file lists are a second, silent copy of the module's dependency graph, and a
# source move does not update them.
CHAT=ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift
# AND YOUTUBE'S. Added 2026-09-22 and it broke six cases the moment it landed,
# for the reason written two comments up: the engine now references
# `StudioChatYouTube`, and this list is a second, silent copy of the module's
# dependency graph that a new file does not update. Every case that compiles
# $ENG needs this too.
CHATYT=ArchiveWatch/ArchiveWatch/Studio/StudioChatYouTube.swift
# The engine reads a host's chat filter, so every case that compiles the
# engine needs it. This list is the harness's own second copy of the
# module's dependency graph (§6.2n) — adding one file broke eight cases.
CHATFILTER=ArchiveWatch/ArchiveWatch/Studio/StudioChatFilter.swift
AUTH=ArchiveWatch/ArchiveWatch/Studio/StudioPlatformAuth.swift
PLAT=ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift
MEDIA=tools/StudioTestMedia.swift

swift_case "8.1 rtmp publish"      "$PUB" "$MEDIA" "$SHIM" tools/test_rtmp_publish.swift
swift_case "8.4 rtmp reconnect"    "$PUB" "$MEDIA" "$SHIM" tools/test_rtmp_reconnect.swift
# ONE ENCODE, TWO DESTINATIONS. Simulcast's claim is that the expensive half
# happens once, so this asserts the frames are the SAME frames and that both
# servers read a complete stream back — not merely that two sockets opened.
swift_case "8.37 simulcast"        "$PUB" "$MEDIA" "$SHIM" tools/test_studio_simulcast.swift
swift_case "8.5 thermal"           "$PUB" "$ENG" "$REC" "$CHATFILTER" "$OUT" "$AUD" "$OVL" "$CHAT" "$CHATYT" "$SHIM" tools/test_studio_thermal.swift
swift_case "8.6 back-pressure"     "$PUB" "$ENG" "$REC" "$CHATFILTER" "$OUT" "$AUD" "$OVL" "$CHAT" "$CHATYT" "$SHIM" tools/test_studio_backpressure.swift
swift_case "8.15 audio ring FIFO"  "$PUB" "$ENG" "$REC" "$CHATFILTER" "$OUT" "$AUD" "$OVL" "$CHAT" "$CHATYT" "$SHIM" tools/test_studio_ring.swift
swift_case "8.16 programme rate"   "$PUB" "$ENG" "$REC" "$CHATFILTER" "$OUT" "$AUD" "$OVL" "$CHAT" "$CHATYT" "$DEC" "$SHIM" tools/test_studio_rate.swift
swift_case "8.17 tap resampler"    "$PUB" "$ENG" "$REC" "$CHATFILTER" "$OUT" "$AUD" "$OVL" "$CHAT" "$CHATYT" "$SHIM" tools/test_studio_resample.swift
swift_case "8.56 chat quota"          "$PUB" "$ENG" "$REC" "$CHATFILTER" "$OUT" "$AUD" "$OVL" "$CHAT" "$CHATYT" "$SHIM" tools/test_studio_chat_quota.swift
# The camera-placement settings, asserted against what their LABELS promise.
# Owner 2026-09-20: "I'm not sure the different settings for where your camera
# will go ... are actually working as they should." They were not: theatre was
# corner moved 64 px down, same 332x187 tile in the same corner.
swift_case "8.22 camera placement" "$PUB" "$ENG" "$REC" "$CHATFILTER" "$OUT" "$AUD" "$OVL" "$CHAT" "$CHATYT" "$SHIM" tools/test_studio_layouts.swift
# The camera-stall recovery RULE, which lived inside tvOS's own view loop and
# so existed on exactly one platform while PARITY said "no recovery yet" for
# the other two. No $ENG: the rule is a pure value type on purpose.
swift_case "8.23 camera-stall recovery" ArchiveWatch/ArchiveWatch/Studio/StudioCameraStall.swift tools/test_studio_camerastall.swift
# THE MICROPHONE GATE as a pure rule — no ring, no encoder, no clock, the
# shape §8.23 already uses. What is under test is not the multiply: it is that
# the gate does not CHATTER at the boundary, does not CLIP the first syllable,
# and actually reaches zero instead of settling on a quiet copy of the room.
swift_case "8.38 microphone gate" "$PUB" "$AUD" "$SHIM" tools/test_studio_micgate.swift
swift_case "8.24 device selection" ArchiveWatch/ArchiveWatch/Studio/StudioDevices.swift tools/test_studio_devices.swift
swift_case "8.25 output settings" ArchiveWatch/ArchiveWatch/Studio/StudioOutputSettings.swift tools/test_studio_output.swift
swift_case "8.26 call-audio apps" ArchiveWatch/ArchiveWatch/Studio/StudioAudioProcesses.swift tools/test_studio_callapps.swift
swift_case "8.27 film sync" ArchiveWatch/ArchiveWatch/Studio/StudioSync.swift tools/test_studio_sync.swift
swift_case "8.28 room codes" ArchiveWatch/ArchiveWatch/Studio/StudioRoom.swift tools/test_studio_room.swift
# The Worker and the app must normalise a code IDENTICALLY, or a code read
# aloud reaches a different room depending on which end typed it.
printf '\n=== %s\n' "8.34 room alphabet parity"
if python3 tools/test_room_alphabet_parity.py; then
  row "8.34 alphabet parity" PASS ""; PASS=$((PASS+1))
else
  row "8.34 alphabet parity" FAIL "see output"; FAIL=$((FAIL+1))
fi

printf '\n=== %s\n' "8.32 web room client"
if node tools/test_together_web.mjs; then
  row "8.32 web room client" PASS ""; PASS=$((PASS+1))
else
  row "8.32 web room client" FAIL "node exit $?"; FAIL=$((FAIL+1))
fi

printf '\n=== %s\n' "8.29 worker/app code parity"
if node tools/test_together_worker.mjs; then
  row "8.29 worker code parity" PASS ""; PASS=$((PASS+1))
else
  row "8.29 worker code parity" FAIL "node exit $?"; FAIL=$((FAIL+1))
fi

# The room transport against a RUNNING Worker. A route that parses is not a
# route that works (Decision 130), so this drives the real HTTP. It needs a
# local `wrangler dev`, and a SKIP here is not a pass — it is the transport
# going unexercised.
printf '\n=== %s\n' "8.30 room transport (live)"
if curl -s --max-time 2 -X POST -H 'content-type: application/json' \
     -d '{"filmID":"probe"}' "$TOGETHER_BASE/together/new" 2>/dev/null | grep -q '"code"'; then
  if BASE="$TOGETHER_BASE" node tools/test_together_live.mjs; then
    row "8.30 room transport" PASS ""; PASS=$((PASS+1))
  else
    row "8.30 room transport" FAIL "see output"; FAIL=$((FAIL+1))
  fi
else
  echo "   no Worker on ${AW_TOGETHER_BASE:-http://127.0.0.1:8799} — start one with:"
  echo "   (cd worker && npx wrangler d1 execute archivewatch-pulse --local --file=schema-rooms.sql && npx wrangler dev --local --port 8799)"
  row "8.30 room transport" SKIP "no local Worker"; SKIP=$((SKIP+1))
fi

# The CLIENT against the same Worker. §8.27 proves the arithmetic and §8.30
# the routes; neither says they are wired together, which is Decision 133.
if curl -s --max-time 2 -X POST -H 'content-type: application/json' \
     -d '{"filmID":"probe"}' "$TOGETHER_BASE/together/new" 2>/dev/null | grep -q '"code"'; then
  AW_TOGETHER_BASE="$TOGETHER_BASE" \
    swift_case "8.31 sync client (live)" \
      ArchiveWatch/ArchiveWatch/Studio/StudioSync.swift \
      ArchiveWatch/ArchiveWatch/Studio/StudioRoom.swift \
      ArchiveWatch/ArchiveWatch/Studio/StudioSyncClient.swift \
      tools/test_studio_syncclient.swift
else
  row "8.31 sync client" SKIP "no local Worker"; SKIP=$((SKIP+1))
fi
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
#
# IT TAKES OVER THE SPEAKERS, so it asks. This case plays two audible tones
# through the DEFAULT OUTPUT DEVICE for about fifteen seconds — it has to,
# because the thing under test is a tap on what another process is really
# rendering, and the device it follows is whatever the person at the desk is
# listening through. On 2026-09-22 the owner asked "why do tones keep being
# played on my computer when it doesn't seem like you are testing sound?" and
# the answer was: because a suite somebody ran in the background took over
# their speakers without saying so.
#
# So it is OPT-IN, and the skip line says exactly how to opt in. That makes it
# a SKIP rather than a silent absence, which is this suite's own rule (a skip
# is not a pass, and it is counted separately) — the soak has the same shape
# for the same kind of reason.
if [ "$(uname)" = "Darwin" ]; then
  if [ "${AW_AUDIBLE:-0}" = "1" ]; then
    # PUT THE VOLUME BACK. This case builds a private aggregate device around
    # the default output, and on 2026-09-22 the owner asked "why do you keep
    # turning up my speakers?" — it had been left at 100 after runs of this
    # suite were killed part-way through. Whatever the exact CoreAudio path,
    # the rule is the one this project already has for the owner's machine:
    # an instrument leaves no trace of itself (the screenshot that caught
    # their documents, the pkill that read as a crash).
    #
    # The trap matters more than the restore: the volume was only ever left
    # wrong on runs that DIED, so a restore on the happy path would have
    # fixed nothing.
    AW_VOL_BEFORE=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null || echo "")
    if [ -n "$AW_VOL_BEFORE" ]; then
      trap 'osascript -e "set volume output volume $AW_VOL_BEFORE" >/dev/null 2>&1' EXIT INT TERM
    fi
    swift_case "8.21 per-process audio tap" tools/test_studio_processtap.swift
    if [ -n "$AW_VOL_BEFORE" ]; then
      osascript -e "set volume output volume $AW_VOL_BEFORE" >/dev/null 2>&1
      AW_VOL_AFTER=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null || echo "")
      [ "$AW_VOL_AFTER" = "$AW_VOL_BEFORE" ] \
        || echo "  NOTE: output volume was $AW_VOL_BEFORE before this case and is now $AW_VOL_AFTER"
    fi
  else
    row "8.21 per-process audio tap" SKIP "plays audible tones; run with AW_AUDIBLE=1"
    SKIP=$((SKIP+1))
  fi
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

# The film's stall names its own cause. Every branch, and the ORDER of the
# branches, which overlap — a rebuilt window also reads as paused.
swift_case "8.40 film-stall reasons" ArchiveWatch/ArchiveWatch/Studio/StudioFilmStall.swift \
  tools/test_studio_filmstall.swift

# §D24 — the guest tile is framed like the camera, and the two framings are
# separate. A shared one would move the host's face whenever they cropped
# their guests.
if bash tools/test_studio_guestframing.sh >"$SCRATCH/guestframing.log" 2>&1; then
  row "8.47 guest tile framing" PASS ""; PASS=$((PASS+1))
else
  row "8.47 guest tile framing" FAIL "the guest tile cannot be framed independently"
  FAIL=$((FAIL+1))
fi

# D133 — everything a host set up before the engine existed survives going
# live. Going live ends the rehearsal and builds a SECOND engine; anything
# attached to the first reaches nothing, silently.
if bash tools/test_studio_armed.sh >"$SCRATCH/armed.log" 2>&1; then
  row "8.46 armed values survive go-live" PASS ""; PASS=$((PASS+1))
else
  row "8.46 armed values survive go-live" FAIL "a host's setup is dropped at Go Live"
  FAIL=$((FAIL+1))
fi

# §8.50 — the engine follows the player's item. The Mac player swaps items
# under a running show; the output left behind is a black program.
if bash tools/test_studio_followitem.sh >"$SCRATCH/followitem.log" 2>&1; then
  row "8.50 engine follows the film's item" PASS ""; PASS=$((PASS+1))
else
  row "8.50 engine follows the film's item" FAIL "an item swap blacks out the program"
  FAIL=$((FAIL+1))
fi

# §8.53 — no log line prints a destination URL (its last component is the key).
if bash tools/test_studio_key_in_logs.sh >"$SCRATCH/keylogs.log" 2>&1; then
  row "8.53 no stream key in logs" PASS ""; PASS=$((PASS+1))
else
  row "8.53 no stream key in logs" FAIL "a log line prints a stream key"
  FAIL=$((FAIL+1))
fi

# §8.54 — Go Live ends the preview before arming the broadcast end() deletes.
if bash tools/test_studio_golive_order.sh >"$SCRATCH/goliveorder.log" 2>&1; then
  row "8.54 preview ends before arming" PASS ""; PASS=$((PASS+1))
else
  row "8.54 preview ends before arming" FAIL "Go Live from a preview deletes its own broadcast"
  FAIL=$((FAIL+1))
fi

# §8.55 — ending a show survives the caller's cancellation (tvOS End, A12).
python3 -m http.server 18765 --bind 127.0.0.1 >/dev/null 2>&1 &
HTTPPID=$!
sleep 1
if swiftc -O -o "$SCRATCH/endcancel" tools/test_studio_end_cancel.swift >"$SCRATCH/endcancel.build" 2>&1 \
   && "$SCRATCH/endcancel" 18765 >"$SCRATCH/endcancel.log" 2>&1; then
  row "8.55 end survives cancellation" PASS ""; PASS=$((PASS+1))
else
  row "8.55 end survives cancellation" FAIL "a cancelled teardown never completes the broadcast"
  FAIL=$((FAIL+1))
fi
kill $HTTPPID 2>/dev/null || true

# §8.57 — a live show's film cannot change under it (A11).
if bash tools/test_studio_film_locked.sh >"$SCRATCH/filmlocked.log" 2>&1; then
  row "8.57 film locked while live" PASS ""; PASS=$((PASS+1))
else
  row "8.57 film locked while live" FAIL "autoplay or Play Next can swap the film on air"
  FAIL=$((FAIL+1))
fi

# §8.58 — a room code is taken only by the room's film; players leave on close (A16).
if bash tools/test_studio_room_handoff.sh >"$SCRATCH/roomhandoff.log" 2>&1; then
  row "8.58 room hand-off" PASS ""; PASS=$((PASS+1))
else
  row "8.58 room hand-off" FAIL "a room code hijacks another film, or a closed player stays in the room"
  FAIL=$((FAIL+1))
fi

# §8.49 — every platform tells YouTube the show is over while it is still
# live. After the publisher closes, `complete` is refused 403 and the
# host's broadcast lingers in "Live now".
if bash tools/test_studio_broadcastend.sh >"$SCRATCH/broadcastend.log" 2>&1; then
  row "8.49 broadcast ends before publisher" PASS ""; PASS=$((PASS+1))
else
  row "8.49 broadcast ends before publisher" FAIL "a YouTube broadcast outlives the show"
  FAIL=$((FAIL+1))
fi

# §D12a — a surface never pulls the film out from under a live show. The
# black-programme fault: reproduced twice in eight runs with no signature,
# because it needs a view rebuild at a particular moment in a live show.
if bash tools/test_studio_playerlifetime.sh >"$SCRATCH/playerlifetime.log" 2>&1; then
  row "8.45 player outlives a rebuild" PASS ""; PASS=$((PASS+1))
else
  row "8.45 player outlives a rebuild" FAIL "a teardown can black the programme"
  FAIL=$((FAIL+1))
fi

# §D23's privacy rules for the screen source. The capture is measured on the
# product path; this holds the part that went wrong, which was never capture.
if [ "$(uname)" = "Darwin" ]; then
  if bash tools/test_studio_screensource.sh >"$SCRATCH/screensource.log" 2>&1; then
    row "8.44 screen source privacy" PASS ""; PASS=$((PASS+1))
  else
    row "8.44 screen source privacy" FAIL "a window list or title can leak"
    FAIL=$((FAIL+1))
  fi
fi

# §D22 — the host's chat controls. The filter is a pure function so every
# rule and every interaction is reachable in milliseconds; the layout case
# caught a real defect the same hour it was written (a mirrored column landing
# on the host's face) and a wrap defect seen on air.
swift_case "8.42 chat column layout" \
  ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOutputSettings.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatYouTube.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatFilter.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioRecorder.swift \
  "$SHIM" tools/test_studio_chatlayout.swift

# §D26 — the audience reaching the screen. Renders through the PRODUCT's own
# overlay renderer and asserts the geometry the glass showed wrong twice: a
# banner over the chat column, and a name in a case its owner never typed.
swift_case "8.48 shout-out" \
  ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOutputSettings.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatYouTube.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatFilter.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioRecorder.swift \
  "$SHIM" tools/test_studio_shoutout.swift

# §D30 — a card is a chapter on the replay. PURE mapping; the countdown case
# fails if values are compared instead of kinds (a marker every second).
# §D32 — the film's chat line fits 200 characters and never cuts the link.
swift_case "8.52 film chat line" \
  ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOutputSettings.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatYouTube.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatFilter.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioRecorder.swift \
  "$SHIM" tools/test_studio_chatshare.swift

swift_case "8.51 card markers" \
  ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOutputSettings.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatYouTube.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatFilter.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioRecorder.swift \
  "$SHIM" tools/test_studio_markers.swift

swift_case "8.43 chat filter" \
  ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOutputSettings.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatYouTube.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioChatFilter.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
  ArchiveWatch/ArchiveWatch/Studio/StudioRecorder.swift \
  "$SHIM" tools/test_studio_chatfilter.swift

# US English in everything a person reads (CLAUDE.md, owner 2026-09-22). Found
# four user-facing "catalogue" strings across four platforms on its first run
# that a hand sweep of the same files had missed.
if python3 tools/test_us_english.py >"$SCRATCH/us-english.log" 2>&1; then
  row "8.41 US English on screen" PASS ""; PASS=$((PASS+1))
else
  row "8.41 US English on screen" FAIL "a British spelling reached a user-facing string"
  FAIL=$((FAIL+1))
fi

# §D19's staging, guarded structurally. A card a host is PREPARING must reach
# their own thumbnail and no further; the wire proves one value at one moment,
# this proves there is no path at all.
if bash tools/test_studio_staging.sh >"$SCRATCH/staging.log" 2>&1; then
  row "8.39 staged card goes nowhere" PASS ""; PASS=$((PASS+1))
else
  row "8.39 staged card goes nowhere" FAIL "a staged card can reach the audience"
  FAIL=$((FAIL+1))
fi

# A broadcast's chat id must reach the engine. `YouTubeLive.chat(...)` was
# written and correct and called by nothing, because the id was read and
# dropped inside `StudioGoLive.destination()`. Only the CHAIN fails; a unit
# test of either end passes.
if bash tools/test_studio_chat_carried.sh >"$SCRATCH/chat-carried.log" 2>&1; then
  row "8.36 chat id reaches the engine" PASS ""; PASS=$((PASS+1))
else
  row "8.36 chat id reaches the engine" FAIL "a link drops the live chat id"
  FAIL=$((FAIL+1))
fi

# An uploader's attribution must not fork one film into two cards (Decision
# 040's clustering, and the owner's two Scarecrows).
if python3 tools/test_quoted_title_merge.py >"$SCRATCH/quoted-title.log" 2>&1; then
  row "test_quoted_title_merge.py" PASS ""; PASS=$((PASS+1))
else
  row "test_quoted_title_merge.py" FAIL "an attribution still forks a film"
  FAIL=$((FAIL+1))
fi

# EVERY resampler call site passes a FRAME capacity, not a sample count. A
# SOURCE check for the same reason §8.12 is one: a unit error is invisible at a
# glance and produces correct audio right up to the buffer size where it stops
# being memory-safe. `StudioCallAudioTap` passed `dst.count` and could write 2x
# past its scratch inside a real-time CoreAudio callback.
if bash tools/test_studio_resampler_capacity.sh >"$SCRATCH/resampler-capacity.log" 2>&1; then
  row "8.35 resampler capacity units" PASS ""; PASS=$((PASS+1))
else
  row "8.35 resampler capacity units" FAIL "a call site passes a sample count as frames"
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
  swift_case "8.3 ten-minute soak" "$PUB" "$ENG" "$REC" "$OUT" "$AUD" "$OVL" "$CHAT" "$CHATYT" "$SHIM" tools/test_studio_soak.swift
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
