#!/bin/bash
# A Continuity CAMERA without a MICROPHONE must not be a crash — checked
# mechanically, because the runtime state that proves it needs a phone.
#
# The defect (§9.wwww): `makeSession()` adds a microphone INPUT only when a
# port exists, but the attach path hung a `MicAudioTap` on the session
# regardless. An audio OUTPUT on a capture session with no audio input is an
# invalid configuration and an ObjC exception, so the app went down instead of
# reporting anything.
#
# The state is ORDINARY, not exotic: the camera is found by discovery, the
# microphone only through the picker's `AVContinuityDevice`. Dismiss the picker
# and you have a camera and no microphone.
#
# This is a SOURCE check. It cannot prove the app survives — that needs a phone
# paired and the picker dismissed, on the glass. What it can do is stop the
# guard being deleted by someone who does not have that hardware in front of
# them, which is the situation this was written in.
#
#   bash tools/test_studio_continuity_guard.sh
set -u
cd "$(dirname "$0")/.."
DV=ArchiveWatch/ArchiveWatch/Views/DetailView.swift
SC=ArchiveWatch/ArchiveWatch/Studio/StudioContinuity.swift
fail=0; pass=0

# The checker, factored so the CONTROL can run it over a deliberately broken
# copy. A check that cannot fail is not a check.
check_guarded () {          # $1 = file to inspect
    awk '
        /let mic = MicAudioTap\(\)/ { found=1; if (!guarded) bad=1 }
        /case \.connected\(_, let hasMic\).*hasMic/ { guarded=1 }
        END { if (!found) exit 2; exit (bad ? 1 : 0) }
    ' "$1"
}

echo "== the microphone tap is attached only when there IS a microphone =="
if check_guarded "$DV"; then
    echo "  PASS  DetailView guards the MicAudioTap on state hasMicrophone"; pass=$((pass+1))
else
    case $? in
      2) echo "  FAIL  no MicAudioTap attach found in $DV — has it moved?";;
      *) echo "  FAIL  MicAudioTap attached without a hasMicrophone guard";;
    esac
    fail=$((fail+1))
fi

echo "== the CONTROL: the same check must FAIL on an unguarded copy =="
TMP=$(mktemp -t awcont)
# Strip the guard, keep the attach. This is the code as it crashed.
sed 's/^.*case \.connected(_, let hasMic).*hasMic.*$/            if true {/' "$DV" > "$TMP"
if check_guarded "$TMP"; then
    echo "  FAIL  the control PASSED — this check cannot detect the defect"
    fail=$((fail+1))
else
    echo "  PASS  the control fails, so the check can tell the two apart"; pass=$((pass+1))
fi
rm -f "$TMP"

echo "== the session adds a microphone input only when a port exists =="
if grep -q "if microphonePort() != nil," "$SC"; then
    echo "  PASS  makeSession() gates the microphone input on microphonePort()"; pass=$((pass+1))
else
    echo "  FAIL  makeSession() no longer gates the microphone input"; fail=$((fail+1))
fi

# The tap that outlived its owner (§9.zzzz). `makeTap()` put an UNRETAINED
# reference in the tap's storage with `finalize: nil`, and the process callback
# runs on MediaToolbox's own real-time thread — so it kept firing after the show
# ended and dereferenced a freed object. It killed the app at the end of EVERY
# macOS broadcast, and iOS takes the same path.
echo "== the audio tap retains its owner and releases it in finalize =="
SA=ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift
if grep -q "Unmanaged.passRetained(self).toOpaque()" "$SA" \
   && grep -q "MTAudioProcessingTapGetStorage(tap)).release()" "$SA"; then
    echo "  PASS  passRetained into storage, released in finalize"; pass=$((pass+1))
else
    echo "  FAIL  the tap does not retain its owner — it will outlive the mixer"
    fail=$((fail+1))
fi

echo "== the CONTROL: the same check must FAIL on an unretained copy =="
TMP2=$(mktemp -t awtap)
sed 's/Unmanaged.passRetained(self).toOpaque()/Unmanaged.passUnretained(self).toOpaque()/' "$SA" > "$TMP2"
if grep -q "Unmanaged.passRetained(self).toOpaque()" "$TMP2"; then
    echo "  FAIL  the control PASSED — this check cannot detect the defect"; fail=$((fail+1))
else
    echo "  PASS  the control fails, so the check can tell the two apart"; pass=$((pass+1))
fi
rm -f "$TMP2"

# A MONO FILM MUST NOT BROADCAST SILENCE (§9.jjjjj). `FilmAudioDecoder` — the
# tvOS pull path — hardcoded `mChannelsPerFrame: 2`, so a mono stream failed
# every decode with 'bada' and the television sent picture with no sound. A
# public-domain catalogue is mostly pre-1950s cinema, so that was most of the
# library. The older TAP path (macOS/iOS) always handled one, two and
# deinterleaved shapes; only the newer decoder assumed.
echo "== the film decoder does not hardcode a stereo channel count =="
FD=ArchiveWatch/ArchiveWatch/Studio/FilmAudioDecoder.swift
if grep -q "mChannelsPerFrame: sourceChannels" "$FD" && grep -q "triedMonoFallback" "$FD"; then
    echo "  PASS  channel count is read, with a mono retry"; pass=$((pass+1))
else
    echo "  FAIL  the decoder assumes a channel count — mono films will be silent"
    fail=$((fail+1))
fi

echo "== the CONTROL: the same check must FAIL on a hardcoded copy =="
TMP3=$(mktemp -t awmono)
sed 's/mChannelsPerFrame: sourceChannels/mChannelsPerFrame: 2/' "$FD" > "$TMP3"
if grep -q "mChannelsPerFrame: sourceChannels" "$TMP3"; then
    echo "  FAIL  the control PASSED — this check cannot detect the defect"; fail=$((fail+1))
else
    echo "  PASS  the control fails, so the check can tell the two apart"; pass=$((pass+1))
fi
rm -f "$TMP3"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
