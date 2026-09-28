#!/usr/bin/env python3
"""
test_scrub_cleared_match.py — a cleared match leaves nothing it filled that the
Archive item itself does not vouch for.

Owner, 2026-09-28: "All inaccurate information should be scrubbed from the
database. Unless it is somehow verified, keeping bad info on "junk uploads"
doesn't seem helpful to anyone." A two-minute cable-outage clip kept the year
1916 from a cleared match and sat on the silent-era shelves.

Ends with a CONTROL: the same cases run through a scrub that does nothing must
fail, or the assertions prove nothing.

Run: python3 tools/test_scrub_cleared_match.py
"""
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402

OWN = {
    "outage-clip": {"year": None, "director": None, "creator": "someuploader", "mentioned": []},
    "notld-upload": {"year": None, "director": None, "creator": None, "mentioned": [1968]},
    "wrong-year": {"year": 1976, "director": None, "creator": "Paul Kyriazi", "mentioned": []},
    "Keaton1921Short": {"year": None, "director": None, "creator": None, "mentioned": []},
    "credited": {"year": 1950, "director": "Roy William Neill", "creator": None, "mentioned": []},
    "wd-film": {"year": None, "director": None, "creator": None, "mentioned": []},
    "doa-upload": {"year": None, "director": None, "creator": None, "mentioned": []},
    "dividend-upload": {"year": 1941, "director": "Vincent Minnelli", "creator": "MGM", "mentioned": []},
}

# Other copies of the same films whose matches are live (sibling_index shape).
SIBLINGS = R.sibling_index([
    {"title": "doa upload", "year": 1949, "director": "Rudolph Maté", "genres": ["Film-Noir"],
     "imdbID": "tt0042369", "matchVerdict": "verified"},
    {"title": "dividend upload", "year": 1951, "director": "Vincente Minnelli", "genres": [],
     "imdbID": "tt0043529", "matchVerdict": "unverifiable"},
    # A cleared sibling is no witness.
    {"title": "outage clip", "year": 1916, "genres": ["Drama"], "imdbID": "tt9",
     "matchVerdict": "cleared_runtime"},
])


def base(aid, **kw):
    it = {"archiveID": aid, "title": aid.replace("-", " "), "year": 1916, "decade": 1910,
          "isSilentFilm": True, "contentType": "silent-film", "genres": ["Drama"],
          "director": "Somebody Else", "collections": [], "subjects": [],
          "runtimeSeconds": 120, "fileRuntimeSeconds": 120, "imdbID": None, "tmdbID": None,
          "matchVerdict": "cleared_runtime"}
    it.update(kw)
    return it


CASES = [
    # (name, item, expectations)
    ("unvouched year, type and genres go", base("outage-clip"),
     {"year": None, "decade": None, "contentType": "short-film", "genres": [], "director": None}),
    ("a year the uploader's description states stays", base("notld-upload", year=1968, decade=1960,
                                                           contentType="feature-film", isSilentFilm=False,
                                                           runtimeSeconds=5760, fileRuntimeSeconds=5760),
     {"year": 1968}),
    ("the Archive's own year replaces the match's", base("wrong-year", year=1916),
     {"year": 1976, "decade": 1970, "director": None}),
    ("a year the archive id names stays", base("Keaton1921Short", year=1921),
     {"year": 1921, "contentType": "silent-film"}),
    ("a director the Archive credits stays", base("credited", year=1950, director="Roy William Neill",
                                                  contentType="feature-film", runtimeSeconds=4000,
                                                  fileRuntimeSeconds=4000),
     {"director": "Roy William Neill", "year": 1950}),
    ("Wikidata-anchored identity is left alone", base("wd-film", discoverySource="wikidata"),
     {"year": 1916, "director": "Somebody Else", "genres": ["Drama"]}),
    ("a re-matched item has a new identity and is left alone", base("outage-clip", imdbID="tt0000001"),
     {"year": 1916, "genres": ["Drama"], "director": "Somebody Else"}),
    ("an item nobody fetched keeps year and director (unknown is not wrong)", base("not-in-cache"),
     {"year": 1916, "director": "Somebody Else", "genres": []}),
    ("an item whose match was never cleared is untouched", base("outage-clip", matchVerdict="verified"),
     {"year": 1916, "genres": ["Drama"]}),
    ("a live-matched copy of the same film keeps its year; its genres, not others",
     base("doa-upload", year=1949, decade=1940, contentType="feature-film", genres=["Film-Noir", "Western"],
          director="Rudolph Maté", runtimeSeconds=5000, fileRuntimeSeconds=5000),
     {"year": 1949, "genres": ["Film-Noir"], "director": "Rudolph Maté"}),
    ("a sibling's year beats the uploader's wrong date; a misspelled credit still vouches",
     base("dividend-upload", year=1951, decade=1950, contentType="feature-film", director="Vincente Minnelli",
          genres=[], runtimeSeconds=5500, fileRuntimeSeconds=5500),
     {"year": 1951, "director": "Vincente Minnelli"}),
]


def run(scrub):
    fails = 0
    for name, item, want in CASES:
        it = copy.deepcopy(item)
        scrub(it, OWN, SIBLINGS)
        bad = {k: (it.get(k), v) for k, v in want.items() if it.get(k) != v}
        print(("  PASS  " if not bad else "  FAIL  ") + name + (f"  {bad}" if bad else ""))
        fails += bool(bad)
    return fails


print("scrub_cleared_match:")
fails = run(R.scrub_cleared_match)

# Recorded evidence and idempotence.
it = base("outage-clip")
R.scrub_cleared_match(it, OWN)
rec_ok = it.get("scrubbedFields") == ["contentType", "director", "genres", "year"] and it.get("yearWas") == 1916
print(("  PASS  " if rec_ok else "  FAIL  ") + f"scrubbedFields/yearWas recorded {it.get('scrubbedFields')} {it.get('yearWas')}")
again = R.scrub_cleared_match(it, OWN)
print(("  PASS  " if again == [] else "  FAIL  ") + f"a second build changes nothing ({again})")
fails += (not rec_ok) + (again != [])

print("control (a scrub that does nothing):")
ctl = run(lambda it, own, sib: [])
ctl_ok = ctl == 4   # the four cases where a scrub has something to remove
print(("PASS" if ctl_ok else "FAIL") + f": control fails {ctl} case(s), as it should")

print("control (no sibling witness):")
ctl2 = run(lambda it, own, sib: R.scrub_cleared_match(it, own, None))
ctl2_ok = ctl2 == 2   # D.O.A.'s year and Minnelli's credit would be lost
print(("PASS" if ctl2_ok else "FAIL") + f": without siblings {ctl2} case(s) fail, as they should")

sys.exit(1 if fails or not ctl_ok or not ctl2_ok else 0)
