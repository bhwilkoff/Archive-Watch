#!/usr/bin/env python3
"""Report-only: a Browse chip that would return nothing when tapped.

The facet chips and the grid they filter do NOT share a WHERE clause. Chips come
from `topGenres` / `topKeywords` / `topStudios` / `decadeCounts`, which apply only
the adult filter; the grid additionally drops commercials, standalone TV
(tv-special / tv-episode) and unplayable items. So a chip can be offered on the
strength of rows the grid will then throw away, and the viewer taps a filter that
returns an empty screen.

That failure has happened here before and was visible to the owner: the Classic TV
category tile returned zero rows for weeks because its WHERE clause contradicted
itself (2026-06-11). This runs every publish so the next one is caught by a build,
not by the owner.

Measured 2026-08-18: 24 genre, 40 keyword, 40 studio and 14 decade chips, and NONE
returns fewer than 5 — the asymmetry exists but does not bite, because the top-N
chips are all high-population. It is therefore reported, not "fixed": changing the
facet queries to match the grid would be a change with no defect behind it, and
this check is what makes a future drift visible.

  python3 tools/audit_browse_facets.py --db catalog.sqlite [--min 5]
"""
import argparse, sqlite3, sys

# What browse() excludes and the facet queries do not.
BROWSE = ("AND i.contentType != 'commercial' "
          "AND i.contentType NOT IN ('tv-special','tv-episode') "
          "AND i.playable = 1")

FACETS = (("genre", "item_genres", "genre", 24),
          ("keyword", "item_keywords", "keyword", 40),
          ("studio", "item_studios", "studio", 40))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="catalog.sqlite")
    ap.add_argument("--min", type=int, default=5,
                    help="a chip yielding fewer than this is reported")
    args = ap.parse_args()
    db = sqlite3.connect(args.db)
    thin = []

    for label, table, col, limit in FACETS:
        chips = [r[0] for r in db.execute(
            f"""SELECT x.{col}, COUNT(*) c FROM {table} x JOIN items i USING(archiveID)
                GROUP BY x.{col} ORDER BY c DESC, x.{col} LIMIT {limit}""")]
        for v in chips:
            n = db.execute(
                f"""SELECT COUNT(*) FROM {table} x JOIN items i USING(archiveID)
                    WHERE x.{col} = ? {BROWSE}""", (v,)).fetchone()[0]
            if n < args.min:
                thin.append((label, v, n))
        print(f"[facets] {label}: {len(chips)} chips checked")

    decades = [r[0] for r in db.execute(
        """SELECT i.decade FROM items i
           WHERE i.decade BETWEEN 1890 AND 2029 AND i.contentType != 'commercial'
           GROUP BY i.decade""")]
    for d in decades:
        n = db.execute(f"SELECT COUNT(*) FROM items i WHERE i.decade = ? {BROWSE}",
                       (d,)).fetchone()[0]
        if n < args.min:
            thin.append(("decade", f"{d}s", n))
    print(f"[facets] decade: {len(decades)} chips checked")

    if thin:
        print(f"\n[facets] {len(thin)} chip(s) would return almost nothing:")
        for label, v, n in thin:
            print(f"    {label:8} '{v}' -> {n}")
    else:
        print("\n[facets] every offered chip returns results")
    return 0


if __name__ == "__main__":
    sys.exit(main())
