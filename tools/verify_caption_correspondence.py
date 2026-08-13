#!/usr/bin/env python3
"""Does the SCREEN match the AUDIO? The caption harness that measures the goal.

Every earlier caption harness measured a mechanism — cue mapping, display
pacing, judge verdicts — and ten builds shipped while the owner kept seeing
captions that did not match the film. This one measures the owner's bar
directly, per word:

  spoken -> screen   when a word is SPOKEN, is it on screen within +/-2.5s?
  screen -> spoken   when a cue is DISPLAYED, were its words heard nearby?

The audio side is ground truth: windows of the film transcribed by the shipped
SpeechAnalyzer harness (/tmp/awlive prints exact `cue S-E:` spans on the
analyzer's own clock). The screen side simulates the SHIPPED display function
(LiveCaptions.display: the cue covering t, held to end + 0.5) over the
published VTT — the same pure function the device display loop feeds with the
real playhead.

Calibration is built in: the same metric over a +10s-shifted copy of the VTT
must crater, or the harness could not detect the very fault it exists to
catch. A machine transcript mishears words constantly (WER ~50% on 1940s
optical sound), so ABSOLUTE coverage tops out well below 100% — judge the
CONTRAST between aligned and shifted, and between windows.

Usage:
  python3 tools/verify_caption_correspondence.py <video-url> <vtt-url-or-path> \
      [--windows 300,1800,3600] [--window-len 120] [--awlive /tmp/awlive]
"""
import argparse, json, re, subprocess, sys, tempfile, urllib.request
from pathlib import Path

WORD = re.compile(r"[a-z']{4,}")
HOLD_AFTER_END = 0.5


def parse_vtt(text):
    cues, block = [], []
    for line in text.splitlines():
        m = re.match(r"(?:(\d+):)?(\d+):(\d+)\.(\d+) --> (?:(\d+):)?(\d+):(\d+)\.(\d+)", line)
        if m:
            h1, m1, s1, ms1, h2, m2, s2, ms2 = (int(x) if x else 0 for x in m.groups())
            block = [h1 * 3600 + m1 * 60 + s1 + ms1 / 1000,
                     h2 * 3600 + m2 * 60 + s2 + ms2 / 1000]
        elif block and line.strip() and not line.strip().isdigit() \
                and not line.startswith(("WEBVTT", "X-TIMESTAMP")):
            block.append(line.strip())
        elif not line.strip() and len(block) > 2:
            cues.append((block[0], block[1], " ".join(block[2:])))
            block = []
    if len(block) > 2:
        cues.append((block[0], block[1], " ".join(block[2:])))
    return cues


def display_at(cues, t):
    """Mirror of the SHIPPED LiveCaptions.display — keep in lockstep."""
    covering = None
    for c in cues:
        if c[0] <= t:
            covering = c
        else:
            break
    if covering and t <= covering[1] + HOLD_AFTER_END:
        return covering[2]
    return ""


def transcribe(video, start, length, awlive):
    with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as f:
        m4a = f.name
    r = subprocess.run(
        ["ffmpeg", "-y", "-ss", str(start), "-i", video, "-t", str(length),
         "-vn", "-c:a", "aac", "-b:a", "64k", m4a],
        stdin=subprocess.DEVNULL, capture_output=True, timeout=300)
    if r.returncode != 0:
        return []
    r = subprocess.run([awlive, f"file://{m4a}"],
                       capture_output=True, text=True, timeout=220)
    heard = []
    seen_exact = set()
    for line in r.stdout.splitlines():
        m = re.match(r"\[AWCAP\] cue ([\d.]+)-([\d.]+)s: (.*)", line)
        if m:
            heard.append((start + float(m.group(1)), start + float(m.group(2)),
                          m.group(3)))
            seen_exact.add(m.group(3)[:24])
            continue
        # The analyzer finalizes only a handful of cues per window on a Mac;
        # the volatile "playhead" lines carry the rest. Their stamp is the
        # display moment — roughly the END of the words, 1-3s of recognition
        # latency included — so back the words off by speaking rate. The
        # +10s shifted control keeps the verdict valid despite that jitter.
        m = re.match(r"\s*playhead\s+([\d.]+)s\s+\d+ words\s+(.*)", line)
        if m and m.group(2)[:24] not in seen_exact:
            text = m.group(2)
            n = max(1, len(WORD.findall(text.lower())))
            end = start + float(m.group(1))
            heard.append((end - 0.4 * n, end, text))
    Path(m4a).unlink(missing_ok=True)
    return heard


