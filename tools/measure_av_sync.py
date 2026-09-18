#!/usr/bin/env python3
"""Measure A/V alignment from a recording of a synchronised marker signal.

`StudioSyncDeviceTest` publishes one WHITE frame and one full-scale tone burst
on the SAME frame index, once a second, stamped from one clock. Whatever
offset appears between them in the server's own recording is the pipeline's,
not the test's — which is the only way to get a NUMBER rather than "the start
times agree" (docs/WATCH-TOGETHER.md §6.2g).

It reads brightness per video frame and RMS per audio frame straight out of
ffmpeg's own filters, pairs each flash with its nearest burst, and reports the
median and spread. A single pairing can be wrong; a median over twenty cannot
be wrong in the same direction by accident.

    python3 tools/measure_av_sync.py <recording.mp4>
"""
import json
import subprocess
import statistics
import sys


def probe(args, cwd=None):
    out = subprocess.run(args, capture_output=True, text=True, cwd=cwd)
    return out.stdout


def lavfi(graph, entries, path):
    """Run an ffprobe lavfi graph over `path`.

    Two things this gets right that cost a round of debugging:
    `pkt_pts_time` is gone in current ffmpeg (it is `pts_time`), and a
    filtergraph cannot take a raw absolute path — the slashes and colons are
    graph syntax — so the file is referenced by NAME from its own directory.
    """
    import os
    d, name = os.path.split(os.path.abspath(path))
    return probe([
        "ffprobe", "-v", "error", "-f", "lavfi", graph.format(name=name),
        "-show_entries", entries, "-of", "json",
    ], cwd=d)


def video_brightness(path):
    """(time, YAVG) per frame, from ffmpeg's signalstats."""
    raw = lavfi("movie={name},signalstats",
                "frame=pts_time:frame_tags=lavfi.signalstats.YAVG", path)
    frames = json.loads(raw or "{}").get("frames", [])
    out = []
    for f in frames:
        t = f.get("pts_time") or f.get("pkt_pts_time")
        y = (f.get("tags") or {}).get("lavfi.signalstats.YAVG")
        if t is not None and y is not None:
            out.append((float(t), float(y)))
    return out


def audio_rms(path):
    """(time, RMS dB) per audio frame, from ffmpeg's astats."""
    raw = lavfi("amovie={name},astats=metadata=1:reset=1",
                "frame=pts_time:frame_tags=lavfi.astats.Overall.RMS_level", path)
    frames = json.loads(raw or "{}").get("frames", [])
    out = []
    for f in frames:
        t = f.get("pts_time") or f.get("pkt_pts_time")
        r = (f.get("tags") or {}).get("lavfi.astats.Overall.RMS_level")
        if t is not None and r is not None:
            try:
                out.append((float(t), float(r)))
            except ValueError:
                pass          # astats prints "-inf" for pure silence
    return out


def peaks(series, threshold, min_gap=0.4):
    """Local maxima above `threshold`, at most one per `min_gap` seconds."""
    hits = [(t, v) for t, v in series if v >= threshold]
    out = []
    for t, v in hits:
        if out and t - out[-1][0] < min_gap:
            if v > out[-1][1]:
                out[-1] = (t, v)
            continue
        out.append((t, v))
    return [t for t, _ in out]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]

    vid = video_brightness(path)
    aud = audio_rms(path)
    if not vid or not aud:
        print(f"FAIL: could not read both streams (video frames={len(vid)} audio frames={len(aud)})")
        return 1

    ybase = statistics.median(v for _, v in vid)
    ymax = max(v for _, v in vid)
    print(f"video frames {len(vid)}  median YAVG {ybase:.1f}  max {ymax:.1f}")

    # SILENCE IS -inf, AND THAT BROKE THE FIRST VERSION OF THIS.
    #
    # Between markers the signal is pure zeros, so astats reports -inf. A
    # median over those is -inf, a midpoint against it is -inf, and every
    # audio frame then counts as a burst: the first run found 16 "bursts"
    # against 6 flashes and still printed a confident +50.5 ms. The tell was
    # the count, not the number.
    #
    # So the threshold is ABSOLUTE. Anything above -40 dBFS is a marker,
    # because nothing else in this signal is above silence at all.
    finite = [(t, v) for t, v in aud if v > float("-inf")]
    print(f"audio frames {len(aud)}  ({len(finite)} above silence)")
    flashes = peaks(vid, (ybase + ymax) / 2)
    bursts = peaks(finite, -40.0)
    print(f"flashes {len(flashes)}  bursts {len(bursts)}")
    if len(flashes) < 3 or len(bursts) < 3:
        print("FAIL: too few markers found — was the sync test the source?")
        return 1
    # The counts must AGREE, or the pairing is matching the wrong things.
    # One marker either side is the recording's own edges.
    if abs(len(flashes) - len(bursts)) > 2:
        print(f"FAIL: {len(flashes)} flashes but {len(bursts)} bursts — "
              "the detector is finding something other than the markers, "
              "so any offset it computes is meaningless")
        return 1

    # Pair each flash with its nearest burst, then take the median offset.
    offsets = []
    for t in flashes:
        nearest = min(bursts, key=lambda b: abs(b - t))
        if abs(nearest - t) < 0.5:
            offsets.append((nearest - t) * 1000.0)
    if len(offsets) < 3:
        print("FAIL: markers found but none paired within 500 ms")
        return 1

    med = statistics.median(offsets)
    spread = max(offsets) - min(offsets)
    print()
    print(f"paired markers      {len(offsets)}")
    print(f"median offset       {med:+.1f} ms   (audio later than video when positive)")
    print(f"spread              {spread:.1f} ms")
    print(f"worst single marker {max(offsets, key=abs):+.1f} ms")
    print()
    # A viewer notices audio LEADING the picture sooner than lagging; the
    # broadcast convention is to keep both inside ~40 ms either way.
    verdict = "PASS" if abs(med) <= 40 and spread <= 80 else "FAIL"
    print(f"{verdict}: median |offset| {abs(med):.1f} ms, spread {spread:.1f} ms "
          f"(bar: 40 ms / 80 ms)")
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
