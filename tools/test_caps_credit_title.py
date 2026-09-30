#!/usr/bin/env python3
"""A collector's title in CAPITALS followed by its credits keeps only the
capitals, title-cased; titles without a credits tail are left alone."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

CASES = [
    ("A SAILOR MADE MAN Harold Lloyd Silent", "A Sailor Made Man"),
    ("THE LUCKY DOG A Stan Laurel Reelcraft Comedy", "The Lucky Dog"),
    ("CAPTAIN BLOOD J. Warren Kerrigan Abridged Silent Vitagraph Feature", "Captain Blood"),
    ("BRONCHO BILLY AND THE GREASER G. M. Anderson Silent An Essanay Film", "Broncho Billy and the Greaser"),
    ("FICKLE FLORA Our Gang Silent ( 9.5mm Footage From The First Our Gang C", "Fickle Flora"),
    ("YOU'RE ONLY YOUNG TWICE (Full Series)", "You're Only Young Twice"),
    # controls: no credits tail, or not capitals
    ("NASA SCI Files - The Scientific Method", "NASA SCI Files - The Scientific Method"),
    ("EAST OF BORNEO", "EAST OF BORNEO"),
    ("D.O.A.", "D.O.A."),
    ("The Silent Enemy", "The Silent Enemy"),
    ("GMT137 08 26 Jack-Fischer 88789J Nanoracks-137 DP014401", "GMT137 08 26 Jack-Fischer 88789J Nanoracks-137 DP014401"),
]
bad = [(i, R._caps_title_before_credits(i), w) for i, w in CASES if R._caps_title_before_credits(i) != w]
for b in bad:
    print("FAIL", b)
print(f"{len(CASES) - len(bad)}/{len(CASES)} caps-credit-title cases")

PREFIX = [
    ('Fifties Television: "Dr. Hudson\'s Secret Journal" - Dr. Means Surgery', '"Dr. Hudson\'s Secret Journal" - Dr. Means Surgery'),
    ('Artistic Masterpiece: "Howdy Doody" - 1 April', '"Howdy Doody" - 1 April'),
    ('1950\'s Pop Culture: "Howdy Doody" - April 6', '"Howdy Doody" - April 6'),
    ('"Sheriff of Cochise" - Husband and Wife (Format: iPod)', '"Sheriff of Cochise" - Husband and Wife'),
    ('"Ding Dong School" - Misc episode', '"Ding Dong School"'),
    # controls
    ("Diver Dan: Ep 22 Lost In The Sargasso Sea", "Diver Dan: Ep 22 Lost In The Sargasso Sea"),
    ("The Big Picture: The Korean War", "The Big Picture: The Korean War"),
    ("Unsold Television Pilot: \"Unsolved\"", "Unsold Television Pilot: \"Unsolved\""),
]
pbad = [(i, R._strip_editorial_prefix(i), w) for i, w in PREFIX if R._strip_editorial_prefix(i) != w]
for b in pbad:
    print("FAIL", b)
print(f"{len(PREFIX) - len(pbad)}/{len(PREFIX)} editorial-prefix cases")
sys.exit(1 if (bad or pbad) else 0)
