#!/usr/bin/env python3
"""A TV series carries TVmaze's rating from its spine to its card to the app's
database and the web index, so Top Rated orders television (owner, 2026-10-27:
"Yes to ratings on TV series (TV maze is great)").

Found: no series card had a rating (reconcile_tv_catalog wrote None), so Top
Rated tied every series and SQLite returned them in insertion order, which read
as A–Z. Cases: the rating reaches the card, the `tvmazeRating` column and the
index's rating column. Controls: it is never written as IMDb's, and a film's
index rating stays IMDb's. Since Decision 171 Top Rated sorts on ratingRank and
the index's rating column is IMDb's alone; tools/test_best_rating.py holds that.
"""
import sqlite3
import sys
import tempfile
from pathlib import Path

R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import build_sqlite as bs
import reconcile_tv_catalog as rt

ok = True


def check(name, got, want):
    global ok
    good = got == want
    ok &= good
    print(f"  {'ok  ' if good else 'FAIL'} {name}" + ("" if good else f"  got={got!r} want={want!r}"))


card = rt.series_card({"seriesID": "the-twilight-zone-1959", "title": "The Twilight Zone",
                       "yearStart": 1959, "seasons": [], "episodesCount": 0, "tvmazeRating": 8.9})
check("the card carries the spine's TVmaze rating", card.get("tvmazeRating"), 8.9)
check("control: it is never written as IMDb's", card.get("imdbRating"), None)

db = sqlite3.connect(":memory:")
bs.create_schema(db)
cols = [r[1] for r in db.execute("PRAGMA table_info(items)")]
check("the items table has tvmazeRating", "tvmazeRating" in cols, True)
check("... after every older column, so an older reader's positions hold",
      cols[-2:], ["tvmazeRating", "ratingRank"])

with tempfile.TemporaryDirectory() as td:
    film = {"archiveID": "nosferatu", "title": "Nosferatu", "year": 1922, "contentType": "silent-film",
            "imdbRating": 7.9, "imdbVotes": 100000, "downloadURL": "x", "playbackVerified": True,
            "posterURL": "p", "hasRealArtwork": True, "genres": [], "collections": []}
    out = Path(td) / "t.sqlite"
    bs.build_db_obj({"items": [card, film]}, out, materialize_episodes=False)
    got = dict(sqlite3.connect(out).execute("SELECT archiveID, tvmazeRating FROM items"))
    check("the DB row carries it", got.get("series:the-twilight-zone-1959"), 8.9)
    check("control: a film has none", got.get("nosferatu"), None)

src = (R / "tools" / "build_catalog_index.py").read_text()
check("the web index's rating column is IMDb's alone (Decision 171), so a reader can label it",
      'r = it.get("imdbRating")\n' in src and 'it.get("tvmazeRating") if' not in src, True)

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
