#!/usr/bin/env python3
"""
test_roku_legacy_syntax.py — which components a legacy Roku will REFUSE, and why.

THE MEASUREMENT (2026-09-11). The owner asked whether the channel could run on
their Roku 2 XD. Developer mode was enabled on the box and the package
sideloaded to it; Roku OS 9.1.0 answered precisely:

    Install Failure: Error parsing multiple XML components
    (CatalogService, ChannelsScreen, HomeTask, SearchScreen, SeriesScreen,
     VersionsTask)

Six of twenty-nine components. The message says XML, and the XML is fine —
Python's own parser reads all 29 without complaint, the field types and node
types in the six are the same ones the other 23 use, and a failing Task is
structurally identical to a passing one. What the six actually share is a
BrightScript statement the firmware does not have: **`continue for`**, 34
occurrences, every one the same guard idiom.

The correlation is EXACT — the set of files containing `continue for` is the
set the device named, with no false positives and no false negatives. That is
what makes this a root cause rather than a suspicion.

WHY IT MATTERS BEYOND ONE BOX. The channel's manifest deliberately refuses
`rsg_version=1.3` to keep the firmware floor low, because "an archive of
public-domain film is exactly the app that should run on the cheap old box
somebody already owns". One language feature, adopted without noticing, undid
that for every Roku below the version that introduced it.

REPORT-ONLY by default, because 34 occurrences exist today and a gate that
fails the moment it lands is a gate somebody disables (Decision 107). Run with
`--strict` once they are gone, and wire that into CI so the floor stays where
the manifest says it is.

    python3 tools/test_roku_legacy_syntax.py            # report + self-test
    python3 tools/test_roku_legacy_syntax.py --strict   # non-zero if any found
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Each pattern is a construct MEASURED to break, or documented as newer than
# the floor the manifest keeps. `continue for` is the one the device named.
PATTERNS = {
    "continue for/while": re.compile(r"\bcontinue\s+(?:for|while)\b"),
    "optional chaining ?. ?[": re.compile(r"\?\.|\?\["),
    "null coalescing ??": re.compile(r"\?\?"),
}

# The device's own verdict, kept so the checker can prove itself against a
# real observation rather than its own opinion.
DEVICE_REFUSED = {"CatalogService", "ChannelsScreen", "HomeTask",
                  "SearchScreen", "SeriesScreen", "VersionsTask"}


def scan(root: str) -> dict:
    found = {}
    for path in sorted(glob.glob(os.path.join(root, "roku", "**", "*.brs"),
                                 recursive=True)):
        text = open(path, encoding="utf-8", errors="replace").read()
        hits = {}
        for name, pat in PATTERNS.items():
            n = len(pat.findall(text))
            if n:
                hits[name] = n
        if hits:
            found[os.path.basename(path)[:-4]] = hits
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true",
                    help="exit non-zero if any legacy-breaking syntax remains")
    a = ap.parse_args()

    found = scan(REPO)

    # SELF-TEST FIRST, with a negative control. A checker that cannot be shown
    # to catch the thing is not evidence of its absence.
    ok = True
    probe = 'for each r in rows\n  if r = 1 then continue for\nend for\n'
    control = 'for each r in rows\n  if r <> 1 then doThing(r)\nend for\n'
    if not PATTERNS["continue for/while"].search(probe):
        print("FAIL self-test: the pattern does not match a real `continue for`")
        ok = False
    if PATTERNS["continue for/while"].search(control):
        print("FAIL self-test: the pattern matches a loop that has none")
        ok = False
    if ok:
        print("PASS self-test: flags `continue for`, and a plain guard loop is clean")

    if not found:
        print("\nno legacy-breaking BrightScript found — the floor is where the "
              "manifest says it is")
        return 0 if ok else 1

    total = sum(sum(h.values()) for h in found.values())
    print(f"\n{len(found)} component(s), {total} occurrence(s) a pre-OS-11 Roku "
          f"cannot compile:\n")
    for comp in sorted(found):
        detail = ", ".join(f"{k} x{v}" for k, v in sorted(found[comp].items()))
        mark = "device refused it" if comp in DEVICE_REFUSED else "NOT yet seen to fail"
        print(f"  {comp:20} {detail:28} ({mark})")

    # The strongest check available: does the static finding reproduce the
    # device's own verdict exactly?
    if DEVICE_REFUSED:
        if set(found) == DEVICE_REFUSED:
            print("\nEXACT MATCH with the Roku OS 9.1 install failure of "
                  "2026-09-11 — every refused component is explained, and no "
                  "unrefused one is implicated.")
        else:
            print(f"\nNOTE: static finding {sorted(set(found))} differs from the "
                  f"2026-09-11 device verdict {sorted(DEVICE_REFUSED)} — the code "
                  f"has moved since, so re-measure on hardware before trusting "
                  f"either.")
    if a.strict:
        return 1
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
