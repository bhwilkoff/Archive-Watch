#!/usr/bin/env python3
"""
test_cleared_match_residue.py — a cleared match must leave nothing behind.

The defect: `verify_external_match` Tier 0c called `adopt(it, {})` to clear a
wrong modern match, and every branch of `adopt` is guarded by
`if rec.get(...)` — so an EMPTY record clears nothing at all. 266 items were
marked cleared while still wearing the other film's identity: 223 its
synopsis, 221 its release date, 187 its studios, 121 its vote count. A 1924
silent short was serving Scorsese's 1993 plot, tagline, Oscar, Columbia
Pictures credit and 73,037 IMDb votes.

Checked to FAIL against the leave-it-behind build.

Run: python3 tools/test_cleared_match_residue.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from remediate_catalog import strip_cleared_match_residue

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


def age_of_innocence():
    """The live item, verbatim in the fields that matter."""
    return {
        "archiveID": "the-age-of-innocence", "title": "The Age of Innocence",
        "matchVerdict": "cleared_modern", "modernPosterCleared": 1993,
        "imdbID": "tt0106226", "tmdbID": 10436, "imdbRating": 7.2,
        "imdbVotes": 73037, "releaseDate": "1993-09-10",
        "awards": "Won 1 Oscar. 15 wins & 33 nominations total",
        "studios": ["Columbia Pictures", "Cappa/De Fina Productions"],
        "cinematographer": "Michael Ballhaus", "composer": "Elmer Bernstein",
        "contentRating": "PG", "tagline": "In a world of tradition.",
        "canonicalTitle": "The Age of Innocence",
        "synopsis": "In 19th century New York high society...",
        "synopsisSource": "omdb",
        "backdropURL": "https://image.tmdb.org/t/p/w1280/x.jpg",
        # These are the 1924 film's OWN credits and must survive.
        "director": "Wesley Ruggles",
        "cast": [{"name": "Edith Roberts", "order": 0}],
        "posterURL": "https://commons.wikimedia.org/wiki/Special:FilePath/Beverly.jpg",
        "artworkSource": "commons", "hasRealArtwork": True,
    }


it = age_of_innocence()
check("it is recognised as unfinished business", strip_cleared_match_residue(it))
for f in ("imdbID", "tmdbID", "imdbRating", "imdbVotes", "releaseDate", "awards",
          "studios", "cinematographer", "composer", "contentRating", "tagline",
          "canonicalTitle", "synopsis", "backdropURL"):
    check(f"the other film's {f} is gone", not it.get(f), repr(it.get(f)))

print("\nwhat must survive")
check("the item's OWN director survives", it.get("director") == "Wesley Ruggles")
check("the item's OWN cast survives", bool(it.get("cast")))
check("a Commons poster survives — it did not come from the match",
      it.get("posterURL", "").startswith("https://commons."), repr(it.get("posterURL")))
check("and it is still flagged as real artwork", it.get("hasRealArtwork") is True)

print("\nwhat must NOT be touched")
tmdb_art = age_of_innocence()
tmdb_art.update(posterURL="https://image.tmdb.org/t/p/w500/y.jpg", artworkSource="tmdb")
strip_cleared_match_residue(tmdb_art)
check("a poster that DID come from the match is dropped", not tmdb_art.get("posterURL"))

clean = {"archiveID": "x", "matchVerdict": "cleared_modern", "director": "Someone"}
check("an item with nothing left to strip is left alone",
      strip_cleared_match_residue(clean) is False)

never = {"archiveID": "y", "imdbID": "tt0000001", "imdbVotes": 500,
         "synopsis": "A real synopsis.", "synopsisSource": "omdb"}
check("an item the verifier never cleared is NEVER touched",
      strip_cleared_match_residue(never) is False and never["imdbID"] == "tt0000001")

own = {"archiveID": "z", "matchVerdict": "cleared_modern", "imdbID": "tt1",
       "synopsis": "From the uploader.", "synopsisSource": "archive"}
strip_cleared_match_residue(own)
check("a synopsis from another source is kept", own.get("synopsis") == "From the uploader.")

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
