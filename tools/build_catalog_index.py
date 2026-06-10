#!/usr/bin/env python3
"""
build_catalog_index.py — emit a tiny, browser-friendly search index of the FULL
catalog for the public editorial tool (index.html "Browse the catalog").

The full catalog (~95 MB) lives on a GitHub Release and can't be fetched from a
browser (Release assets send no CORS header — verified). So we publish a slim
index to GitHub Pages (same-origin as the tool). To keep it small AND
git-delta-friendly (it's committed + refreshed on every DB update), each item is
a positional array, not an object:

    [archiveID, title, year, contentType, poster]

`poster` is the designed-artwork URL (TMDb/Wikidata/commons/generated) or null;
the browser falls back to archive.org/services/img/{id} when null — so the web
viewer keeps the same visual dignity as the apps without shipping the 95 MB
catalog. (Schema 2; schema-1 consumers ignore the extra column.) Adult-collection items (featured.json.adultCollections)
are excluded — this index feeds a PUBLIC tool.

Reads ./catalog.json (fetch it first via catalog_release.py). Writes
./catalog-index.json at the repo root (served by Pages).
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
FEATURED = REPO / "featured.json"
OUT = REPO / "catalog-index.json"


def main():
    if not CATALOG.exists():
        print("[index] no catalog.json — run tools/catalog_release.py fetch first", file=sys.stderr)
        return 1
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = catalog.get("items", catalog if isinstance(catalog, list) else [])

    adult = set()
    if FEATURED.exists():
        try:
            adult = {c.lower() for c in json.loads(FEATURED.read_text())
                     .get("adultCollections", [])}
        except Exception:  # noqa: BLE001
            adult = set()

    rows = []
    for it in items:
        if it.get("excluded"):          # rights audit (Decision 027)
            continue
        cols = {c.lower() for c in (it.get("collections") or [])}
        if adult & cols:
            continue
        aid = it.get("archiveID")
        if not aid:
            continue
        poster = it.get("posterURL")
        if poster and "archive.org/services/img" in poster:
            poster = None          # derivable from the id; don't bloat the index
        rows.append([aid, it.get("title") or aid, it.get("year"),
                     it.get("contentType") or "", poster])

    # Sort by popularity so the most useful titles search/scroll first.
    pop = {it.get("archiveID"): (it.get("popularityScore") or 0) for it in items}
    rows.sort(key=lambda r: pop.get(r[0], 0), reverse=True)

    out = {
        "schema": 2,
        "updatedAt": catalog.get("updatedAt") or "",
        "count": len(rows),
        "fields": ["id", "title", "year", "contentType", "poster"],
        "items": rows,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    mb = OUT.stat().st_size / 1_000_000
    print(f"[index] wrote {OUT.name}: {len(rows):,} items, {mb:.1f} MB", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
