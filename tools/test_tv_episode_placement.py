#!/usr/bin/env python3
"""A single-episode upload is placed by its OWN words (file name, archive.org id),
never by the canonical title of the slot it already holds (2026-10-27).

Cases, each from the live spines: "s01e01.The.Speckled.Band" is not TVmaze's
1x01 "The Case of the Cunningham Heritage"; "Season4Episode3 ... Humphrey Bogart"
is 4x03, not 1x03; a colorized file named "At Night All Cats Are Gray" goes to
that episode, not to the number it carries; a Twilight Zone promo is not the
episode it advertises; a not_films item (LTT101, a Looney Tunes rip) is served
by no spine; an unplaced title loses the show's name in front; a colorized copy
never takes a slot from a black-and-white one (Decision 158).
Controls: "Burns-Allen-Show_S2E7_Christmas" keeps "Christmas with Mamie Kelly"
(a shared word); an untitled "Soul Train (Season 2, Episode 5)" goes by its
number; an episode re-pooled with its own correct title stays put.
"""
import sys
from pathlib import Path
R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import build_canonical_tv as T

ok = True


def check(name, got, want):
    global ok
    good = got == want
    ok &= good
    print(f"  {'ok  ' if good else 'FAIL'} {name}" + ("" if good else f"  got={got!r} want={want!r}"))


def c(s, n, title, rt=1800):
    return {"season": s, "number": n, "title": title, "overview": None, "airDate": None,
            "stillURL": None, "runtimeSeconds": rt}


def ep(aid, title, fname):
    return {"archiveID": aid, "title": title, "downloadURL": f"https://archive.org/download/{aid}/{fname}",
            "videoFile": {"name": fname}}


def place(eps, canon, show):
    mapped, extras = T.map_items_to_canonical(eps, canon, show)
    return {it["archiveID"]: k for k, (_, it) in mapped.items()}, extras


sherlock = [c(1, 1, "The Case of the Cunningham Heritage"), c(1, 2, "The Case of Lady Beryl")]
by, extras = place([ep("s01e01.The.Speckled.Band", "The Case of the Cunningham Heritage",
                       "s01e01.The.Speckled.Band.mp4")], sherlock, "Sherlock Holmes")
check("a file naming another episode does not take its number's slot", by, {})
check("... and is listed by its own words", T.clean_extra_title(extras[0]["title"], "Sherlock Holmes"),
      "The Speckled Band")

burns = [c(2, 7, "Christmas with Mamie Kelly")]
by, _ = place([ep("Burns-Allen-Show_S2E7_Christmas", "Christmas with Mamie Kelly",
                  "Burns-Allen-Show_S2E7_Christmas.mp4")], burns, "The George Burns and Gracie Allen Show")
check("control: a title sharing a word with its slot keeps it", by, {"Burns-Allen-Show_S2E7_Christmas": (2, 7)})

benny = [c(1, 3, "Claudette Colbert and Basil Rathbone Show"), c(4, 3, "Humphrey Bogart Show")]
by, _ = place([ep("TheJackBennyProgramSeason4Episode3HumphreyBogartGuest-Aired",
                  "Claudette Colbert and Basil Rathbone Show", "JackBennyProgram-4x03-Humphrey_Bogart_Show.mp4")],
              benny, "The Jack Benny Program")
check("a stated season is read (4x03 / Season4Episode3), never assumed to be 1",
      by, {"TheJackBennyProgramSeason4Episode3HumphreyBogartGuest-Aired": (4, 3)})

march = [c(1, 4, "The Abominable Snowman"), c(1, 7, "At Night All Cats Are Grey")]
by, _ = place([ep("colonel-march-of-scotland-yard-tv-1954-colorized-s01e04-at-night-all-cats-are-gray",
                  "The Abominable Snowman",
                  "Colonel March of Scotland Yard TV 1954 colorized s01e04 At Night All Cats Are Gray.mp4")],
              march, "Colonel March of Scotland Yard")
check("the upload's own title outranks its number", list(by.values()), [(1, 7)])

