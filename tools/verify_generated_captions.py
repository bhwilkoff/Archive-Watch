#!/usr/bin/env python3
"""Check machine captions against HUMAN captions for the same film.

WHY THIS IS THE ONLY TEST THAT COUNTS. `CaptionQuality` rejects output that is
sparse, looping, or truncated — a recognizer failing VISIBLY. It cannot detect a
transcript that is fluent and WRONG, which is exactly what retired the whisper
pipeline (Decision 039b): confident, plausible dialogue that bore no relation to
the film. Passing the gate is therefore evidence of nothing on its own.

Ground truth is available and free: ~5,700 films already carry HUMAN subtitles.
Transcribing those with the same engine and comparing gives a real accuracy
number on exactly the material we care about — scratchy, 60-to-90-year-old
optical soundtracks — instead of an assumption.

THE METRIC, and why the obvious one is wrong. The first version of this script
scored each human cue against the machine words in the SAME time window, and
reported mean 0.14 — an apparent catastrophe. It was measuring the wrong thing.
Human subtitles are sourced by IMDb id and synced to whichever RELEASE the
uploader had; ours are timed to the archive.org encode we actually stream. The
measured best global offsets were +70s, +30s, -10s, so a windowed score compares
two differently-synced documents and reads near zero even for a perfect
transcript.

What answers "is this the right dialogue" is the overlap of DISTINCTIVE
vocabulary (>4 letters, stopwords removed), ignoring time entirely. Measured on
six films, with the off-diagonal as a negative control:

    same film       0.89 mean   (range 0.83-0.95)
    different film  0.30 mean   (range 0.23-0.44)

A 3x separation with no overlap, so the metric discriminates. The control is
computed on every run and printed: a metric that cannot tell two films apart
would prove nothing about accuracy, and that must be visible rather than
assumed.

Timing is reported SEPARATELY, as the best-offset windowed agreement, because a
transcript can be right about the words and wrong about when they are said —
and only the first is a hallucination.

    python3 tools/verify_generated_captions.py --machine gen/ --report out.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import statistics
import sys
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

TS = re.compile(r"(?:(\d{1,3}):)?(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*"
                r"(?:(\d{1,3}):)?(\d{2}):(\d{2})[.,](\d{3})")
WORD = re.compile(r"[a-z']+")

# Words that carry no identifying signal; a match on them is not evidence.
STOP = {"the", "a", "an", "and", "of", "to", "in", "is", "it", "that", "this",
        "you", "i", "we", "he", "she", "they", "for", "on", "with", "as", "at",
        "be", "are", "was", "were", "so", "but", "or", "not", "have", "has"}


def parse_vtt(text: str) -> list[tuple[float, float, str]]:
    cues, lines = [], text.splitlines()
    for i, line in enumerate(lines):
        m = TS.search(line)
        if not m:
            continue
        g = m.groups()
        start = int(g[0] or 0) * 3600 + int(g[1]) * 60 + int(g[2]) + int(g[3]) / 1000
        end = int(g[4] or 0) * 3600 + int(g[5]) * 60 + int(g[6]) + int(g[7]) / 1000
        body = []
        for nxt in lines[i + 1:]:
            if not nxt.strip() or TS.search(nxt):
                break
            body.append(nxt)
        cues.append((start, end, " ".join(body)))
    return cues


def words_in(cues, a: float, b: float) -> list[str]:
    out = []
    for s, e, t in cues:
        if e < a or s > b:
            continue
        out.extend(WORD.findall(t.lower()))
    return out


def agreement(human: list, machine: list) -> tuple[float, int]:
    """Mean per-window similarity between the two transcripts."""
    scores = []
    for s, e, text in human:
        h = [w for w in WORD.findall(text.lower()) if w not in STOP]
        if len(h) < 3:
            continue
        # A generous window: ASR cue boundaries never line up with a human's.
        m = [w for w in words_in(machine, s - 2.5, e + 2.5) if w not in STOP]
        if not m:
            scores.append(0.0)
            continue
        scores.append(SequenceMatcher(None, h, m).ratio())
    return (statistics.mean(scores) if scores else 0.0), len(scores)


def fetch(url: str) -> str | None:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "ArchiveWatch-verify/1.0"})
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.read().decode("utf-8", errors="replace")
    except Exception:
        return None


def distinctive(cues) -> set:
    """Words that identify a FILM rather than the English language."""
    return {w for _, _, t in cues
            for w in WORD.findall(t.lower())
            if w not in STOP and len(w) > 4}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--machine", required=True, help="dir of <archiveID>/en.vtt")
    ap.add_argument("--report", default="tools/caption_accuracy.csv")
    ap.add_argument("--floor", type=float, default=0.60,
                    help="mean same-film vocabulary overlap below this fails")
    args = ap.parse_args()

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    by_id = {it.get("archiveID"): it for it in items}

    mach, hum, titles, rows = {}, {}, {}, []
    for vtt_path in sorted(Path(args.machine).glob("*/en.vtt")):
        aid = vtt_path.parent.name
        it = by_id.get(aid)
        if it is None:
            continue
        human_url = next((c.get("vttURL") or c.get("url")
                          for c in (it.get("captions") or [])
                          if (c.get("source") or "") in ("subsource", "subdl", "opensubtitles")),
                         None)
        if not human_url:
            continue
        human_txt = fetch(human_url)
        if not human_txt:
            continue
        h, m = parse_vtt(human_txt), parse_vtt(vtt_path.read_text(encoding="utf-8", errors="replace"))
        if len(h) < 10 or len(m) < 10:
            continue
        mach[aid], hum[aid] = distinctive(m), distinctive(h)
        titles[aid] = (it.get("title") or aid)[:34]
        # Timing, reported separately: the best global offset and its score.
        best = (0, -1.0)
        for off in range(-180, 181, 10):
            sc, _ = agreement(h[:120], [(s2 + off, e2 + off, t2) for s2, e2, t2 in m])
            if sc > best[1]:
                best = (off, sc)
        rows.append({"archiveID": aid, "title": titles[aid],
                     "sameFilmVocab": 0.0, "controlVocab": 0.0,
                     "bestOffsetSeconds": best[0], "timingScore": round(best[1], 3),
                     "humanCues": len(h), "machineCues": len(m)})

    if not rows:
        print("no films had BOTH a human track and a machine track — nothing to compare")
        return 2

    ids = list(mach)
    same, control = [], []
    for r in rows:
        a = r["archiveID"]
        r["sameFilmVocab"] = round(len(mach[a] & hum[a]) / max(len(hum[a]), 1), 3)
        others = [len(mach[a] & hum[b]) / max(len(hum[b]), 1) for b in ids if b != a]
        r["controlVocab"] = round(statistics.mean(others), 3) if others else 0.0
        same.append(r["sameFilmVocab"])
        control.extend(others)
        print(f"  {r['sameFilmVocab']:5.3f} (control {r['controlVocab']:.2f})  "
              f"{titles[a]:36} timing {r['timingScore']:.2f} @ {r['bestOffsetSeconds']:+}s")

    with open(args.report, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    mean_same = statistics.mean(same)
    mean_ctl = statistics.mean(control) if control else 0.0
    print(f"\ncompared {len(rows)} films against their own human subtitles")
    print(f"  same-film vocabulary overlap   {mean_same:.3f}")
    print(f"  DIFFERENT-film control         {mean_ctl:.3f}")
    print(f"  separation                     {mean_same - mean_ctl:+.3f}")
    print(f"  report                         {args.report}")

    discriminates = (mean_same - mean_ctl) >= 0.25
    ok = mean_same >= args.floor and discriminates
    if not discriminates:
        print("\nVERDICT: INCONCLUSIVE — the metric cannot tell two films apart, "
              "so it proves nothing about accuracy. Fix the measurement first.")
    elif ok:
        print("\nVERDICT: the transcripts carry the right film's dialogue — not "
              "hallucination. (Timing is reported separately; human subs are "
              "synced to other releases, so a nonzero best offset is expected.)")
    else:
        print("\nVERDICT: FAILS — plausible text that does not match what is said. "
              "Do not ship these.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
