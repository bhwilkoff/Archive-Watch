#!/usr/bin/env python3
"""Credits as a viewer reads them: peerage labels off, one actor once, names-only directors."""
import sys
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

items = [
    {"cast": [{"name": "Oliver Hardy", "character": "Ollie"},
              {"name": "Charles Middleton, 1st Baron Barham", "character": None, "profilePath": "/noble.jpg"}],
     "director": "A. Edward Sutherland"},
    {"cast": [{"name": "Rodney Saulsberry", "character": "Announcer"},
              {"name": "Rodney Saulsberry", "character": "Narrator"}], "director": "Paul Julian/Les Goldman"},
    {"cast": [{"name": "The Earl Carroll Girls", "character": None}], "director": "Y.C. Zai/謝雲卿"},
    {"director": "Joseph Jones https://twitter"},
]
st = Counter()
R.tidy_credits(items, st)
bad = []
if items[0]["cast"][1] != {"name": "Charles Middleton", "character": None, "profilePath": None}: bad.append(items[0]["cast"])
if items[1]["cast"] != [{"name": "Rodney Saulsberry", "character": "Announcer / Narrator"}]: bad.append(items[1]["cast"])
if items[1]["director"] != "Paul Julian, Les Goldman": bad.append(items[1]["director"])
if items[2]["cast"][0]["name"] != "The Earl Carroll Girls": bad.append(items[2]["cast"])   # control: "Earl" is not a peerage here
if items[2]["director"] != "Y.C. Zai": bad.append(items[2]["director"])
if items[3]["director"] != "Joseph Jones": bad.append(items[3]["director"])
if items[0]["director"] != "A. Edward Sutherland": bad.append(items[0]["director"])        # control
for b in bad:
    print("FAIL", b)
print("PASS tidy credits" if not bad else "FAIL")
sys.exit(1 if bad else 0)
