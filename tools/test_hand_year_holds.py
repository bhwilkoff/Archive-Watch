#!/usr/bin/env python3
"""A year a person judged (shared/editorial/year_corrections.json) survives the
rules that clear doubtful years; the TYPE is corrected instead.

Measured 2026-09-29: 5 of 41 hand-corrected years were gone from the
published catalog. Oliver Twist (1933), Svengali (1931) and Viy (1967) are
sound films typed silent-film, and the "silent film dated after 1930" rule
wiped the year each build; Ravished Armenia (1919) was typed tv-special, the
"TV before television" rule wiped it, and the film was then hidden as undated.
(Rumpole's case, the rights confirm re-date, is in test_audit_rights.py.)
Each case has a control without the hand mark, which must still be cleared.

Run: python3 tools/test_hand_year_holds.py   (exit 0 = pass)
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

fails = 0
def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    fails += not cond


def item(aid, year, ct, rt, hand):
    it = {"archiveID": aid, "title": "Svengali", "year": year, "decade": R.decade_of(year),
          "contentType": ct, "runtimeSeconds": rt, "colorMode": "bw",
          "isSilentFilm": ct == "silent-film"}
    if hand:
        it["yearSource"] = "agent-reviewed"
    return it

sound = item("hand-sound", 1931, "silent-film", 4931, True)
sound_ctrl = item("ctrl-sound", 1931, "silent-film", 4931, False)
tv = item("hand-tv", 1919, "tv-special", 1434, True)
tv_ctrl = item("ctrl-tv", 1919, "tv-special", 1434, False)
R.remediate([sound, sound_ctrl, tv, tv_ctrl])

check("a hand-dated sound film typed silent keeps its year", sound["year"] == 1931)
check("  ...and is re-typed a feature, not silent",
      sound["contentType"] == "feature-film" and not sound["isSilentFilm"])
check("control: the same film without the hand mark still loses the year", sound_ctrl["year"] is None)
check("a hand-dated 1919 film typed tv-special keeps its year", tv["year"] == 1919)
check("  ...and is re-typed a silent film", tv["contentType"] == "silent-film")
check("control: a TV item dated before television without the hand mark is cleared",
      tv_ctrl["year"] is None)

print("PASS: 0 failure(s)" if not fails else f"FAIL: {fails} failure(s)")
sys.exit(1 if fails else 0)
