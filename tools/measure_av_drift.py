#!/usr/bin/env python3
"""Measure audio/video drift in a Studio recording (launch audit B).

Video is stamped from the engine's host-clock frame counter and audio from
the mixer's sample count, which the audio hardware paces. If those clocks
disagreed, the two tracks' spans would part over a long show. Run it on a
server recording (mediamtx `record: yes`, fMP4) at intervals; the spans'
difference should stay flat.

    python3 tools/measure_av_drift.py <dir-or-file.mp4>

CHECK THE RECORDING IS THE FILM before believing a flat line: the first
1,200 s run was flat because it was a still closing card at 88 kbps with no
film audio — the audio clock under test never ran. Look at the bitrate and a
frame, and run `volumedetect` on the audio, first.
"""
import glob
import os
import subprocess
import sys

arg = sys.argv[1]
f = sorted(glob.glob(os.path.join(arg, "*.mp4")))[-1] if os.path.isdir(arg) else arg


def span(sel):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", sel,
                          "-show_entries", "packet=pts_time", "-of", "csv=p=0", f],
                         capture_output=True, text=True).stdout.split()
    t = [float(x) for x in out if x not in ("", "N/A")]
    return (min(t), max(t), len(t)) if t else None


v, a = span("v:0"), span("a:0")
if not v or not a:
    sys.exit("need both a video and an audio track")
print("file", os.path.basename(f))
print("video first %.3f last %.3f packets %d" % v)
print("audio first %.3f last %.3f packets %d" % a)
vs, as_ = v[1] - v[0], a[1] - a[0]
print("video span %.3f s, audio span %.3f s, audio-minus-video %+.3f s" % (vs, as_, as_ - vs))
