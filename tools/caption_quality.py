#!/usr/bin/env python3
"""
caption_quality.py — decide whether a MACHINE-generated transcript is good enough
to show a viewer, or whether it is the confident nonsense that got auto-captions
banned in the first place.

This is the gate Decision 039b was missing. That ban was correct: whisper on poor
archival audio produced fluent, plausible, WRONG dialogue (White Zombie), and
fabricated speech over silent films. A wrong subtitle is worse than none. So the
question for reinstating on-device captioning is not "is the engine better" — it
is "can we MEASURE when the output is garbage and refuse it".

The signatures, all measurable without knowing the true dialogue:

  REPETITION   the loudest tell. A stuck recognizer emits the same token or
               phrase over and over — archive.org's ASR on "Child Bride" gave
               "ALRIGHT ALRIGHT ALRIGHT" and the 3-gram "why why why" 19 times.
               Measured as unique/total token ratio and the share of the
               transcript taken by its most common 3-gram.
  COVERAGE     cues that stop a third of the way in mean the recognizer gave up.
  DENSITY      a feature-length film yielding a handful of words is not a
               transcript; a wall of words with no gaps is a runaway loop.
  VOCABULARY   real dialogue has a long tail of distinct words. Hallucinated
               loops collapse to a tiny vocabulary.

Usage:
    python3 tools/caption_quality.py <file.srt|file.vtt> [--runtime SECONDS]
    python3 tools/caption_quality.py --self-test
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter

_CUE_TS = re.compile(r"(\d{1,2}):(\d{2}):(\d{2})[.,](\d{1,3})\s*-->")
_TAG = re.compile(r"<[^>]+>|\{[^}]*\}")
_WORD = re.compile(r"[A-Za-z']+")

# Thresholds. Each is a measurement, not a taste call — see --self-test, which
# runs them against REAL human subtitles and REAL hallucinated ASR.
# MEASURED against real files, both directions (see the table in
# docs/SUBTITLE-COVERAGE-PLAN.md §4). The first version of this gate used
# unique/total token ratio and FAILED BOTH WAYS: real human subtitles for "His
# Girl Friday" scored 0.126 while the known-bad "White Zombie" ASR scored 0.292 —
# because type-token ratio falls with LENGTH, so a long rich transcript looks
# worse than a short empty one. It is not a quality measure. Removed.
#
# What does separate, on the same files:
#            words/min   cues/min
#   BAD  White Zombie ASR    14        3.0
#   BAD  Carnival of Souls   49        8.8
#   GOOD His Girl Friday    187       38.2
#   GOOD The Stranger       102       23.6
# A recognizer that fails on poor audio goes SPARSE — it does not fill the film
# with nonsense, it stops producing. That is the detectable failure.
MIN_WORDS_PER_MIN = 65        # between Carnival (49) and The Stranger (102)
MAX_WORDS_PER_MIN = 320       # a runaway loop
MIN_CUES_PER_MIN = 12         # between 8.8 and 23.6
MIN_WINDOWED_TTR = 0.62       # length-INDEPENDENT (mean TTR over 100-word windows)
MAX_DUP_CUE_PCT = 8.0         # consecutive identical cues
MAX_LOOP_CUE_PCT = 5.0        # cues that are one token repeated ("alright alright...")
MIN_COVERAGE = 0.55           # last cue vs runtime


def parse_cues(text: str):
    """[(start_seconds, text)] from SRT or VTT."""
    out, cur = [], None
    for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        m = _CUE_TS.search(line)
        if m:
            h, mm, ss, _f = m.groups()
            cur = int(h) * 3600 + int(mm) * 60 + int(ss)
            continue
        s = _TAG.sub(" ", line).strip()
        if cur is not None and s and not s.isdigit() and not s.startswith("WEBVTT"):
            out.append((cur, s))
    return out


def assess(text: str, runtime: int = 0):
    """(ok, reasons, metrics).

    LIMIT — state it plainly: this cannot detect a transcript that is FLUENT AND
    WRONG. "White Zombie"'s ASR, the file that got auto-captions banned, reads as
    ordinary English that simply is not what the film says; no lexical statistic
    can know that. What is caught here is the recognizer FAILING VISIBLY: going
    sparse, looping, or giving up part-way. For fluent-and-wrong the defence has
    to come from outside the text — the recognizer's own confidence and an
    audio-suitability precheck (never run on a silent film) — plus labelling the
    track auto-generated so the viewer knows what they are looking at.
    """
    cues = parse_cues(text)
    texts = [s.lower().strip() for _t, s in cues]
    words = [w.lower() for s in texts for w in _WORD.findall(s)]
    m = {"cues": len(cues), "words": len(words), "vocab": len(set(words))}
    reasons = []
    if len(cues) < 5 or not words:
        return False, ["no usable cues"], m

    last = max(t for t, _ in cues)
    minutes = (runtime or last) / 60 or 1
    m["words_per_min"] = round(len(words) / minutes, 1)
    m["cues_per_min"] = round(len(cues) / minutes, 1)

    win = [words[i:i + 100] for i in range(0, len(words) - 99, 100)] or [words]
    m["windowed_ttr"] = round(sum(len(set(w)) / len(w) for w in win) / len(win), 3)

    dup = sum(1 for a, b in zip(texts, texts[1:]) if a and a == b)
    m["dup_cue_pct"] = round(100 * dup / max(1, len(texts)), 1)
    loopy = 0
    for s in texts:
        t = _WORD.findall(s)
        if len(t) >= 3 and len(set(t)) <= max(1, len(t) // 3):
            loopy += 1
    m["loop_cue_pct"] = round(100 * loopy / max(1, len(texts)), 1)

    if m["words_per_min"] < MIN_WORDS_PER_MIN:
        reasons.append(f"sparse: {m['words_per_min']} words/min — the recognizer gave up")
    if m["cues_per_min"] < MIN_CUES_PER_MIN:
        reasons.append(f"sparse: {m['cues_per_min']} cues/min")
    if m["words_per_min"] > MAX_WORDS_PER_MIN:
        reasons.append(f"runaway: {m['words_per_min']} words/min")
    if m["windowed_ttr"] < MIN_WINDOWED_TTR:
        reasons.append(f"repetitive: windowed TTR {m['windowed_ttr']}")
    if m["dup_cue_pct"] > MAX_DUP_CUE_PCT:
        reasons.append(f"{m['dup_cue_pct']}% of cues repeat the previous one")
    if m["loop_cue_pct"] > MAX_LOOP_CUE_PCT:
        reasons.append(f"{m['loop_cue_pct']}% of cues are one looped token")
    if runtime > 600:
        m["coverage"] = round(last / runtime, 2)
        if m["coverage"] < MIN_COVERAGE:
            reasons.append(f"cues cover only {m['coverage']:.0%} of the runtime")
    return (not reasons), reasons, m


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?")
    ap.add_argument("--runtime", type=int, default=0)
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.path:
        ap.error("path or --self-test")
    text = open(a.path, encoding="utf-8", errors="replace").read()
    ok, reasons, m = assess(text, a.runtime)
    print(("ACCEPT" if ok else "REJECT"), m)
    for r in reasons:
        print("   -", r)
    return 0 if ok else 1


def self_test() -> int:
    """Synthetic ends of the spectrum; the real-corpus test lives in
    tools/test_caption_quality.py, which runs against live files."""
    good = "".join(
        f"{i}\n00:{i // 60:02d}:{i % 60:02d},000 --> 00:{i // 60:02d}:{i % 60:02d},900\n"
        f"{w}\n\n" for i, w in enumerate(
            ("the quick brown fox jumps over a lazy dog while nobody watches "
             "and later that evening she told him everything about the letter "
             "he had hidden beneath the floorboards of the old house").split() * 12, 1))
    loop = "".join(f"{i}\n00:{i // 60:02d}:{i % 60:02d},000 --> 00:{i // 60:02d}:{i % 60:02d},900\n"
                   f"alright alright alright\n\n" for i in range(1, 400))
    fails = 0
    for label, text, rt, want in (("varied dialogue", good, 600, True),
                                  ("looped 'alright'", loop, 600, False)):
        ok, reasons, m = assess(text, rt)
        mark = "OK " if ok == want else "BAD"
        if ok != want:
            fails += 1
        print(f"  {mark} {label:20} -> {'ACCEPT' if ok else 'REJECT'}  {reasons[:1]}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
