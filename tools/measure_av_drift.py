#!/usr/bin/env python3
"""Measure audio/video drift in a Studio recording (launch audit B).

Video is stamped from the engine's host-clock frame counter and audio from
the mixer's sample count, which the audio hardware paces. If those clocks
disagreed, the two tracks' spans would part over a long show. Run it on a
server recording (mediamtx `record: yes`, fMP4) at intervals; the spans'
difference should stay flat.

    python3 tools/measure_av_drift.py <dir-or-file.mp4>

Measured 2026-09-23 on macOS (M3, That Certain Thing, 6 Mbps, 30 fps), five
readings over 1,200 s on air: +51, +48, +46, +50, +37 ms — no trend; both
spans matched wall time (1200.62 / 1200.66 s). iOS, tvOS and Android are
not yet measured this way.
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
