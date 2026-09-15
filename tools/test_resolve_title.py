#!/usr/bin/env python3
"""The title resolver's scoring, pinned against the wrong match that put a
Minnie Mouse slideshow into Party Play as the 1922 film *Minnie*
(2026-09-14). Each case is the search response archive.org actually gave,
reduced to the fields the scorer reads. Negative controls first: the real
film must still resolve, or the guard is a guard against everything."""
import sys
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

GALLERY = {"identifier": "cartoon-female-image-gallery-11-minnie-mouse-and-daisy-duck",
           "title": "Cartoon Female Image Gallery #11 - Minnie Mouse and Daisy Duck",
           "downloads": 301}
REAL = {"identifier": "minnie-1922-marshall-neilan", "title": "Minnie (1922)",
        "year": "1922", "downloads": 120}
DURAN = {"identifier": "duran-duran-new-moon-on-monday-edit-version-1",
         "title": "Duran Duran New Moon On Monday (Edit Version 1)", "downloads": 2000}
NEWMOON = {"identifier": "new-moon-1930", "title": "New Moon 1930 Grace Moore Lawrence Tibbett",
           "year": "1930", "downloads": 400}
LEATHERNECK = {"identifier": "the-leatherneck-1929",
               "title": "The Leatherneck (1929) Reels Two & Five (Restored Sound From Vitaphone Discs)",
               "year": "1929", "downloads": 50}
LONGWANT_NOYEAR = {"identifier": "the-cabinet-of-dr-caligari", "title": "The Cabinet of Dr. Caligari",
                   "downloads": 9000}

CASES = [
    # (want title, want year, search docs, expected identifier or None)
    ("Minnie", 1922, [REAL], REAL["identifier"]),                       # control: the film resolves
    ("Minnie", 1922, [GALLERY], None),                                  # the slideshow does not
    ("Minnie", 1922, [GALLERY, REAL], REAL["identifier"]),              # and never outranks it
    ("New Moon", 1930, [DURAN], None),                                  # two-word want, pop video
    ("New Moon", 1930, [DURAN, NEWMOON], NEWMOON["identifier"]),        # the film with cast names + year
    ("The Leatherneck", 1929, [LEATHERNECK], LEATHERNECK["identifier"]),  # extras but its year agrees
    ("The Cabinet of Dr. Caligari", 1920, [LONGWANT_NOYEAR], LONGWANT_NOYEAR["identifier"]),  # long want, no year: still fine
]


def main():
    fails = 0
    for want, year, docs, expect in CASES:
        with mock.patch.object(A, "adv_search", return_value=docs):
            got, score, _ = A.resolve_title(want, year, session=None)
        ok = got == expect
        fails += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} {want!r:32} -> {got!r:52} score={score}")
    print(f"resolve_title: {len(CASES) - fails}/{len(CASES)} pass")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