def word_times(spans):
    """(time, word) for each >=4-char word, spread across its span."""
    out = []
    for s, e, text in spans:
        ws = WORD.findall(text.lower())
        if not ws:
            continue
        dur = max(e - s, 0.4)
        for i, w in enumerate(ws):
            out.append((s + dur * (i + 0.5) / len(ws), w))
    return out


def correspondence(cues, heard, tol=2.5):
    """(spoken->screen coverage, screen->spoken coverage, sample size)."""
    hw = word_times(heard)
    hits = 0
    for t, w in hw:
        lo, hi = t - tol, t + tol
        tt = lo
        found = False
        while tt <= hi and not found:
            if w in WORD.findall(display_at(cues, tt).lower()):
                found = True
            tt += 0.5
        hits += found
    spoken_to_screen = hits / len(hw) if hw else 0.0

    heard_words = {}
    for t, w in hw:
        heard_words.setdefault(w, []).append(t)
    window_lo = min((s for s, _, _ in heard), default=0)
    window_hi = max((e for _, e, _ in heard), default=0)
    shown = [c for c in cues if c[0] < window_hi and c[1] > window_lo]
    total = hits2 = 0
    for s, e, text in shown:
        for w in WORD.findall(text.lower()):
            total += 1
            times = heard_words.get(w, [])
            if any(s - 3 <= t <= e + 3 for t in times):
                hits2 += 1
    screen_to_spoken = hits2 / total if total else 0.0
    return spoken_to_screen, screen_to_spoken, len(hw), total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("vtt")
    ap.add_argument("--windows", default="300,1800,3600")
    ap.add_argument("--window-len", type=int, default=120)
    ap.add_argument("--awlive", default="/tmp/awlive")
    args = ap.parse_args()

    if re.match(r"https?://", args.vtt):
        body = urllib.request.urlopen(args.vtt).read().decode()
    else:
        body = Path(args.vtt).read_text()
    cues = parse_vtt(body)
    if not cues:
        sys.exit("no cues parsed from VTT")
    shifted = [(s + 10, e + 10, t) for s, e, t in cues]
    print(f"{len(cues)} cues; windows at {args.windows}")

    agg = {"aligned": [0, 0, 0, 0], "shifted+10s": [0, 0, 0, 0]}
    for w in (int(x) for x in args.windows.split(",")):
        heard = transcribe(args.video, w, args.window_len, args.awlive)
        if len(heard) < 5:
            print(f"  window {w}: only {len(heard)} utterances heard — skipped")
            continue
        for name, cs in (("aligned", cues), ("shifted+10s", shifted)):
            a, b, n, m = correspondence(cs, heard)
            agg[name][0] += a * n; agg[name][1] += n
            agg[name][2] += b * m; agg[name][3] += m
            if name == "aligned":
                print(f"  window {w}: spoken->screen {a:.0%} ({n} words), "
                      f"screen->spoken {b:.0%} ({m} words)")

    print()
    results = {}
    for name, (an, n, bm, m) in agg.items():
        s2s = an / n if n else 0
        s2sp = bm / m if m else 0
        results[name] = (s2s, s2sp)
        print(f"{name:12} spoken->screen {s2s:.0%}   screen->spoken {s2sp:.0%}")

    al, sh = results.get("aligned", (0, 0)), results.get("shifted+10s", (0, 0))
    # The bar: aligned correspondence must be strong in BOTH directions and
    # clearly separated from the shifted control, or the file/display does not
    # match the film the way a viewer experiences it.
    ok = al[0] >= 0.45 and al[1] >= 0.45 and al[0] >= sh[0] * 1.8
    print("\nRESULT:", "OK — the screen tracks the audio, and the harness can "
          "tell (shifted control craters)." if ok else
          "FAIL — displayed captions do not track the audio.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
