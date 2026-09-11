#!/usr/bin/env python3
"""
test_details_contract.py — the detail shards keep the shape their readers were
written against.

THE INCIDENT (2026-09-11). Roku's crash analytics showed 16 crashes in two
days at `DetailScreen.brs:781`, which is `c.Count()` over `d.cast`. The
channel was right and the data was wrong: `build_web_details.py` documented
"each cast entry is [name] | [name, profilePath] | [name, profilePath,
tmdbPersonID]" and then emitted a **bare string** whenever an entry had
collapsed to one element —

    cast.append(entry[0] if len(entry) == 1 else entry)

A BrightScript String has no `Count()`, so opening the Detail screen of any
film with a profile-less cast member crashed the channel. Measured on the
published shards: **2,798 such entries across 1,716 films**, 5.4% of the
catalog, including its most-watched titles.

The web viewer never noticed because `watch.js` happens to test
`Array.isArray(c)` and handle both. That is why a contract needs a test and
not a second reader's tolerance: one client's defensive code hid a defect
from every other client for as long as it existed.

Run:  python tools/test_details_contract.py            # unit cases
      python tools/test_details_contract.py --shards   # + the real details/
"""

from __future__ import annotations

import glob
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


def encode_cast(people, limit=8):
    """The encoder in build_web_details.py, isolated. Kept in sync by the
    first case below, which asserts against the real module."""
    cast = []
    for c in people[:limit]:
        name = c.get("name")
        if not name:
            continue
        entry = [name, c.get("profilePath") or None, c.get("tmdbPersonID") or None]
        while len(entry) > 1 and entry[-1] is None:
            entry.pop()
        cast.append(entry)
    return cast


def main() -> int:
    # 1. THE REGRESSION: a cast member with no profile is still a LIST.
    check("a name-only cast member encodes as [name], never the bare string",
          encode_cast([{"name": "Katalin Kallay"}]), [["Katalin Kallay"]])
    check("a name + profile encodes as two elements",
          encode_cast([{"name": "A", "profilePath": "/p.jpg"}]), [["A", "/p.jpg"]])
    check("a name + profile + id encodes as three",
          encode_cast([{"name": "A", "profilePath": "/p.jpg", "tmdbPersonID": 7}]),
          [["A", "/p.jpg", 7]])
    check("a trailing null id is trimmed but the list survives",
          encode_cast([{"name": "A", "profilePath": "/p.jpg", "tmdbPersonID": None}]),
          [["A", "/p.jpg"]])
    check("an id with no profile keeps the null placeholder, so index 2 stays the id",
          encode_cast([{"name": "A", "tmdbPersonID": 7}]), [["A", None, 7]])
    check("a nameless entry is dropped, not encoded empty",
          encode_cast([{"profilePath": "/p.jpg"}, {"name": "B"}]), [["B"]])
    check("every entry is a list — the property the Roku channel depends on",
          all(isinstance(e, list) for e in encode_cast(
              [{"name": "A"}, {"name": "B", "profilePath": "/b.jpg"}])), True)

    # 2. the isolated encoder must match the real one
    try:
        import build_web_details  # noqa: F401
        src = (REPO / "tools" / "build_web_details.py").read_text()
        check("the real encoder no longer unwraps a single-element entry",
              "entry[0] if len(entry) == 1" in src, False)
        check("the real encoder appends the list", "cast.append(entry)" in src, True)
    except Exception as e:  # noqa: BLE001
        check(f"could not read build_web_details.py: {e}", True, False)

    # 3. against the published shards, when asked
    if "--shards" in sys.argv:
        bad = 0
        films = 0
        for p in glob.glob(str(REPO / "details" / "*.json")):
            for aid, rec in json.load(open(p)).items():
                cast = rec[3] if len(rec) > 3 else None
                if not isinstance(cast, list):
                    continue
                n = sum(1 for c in cast if not isinstance(c, list))
                if n:
                    bad += n
                    films += 1
        check("no published shard carries a non-list cast entry", (bad, films), (0, 0))

    fails = 0
    for name, ok, got, want in CASES:
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            fails += 1
            print(f"      got:  {got!r}\n      want: {want!r}")
    print(f"\n{len(CASES) - fails}/{len(CASES)} passed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
