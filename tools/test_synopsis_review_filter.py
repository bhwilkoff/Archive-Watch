#!/usr/bin/env python3
"""A user's review filed as a plot is never adopted as a synopsis; plots that
merely mention viewers or begin with an "I ..." title are."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import synopsis_provenance as S

REVIEWS = [
    ("Some time back, I'd read about an invention they tried out in the 1940s.", ""),
    ("The Terrytoons are oddly interesting, mainly for anybody wanting to see them.", ""),
    ("It's true the existing print of this film is poor, but it deserves a restoration.", ""),
    ("This film is a treasure. It's one of the best examples of camouflage.", ""),
]
PLOTS = [
    ("I Walk Alone is a 1947 film noir released by Paramount Pictures.", "I Walk Alone"),
    ("The film is set in a bar on New Year's Eve. We see plenty of Germans swilling beer.", ""),
    ("A shipwrecked man's prolonged stay on a desert island.", ""),
    ("Soldiers of World War I. In the trenches, men wait for dawn.", ""),
    ('The Ponce Sisters perform two songs: "Too Busy" and "I\'d Rather Cry Over You."', ""),
    ('Krazy Kat sings "I am a bird man!" several times and straps a plank to each arm.', ""),
]
bad = [t for t, ti in REVIEWS if not S._REVIEW.search(t, ti)] + [t for t, ti in PLOTS if S._REVIEW.search(t, ti)]
for b in bad:
    print("FAIL", b)
print(f"{len(REVIEWS) + len(PLOTS) - len(bad)}/{len(REVIEWS) + len(PLOTS)} review-filter cases")
sys.exit(1 if bad else 0)
