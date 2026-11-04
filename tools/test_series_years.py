#!/usr/bin/env python3
"""Decision 178: a series' year comes from evidence about the series, reaches its
card, survives the rule against impossible TV years, and a year before film
existed is no year. Run: python3 tools/test_series_years.py
"""
import json, sys, tempfile, datetime as dt
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import enrich_series_years as E
import remediate_catalog as R

ok = True
def check(label, cond):
    global ok
    print(("PASS " if cond else "FAIL ") + label); ok &= bool(cond)

none = lambda t: None
court = {"title": "Court of Last Resort", "seasons": [{"episodes": [{"airDate": "1957-10-04"}, {"airDate": "1958-01-01"}]}]}
check("an episode's air date dates the show", E.find(court, none)["year"] == 1957)
maze = lambda t: {"name": "Men into Space", "premiered": "1959-09-30", "url": "https://tvmaze/x"}
hit = E.find({"title": "Men Into Space", "seasons": []}, maze)
check("TVmaze on an exact title dates it, and says so", hit["year"] == 1959 and hit["how"] == "tvmaze" and hit["source"])
check("CONTROL: TVmaze's nearest other show does not",
      E.find({"title": "Men into Spaces of Mars", "seasons": []}, maze) is None)
prose = {"title": "X", "overview": "An American court show which aired on NBC from 1957 through 1958.", "seasons": []}
check("the show's own overview dates it", E.find(prose, none)["year"] == 1957)
check("CONTROL: nothing is not a year", E.find({"title": "X", "seasons": []}, none) is None)
check("a person's entry is never replaced", not E.needs_year({}, {"how": "reviewed", "year": None}))
check("a whole-series upload is not guessed at: its year is its item's to prove",
      not E.needs_year({"sourceID": "x"}, None))

tmp = Path(tempfile.mkdtemp())
(tmp / "series").mkdir(); (tmp / "shared/editorial").mkdir(parents=True)
(tmp / "series/a.json").write_text(json.dumps({"seriesID": "a", **court}))
(tmp / "series/b.json").write_text(json.dumps({"seriesID": "b", "title": "Nobody", "seasons": []}))
day = dt.date(2026, 11, 4)
asked = []
def counting(t):
    asked.append(t); return None
E.run(tmp, counting, day)
t = json.loads((tmp / "shared/editorial/series_years.json").read_text())
check("a find is written", t["a"]["year"] == 1957)
check("an unknown is recorded", t["b"] == {"year": None, "checked": "2026-11-04"})
n = len(asked); E.run(tmp, counting, day + dt.timedelta(days=5))
check("and left alone for a while", len(asked) == n)
E.run(tmp, counting, day + dt.timedelta(days=31))
check("then asked again", len(asked) == n + 1)
def broken(t): raise OSError("down")
(tmp / "series/c.json").write_text(json.dumps({"seriesID": "c", "title": "C", "seasons": []}))
_, _, err = E.run(tmp, broken, day + dt.timedelta(days=62))
t = json.loads((tmp / "shared/editorial/series_years.json").read_text())
check("a failed search is not a verdict", err >= 1 and "c" not in t)

(tmp / "shared/editorial/series_years.json").write_text(json.dumps({
    "serial": {"year": 1918, "how": "reviewed", "source": "https://x"},
    "show": {"year": 1957, "how": "air date"}, "gone": {"year": None, "checked": "2026-11-04"}}))
R.REPO = tmp
items = [{"archiveID": "series:serial", "seriesID": "serial", "contentType": "tv-series", "year": None},
         {"archiveID": "series:show", "seriesID": "show", "contentType": "tv-series", "year": None},
         {"archiveID": "series:gone", "seriesID": "gone", "contentType": "tv-series", "year": None},
         {"archiveID": "series:bad", "seriesID": "bad", "contentType": "tv-series", "year": 1916},
         {"archiveID": "lecture", "contentType": "short-film", "year": 1801},
         {"archiveID": "early", "contentType": "short-film", "year": 1888}]
st = Counter()
R.apply_series_years(items, st)
R.clear_impossible_film_years(items, st)
R.clear_impossible_tv_years(items, st)
by = {i["archiveID"]: i for i in items}
check("a reviewed year reaches the card", by["series:serial"]["year"] == 1918 and by["series:serial"]["decade"] == 1910)
check("and survives the rule against pre-television years",
      by["series:serial"]["year"] == 1918 and by["series:serial"]["contentType"] == "tv-series")
check("a found year reaches the card", by["series:show"]["year"] == 1957)
check("CONTROL: an unknown stays unknown", by["series:gone"]["year"] is None)
check("CONTROL: an unreviewed pre-television series year is still cleared", by["series:bad"]["year"] is None)
check("a year before film existed is no year", by["lecture"]["year"] is None and by["lecture"]["yearWas"] == 1801)
check("CONTROL: the first films keep theirs", by["early"]["year"] == 1888)
hate = [{"archiveID": "a", "title": "A Documentary", "subjects": ["Holocaust", "Denier"]},
        {"archiveID": "b", "title": "Night and Fog", "subjects": ["Holocaust", "Documentary"]}]
R.exclude_hate_propaganda(hate, Counter())
check("denial named only in the subjects is hidden", hate[0].get("excludedReason") == "hate_propaganda")
check("CONTROL: a film about the Holocaust is not", "excluded" not in hate[1])
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
