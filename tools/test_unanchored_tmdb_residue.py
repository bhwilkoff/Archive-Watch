#!/usr/bin/env python3
"""TMDb credit rows on an item with NO surviving external id are residue of a
cleared match, unless the reverse lookup proves they are this film's own.
The per-item strip is tested here; the keep side (cast_residue_fixes' title
anchor) is measured against the live caches, not unit-fixtured.

The live case: rog561b_netzero_501, a NetZero commercial reel titled "501",
wore the 2008 Danish film "501" — director, writer, studio, release date,
Danish language, ten cast rows with TMDb person ids (2026-09-16)."""
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from remediate_catalog import strip_unanchored_tmdb_residue

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


def reel():
    return {"archiveID": "rog561b_netzero_501", "title": "501", "contentType": "feature-film",
            "imdbID": None, "tmdbID": None, "metaSource": "tmdb", "languageSource": "tmdb",
            "language": "da", "director": "Jesper Maintz", "writer": "Thomas Glud",
            "studios": ["Ja Film"], "releaseDate": "2008-09-01", "imdbRating": 5.5, "imdbVotes": 20,
            "genres": ["Short", "Comedy", "Drama"], "canonicalTitle": "501",
            "cast": [{"name": "Troels Thorsen", "character": "Kim", "order": 0, "tmdbPersonID": 1442697},
                     {"name": "Claus Lund", "character": "Lars", "order": 2}]}


it = reel()
check("reel is stripped", strip_unanchored_tmdb_residue(it) is True)
check("cast gone", it["cast"] == [], str(it["cast"]))
check("director gone", not it.get("director"))
check("writer/studios/releaseDate/rating gone",
      not any(it.get(k) for k in ("writer", "studios", "releaseDate", "imdbRating", "imdbVotes", "canonicalTitle")))
check("language gone", it.get("language") is None and it.get("languageSource") is None)
check("genres emptied for the subject fill", it["genres"] == [])
check("metaSource cleared", it.get("metaSource") is None)
check("marker set", it.get("matchResidueCleared") is True)

# Controls.
anchored = dict(reel(), tmdbID=12345)
check("an item WITH a tmdbID is untouched", strip_unanchored_tmdb_residue(copy.deepcopy(anchored)) is False)
spine = dict(reel(), tmdbID=None, tvmazeID=77, contentType="tv-series")
check("a TV spine card (tvmazeID) is untouched", strip_unanchored_tmdb_residue(copy.deepcopy(spine)) is False)
archive = {"archiveID": "x", "title": "Home Movie", "contentType": "ephemeral", "metaSource": None,
           "director": "Uncle Bob", "cast": [{"name": "Aunt May"}]}
a2 = copy.deepcopy(archive)
check("bare-name Archive credits with no TMDb stamp stay", strip_unanchored_tmdb_residue(a2) is False and a2["director"] == "Uncle Bob")
mixed = dict(reel(), metaSource=None, cast=[{"name": "Aunt May"}, {"name": "Greg Hsu", "character": "Zhou"}])
strip_unanchored_tmdb_residue(mixed)
check("a bare-name row survives beside a stripped TMDb row", [c["name"] for c in mixed["cast"]] == ["Aunt May"], str(mixed["cast"]))
check("director goes with the TMDb rows even without metaSource", not mixed.get("director"))

print(f"{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
