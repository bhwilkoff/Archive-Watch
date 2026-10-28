#!/usr/bin/env python3
"""
test_yearless_match_identity.py — a title search with no year may not take a
famous film of the same name, and what it already took is cleared.

The defect (audit 2026-10-28): "Silence", a 19-second clip, wore Scorsese's
2016 film; "Evolution" (0989_Evolution__01_35_09_15), a 14-minute Prelinger
reel, wore Ivan Reitman's 2001 comedy; 74Help, a 17-minute reel, wore the
Beatles' Help! (1965). Each had no year of its own, so tmdb_lib.search_movie
had nothing to disambiguate with and the most popular title won;
runtime_contradicts_match spared them because the titles agree.

Fragments (the right film, a piece of it) are the other half: they keep their
identity and are flagged noRecommend with reason "fragment".

Controls: a real feature and a real short found by the same yearless path
with agreeing runtimes stay matched; a dated item is not this rule's to judge;
the remediate wiring is proved by stubbing the rule out and seeing it fail.

Run: python3 tools/test_yearless_match_identity.py
"""
import collections
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import omdb_lib as O  # noqa: E402
import remediate_catalog as R  # noqa: E402
import tmdb_lib as T  # noqa: E402

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


# The OMDb cache as the build reads it, for the ids used here.
R._OMDB_CACHE = {
    "tt0490215": {"runtime_min": 161, "director": "Martin Scorsese"},   # Silence (2016)
    "tt0251075": {"runtime_min": 101, "director": "Ivan Reitman"},      # Evolution (2001)
    "tt0059260": {"runtime_min": 92, "director": "Richard Lester"},     # Help! (1965)
    "tt0013442": {"runtime_min": 94, "director": "F.W. Murnau"},        # Nosferatu
    "tt0034583": {"runtime_min": 102},                                  # a real feature
    "tt0000417": {"runtime_min": 13},                                   # a real short
    "tt0031381": {"runtime_min": 238},
}
R._RUNTIME_KEEP = {}


def matched(aid, title, imdb, year, own, **kw):
    it = {"archiveID": aid, "title": title, "year": year, "decade": year // 10 * 10,
          "yearSource": "omdb", "imdbID": imdb, "tmdbID": 1, "contentType": "ephemeral",
          "runtimeSeconds": own, "fileRuntimeSeconds": own, "matchVerdict": "unverifiable",
          "posterURL": "https://image.tmdb.org/t/p/w780/x.jpg", "artworkSource": "tmdb",
          "hasRealArtwork": True, "imdbVotes": 500000, "imdbRating": 7.5,
          "synopsis": "The famous film.", "synopsisSource": "tmdb", "collections": ["prelinger"]}
    it.update(kw)
    return it


print("source: a searched record must pass the identity test")
yearless = {"title": "Help!", "year": None, "fileRuntimeSeconds": 1076}
check("yearless reel vs a 92-minute film refused",
      not O.plausible_identity(yearless, {"title": "Help!", "year": 1965, "runtime_min": 92}))
check("yearless, exact title, runtime within 25% accepted (control)",
      O.plausible_identity({"title": "Casablanca", "fileRuntimeSeconds": 6120},
                           {"title": "Casablanca", "year": 1942, "runtime_min": 102}))
check("yearless, inverted article still exact",
      O.plausible_identity({"title": "Strip, The", "fileRuntimeSeconds": 5100},
                           {"title": "The Strip", "year": 1951, "runtime_min": 85}))
check("yearless, title not exact refused",
      not O.plausible_identity({"title": "Casablanca Express", "fileRuntimeSeconds": 6120},
                               {"title": "Casablanca", "runtime_min": 102}))
check("yearless with no file runtime refused",
      not O.plausible_identity({"title": "Casablanca"}, {"title": "Casablanca", "runtime_min": 102}))
check("dated, 3 years apart refused",
      not O.plausible_identity({"title": "X", "year": 1940}, {"title": "X", "year": 1943}))
check("dated, 2 years apart accepted (control)",
      O.plausible_identity({"title": "X", "year": 1940}, {"title": "X", "year": 1942}))
it = {"title": "Help!", "year": None, "fileRuntimeSeconds": 1076}
check("apply_identity writes nothing for a refused search",
      O.apply_identity(it, {"title": "Help!", "imdb_id": "tt0059260", "year": 1965,
                            "runtime_min": 92, "director": "Richard Lester"}) is False
      and "imdbID" not in it and it["year"] is None)
check("apply_identity(authoritative=True) still adopts a declared id (control)",
      O.apply_identity(it, {"imdb_id": "tt0059260", "year": 1965}, authoritative=True)
      and it["imdbID"] == "tt0059260")


class Resp:
    def __init__(self, data, status=200):
        self._d, self.status_code, self.ok = data, status, status < 400

    def json(self):
        return self._d


class Sess:
    def __init__(self, results, runtime):
        self.results, self.runtime, self.calls = results, runtime, []

    def get(self, url, params=None, headers=None, timeout=None):
        self.calls.append(url)
        if url.endswith("/search/movie"):
            return Resp({"results": self.results})
        return Resp({"runtime": self.runtime})


silence = [{"id": 68730, "title": "Silence", "release_date": "2016-12-23", "popularity": 40}]
check("search: yearless with no file runtime abstains",
      T.search_movie("Silence", None, "t", Sess(silence, 161)) is None)
check("search: yearless, runtime 19 s vs 161 min abstains",
      T.search_movie("Silence", None, "t", Sess(silence, 161), file_runtime_s=19) is None)
