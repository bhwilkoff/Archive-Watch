#!/usr/bin/env python3
"""Does searching a film's exact title return that film first?

The app orders search by FTS `rank` alone, which scores the WHOLE document —
so a film whose synopsis repeats a word outranks the film actually titled it.
Measured against the served DB on the 25 most popular films, searching each
one's exact title: 15 came first, "Frankenstein" ranked 7th, "Abraham Lincoln"
4th, and "Suddenly" was not in the top ten at all.

Adding an exact-title term ahead of rank, with popularity as the LAST
tie-break, put all 25 first. Popularity must stay last: ordering by it first
lets a famous film outrank an exact title match, which is the same failure
wearing different clothes.

This is the instrument for that claim — run it against a freshly published
catalog.sqlite to catch a regression in ranking, which is otherwise invisible
(search returns results either way; only their ORDER is wrong).

Usage:
  curl -sL -o cat.zz <catalog-db release>/catalog.sqlite.zz
  python3 -c "import zlib;open('cat.sqlite','wb').write(zlib.decompress(open('cat.zz','rb').read(),-15))"
  python3 tools/audit_search_quality.py cat.sqlite [--sample 25]
"""
import argparse, sqlite3, sys

# Mirrors CatalogDB.search's ordering. Keep in step with it — that is the
# point of the tool.
ORDER = "(LOWER(i.title) = LOWER(?)) DESC, rank, i.popularityScore DESC"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db")
    ap.add_argument("--sample", type=int, default=25)
    ap.add_argument("--order", default=ORDER, help="override to compare orderings")
    args = ap.parse_args()

    db = sqlite3.connect(args.db)
    titles = [t[0] for t in db.execute(
        """SELECT title FROM items
           WHERE contentType='feature-film' AND hasRealArtwork=1 AND playable=1
           ORDER BY popularityScore DESC LIMIT ?""", (args.sample,))]

    firsts, misses, bad = 0, 0, []
    for title in titles:
        q = '"' + title.replace('"', '') + '"'
        binds = [q] + ([title] if "?" in args.order else [])
        rows = db.execute(f"""SELECT i.title FROM items_fts f
            JOIN items i ON i.archiveID = f.archiveID
            WHERE items_fts MATCH ? AND i.contentType NOT IN ('tv-special')
            ORDER BY {args.order} LIMIT 10""", binds).fetchall()
        pos = next((n for n, (t,) in enumerate(rows, 1)
                    if t.strip().lower() == title.strip().lower()), None)
        if pos == 1:
            firsts += 1
        else:
            bad.append((title, pos))
            if pos is None:
                misses += 1

    print(f"exact-title searches: {firsts}/{len(titles)} returned first, "
          f"{misses} not in the top ten")
    for title, pos in bad[:12]:
        print(f"  {title[:48]:48} rank={pos}")
    # A regression here is silent in the app — results still appear, just in the
    # wrong order — so fail loudly enough for CI to notice.
    return 0 if firsts == len(titles) else 1


if __name__ == "__main__":
    sys.exit(main())
