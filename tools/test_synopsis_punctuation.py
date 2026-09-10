#!/usr/bin/env python3
"""A stray space before a comma or stop, and Wikipedia citation residue.

Measured on 565 published synopses: 45 (7%) carry the spacing fault. It shows
on every Detail screen on every platform and in every social post — the post
writers can only be as good as their input.

ELLIPSES ARE THE TRAP. A blunter first version treated ". . ." and ". ..." as
faults, which would have mangled 10 legitimate passages to fix 45. Every case
below that starts "keeps" was checked to FAIL against that version.

    python3 tools/test_synopsis_punctuation.py
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from remediate_catalog import _tidy_punctuation as tidy

CASES = [
    # (name, input, expected)
    ("space before a comma",
     "A for Andromeda , again written by Fred", "A for Andromeda, again written by Fred"),
    ("space before a full stop",
     "featuring Harold Lloyd . Prints exist", "featuring Harold Lloyd. Prints exist"),
    ("a citation marker with spaces",
     "Harold Lloyd . [ 1 ] Prints of the film", "Harold Lloyd. Prints of the film"),
    ("stacked citation markers",
     "and John Gilbert.[1][2] It was directed", "and John Gilbert. It was directed"),
    ("space before a semicolon and colon",
     "one thing ; and another : here", "one thing; and another: here"),

    # The ellipsis cases — these must come through UNCHANGED.
    ("keeps a spaced ellipsis",
     "gets kicked out . . . it looks bad", "gets kicked out . . . it looks bad"),
    ("keeps a stop followed by an ellipsis",
     "Bridey Murphy. ... After being shown", "Bridey Murphy. ... After being shown"),
    ("keeps an abbreviation",
     "joins the R.C.M.P. and gets kicked out", "joins the R.C.M.P. and gets kicked out"),
    ("keeps a decimal",
     "shot on 16.5 mm stock", "shot on 16.5 mm stock"),
    ("leaves clean text alone",
     "A notable Danish film, directed by Dreyer.", "A notable Danish film, directed by Dreyer."),
]

def main():
    p = f = 0
    for name, src, want in CASES:
        got = tidy(src)
        ok = got == want
        p, f = (p + 1, f) if ok else (p, f + 1)
        print(f"  {'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f"\n         got  {got!r}\n         want {want!r}"))
    print(f"\n{p} passed, {f} failed")
    return 1 if f else 0

if __name__ == "__main__":
    raise SystemExit(main())
