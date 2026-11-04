#!/usr/bin/env python3
"""Each file of a compilation is judged by its own title (Decision 179): a renewed
short leaves, a free one stays, and a same-named work by someone else claims nothing.
The printed records here are the real ones. Run: python3 tools/test_compilation_claims.py
"""
import datetime as dt, json, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_tv_rights as A
import build_bundle_series as B
import corroborate_copyright as C
import remediate_catalog as R
import takedown_lib as T

bad = []


def check(name, ok):
    if not ok:
        bad.append(name)


AGE = 1931


def row(t, y, r, c="Exclusive Pictures Corp. (PWH)", rl=1, vol="v", s=None):
    return {"t": t, "y": y, "r": r, "reg": "M1", "c": c, "vol": vol, "rl": rl, **({"s": s} if s else {})}


C._CCE = {}
for x in [row("FIDDLESTICKS", 1931, "R233745"), row("FLYING FISTS", 1931, "R233746"), row("THE SOUP SONG", 1931, "R233739", c=""),
          row("LAUGHING GAS", 1931, "R233742"), row("JAIL BIRDS", 1932, "R246616"), row("JAIL BIRDS", 1934, "R284106", c="CBS Films, Inc. (PWH)"),
          row("SPOOKS", 1932, "R246622"), row("SCHOOL DAYS", 1932, "R246625", c="TBE Nes"), row("CIRCUS", 1932, "R246629"),
          row("PLANE CRAZY", 1933, "R273069", c="United Artists Associated", rl=2),
          row("THE MECHANICAL COW", 1937, "R341358", c="CBS Films, (PWH)"),
          row("WHAT A LIFE", 1939, "R359598", c="Emka, division of Universal", rl=8),
          row("WHAT A LIFE", 1935, "R999999", c="Exclusive Pictures Corp. (PWH)", rl=8),
          row("GOOD TIMES", 1933, "R500000", c="Someone Else Inc. (PWH)", vol="w"),
          row("The electrical brain", 1932, "R506411", s="BATMAN")]:
    C._CCE.setdefault(C.norm_title(x.get("s") or x["t"]), []).append(x)


def ep(tok, title, secs=420, **kw):
    return {"archiveID": f"item@{tok}", "sourceID": "item", "title": title, "year": 1930, "runtimeSeconds": secs, **kw}


def spine(eps, **kw):
    return {"seriesID": "flip", "sourceID": "item", "title": "Flip The Frog", "yearStart": 1930,
            "seasons": [{"seasonNumber": 1, "episodes": eps}], **kw}


FLIP = spine([ep("e01", "Fiddlesticks", year=1930, yearSource="film"),   # registered 1931, released 1930
              ep("e02", "Flying Fists"),                 # no release date of its own: the printed date stands
              ep("e03", "The Soup Song"),                # claimant lost to OCR: filed in the same batch
              ep("e04", "Laughing Gas"),
              ep("e05", "Jail Birds"),                   # a CBS short of 1934 shares the name
              ep("e06", "Spooks", year=1930, yearSource="film"),   # a same-named film of 1930 is within a year
              ep("e07", "School Days"),                  # claimant ruined, same batch
              ep("e08", "Puddle Pranks"),                # no renewal at all: stays
              ep("e09", "Flip The Frog - Circus [1932]"),
              ep("e10", "What a Life"),                  # eight reels printed, a seven-minute file: not this cartoon
              ep("e11", "The Mechanical Cow"),           # another studio's
              ep("e12", "Good Times"),                   # renewed once, by a stranger to this compilation
              ep("e13", "Plane Crazy")])                 # likewise
got = C.compilation_claims([FLIP], AGE)
ids = {k.split("@")[1] for k in got}
check(f"leaves: {sorted(ids)}", ids == {"e02", "e03", "e04", "e05", "e06", "e07", "e09"})
check("a 1930 release is free by age whatever its registration says", "e01" not in ids)
check("a file with no renewal stays", "e08" not in ids)
check("same-named film ten years off does not move the year", C.compilation_claims(
    [spine([ep("e05", "Jail Birds", year=1940, yearSource="film"), ep("e02", "Flying Fists"), ep("e04", "Laughing Gas"),
            ep("e09", "Circus")])], AGE)["item@e05"][0] == 1932)
check("the renewal cited is the claimant's, not the stranger's", got["item@e05"][1]["r"] == "R246616")
check("a chapter is not a work of its own", not C.compilation_claims(
    [spine([ep("e01", "Batman"), ep("e02", "Flying Fists"), ep("e03", "Laughing Gas"), ep("e04", "Circus")])],
    AGE).get("item@e01"))
check("past the age line nothing is claimed", not C.compilation_claims([FLIP], 1940))
check("a year out of the run is not asked", not C.compilation_claims([spine(FLIP["seasons"][0]["episodes"], yearStart=1960)], AGE))
keep, C._CCE = C._CCE, {}
C.cce_renewal = lambda *a, **k: None
try:
    C.compilation_claims([FLIP], AGE)
    check("an unread table must stop the judge, never clear everyone", False)
