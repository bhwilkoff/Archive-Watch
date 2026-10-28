#!/usr/bin/env python3
"""Racist caricature in cartoons is never recommended and always findable
(Decision 174; owner, 2026-10-28: "make it so that racist cartoons don't
continually show up on the party play and cartoon features of the surprise
surface" — "Scrub Me Mama with a Boogie Beat ... has shown up repeatedly").

Cases: the Censored Eleven by the record, a documented title with no tag at all
(Scrub Me Mama), a character series (Bosko), a cartoon's own racism tag.
Controls: a documentary ABOUT racism is not a caricature; "banned" alone (the
Hays Code cut Betty Boop) is not evidence; `not` exempts; the flag sets
noRecommend with its reason and lifts when the evidence goes.
"""
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

ok = True


def check(name, got, want):
    global ok
    good = got == want
    ok &= good
    print(f"  {'ok  ' if good else 'FAIL'} {name}" + ("" if good else f"  got={got!r} want={want!r}"))


def cartoon(title, year, **kw):
    return {"archiveID": title.lower().replace(" ", "-"), "title": title, "year": year,
            "contentType": "animation", **kw}


check("Censored Eleven by the record", bool(R.racist_caricature(cartoon("Jungle Jitters", 1938))), True)
check("... matched without punctuation", bool(R.racist_caricature(cartoon("Goldilocks and the Jivin Bears", 1944))), True)
check("a documented title with no tag (Scrub Me Mama)",
      bool(R.racist_caricature(cartoon("Scrub Me Mama with a Boogie Beat", 1941))), True)
check("a character series (Bosko)", bool(R.racist_caricature(cartoon("Bosko's Holiday", 1931))), True)
check("a cartoon's own tag", bool(R.racist_caricature(cartoon("The Chinaman", 1920, keywords=["racism"]))), True)
check("a subject phrase split on ';'",
      bool(R.racist_caricature(cartoon("X", 1940, subjects=["vintage cartoons; stereotype cartoons"]))), True)
check("control: a documentary ABOUT racism",
      R.racist_caricature({"archiveID": "levittown", "title": "Crisis in Levittown", "year": 1957,
                           "contentType": "short-film", "subjects": ["racism"]}), None)
check("control: 'banned' alone (Hays Code)",
      R.racist_caricature(cartoon("Betty Boop Halloween Party", 1933, subjects=["banned cartoons"])), None)
check("control: a same-titled film in another year",
      R.racist_caricature(cartoon("Clean Pastures", 1990)), None)
table = dict(R._racist_table()); table["not"] = {"jungle-jitters": "test"}
check("control: `not` exempts", R.racist_caricature(cartoon("Jungle Jitters", 1938), table), None)

items = [cartoon("Scrub Me Mama with a Boogie Beat", 1941), cartoon("Steamboat Bill", 1928)]
R.flag_propaganda(items, Counter(), table={})
check("flagged noRecommend", items[0].get("noRecommend"), True)
check("... with its reason", (items[0].get("noRecommendReason") or "").startswith("racist caricature"), True)
check("control: an unflagged cartoon", items[1].get("noRecommend"), None)
items[0]["title"] = "Something Else"
R.flag_propaganda(items, Counter(), table={})
check("the flag lifts when the evidence goes", items[0].get("noRecommend"), None)

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
