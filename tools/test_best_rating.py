#!/usr/bin/env python3
"""Each title's best rating and the Top Rated rank (Decision 171; owner,
2026-10-27: "Please make use of the best ratings available per content").

Cases, each with the control that would fail without the rule:
  * the largest crowd's rating is the best one (IMDb wins a tie); TVmaze, which
    publishes no count, only when no counted rating exists
  * a big crowd's 8.6 outranks a tiny crowd's 9.2 (Der Vierte kommt nicht led
    feature films' Top Rated from 13 votes); control: undiscounted, it would not
  * archive.org's generous stars are measured against archive.org's reviewers
  * series are measured against series, films against films
  * an id OMDb calls a movie is not a series' rating (Atom Man vs. Superman)
  * the series card carries IMDb's rating from its spine, and a one-item series
    its upload's reviewers
  * the DB and the index carry the rank as their last column
"""
import json
import sqlite3
import sys
import tempfile
from pathlib import Path

R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import best_rating as B
import build_sqlite as bs
import enrich_tv_ratings as E
import reconcile_tv_catalog as rt

ok = True


def check(name, got, want):
    global ok
    good = got == want
    ok &= good
    print(f"  {'ok  ' if good else 'FAIL'} {name}" + ("" if good else f"  got={got!r} want={want!r}"))


def film(aid, **kw):
    return {"archiveID": aid, "title": aid, "contentType": "feature-film", **kw}


print("best: the largest crowd")
check("IMDb with more votes than reviews",
      B.best(film("a", imdbRating=7.1, imdbVotes=900, avgRating=4.9, numReviews=12))[0], "imdb")
check("archive.org reviewers when they outnumber IMDb's voters",
      B.best(film("b", imdbRating=6.0, imdbVotes=7, avgRating=4.5, numReviews=40))[:2], ("archive", 9.0))
check("IMDb wins a tie", B.best(film("c", imdbRating=6.0, imdbVotes=5, avgRating=4.0, numReviews=5))[0], "imdb")
series = {"archiveID": "series:x", "contentType": "tv-series"}
check("TVmaze only when nothing counted exists", B.best({**series, "tvmazeRating": 8.1})[0], "tvmaze")
check("control: a series IMDb rates uses IMDb, not TVmaze",
      B.best({**series, "tvmazeRating": 8.9, "imdbRating": 9.0, "imdbVotes": 98000})[0], "imdb")
check("unrated is None", B.best(film("d")), None)
check("a zero rating is no rating", B.best(film("e", imdbRating=0, imdbVotes=0)), None)

print("rank: confidence-weighted, per crowd")
pool = [film(f"f{i}", imdbRating=r, imdbVotes=500) for i, r in enumerate([5.0, 6.0, 6.0, 7.0])]
pool += [film(f"g{i}", avgRating=a, numReviews=3) for i, a in enumerate([3.0, 4.0, 4.0, 5.0])]
harakiri = film("harakiri", imdbRating=8.6, imdbVotes=90669)
vierte = film("vierte", imdbRating=9.2, imdbVotes=13)
pool += [harakiri, vierte]
st = B.crowd_stats(pool)
check("a big crowd's 8.6 outranks a tiny crowd's 9.2", B.rank(harakiri, st) > B.rank(vierte, st), True)
m, sd = st[("imdb", False)]
check("control: undiscounted, the 9.2 would lead", (9.2 - m) / sd > (8.6 - m) / sd, True)
one_review = film("soundie", avgRating=5.0, numReviews=1)
imdb_500 = film("known", imdbRating=7.5, imdbVotes=500)
check("one five-star review ranks below a 7.5 from 500 voters",
      B.rank(one_review, st) < B.rank(imdb_500, st), True)
check("archive.org is measured against archive.org: its mean is its own",
      round(st[("archive", False)][0], 2) != round(st[("imdb", False)][0], 2), True)
check("an unrated title has no rank", B.rank(film("none"), st), None)
check("excluded titles do not move a crowd's average",
      B.crowd_stats(pool + [film("hidden", imdbRating=1.0, imdbVotes=9999, excluded=True)]) == st, True)
s_pool = [{**series, "archiveID": f"series:{i}", "imdbRating": r, "imdbVotes": 2000}
          for i, r in enumerate([7.0, 8.0, 9.0])]
st2 = B.crowd_stats(pool + s_pool)
check("series are measured against series", ("imdb", True) in st2 and st2[("imdb", True)][0] == 8.0, True)
check("control: films' average is not moved by series", st2[("imdb", False)] == st[("imdb", False)], True)

print("enrich_tv_ratings: only an id OMDb calls a series")
check("a rated series is used", E.series_rating({"omdb_type": "series", "imdb_rating": 8.8, "imdb_votes": 112538}),
      (8.8, 112538))
check("an id that answers as a movie is not", E.series_rating({"omdb_type": "movie", "imdb_rating": 6.9, "imdb_votes": 800}),
      None)
check("an entry from the films' backfill (no type yet) is re-asked",
      E.needs_omdb({"imdb_rating": 7.0, "fetched_at": "2026-10-27T00:00:00Z"}, E._now()), True)

print("reconcile: the card carries what the spine says")
card = rt.series_card({"seriesID": "fawlty-towers-1975", "title": "Fawlty Towers", "yearStart": 1975,
                       "seasons": [], "episodesCount": 12, "tvmazeRating": 8.5,
                       "imdbRating": 8.8, "imdbVotes": 112538})
check("IMDb's rating of the series", (card["imdbRating"], card["imdbVotes"]), (8.8, 112538))
check("TVmaze's beside it", card["tvmazeRating"], 8.5)
reviewed = {"UFO.complete": (4.6, 14), "UFO.alt": (4.0, 3)}
check("a one-item series takes its upload's reviewers",
      rt._source_reviews({"sourceID": "UFO.complete", "sourceIDs": ["UFO.complete", "UFO.alt"]}, reviewed),
      {"avgRating": 4.6, "numReviews": 14})
check("control: a TVmaze spine has no source upload", rt._source_reviews({"tvmazeID": 1}, reviewed), {})

print("the DB and the index")
db = sqlite3.connect(":memory:")
bs.create_schema(db)
cols = [r[1] for r in db.execute("PRAGMA table_info(items)")]
check("ratingRank is the items table's last column", cols[-1], "ratingRank")
with tempfile.TemporaryDirectory() as td:
    out = Path(td) / "t.sqlite"
    pf = {"downloadURL": "x", "playbackVerified": True, "posterURL": "p", "hasRealArtwork": True,
          "genres": [], "collections": []}
    bs.build_db_obj({"items": [{**harakiri, **pf}, {**vierte, **pf}, {**film("plain"), **pf}]
                     + [{**i, **pf} for i in pool[:4]]}, out, materialize_episodes=False)
    got = dict(sqlite3.connect(out).execute("SELECT archiveID, ratingRank FROM items"))
    check("the DB ranks Harakiri above Der Vierte", got["harakiri"] > got["vierte"], True)
    check("an unrated film's rank is NULL", got["plain"], None)
src = (R / "tools" / "build_catalog_index.py").read_text()
check("the index declares ratingRank100 last", '"noRecommend", "ratingRank100"],' in src, True)
check("the index row ends with it", "hero, minutes, no_rec, rank100])" in src, True)

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
