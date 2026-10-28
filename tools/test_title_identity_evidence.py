#!/usr/bin/env python3
"""
test_title_identity_evidence.py — the cluster's own evidence names the wrong copy.

audit_title_identity acted only when an old film's copies split across the
modern/old IMDb id ranges; the 25 clusters open on 2026-10-28 were all two
LOW ids, so none was decided. Radio Ranch (69 min) wore the 245-minute
Phantom Empire serial; "The Magician" (79 min) a one-minute Méliès film;
BRONCHOBILLYANDTHEGREASERG.M.Anderson... wore Raoul Walsh.

Each rule needs a positive alternative in the cluster. Controls: a fragment of
the right film with no alternative that fits (Isn't Life Wonderful, 31 of 115
minutes), two distinct films that both fit their own files (the two 1928 Ushers
at 13 and 72 minutes), an upload that declared its own id, a director the
item's id names correctly.

Run: python3 tools/test_title_identity_evidence.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_title_identity as I  # noqa: E402

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


def m(aid, imdb, own_min, director=None, **kw):
    d = {"archiveID": aid, "imdbID": imdb, "fileRuntimeSeconds": own_min * 60 if own_min else None,
         "director": director, "title": kw.pop("title", "Radio Ranch"), "year": kw.pop("year", 1940),
         "contentType": "feature-film", "matchVerdict": "unverifiable"}
    d.update(kw)
    return d


OMDB = {"tt0032782": {"runtime_min": 70}, "tt0026867": {"runtime_min": 245},
        "tt0017103": {"runtime_min": 83}, "tt0214902": {"runtime_min": 1},
        "tt0015018": {"runtime_min": 115}, "tt0196644": {"runtime_min": 83},
        "tt0018873": {"runtime_min": 13}, "tt0018770": {"runtime_min": 72},
        "tt0191848": {"runtime_min": 15}}
VERIFY = {"1": {"year": 1940}, "2": {"year": 1935}, "3": {"year": 1924}}


def names(mem, year=1940, verify=None):
    return [it["archiveID"] for it, _ in I.evidenced_wrong(year, mem, OMDB, verify or {})]


radio = [m("RadioRanch", "tt0032782", 69), m("RadioRanch_201609", "tt0026867", 69)]
check("runtime: the serial on a feature-length file is named", names(radio) == ["RadioRanch_201609"],
      names(radio))
magic = [m("the-magician", "tt0017103", 71), m("the-magician-1926", "tt0214902", 79)]
check("runtime: a one-minute film on a 79-minute file is named", names(magic, 1926) == ["the-magician-1926"])
isnt = [m("silent-isnt-life-wonderful", "tt0015018", 115), m("isnt-life-wonderful-1924", "tt0015018", 31),
        m("IsntLifeWonderful", "tt0196644", 31)]
check("a fragment with no alternative that fits is not named (control)", names(isnt, 1924) == [],
      names(isnt, 1924))
usher = [m("Fall_of_the_House_of_Usher_1928_Watson", "tt0018873", 12),
         m("thefallofthehouseofusher1928", "tt0018770", 66)]
check("two distinct films that fit their own files: nothing named (control)", names(usher, 1928) == [])
usher.append(m("TheFallOfTheHouseOfUsher1928", "tt0018770", 12))
check("...and the 12-minute copy wearing the 72-minute film is", names(usher, 1928) == ["TheFallOfTheHouseOfUsher1928"])
declared = [m("RadioRanch", "tt0032782", 69), m("RadioRanch_201609", "tt0026867", 69, matchVerdict="verified")]
check("an upload that declared its id is never named (control)", names(declared) == [])

broncho = [m("BronchoBillyAndTheGreaser1914", "tt0191848", 16, "Gilbert M. Anderson", year=1914),
           m("BRONCHOBILLYANDTHEGREASERG.M.AndersonSil", "tt0210082", 16, "Raoul Walsh", year=1914)]
check("director: an id naming the other member's director is named",
      names(broncho, 1914) == ["BRONCHOBILLYANDTHEGREASERG.M.AndersonSil"], names(broncho, 1914))
right = [m("the-merry-widow-1925-directed-by-erich-von-stroheim", "tt0016104", None, "Erich von Stroheim", year=1925),
         m("the-merry-widow-1925", "tt0009771", None, "Michael Curtiz", year=1925)]
check("an id naming its OWN director is not named (control)",
      "the-merry-widow-1925-directed-by-erich-von-stroheim" not in names(right, 1925))

yr = [m("a", "tt1", None, tmdbID=1), m("b", "tt2", None, tmdbID=2)]
check("year: a match released five years off is named when another agrees",
      names(yr, 1940, VERIFY) == ["b"], names(yr, 1940, VERIFY))
check("year: nothing named when no member agrees (control)",
      names([m("a", "tt1", None, tmdbID=3), m("b", "tt2", None, tmdbID=2)], 1940, VERIFY) == [])

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
