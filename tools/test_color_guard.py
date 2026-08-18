#!/usr/bin/env python3
"""The color guard's behaviour, asserted — including what it must NOT do.

Decision 040 refuses to merge two same-titled copies whose color disagrees,
because a B&W original and a color remake are different works. Decision 084
narrows that to CONFIDENT readings, since the chroma statistic overlaps between
classes on faded prints. The negative control is the important row here: a
clean B&W reading against a clean color one must STILL block, or the fix has
quietly deleted the guard instead of narrowing it.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_sqlite import _color_compatible  # noqa: E402


def item(sat, mode, aid="x", title="t"):
    return {"colorMode": mode, "colorSat": sat, "archiveID": aid, "title": title}


CASES = [
    ("clean B&W vs clean color still BLOCKS",   item(0.0, "bw"),    item(22.0, "color"), False),
    ("marginal vs marginal allows the merge",   item(7.1, "bw"),    item(9.0, "color"),  True),
    ("clean bw vs MARGINAL color allows it",    item(0.0, "bw"),    item(9.0, "color"),  True),
    ("clean color vs marginal bw allows it",    item(22.0, "color"),item(7.6, "bw"),     True),
    ("unmeasured pair behaves as before",       item(None, "bw"),   item(None, "color"), False),
    ("agreeing readings are compatible",        item(7.1, "bw"),    item(0.0, "bw"),     True),
    ("unknown mode never contradicts",          item(None, None),   item(9.0, "color"),  True),
    ("a stated colorization beats a weak read", item(7.0, "bw"),
     item(9.0, "color", aid="silver-on-the-sage-1939-colorized"),                        False),
]


def main():
    failures = 0
    for name, a, b, want in CASES:
        got = _color_compatible(a, b)
        if got != want:
            failures += 1
            print(f"  FAIL {name}: compatible={got}, expected {want}")
        else:
            print(f"  ok   {name}")
    print(f"\n{len(CASES) - failures}/{len(CASES)} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