check("search: yearless, runtime agrees accepted (control)",
      T.search_movie("Silence", None, "t", Sess(silence, 161), file_runtime_s=9500) == 68730)
two = silence + [{"id": 5, "title": "Silence", "release_date": "1971-01-01"}]
check("search: yearless, two exact titles abstains",
      T.search_movie("Silence", None, "t", Sess(two, 161), file_runtime_s=9500) is None)
check("search: dated, best release 5 years off rejected",
      T.search_movie("Silence", 2011, "t", Sess(silence, 161)) is None)
check("search: dated, 1 year off accepted (control)",
      T.search_movie("Silence", 2015, "t", Sess(silence, 161)) == 68730)
check("search: trust_yearless keeps the old path for a cast-verified caller",
      T.search_movie("Silence", None, "t", Sess(silence, 161), trust_yearless=True) == 68730)

print("\nbacklog: remediate clears what the yearless search took")
cases = [
    matched("silence", "Silence", "tt0490215", 2016, 19, fileRuntimeSeconds=None),
    matched("0989_Evolution__01_35_09_15", "Evolution", "tt0251075", 2001, 841),
    matched("74Help", "Help!", "tt0059260", 1965, 1076),
    # controls
    matched("casablanca_x", "Casablanca", "tt0034583", 1942, 6100),        # a real feature
    matched("a_short", "A Trip", "tt0000417", 1902, 760),                   # a real short
    matched("own_year", "Help!", "tt0059260", 1965, 1076, yearSource=None),  # dated by itself
    matched("RiverboatChapter3", "Riverboat (Chapter 3)", "tt0031381", 1944, 1100),
]
items = copy.deepcopy(cases)
st = R.remediate(items)
by = {i["archiveID"]: i for i in items}
for aid, y in (("silence", 2016), ("0989_Evolution__01_35_09_15", 2001), ("74Help", 1965)):
    i = by[aid]
    check(f"{aid}: identity cleared",
          i.get("imdbID") is None and i.get("tmdbID") is None
          and i.get("matchVerdict") == "cleared_yearless_runtime", i.get("matchVerdict"))
    check(f"{aid}: the match's year goes, recorded", i.get("year") is None and i.get("yearWas") == y,
          (i.get("year"), i.get("yearWas")))
    check(f"{aid}: the match's votes and synopsis go",
          not i.get("imdbVotes") and not i.get("synopsis")
          and "tmdb.org" not in (i.get("posterURL") or ""), i.get("posterURL"))
check("a real feature keeps its match", by["casablanca_x"].get("imdbID") == "tt0034583")
check("a real short keeps its match", by["a_short"].get("imdbID") == "tt0000417")
check("an item dated by itself is not this rule's", by["own_year"].get("matchVerdict") != "cleared_yearless_runtime")
check("a pre-1978 chapter keeps its identity (fragment path)",
      by["RiverboatChapter3"].get("imdbID") == "tt0031381")
check("stats count the clears", st.get("yearless_match_cleared") == 3, st.get("yearless_match_cleared"))
again = copy.deepcopy(items)
st2 = R.remediate(again)
check("a second pass clears nothing", not st2.get("yearless_match_cleared"))

print("\ncontrol: with the rule stubbed out, remediate keeps Silence's wrong identity")
real = R.yearless_match_conflict
R.yearless_match_conflict = lambda it: None
ctl = copy.deepcopy(cases[:1])
R.remediate(ctl)
R.yearless_match_conflict = real
check("the stub leaves the wrong film in place (so the wiring is what clears it)",
      ctl[0].get("imdbID") == "tt0490215")

print("\nfragments: the right film, a piece of it")
nos = {"archiveID": "Nosferatu_DVD_quality", "title": "Nosferatu", "year": 1922,
       "imdbID": "tt0013442", "fileRuntimeSeconds": 1190, "contentType": "silent-film"}
full = dict(nos, archiveID="nosferatu_full", fileRuntimeSeconds=5400)
part = dict(nos, archiveID="nosferatu_upload", fileRuntimeSeconds=None,
            videoFile={"name": "nosferatu_part2.mp4"})
partitle = dict(part, archiveID="nosferatu_p2_titled", title="Nosferatu (Part 2)")
short = {"archiveID": "a_short", "title": "A Trip", "year": 1902, "imdbID": "tt0000417",
         "fileRuntimeSeconds": 760, "contentType": "short-film"}
check("20 minutes of Nosferatu is a fragment", (R.fragment_of(nos) or "").startswith("20 of 94"),
      R.fragment_of(nos))
check("the whole film is not (control)", R.fragment_of(full) is None)
check("a part-named file under a title that is not", (R.fragment_of(part) or "").startswith("file "))
check("a title that says it is a part is honest, not flagged", R.fragment_of(partitle) is None)
check("a short matched to a short is not (control)", R.fragment_of(short) is None)
items = [copy.deepcopy(nos), copy.deepcopy(full)]
st = collections.Counter()
R.flag_propaganda(items, st, table={})
check("flagged noRecommend with the fragment reason, identity kept",
      items[0].get("noRecommend") and items[0]["noRecommendReason"].startswith("fragment")
      and items[0]["imdbID"] == "tt0013442" and items[0].get("fragmentOf") == "tt0013442")
check("the whole film stays recommendable", not items[1].get("noRecommend"))
items[0]["fileRuntimeSeconds"] = 5400            # a better copy replaced the file
R.flag_propaganda(items, collections.Counter(), table={})
check("the flag lifts when the evidence goes", not items[0].get("noRecommend")
      and "fragmentOf" not in items[0])

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
