#!/usr/bin/env python3
"""An uploader's tail on a title — a fullwidth-bar credit, an ALL-CAPS genre,
or a name from the item's OWN cast followed by a genre word — comes off; a
name that IS the title, or a caps title, stays (2026-09-16)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402

CASES = [
    ("Hell's House Bette Davis ｜ Drama", [], "Hell's House Bette Davis"),
    ("Fog Island ｜ Classic Mystery Thriller Movie", [], "Fog Island"),
    ("A Bride For Henry COMEDY", [], "A Bride For Henry"),
    ("Road To Happiness DRAMA", [], "Road To Happiness"),
    ("John Parker's DAUGHTER OF HORROR", [], "John Parker's DAUGHTER OF HORROR"),
    ("The Killer Shrews SCI FI HORROR", [], "The Killer Shrews SCI FI HORROR"),
    ("The Corpse Vanishes Bela Lugosi Horror", ["Bela Lugosi"], "The Corpse Vanishes"),
    ("Bluebeard John Carradine Crime", [{"name": "John Carradine"}], "Bluebeard"),
    ("War of the Wildcats - John Wayne", ["John Wayne"], "War of the Wildcats"),
    ("Try and Get Me Frank Lovejoy, Lloyd Bridges", ["Frank Lovejoy", "Lloyd Bridges"], "Try and Get Me"),
    ("High Heels - Mia Farrow, Jean-Paul Belmondo", ["Mia Farrow", "Jean-Paul Belmondo"], "High Heels"),
    # Controls: the name is the title, or follows with/by/for.
    ("Asi Cantaba Carlos Gardel", ["Carlos Gardel"], "Asi Cantaba Carlos Gardel"),
    ("Art Of Cake Decorating With Norman Wilton", ["Norman Wilton"], "Art Of Cake Decorating With Norman Wilton"),
    ("FILMING OTHELO by Orson Welles", ["Orson Welles"], "FILMING OTHELO by Orson Welles"),
    ("Cleopatra ( Fragment 2) Theda Bara", ["Theda Bara"], "Cleopatra ( Fragment 2) Theda Bara"),
    ("Daughter of Horror", [], "Daughter of Horror"),
    ("Beat The Devil Action", [], "Beat The Devil Action"),
]


def main():
    fails = 0
    for t, cast, want in CASES:
        it = {"title": t, "cast": cast, "archiveID": "x"}
        R.sanitize_title(it)
        ok = it["title"] == want
        fails += not ok
        print(f"{'ok ' if ok else 'FAIL'} {it['title']!r}")
    print(f"{len(CASES) - fails}/{len(CASES)} title-tail cases")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
