#!/usr/bin/env python3
"""Strip `fav-<username>` pseudo-collections from a catalog.json.

These are per-user "favorites" markers scraped from Archive.org. They make
up ~half the catalog file (1.17M of 1.34M collection entries) but never
surface in the UI — they only fed "More Like This" scoring, where a
mega-popular film's shared fans actually hurt relevance. Dropping them
roughly halves the bundle and leaves the real collections + genre +
decade + director signals intact.

Usage: python3 tools/slim-catalog.py <catalog.json> [more.json ...]
"""
import json, os, sys


def slim(path: str) -> None:
    before = os.path.getsize(path)
    with open(path) as f:
        data = json.load(f)
    items = data.get("items", [])
    removed = 0
    for it in items:
        cols = it.get("collections")
        if not cols:
            continue
        kept = [c for c in cols if not c.startswith("fav-")]
        removed += len(cols) - len(kept)
        it["collections"] = kept
    # Compact separators to shave whitespace too.
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    after = os.path.getsize(path)
    print(f"{path}: {before/1e6:.1f}MB -> {after/1e6:.1f}MB "
          f"(removed {removed:,} fav- entries)")


if __name__ == "__main__":
    targets = sys.argv[1:]
    if not targets:
        print(__doc__)
        sys.exit(1)
    for t in targets:
        slim(t)
