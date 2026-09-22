#!/usr/bin/env python3
"""An uploader's attribution must not fork one film into two cards.

The owner, 2026-09-22, having found two entries for one Buster Keaton short:
*"there are two different copies of 'The Scarecrow' (one with sound and one
without) ... Why are there two versions of the same movie that aren't folded
together as different versions that can be pulled in the versions picker?"*

MEASURED CAUSE. Decision 040's merge clusters by NORMALISED TITLE first and
only then asks `_same_film`. `Buster Keaton's "The Scarecrow"` keyed to
`busterkeatonsthescarecrow` and `The Scarecrow` to `scarecrow`, so the two were
never in the same cluster and `_same_film` — which returns True for that pair,
one carrying tt0011656 and the other none, runtimes 5% apart against a 40%
tolerance — was never consulted.

THE GUARD THIS FILE IS. The fix is narrow on purpose: a QUOTED run at the END
of a title is the title, and the words before it are the uploader naming the
star. Stripping any leading possessive instead would turn *Pandora's Box* into
`box`, and this asserts that it does not.
"""
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("bs", "tools/build_sqlite.py")
bs = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(bs)
except SystemExit:
    pass

CASES = [
    # The uploader convention: attribution outside, title inside, at the END.
    ('Buster Keaton\'s "The Scarecrow"', "scarecrow"),
    ('Charlie Chaplin\'s "Easy Street"', "easystreet"),
    ('Charlie Chaplin in "The Kid"', "kid"),
    ('"Metropolis"', "metropolis"),
    # An apostrophe INSIDE a double-quoted title is a letter, not a delimiter.
    ('Buster Keaton\'s "My Wife\'s Relations"', "mywifesrelations"),
    # …and the bare titles they must now cluster WITH.
    ("The Scarecrow", "scarecrow"),
    ("Easy Street", "easystreet"),
    # NOT touched: a possessive that is part of the title.
    ("Pandora's Box", "pandorasbox"),
    ("It's a Wonderful Life", "itsawonderfullife"),
    # NOT touched: a quoted nickname in the MIDDLE of a name. This is the case
    # that end-anchoring exists for.
    ("Al 'Scarface' Capone", "alscarfacecapone"),
    ("Nosferatu", "nosferatu"),
    # SINGLE QUOTES ARE DELIBERATELY NOT A DELIMITER, and this asserts it.
    # A single quote is an apostrophe far more often than a quote mark.
    # MEASURED against the real catalogue: handling it turned
    # `Let's Get Movin'` into `s Get Movin` and
    # `Excerpt from 'Art Linkletter's House Party'` into `s House Party`,
    # while every one of the 121 titles the rule is actually for uses double
    # quotes. The damage was real and the benefit was hypothetical.
    ("Let's Get Movin'", "letsgetmovin"),
    ("Alfred Hitchcock's 'The Lodger'", "alfredhitchcocksthelodger"),
]

fail = 0
print("Decision 040 — an attribution does not fork a film into two cards")
print()
for title, want in CASES:
    got = bs._dupe_title_key(title)
    if got == want:
        print(f"  PASS  {title!r} -> {got}")
    else:
        print(f"  FAIL  {title!r} -> {got}, wanted {want}")
        fail = 1

print()
# THE PAIR THAT STARTED IT, asserted as a pair rather than as two keys.
a = bs._dupe_title_key('Buster Keaton\'s "The Scarecrow"')
b = bs._dupe_title_key("The Scarecrow")
if a == b:
    print(f"  PASS  both Scarecrows cluster together ({a})")
else:
    print(f"  FAIL  the Scarecrows still cluster apart: {a} vs {b}")
    fail = 1

# AND THEY MUST ALSO PASS `_same_film`, or clustering them achieves nothing.
keaton = {"imdbID": "", "runtimeSeconds": 1085, "year": 1920}
anchor = {"imdbID": "tt0011656", "runtimeSeconds": 1140, "year": 1920}
if bs._same_film(keaton, anchor):
    print("  PASS  _same_film agrees they are one film")
else:
    print("  FAIL  _same_film refuses the pair, so the key change is inert")
    fail = 1

print()
# CONTROL — the check can fail. Without it these asserts prove only that the
# function runs (Decision 120's rule).
if bs._dupe_title_key("Pandora's Box") == "box":
    print("  FAIL  CONTROL — a bare possessive was stripped; over-merge risk")
    fail = 1
else:
    print("  PASS  CONTROL — a bare possessive is left alone")

print()
print("FAILED" if fail else "AN ATTRIBUTION NO LONGER FORKS A FILM.")
sys.exit(fail)
