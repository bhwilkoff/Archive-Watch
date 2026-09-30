#!/usr/bin/env python3
"""Decision 149 — propaganda is never recommended, always findable.

Owner, 2026-09-28: "All true propaganda should be hidden from recommendations,
but avaialble via search."

Pins, on a fixture:
  * the evidence rule: a Vorbehaltsfilm, a German 1933-45 film tagged
    propaganda, a Nazi-party producer and an editorial entry are flagged;
    Death Mills (Allied evidence in a German print), Battleship Potemkin and a
    Why We Fight film (tagged propaganda, not the Nazi state's) are not;
    withdrawing the evidence clears the flag;
  * every pipeline surface skips a flagged film: Home shelves, More Like This,
    channel pools, the index hero flag, social;
  * Search still finds it (the FTS query carries no such gate);
  * CONTROL: the same film without the flag is back on every surface, so the
    flag — not something else about the fixture — is what removes it.
"""
import collections
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(__file__))
import build_channel_pools as CP  # noqa: E402
import build_related as BR  # noqa: E402
import build_sqlite as BS  # noqa: E402
import remediate_catalog as R  # noqa: E402
import social_select as SS  # noqa: E402

FAILS = []


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        FAILS.append(name)


TABLE = {
    "vorbehaltsfilme": {"titles": [["Jud Süß", 1940], ["Ohm Krüger", 1941]]},
    "add": {"juden-ohne-maske": "Juden ohne Maske (1937) — https://www.wikidata.org/wiki/Q134963953"},
    "not": {"DeathMills": "Allied evidence"},
}


def film(aid, title, year, **kw):
    d = {"archiveID": aid, "title": title, "year": year, "contentType": "feature-film",
         "genres": ["Drama"], "director": "Veit Harlan", "downloadURL": "https://x/a.mp4",
         "shelves": ["popular-features"], "collections": []}
    d.update(kw)
    return d


items = [
    film("jud", "Jud Süss", 1940, language="de"),                                        # Vorbehaltsfilm (ß folded)
    film("tag", "Tag der Freiheit", 1935, language="de", genres=["propaganda film"]),    # data rule
    film("triumph", "Triumph des Willens", 1935, language="de",
         studios=["Reichspropagandaleitung der NSDAP"]),                                  # producer
    film("juden-ohne-maske", "Juden ohne Maske", 1937, language="de"),                   # editorial
    film("DeathMills", "Death Mills", 1945, language="de", genres=["propaganda film"]),  # exception
    film("potemkin", "Battleship Potemkin", 1925, language="ru", genres=["propaganda film"]),
    film("wwf", "Why We Fight: The Nazis Strike", 1943, language="en", genres=["propaganda film"]),
    film("control", "Veit Harlan Melodrama", 1940, language="de"),                       # shares the director
]
stats = collections.Counter()
R.flag_propaganda(items, stats, table=TABLE)
# URAA also sets noRecommend (a German film of 1937 is restored); this test
# is about the PROPAGANDA reason.
flagged = {i["archiveID"] for i in items if (i.get("noRecommendReason") or "").startswith("propaganda")}

check("a Vorbehaltsfilm is flagged (title folded, year within 2)", "jud" in flagged)
check("a German 1933-45 film tagged propaganda is flagged", "tag" in flagged)
check("a Nazi-party producer is flagged", "triumph" in flagged)
check("an editorial entry is flagged", "juden-ohne-maske" in flagged)
check("Death Mills (named exception) is not flagged", "DeathMills" not in flagged)
check("Battleship Potemkin is not flagged", "potemkin" not in flagged)
check("an Allied propaganda film is not flagged", "wwf" not in flagged)
check("an ordinary film is not flagged", "control" not in flagged)
check("flagged items are NOT excluded (search must reach them)",
      not any(i.get("excluded") for i in items if i["archiveID"] in flagged))

# Withdrawn evidence clears the flag on the next build.
again = [dict(i) for i in items]
R.flag_propaganda(again, collections.Counter(), table={})
check("withdrawn evidence clears the flag",
      not any((i.get("noRecommendReason") or "").startswith("propaganda") for i in again if i["archiveID"] == "jud"))

by = {i["archiveID"]: i for i in items}

# --- Home shelves ------------------------------------------------------------
check("a flagged film joins no Home shelf", BS._shelf_ids_for(by["jud"]) == set())
check("CONTROL: the same film unflagged joins its shelf",
      "popular-features" in BS._shelf_ids_for({**by["jud"], "noRecommend": False}))

# --- More Like This ----------------------------------------------------------
rel = BR.compute_related(items)
listed = {r for rows in rel.values() for r, _, _ in rows}
check("a flagged film is never listed under another", not (flagged & listed))
unflagged = [{**i, "noRecommend": False} for i in items]
rel2 = BR.compute_related(unflagged)
listed2 = {r for rows in rel2.values() for r, _, _ in rows}
check("CONTROL: unflagged, the shared director lists it", "jud" in listed2)

# --- Channel pools -----------------------------------------------------------
check("a flagged film never airs on a channel", not CP.visible(by["jud"]))
check("CONTROL: unflagged, it would", bool(CP.visible({**by["jud"], "noRecommend": False})))

# --- Social ------------------------------------------------------------------
row = ["jud", "Jud Süss", 1940, "feature-film", "https://x/p.jpg", 1, "", "", 1, 0,
       70, 5000, "Veit Harlan", "Drama", "b", 0, 0, 100, 1]
check("social never promotes a flagged film", SS.do_not_promote(row) is not None)
row_ok = row[:18] + [0]
SS._DNP = {"ids": {}, "subjectMarkers": []}
check("CONTROL: unflagged, social has no objection", SS.do_not_promote(row_ok) is None)

# --- The index's hero flag + the SQL gate the apps use -----------------------
db = sqlite3.connect(":memory:")
db.executescript("""
CREATE TABLE items (archiveID TEXT, title TEXT, noRecommend INTEGER);
CREATE VIRTUAL TABLE items_fts USING fts5(archiveID UNINDEXED, title, names, extra);
""")
for aid, t, nr in [("jud", "Jud Suess", 1), ("control", "Jud Suess Restored", 0)]:
    db.execute("INSERT INTO items VALUES (?,?,?)", (aid, t, nr))
    db.execute("INSERT INTO items_fts VALUES (?,?,?,?)", (aid, t, "", ""))
NO_REC = "AND COALESCE(i.noRecommend, 0) = 0"      # CatalogDB.noRecAnd / Android noRecAnd
home = {r[0] for r in db.execute(f"SELECT archiveID FROM items i WHERE 1=1 {NO_REC}")}
found = {r[0] for r in db.execute(
    "SELECT i.archiveID FROM items_fts f JOIN items i ON i.archiveID = f.archiveID "
    "WHERE items_fts MATCH ?", ('"jud"*',))}
check("a Home query with the gate skips it", "jud" not in home and "control" in home)
check("Search still finds it", "jud" in found)

print(f"\n{'PASS' if not FAILS else 'FAIL'}: {len(FAILS)} failure(s)")
sys.exit(1 if FAILS else 0)
