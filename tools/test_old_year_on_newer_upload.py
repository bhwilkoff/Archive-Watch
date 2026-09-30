#!/usr/bin/env python3
"""A silent-era year on an upload whose own naming says a later year is a
borrowed year (a namesake's), and it is the whole case for public domain by
age. Each case pairs with a control the rule must leave alone."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

def it(aid, title, year, **kw):
    return {"archiveID": aid, "title": title, "year": year, **kw}

cases = [
    (it("the-court-martial-of-billy-mitchell-otto-preminger-1955", "Court Martial", 1928, imdbID="tt0018796"), 1955),
    (it("vengeance.-is.-mine.-1979.1080p.-blu-ray.x-264.-aac-yts.-mx", "Vengeance Is Mine", 1917), 1979),
    (it("sirocco-1951", "Sirocco", 1065), 1951),
    # controls
    (it("koko-in-1999_1927", "Koko in 1999", 1927), None),
    (it("2000_leagues_under_the_sea_ipod", "20,000 Leagues Under the Sea", 1916), None),
    (it("metropolis-restored-2010", "Metropolis", 1927), None),
    (it("img-1943", "My Old Kentucky Home", 1926), None),
    (it("macbeth_202004", "Macbeth", 1922), None),
    (it("pandoras-box_1930", "Pandora's Box", 1929), None),
    (it("court-martial-1955", "Court Martial", 1955), None),   # already right
]
bad = [(c["archiveID"], R.old_year_on_newer_upload(c), want) for c, want in cases
       if R.old_year_on_newer_upload(c) != want]
x = it("the-court-martial-of-billy-mitchell-otto-preminger-1955", "Court Martial", 1928,
       imdbID="tt0018796", artworkSource="tmdb", posterURL="p", contentType="silent-film", isSilentFilm=True)
R.fix_old_year_on_newer_upload(x)
if not (x["year"] == 1955 and x["imdbID"] is None and x["posterURL"] is None
        and not x["isSilentFilm"] and x["contentType"] != "silent-film"):
    bad.append(("apply", x))
print("FAIL", bad) if bad else print(f"ok {len(cases)} cases + apply")
sys.exit(1 if bad else 0)