tz = [c(2, 25, "The Silence")]
by, extras = place([ep("tz_promos_s2_1960-61", "The Silence", "Twilight Zone promo (S2E25 The Silence).mp4")],
                   tz, "The Twilight Zone")
check("a promo is not the episode it advertises", by, {})
check("... and is labeled as that episode's promo", extras[0]["title"], "Promo: The Silence")

soul = [c(1, 5, "Bill Withers/ Al Green/ Viola Wills"), c(2, 5, "The Temptations")]
by, _ = place([ep("soul-train-season-2-episode-5", "Soul Train", "Soul Train (Season 2, Episode 5).mp4")],
              soul, "Soul Train")
check("control: an untitled upload goes by its stated number", by, {"soul-train-season-2-episode-5": (2, 5)})

lone = [c(1, 44, "White Man's Magic")]
bw = ep("lone-ranger-s01e44-white-mans-magic", "White Man's Magic", "Lone Ranger s01e44 White Mans Magic.mp4")
col = ep("lone-ranger-tv-1950-colorized-s01e44-white-mans-magic", "White Man's Magic",
         "The Lone Ranger TV 1950 colorized s01e44 White Man's Magic.mp4")
by, _ = place([col, bw], lone, "The Lone Ranger")
check("a colorized copy never takes the slot from the black-and-white one",
      by.get("lone-ranger-s01e44-white-mans-magic"), (1, 44))
by, _ = place([dict(bw)], lone, "The Lone Ranger")
check("control: an episode re-pooled with its own title stays put", by, {"lone-ranger-s01e44-white-mans-magic": (1, 44)})

dinah = [c(1, 1, "November 2, 1956")]
by, _ = place([ep("dinah-1959-11-01", "The Dinah Shore Chevy Show - 1 November 1959", "The Dinah Shore Chevy Show - 1 November 1959.mp4")],
              dinah, "The Dinah Shore Chevy Show")
check("a title match is refused when the years disagree", by, {})
bonanza = [c(2, 15, "The Blood Line"), c(9, 20, "Blood Tie")]
by, _ = place([ep("bonanza-the-blood-line", "Bonanza", "Bonanza_-_The_Blood_Line.mp4")], bonanza, "Bonanza")
check("an exact title wins over a closer spelling", by, {"bonanza-the-blood-line": (2, 15)})

check("an unplaced title loses the show's name in front",
      T.clean_extra_title("'Mack and Myer for Hire'- Wacky Wizardry (60's Sitcom) (Classic TV)", "Mack and Myer for Hire"),
      "Wacky Wizardry")
check("control: a title that IS the show's name is kept",
      T.clean_extra_title("Mack and Myer", "Mack and Myer"), "Mack and Myer")
check("a colorized cluster's name resolves as its show",
      T.clean_title("Have Gun Will Travel TV 1962 colorized"), "Have Gun Will Travel")

T._NOT_FILMS = {"LTT101"}
T.expand_bundles = lambda eps, keep=frozenset(): (eps, 0)
show = {"id": 1, "name": "Looney Tunes", "premiered": "1929-01-01",
        "_embedded": {"episodes": [{"season": 1, "number": n, "name": t, "runtime": 7}
                                   for n, t in ((1, "Smile, Darn Ya, Smile!"), (2, "The Queen Was in the Parlor"))]}}
eps = [ep("LTT101@s1e01", "Smile, Darn Ya, Smile!", "Smile Darn Ya Smile.mp4") | {"sourceID": "LTT101", "episodeNumber": 1, "seasonNumber": 1},
       ep("queen-was-in-the-parlor-1932", "The Queen Was in the Parlor", "The Queen Was in the Parlor.mp4")]
series, _ = T.rebuild_show(show, eps, repick=False)
served = [e["archiveID"] for s in (series or {}).get("seasons", []) for e in s["episodes"]]
check("a not_films item is served by no spine", "LTT101@s1e01" in served, False)
check("control: the show's other episodes are", "queen-was-in-the-parlor-1932" in served, True)

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
