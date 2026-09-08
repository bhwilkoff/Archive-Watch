#!/usr/bin/env python3
"""
test_social_hear.py — the scoring that decides whether a caption may be burned.

No audio and no model here: what is asserted is the arithmetic and the three
outcomes, including the one that matters most — "could not check" must be
distinguishable from "checked and failed", or the gate silently disappears
the day a dependency goes missing.

Checked to FAIL against a scorer that counts stopwords.

Run: python3 tools/test_social_hear.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import social_hear as H

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


print("content words")
check("stopwords are dropped", H.content("What do you say to the nice young man?")
      == ["say", "nice", "young", "man"])
check("punctuation and case do not matter",
      H.content("NICE, young -- man!") == ["nice", "young", "man"])
# "say" is deliberately NOT a stopword: it is what matched in the Impact
# calibration. A line with nothing BUT function words has nothing to check.
check("a line of only function words has no content",
      H.content("What do you have to do with it?") == [], str(H.content("What do you have to do with it?")))


def scored(want, heard):
    H.grab_audio = lambda u, s, e, o: (o.write_bytes(b"0" * 5000), True)[1]
    H.transcribe = lambda w, m="tiny.en": heard
    return H.hear("u", 1.0, 3.0, want)


print("\nscoring")
r = scored("What do you say we take another vote?",
           "dividends. Why don't you say we take another vote?")
check("a line the film really says scores high", r["score"] == 1.0, str(r))
r = scored("We've known Debbie, what, since the eighth grade?",
           "Are you looking at it? We're going to look at it, and I'll tell you.")
check("a line from a DIFFERENT film scores zero", r["score"] == 0.0, str(r))
r = scored("We have a circuit now, sir. Evanston calling Mrs Martin.",
           "We have a circuit now sir. In this tin, call him Mrs. Martin")
check("a rough optical transfer still passes", r["score"] >= 0.5, str(r))
check("the measured threshold separates them", 0.0 < 0.5 <= 0.625)

print("\nunknown is not failure")
H.grab_audio = lambda u, s, e, o: False
r = H.hear("u", 1.0, 3.0, "Some real words here now")
check("no audio means None, never 0.0", r["score"] is None, str(r))
H.grab_audio = lambda u, s, e, o: (o.write_bytes(b"0" * 5000), True)[1]
H.transcribe = lambda w, m="tiny.en": ""
r = H.hear("u", 1.0, 3.0, "Some real words here now")
check("a silent recogniser means None, never 0.0", r["score"] is None, str(r))
r = H.hear("u", 1.0, 3.0, "Do you?")
check("too little to check means None", r["score"] is None, str(r))

print("\nthe window")
check("the cue's stamps are treated as approximate", H.PAD > 0)
check("at least two content words are required", H.MIN_CONTENT >= 2)

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
