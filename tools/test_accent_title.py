#!/usr/bin/env python3
"""Locks the accent-drop title rule (remediate_catalog._accent_dropped and its
adoption in _canonical_clean). First rows are the NEGATIVE controls: a
canonical that merely resembles the title must not be adopted by this door."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import remediate_catalog as rc

CASES = [
    # title, canonical, expected adoption via the accent door
    ("La fee des roches noires", "La fée des roches noires", False),   # transliterated, not deleted
    ("La fe des roches", "La fée des roches noires", False),           # shorter — a different string
    ("The Web", "The Web", False),                                     # no accent at all
    ("Les Vampires", "Les Vampires", False),
    ("La fe des roches noires", "La fée des roches noires", True),
    ("Le mystre des roches de Kador", "Le mystère des roches de Kador", True),
    ("Krlek och journalistik", "Kärlek och journalistik", True),
    ("h, i morron kvll", "Åh, i morron kväll", True),
    ("Faust et Mphistophls", "Faust et Méphistophélès", True),
    ("L'antique Tolde", "L'antique Tolède", True),
]
fails = 0
for title, canon, want in CASES:
    got = rc._accent_dropped(title, canon)
    ok = got == want
    fails += (not ok)
    print(("PASS" if ok else "FAIL"), repr(title), "->", got)
    if want:
        adopted = rc._canonical_clean({"title": title, "canonicalTitle": canon})
        if adopted != canon:
            fails += 1
            print("FAIL adoption", repr(title), "->", repr(adopted))
print(f"{len(CASES) - fails}/{len(CASES)} accent-title cases")
sys.exit(1 if fails else 0)
