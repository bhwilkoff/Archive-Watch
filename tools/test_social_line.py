#!/usr/bin/env python3
"""
test_social_line.py — the line a teaser is built on must be quotable.

Every rejection below is a line the picker ACTUALLY CHOSE from a real
published VTT before the rule existed. This is a record of what machine
transcription of 1930s film audio really contains, not a guess at it.
"""
import importlib.util, pathlib, sys

spec = importlib.util.spec_from_file_location(
    "sl", pathlib.Path(__file__).with_name("social_line.py"))
sl = importlib.util.module_from_spec(spec); spec.loader.exec_module(sl)

REJECT = [
    ("(dramatic music)",                       "a sound cue is not dialogue"),
    ("[door slams]",                           "bracketed sound cue"),
    ("♪ And I think to myself ♪",    "song lyric marker"),
    ("- That was robot. - Doctor Sockman.",    "two speakers in one cue"),
    ("THE END",                                "title card, all caps"),
    ("Certainly.",                             "too short to carry alone"),
    ("around those eyes and of the mouth?",    "opens lowercase — tail of the previous cue"),
    ("And I rented the house of the bewitched hill...", "trails off, thought unfinished"),
    ("There's work to be done on it,",         "ends on a comma"),
    ("A very long line indeed that simply keeps going and going past what will ever fit on a phone screen.",
                                                "too long to burn legibly"),
]
KEEP = [
    "We've known Debbie, what, since the eighth grade?",
    "I can control it or destroy it as I please.",
    "And you shall see and tell them.",
    '"You must never open that door."',
]

fails = 0
for text, why in REJECT:
    ok = not sl.quotable(text)
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  refuse ({why}): {text[:52]}")
for text in KEEP:
    ok = sl.quotable(text)
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  keep: {text[:60]}")

# Ordering: a question wins over a statement, because it stops a scroll.
VTT = """WEBVTT

1
00:01:30.000 --> 00:01:33.000
The robot is finished and it works.

2
00:02:10.000 --> 00:02:13.000
Are you certain you want to open it?
"""
pick = sl.pick_line(VTT)
ok = pick and pick["text"].endswith("?")
if not ok: fails += 1
print(f"  {'ok  ' if ok else 'FAIL'}  a question outranks a statement  — {pick and pick['text']}")

# The window: nothing before 60s (titles/idents) or after the first act.
EARLY = VTT.replace("00:01:30.000", "00:00:20.000").replace("00:02:10.000", "00:00:25.000")
ok = sl.pick_line(EARLY) is None
if not ok: fails += 1
print(f"  {'ok  ' if ok else 'FAIL'}  refuses the title sequence (before 60s)")

total = len(REJECT) + len(KEEP) + 2
print(f"\n{total - fails}/{total} passed")
sys.exit(0 if fails == 0 else 1)