except RuntimeError:
    pass
C._CCE = keep

# Years the file can show for itself.
for raw, want in [("Big Man from the North [1-19-31 LT][720p", 1931), ("Soda Squirt (1933)", 1933), ("Bosko, the Talk-Ink Kid [produced May 1929 30 fps", 1929),
                  ("Space: 1999", None), ("Studio One 1984", None), ("Fiddlesticks", None)]:
    check(f"stated_year {raw}", C.stated_year(raw) == want)
check("run-together title", C.file_title("TheVillageSpecialist", "Flip The Frog") == "The Village Specialist")
sp = spine([ep("e01", "Fiddlesticks"), ep("e02", "[1-19-31 LT] x"), ep("e03", "Plane Crazy"), ep("e04", "Africa Squeaks")])
# Langdon's two-reel Fiddlesticks of 1927 is not Iwerks's seven-minute one of 1930.
B.stamp_years(sp, {"fiddlesticks": {(1930, 6.5), (1927, 21)}, "planecrazy": {(1928, 7), (1933, 7)}, "africasqueaks": {(1960, 7)}})
e = sp["seasons"][0]["episodes"]
check("a film record dates a file", (e[0]["year"], e[0].get("yearSource")) == (1930, "film"))
check("the file's own date wins", (e[1]["year"], e[1].get("yearSource")) == (1931, "title"))
check("two film records years apart date nothing", not e[2].get("yearSource"))
check("a record outside the run dates nothing", not e[3].get("yearSource"))

# Through the takedown list: the rule's lines, and only the rule's.
tmp = Path(tempfile.mkdtemp())
(tmp / "shared/editorial").mkdir(parents=True)
(tmp / "series").mkdir()
year = dt.date.today().year
T.path(tmp).write_text(json.dumps({
    "_how": "ignored",
    "item@e10": {"date": "2026-01-01", "case": "TD-1"},
    "item@e12": {"date": "2026-01-01", "case": "renewal R1", "until": year + 1, "rule": "file"},
    "item@e13": {"date": "2026-01-01", "case": "renewal R2", "until": year + 1, "rule": "file"},
    "gone@e01": {"date": "2026-01-01", "case": "renewal R3", "until": year + 1, "rule": "file"},
    "expired@e01": {"date": "2026-01-01", "case": "renewal R4", "until": year, "rule": "file"}}))
(tmp / "series/flip.json").write_text(json.dumps(FLIP))
real_age = A.AR.PD_BY_AGE
A.AR.PD_BY_AGE = AGE
claims = A.judge_compilations(tmp / "series", True, tmp)
A.AR.PD_BY_AGE = real_age
table = T.load(tmp)
check("a claimed file gets its line", table.get("item@e02", {}).get("case") == "renewal R233746")
check("until is the year its copyright ends", table["item@e02"]["until"] == 1931 + 96)
check("a file the record no longer claims loses its line", "item@e12" not in table and "item@e13" not in table)
check("a person's line is never touched", "item@e10" in table)
check("a line for a file no spine holds is left alone", "gone@e01" in table)
check("an expired line no longer holds", "expired@e01" not in table)
check("a free file has no line", "item@e01" not in table and "item@e08" not in table)
T.strip_spines(table, tmp)
left = {x["archiveID"] for s in json.loads((tmp / "series/flip.json").read_text())["seasons"] for x in s["episodes"]}
check(f"a renewed short leaves and a free one stays: {sorted(left)}", "item@e02" not in left and {"item@e01", "item@e08"} <= left)
check("second run changes nothing", T.write_rule_lines(claims, {"item@e02"}, tmp) == (0, 0))

# Deleting a line restores the title; a series emptied by its files stays down.
R.REPO = tmp
(tmp / "shared/editorial/takedowns.json").write_text("{}")
(tmp / "series/back.json").write_text(json.dumps({"seriesID": "back", "seasons": [{"episodes": [{"archiveID": "b1"}]}]}))
items = [{"archiveID": "was-listed", "excluded": True, "excludedReason": "takedown"},
         {"archiveID": "series:back", "seriesID": "back", "excluded": True, "excludedReason": "takedown"},
         {"archiveID": "series:emptied", "seriesID": "emptied", "excluded": True, "excludedReason": "takedown"},
         {"archiveID": "other-hide", "excluded": True, "excludedReason": "trailer"}]
from collections import Counter
R.exclude_takedowns(items, Counter())
check("a line deleted brings the card back", not items[0].get("excluded") and not items[1].get("excluded"))
check("a series with no spine stays hidden", items[2].get("excluded"))
check("another hide is not ours to clear", items[3].get("excluded"))

for b in bad:
    print("FAIL", b)
print(f"{'PASS' if not bad else 'FAIL'}: compilation files judged by their own titles")
sys.exit(1 if bad else 0)
