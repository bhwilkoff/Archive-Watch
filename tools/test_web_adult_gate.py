#!/usr/bin/env python3
"""
test_web_adult_gate.py — the web has no mature-content setting, so every
artifact it reads must already be the apps' default-off state (Decision 105),
judged by the ONE predicate, build_sqlite._is_adult.

Found 2026-09-10 by auditing the committed artifacts against that predicate:
two title-marker films in the detail shards (a looser local copy of the
rule), nine Playboy After Dark episodes in episodes-index.json (no gate at
all), and 32 web aliases forwarding a saved id to a mature survivor. Each
case below is one of those, plus the control that must keep passing.

Run:  python tools/test_web_adult_gate.py
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

from build_sqlite import _is_adult  # noqa: E402
import build_episode_index as E  # noqa: E402

CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


def main() -> int:
    # The predicate itself: the two shard leaks were title markers the local
    # copy in build_web_details never looked at.
    check("control: a plain film is not mature",
          _is_adult({"title": "Suddenly", "collections": ["feature_films"]}), 0)
    check("a 'Porno' title is mature by the shared predicate",
          _is_adult({"title": "Le Notti Porno Nel Mondo", "collections": ["feature_films"]}), 1)
    check("the item flag alone is enough", _is_adult({"title": "X", "isAdult": True, "collections": []}), 1)
    check("a fav-<user> list containing 'adult' is NOT a marker (Mon Oncle stays)",
          _is_adult({"title": "Mon Oncle", "collections": ["fav-adult_z"]}), 0)

    # The episode index gate, driven by a synthetic catalog.
    E.CATALOG = REPO / "nonexistent-catalog.json"   # no rows: title-only path
    gate = E._mature_gate()
    check("control: an ordinary episode stays",
          gate("ep1", "the-lucy-show", "Lucy and Viv", "The Lucy Show"), False)
    check("an episode whose SERIES title trips the marker is withheld",
          gate("ep2", "some-show", "Episode 3", "Hardcore Porno Nights"), True)
    check("an episode whose OWN title trips the marker is withheld",
          gate("ep3", "some-show", "XXX Special", "Some Show"), True)

    bad = 0
    for name, ok, got, want in CASES:
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            bad += 1
            print(f"      got {got!r} want {want!r}")
    print(f"\n{len(CASES) - bad}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
