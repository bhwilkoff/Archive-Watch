#!/usr/bin/env python3
"""
test_no_evidence_gate.py — an item we know NOTHING about is not public domain.

THE INSTRUCTION (owner, 2026-09-11): "we are trying to ONLY have public domain
videos within the app, so you should never have to ask whether or not to do a
rights audit. Those movies show up on every platform, so they are getting
through every gate we have ever set up."

The gate they were getting through was `unknown_year -> keep`. Decision 027's
rule is never to hide on a FAILED check — which is right, and which is not the
same thing as never having run one. An item with no year, no licence, no
external match and no release date has had nothing established about it at
all, and was being shown as public domain on every platform.

Measured on the live catalog: 4,579 such items were visible (14.4%). Sampling
found The Dick Van Dyke Show Season 5 (CBS), the 1979 JESUS Film, modern web
series and a DOS 6.2 demo.

THE CONTROLS ARE THE POINT, and they are first. A rule that hides 11% of a
catalog has to prove it spares what matters: an enriched canon film, a
government or Prelinger deposit, and anything carrying a single fact.

Run:  python3 tools/test_no_evidence_gate.py
"""

from __future__ import annotations

import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

from audit_rights import bucket, unevidenced, HIDE_BUCKETS  # noqa: E402

CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


def item(**kw):
    base = {"archiveID": "x", "title": "Something", "contentType": "feature-film",
            "rightsStatus": "public_domain"}
    base.update(kw)
    return base


def main() -> int:
    # ---- CONTROLS FIRST ----
    check("control: a dated film is untouched by this rule",
          unevidenced(item(year=1925)), False)
    check("control: an IMDb match is evidence",
          unevidenced(item(imdbID="tt0015648")), False)
    check("control: a TMDb match is evidence",
          unevidenced(item(tmdbID=12345)), False)
    check("control: a release date is evidence",
          unevidenced(item(releaseDate="1925-12-24")), False)
    check("control: a real licence is evidence",
          unevidenced(item(archiveLicense="http://creativecommons.org/publicdomain/zero/1.0/")),
          False)
    check("control: a Prelinger deposit is clear by ORIGIN",
          unevidenced(item(collections=["prelinger", "moviesandfilms"])), False)
    check("control: a government collection is clear by ORIGIN",
          unevidenced(item(collections=["nasa"])), False)

    # ---- THE RULE ----
    check("nothing known at all is unevidenced",
          unevidenced(item(collections=["feature_films_unsorted", "moviesandfilms"])), True)
    check("...and buckets as no_evidence",
          bucket(item(collections=["moviesandfilms"]))[0], "no_evidence")
    check("...which HIDES", bucket(item(collections=["moviesandfilms"]))[1], "hide")
    check("no_evidence is registered in HIDE_BUCKETS, or the reconcile un-hides it",
          "no_evidence" in HIDE_BUCKETS, True)

    # An empty collections list must not crash or accidentally match an origin
    check("no collections at all is still unevidenced", unevidenced(item()), True)

    # The dated path must still reach its own buckets, not this one
    check("a modern dated film keeps its own verdict",
          bucket(item(year=2011, rightsConfirmed=True))[0], "modern_copyright_confirmed")

    bad = 0
    for name, ok, got, want in CASES:
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            bad += 1
            print(f"      got:  {got!r}\n      want: {want!r}")
    print(f"\n{len(CASES) - bad}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
