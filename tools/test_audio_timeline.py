#!/usr/bin/env python3
"""Locks `audio_timeline_broken`, the guard behind the owner's report that
"the audio is intermittent" on The Sheik.

The real numbers are row 1: archive.org's own h.264 derivative of TheSheik
declares 5,164s of video against 3,305,533s of audio. Rows 3-6 are the ones
that must NOT trip -- the guard is worth having only if it leaves ordinary
files alone, and a de-verification sweep in this very tool once cost 1,205
playable titles (see its docstring)."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from repick_derivatives import audio_timeline_broken as broken

CASES = [
    # (video, audio, expected_broken, why)
    (5164.92, 3305533.47, True,  "TheSheik: audio timeline 640x the picture"),
    # NOT actionable: a music score that stops before a silent film does is
    # how the file was made. Measured on the sweep's first 200 items
    # (MysteryOfTheLeapingFish_348, 1516s picture / 699s music). Re-picking on
    # this would trade a known file for an unknown one on a guess.
    (5164.92, 120.0,      False, "audio shorter than picture: report, do not act"),
    (1516.0,  699.0,      False, "silent short whose music stops early"),
    (5164.92, 5164.86,    False, "TheSheik_512kb: the healthy derivative"),
    (3600.0,  3598.5,     False, "ordinary 1.5s disagreement"),
    (3600.0,  4200.0,     False, "audio 17% longer -- sloppy, not broken"),
    (5164.92, None,       False, "silent film, no audio track: not a fault"),
    (None,    5164.0,     False, "no video duration: cannot judge"),
    (0.0,     5164.0,     False, "zero-length video: never divide by it"),
]

def main() -> int:
    bad = 0
    for v, a, want, why in CASES:
        got = broken(v, a)
        ok = got == want
        if not ok: bad += 1
        print(f"  {'ok  ' if ok else 'FAIL'}  v={str(v):>9} a={str(a):>12}  "
              f"want={want!s:5} got={got!s:5}  {why}")
    print(f"\n{len(CASES)-bad}/{len(CASES)} passed")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
