#!/usr/bin/env python3
"""A Wikipedia lead names its film and year; when both disagree with the
item it is the wrong article. Cases from 2026-09-16."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402

CASES = [
    # A release title inside fifteen years is the same film (The Curse of Greed IS The Twin Pawns).
    ("The Curse of Greed", 1914, "silent-the-curse-of-greed", "The Twin Pawns is a 1919 American silent drama film.", False),
    ("A Heart of Gold!", 2022, "mnn_906717_187", "Heart of Gold is a 1923 Spanish silent film.", True),
    ("1977 Pentru Patrie", 1914, "pentru-patrie-1977-3-h-12", "Patrie is a 1917 French film by Albert Capellani.", True),
    ("The Hands of Orlac", 1928, "the-hands-of-orlac_1928", "The Hands of Orlac is a 1924 Austrian silent film.", False),
    ("Wien", 1910, "1943-Wien-1910", "Vienna 1910 is a 1943 German biographical film.", False),
    ("Teenage Monster", 1958, "teenage-monster", "Teenage Monster is a 1957 American science fiction-horror Western film.", False),
]


def main():
    fails = 0
    for t, y, aid, syn, want in CASES:
        got = R._wiki_lead_is_another_film({"title": t, "year": y, "archiveID": aid}, syn)
        ok = got == want
        fails += not ok
        print(f"{'ok ' if ok else 'FAIL'} {t} -> {got}")
    print(f"{len(CASES) - fails}/{len(CASES)} wikipedia-lead cases")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
