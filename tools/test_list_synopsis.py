#!/usr/bin/env python3
"""remediate survives a synopsis archive.org stored as a LIST of notes.

2026-09-30: is_adult_signal read item["synopsis"] with a regex before
sanitize_synopsis turned the list into text, and one Romanian item
(TovarasulMirceaAlbulescu...) took publish-db and the subtitle apply down."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

items = [{"archiveID": "x", "title": "Tovarasul", "year": 1980, "contentType": "short-film",
          "synopsis": ["Primul rand.", "Al doilea rand."]},
         {"archiveID": "y", "title": "Control", "year": 1950, "contentType": "feature-film",
          "synopsis": "An erotic short of the 1950s."}]
try:
    R.is_adult_signal(items[0])
    ok1 = True
except TypeError as e:
    ok1 = False
ok2 = R.is_adult_signal(items[1])
print(("PASS" if ok1 else "FAIL") + " a list synopsis does not crash the adult check")
print(("PASS" if ok2 else "FAIL") + " CONTROL: a string synopsis still reads as adult")
sys.exit(0 if ok1 and ok2 else 1)
