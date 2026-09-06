#!/usr/bin/env python3
"""
test_tv_rights_gate.py — a TV episode must be judged before it is ingested.

There was no such judgement, which is how a 1993 Hanna-Barbera show reached
the app as public domain: audit_rights.py runs over catalog.json, and
episodes are not catalog items. Run:  python tools/test_tv_rights_gate.py
"""
from __future__ import annotations
import sys
from pathlib import Path
REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from backfill_tv_episodes import rights_ok  # noqa: E402
import audit_rights as AR  # noqa: E402

CASES = []
def check(name, got, want): CASES.append((name, got == want, got, want))


def main() -> int:
    old = {"yearStart": 1959}          # One Step Beyond
    new = {"yearStart": 1993}          # 2 Stupid Dogs

    # The reported failure, exactly: a modern show with no licence at all.
    check("modern show, no licence, is REFUSED",
          rights_ok({}, new), False)
    check("pre-1978 is kept without a network claim",
          rights_ok({}, old), True)
    check(f"the cutoff is the film audit's MODERN ({AR.MODERN})",
          rights_ok({}, {"yearStart": AR.MODERN - 1}), True)

    # The item's OWN year wins over the show's, because a spine's yearStart is
    # the show's first season and an upload can be anything.
    check("the item's own year overrides the show's",
          rights_ok({"year": "1994"}, old), False)
    check("a pre-cutoff item under a modern show is kept",
          rights_ok({"year": "1961"}, new), True)

    # Government collections are public domain whatever the year.
    gov = sorted(AR.GOV)[0]
    check(f"a government collection ({gov}) is kept",
          rights_ok({"year": "2020", "collection": [gov]}, new), True)
    check("a string collection field is handled",
          rights_ok({"year": "2020", "collection": gov}, new), True)

    # Licences: only the free-culture variants rescue a MODERN work, and the
    # old-style bare publicdomain URL does not (uploaders claim it on studio
    # films). These are license_rescues' rules, asserted here so a change to
    # them is visible from the TV side too.
    check("CC0 rescues a modern episode",
          rights_ok({"year": "1993",
                     "licenseurl": "http://creativecommons.org/publicdomain/zero/1.0/"}, new),
          True)
    check("a bare publicdomain claim does NOT rescue a modern episode",
          rights_ok({"year": "1993",
                     "licenseurl": "http://creativecommons.org/licenses/publicdomain/"}, new),
          False)
    check("CC-BY-NC does NOT rescue a modern episode",
          rights_ok({"year": "1993",
                     "licenseurl": "http://creativecommons.org/licenses/by-nc/4.0/"}, new),
          False)
    check("CC-BY rescues a modern episode",
          rights_ok({"year": "1993",
                     "licenseurl": "http://creativecommons.org/licenses/by/4.0/"}, new),
          True)

    # A show with no year at all must not be a loophole.
    check("an unknown year on a modern-looking item is refused",
          rights_ok({"year": "2011"}, {}), False)
    check("no year anywhere is kept (nothing to judge on)",
          rights_ok({}, {}), True)

    bad = [c for c in CASES if not c[1]]
    for n, ok, g, w in CASES:
        print(f"  {'PASS' if ok else 'FAIL'}  {n}" + ("" if ok else f"\n        got {g!r}, want {w!r}"))
    print(f"\n{len(CASES)-len(bad)}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
