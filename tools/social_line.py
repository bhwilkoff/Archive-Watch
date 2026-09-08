#!/usr/bin/env python3
"""
social_line.py — find the one line of dialogue a teaser should be built on.

WHY. The three Reels the owner made by hand in the Creation Studio are each
built on a QUOTED PHRASE — "I Love You.", "What a wonderful world.", "left
behind" — stitched from many films that all say it. The phrase is the hook,
the caption and the spine of the edit at once. The automated teaser, by
contrast, picked a shot that MOVED. That difference is the whole quality gap,
and it is not about cropping.

This finds the equivalent for a SINGLE film: a line worth quoting, with the
timing to cut on. The clip is then cut to the line, the line is burned on
screen, and the same line becomes the caption hook.

WHAT IT REFUSES, and why — every rule below came from reading real published
VTTs rather than imagining what subtitles contain:

  (dramatic music)      Sound cues are not dialogue. Bracketed in every
                        convention: (), [], ♪.
  "- A. - B."           A cue holding two speakers is a conversation, not a
                        quotable line, and reads as garbage burned on screen.
  ALL CAPS              Title cards and credits, not speech.
  1-3 words             "Certainly." carries nothing out of context.
  13+ words             Will not fit on a phone screen at a readable size.
  no terminal stop      A cue clipped mid-sentence promises a thought it
                        never finishes.
  lowercase opening     The TAIL of the previous cue. It ends like a sentence
                        but never began as one.

These VTTs are largely machine-transcribed, so some survivors will still be
imperfect English ("You who might help escape from pressure"). No heuristic
here can judge sense; the ordering below prefers questions and exclamations,
which at least fail gracefully — an odd question still reads as intriguing.
"""

from __future__ import annotations

import re

# The first act only. Before 60s is titles and studio idents; the stock shot
# index only analyses the opening ~300s, and the programme's rule is that a
# teaser never reaches an ending it could spoil.
DEFAULT_LO, DEFAULT_HI = 60.0, 300.0

_TS = re.compile(r"(\d{2}):(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[.,](\d{3})")
_SOUND = re.compile(r"[\(\[♪]")
_TAG = re.compile(r"<[^>]+>")


def _secs(h, m, s, ms) -> float:
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0


def parse_cues(vtt: str) -> list:
    """[(start, end, text)] with markup stripped and blank cues dropped."""
    out, lines = [], vtt.splitlines()
    for i, ln in enumerate(lines):
        m = _TS.search(ln)
        if not m:
            continue
        start, end = _secs(*m.groups()[:4]), _secs(*m.groups()[4:])
        body = []
        for nxt in lines[i + 1:]:
            if not nxt.strip() or _TS.search(nxt):
                break
            body.append(_TAG.sub("", nxt).strip())
        text = " ".join(b for b in body if b).strip()
        if text:
            out.append((start, end, text))
    return out


def quotable(text: str) -> bool:
    if _SOUND.search(text):
        return False
    # Two speakers in one cue. A leading dash is fine; a SECOND one is not.
    if text.count(" - ") >= 1 or text.strip().count("- ") > 1:
        return False
    t = text.strip().lstrip("- ").strip()
    if not t or t.endswith(","):
        return False
    letters = [c for c in t if c.isalpha()]
    if letters and sum(c.isupper() for c in letters) / len(letters) > 0.8:
        return False                      # title card / credit
    # A trailing ellipsis is a CONTINUATION marker, not a full stop — the
    # thought carries into the next cue. Same defect as a lowercase opening,
    # at the other end of the line.
    if t.endswith("...") or t.endswith("\u2026"):
        return False
    # A line wrapped in quotes ends on the QUOTE, not the stop — check the
    # sentence inside it. '"You must never open that door."' is real dialogue
    # and the naive last-character test throws it away.
    inner = t.rstrip('"\u201d\u2019\'')
    if not inner or inner[-1] not in ".!?":
        return False
    # A cue that OPENS lowercase is the tail of the previous one — "around
    # those eyes and of the mouth?" is a real pick this rule rejects. It ends
    # like a sentence but never began as one, and burned on screen it reads as
    # a mistake. pick_review learned the identical lesson about quoted text.
    if not (t[0].isupper() or t[0] in '"\u201c\u2018'):
        return False
    words = t.split()
    return 4 <= len(words) <= 12


def pick_line(vtt: str, lo: float = DEFAULT_LO, hi: float = DEFAULT_HI) -> dict | None:
    """The best quotable line in the window, or None.

    Ordering, most wanted first: a QUESTION (it invites the scroll to stop),
    then an exclamation, then a statement; within a class, the one nearest
    eight words, which is the length that reads cleanly burned on a phone.
    """
    got = pick_lines(vtt, lo, hi, limit=1)
    return got[0] if got else None


def pick_lines(vtt: str, lo: float = DEFAULT_LO, hi: float = DEFAULT_HI,
               limit: int = 4) -> list:
    """The best quotable lines, best first.

    More than one because a chosen line still has to be HEARD in the audio
    (`social_hear`) before it can be burned on screen, and a published
    subtitle file is often mistimed — so the caller needs somewhere to go
    when the first candidate is not what the film is saying.
    """
    ranked = []
    for start, end, text in parse_cues(vtt):
        if start < lo or start > hi:
            continue
        if end - start < 1.0 or end - start > 8.0:
            continue                      # too fast to read, or a held card
        if not quotable(text):
            continue
        t = text.strip().lstrip("- ").strip()
        cls = 0 if t.endswith("?") else (1 if t.endswith("!") else 2)
        rank = (cls, abs(len(t.split()) - 8), start)
        ranked.append((rank, {"start": start, "end": end, "text": t}))
    ranked.sort(key=lambda r: r[0])
    return [r[1] for r in ranked[:limit]]


if __name__ == "__main__":                                    # pragma: no cover
    import sys, urllib.request
    url = sys.argv[1] if len(sys.argv) > 1 else None
    if not url:
        print("usage: social_line.py <vtt-url>"); raise SystemExit(2)
    with urllib.request.urlopen(url, timeout=60) as r:
        line = pick_line(r.read().decode("utf-8", "replace"))
    print(line or "no quotable line in the first act")
