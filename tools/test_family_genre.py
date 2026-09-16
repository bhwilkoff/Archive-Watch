#!/usr/bin/env python3
"""Family is a SUBJECT-only genre: a film ABOUT a family, or a home movie OF
one, is not family entertainment. `genres_from_subjects` used to match the
map's keywords against the title too, so "The Family Doctor" and a Prelinger
"Home Movie: Ohio Family" were tagged Family (2026-09-16, the metadata audit).
The remediate pass also DROPS a Family tag it can no longer vouch for on an
item with no external id."""
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402

CASES = [
    ({"title": "The Family Doctor", "subjects": []}, False),
    ({"title": "Home Movie: Ohio Family", "subjects": ["home movies", "prelinger"]}, False),
    ({"title": "Tomorrow's Children", "subjects": ["eugenics"]}, False),
    ({"title": "Untitled", "subjects": ["children's films"]}, True),
    ({"title": "Untitled", "subjects": ["family"]}, False),
    ({"title": "Untitled", "subjects": ["families", "home movies"]}, False),
    ({"title": "Untitled", "subjects": ["family films"]}, True),
    ({"title": "Untitled", "subjects": ["Children's television programs"]}, True),
]


def main():
    fails = 0
    for it, want in CASES:
        got = "Family" in R.genres_from_subjects(it)
        ok = got == want
        fails += not ok
        print(f"{'ok ' if ok else 'FAIL'} {it['title']!r} subjects={it['subjects']} family={got}")

    # The drop rule inside remediate: an already-tagged item loses Family when
    # the subjects do not carry it and nothing external could have set it.
    base = {"archiveID": "hm-ohio-family", "title": "Home Movie: Ohio Family", "subjects": ["home movies"],
            "contentType": "ephemeral", "genres": ["Family"], "year": 1962, "downloadURL": "https://x/y.mp4"}
    keep = dict(base, archiveID="tt-keep", tmdbID=123, metaSource="tmdb")
    items = [copy.deepcopy(base), copy.deepcopy(keep)]
    R.remediate(items)
    a, b = items
    ok1 = "Family" not in (a.get("genres") or [])
    ok2 = "Family" in (b.get("genres") or [])
    fails += (not ok1) + (not ok2)
    print(f"{'ok ' if ok1 else 'FAIL'} remediate drops Family on the no-id home movie -> {a.get('genres')}")
    print(f"{'ok ' if ok2 else 'FAIL'} remediate keeps a TMDb-sourced Family tag -> {b.get('genres')}")
    print(f"{len(CASES) + 2 - fails}/{len(CASES) + 2} family-genre cases")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
