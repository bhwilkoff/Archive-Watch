#!/usr/bin/env python3
"""URAA: a foreign film published after the age line is never recommended;
US, government, free-licence and public-domain-by-age items are not."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

R._ORIGIN = {"1": {"c": ["DE"], "l": "de"}, "2": {"c": ["GB", "US"], "l": "en"},
             "3": {"c": [], "l": "it"}, "4": {"c": ["GB"], "l": "en"}}
C = [
    ({"year": 1931, "tmdbID": 1}, True),                       # M
    ({"year": 1935, "tmdbID": 4}, True),                       # a British film
    ({"year": 1965, "tmdbID": 3}, True),                       # no country, Italian
    ({"year": 1950, "language": "spa"}, True),                 # unmatched, Spanish
    # controls
    ({"year": 1950, "tmdbID": 2}, False),                      # US co-production
    ({"year": 1925, "tmdbID": 1}, False),                      # public domain by age
    ({"year": 1950, "language": "English"}, False),
    ({"year": 1950, "language": ""}, False),                   # nothing known
    ({"year": 1950, "tmdbID": 1, "rightsCorroborated": True}, False),
    ({"year": 1950, "tmdbID": 1, "collections": ["fedflix"]}, False),
]
bad = [(c, bool(R.uraa_restored(c)), w) for c, w in C if bool(R.uraa_restored(c)) != w]
for b in bad:
    print("FAIL", b)
st = __import__("collections").Counter()
items = [{"year": 1931, "tmdbID": 1}]
R.flag_propaganda(items, st, table={})
if not (items[0].get("noRecommend") and items[0]["noRecommendReason"].startswith("URAA")):
    bad.append(("flag", items[0]))
print(f"{len(C) - len(bad)}/{len(C)} URAA cases" + ("" if bad else " + flag"))
sys.exit(1 if bad else 0)
