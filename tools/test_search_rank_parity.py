#!/usr/bin/env python3
"""Search ranking is the same on Apple and Android (tvOS-DESIGN 3.3b).

Reads the ORDER BY the apps SHIP -- CatalogDB.search (Swift) and
CatalogDatabase.SEARCH_ORDER (Kotlin) -- and runs each against a small FTS5
fixture shaped like catalog.sqlite. FTS rank alone put a 1896 park film above
Metropolis for "metro" and a cartoon above His Girl Friday for "his girl".
The control runs the old `ORDER BY rank` and must fail the same assertions.
"""
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "ArchiveWatch/ArchiveWatch/Store/CatalogDB.swift"
KOTLIN = ROOT / "android/app/src/main/java/app/archivewatch/android/data/CatalogDatabase.kt"


def swift_order() -> str:
    s = SWIFT.read_text()
    m = re.search(r"WHERE items_fts MATCH \?1[^\n]*\n\s*ORDER BY (.*?)\n\s*LIMIT", s, re.S)
    if not m:
        sys.exit("FAIL: ORDER BY not found in CatalogDB.search")
    return m.group(1)


def kotlin_order() -> str:
    s = KOTLIN.read_text()
    m = re.search(r"const val SEARCH_ORDER =(.*?rank\")", s, re.S)
    if not m:
        sys.exit("FAIL: SEARCH_ORDER not found in CatalogDatabase.kt")
    return "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)))


# (archiveID, title, director, hasRealArtwork, artworkSource, popularity, names, extra)
ROWS = [
    ("park", "Parque Natural Metropolitano", None, 0, "archive", 5, "", ""),
    ("metro1927", "Metropolis", "Fritz Lang", 1, "tmdb", 900, "Brigitte Helm", ""),
    ("outtakes", "Metropolis Experimental Outtakes", None, 0, "generated", 3, "", ""),
    ("bugs", "Bugs Beetle and His Orchestra", None, 1, "tmdb", 40, "", "his girl"),
    ("hgf", "His Girl Friday", "Howard Hawks", 1, "tmdb", 800, "Cary Grant", ""),
    ("news", "Suspense Story: Press Club Hears Hitchcock", None, 0, "archive", 2, "", ""),
    ("notorious", "Notorious", "Alfred Hitchcock", 1, "tmdb", 700, "", "hitchcock"),
    ("gen1930", "The General", None, 0, "archive", 10, "", ""),
    ("gen1926", "The General", "Clyde Bruckman", 1, "tmdb", 950, "Buster Keaton", ""),
]


def db():
    c = sqlite3.connect(":memory:")
    c.execute("CREATE TABLE items (archiveID TEXT, title TEXT, director TEXT, "
              "hasRealArtwork INTEGER, artworkSource TEXT, popularityScore INTEGER)")
    c.execute("CREATE VIRTUAL TABLE items_fts USING fts5(archiveID UNINDEXED, title, names, extra)")
    for aid, t, d, art, src, pop, names, extra in ROWS:
        c.execute("INSERT INTO items VALUES (?,?,?,?,?,?)", (aid, t, d, art, src, pop))
        c.execute("INSERT INTO items_fts VALUES (?,?,?,?)",
                  (aid, t, " ".join(x for x in [names, d or ""] if x), extra))
    return c


def fts(raw):
    toks = [t for t in re.split(r"[^a-z0-9]+", raw.lower()) if len(t) >= 2]
    return " ".join(f'"{t}"*' for t in toks)


def top(conn, order, q):
    sql = ("SELECT i.archiveID FROM items_fts f JOIN items i ON i.archiveID = f.archiveID "
           f"WHERE items_fts MATCH ?1 ORDER BY {order} LIMIT ?3")
    return [r[0] for r in conn.execute(sql, (fts(q), q, 10))]


CASES = [
    ("metro", "metro1927", "park"),
    ("his girl", "hgf", "bugs"),
    ("hitchcock", "notorious", "news"),
    ("the general", "gen1926", "gen1930"),
]


def check(label, order):
    conn = db()
    bad = 0
    for q, first, below in CASES:
        got = top(conn, order, q)
        ok = got and got[0] == first and (below not in got or got.index(below) > got.index(first))
        print(f"{'PASS' if ok else 'FAIL'} [{label}] {q!r}: {got[:3]}")
        bad += not ok
    return bad


fails = check("swift", swift_order()) + check("kotlin", kotlin_order())
if swift_order().split() != kotlin_order().split():
    print("FAIL: Swift and Kotlin ORDER BY differ"); fails += 1
else:
    print("PASS: Swift and Kotlin ORDER BY are the same text")
# Control: the old ranking must lose at least one case.
ctl = check("control: ORDER BY rank", "rank")
if ctl == 0:
    print("FAIL: control passed -- the fixture cannot tell the rankings apart"); fails += 1
else:
    print(f"PASS: control fails {ctl} case(s), as it should")
sys.exit(1 if fails else 0)
