#!/usr/bin/env python3
"""
build_episode_index.py — episodes as first-class items for the web viewer (Decision 045).

The web data plane (Decision 029) is catalog-index.json + the archive.org metadata API — it has
NO FTS and NO episodes (episodes live in series/*.json, fetched per-series at runtime). This emits
`episodes-index.json` (served from Pages, like catalog-index.json) so the viewer can treat each
playable episode as an item: it carries the episode's own `archiveID` (so favorites / playlists /
share / Detail all key off it like any film, resolving via the id-map) plus the series linkage for
the byline + a "Part of <series>" link. Each row:
  [archiveID, slug, series, season, episode, title, still, year]

Run: python tools/build_episode_index.py   (after the series/ spines are present)
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SERIES_DIR = REPO / "series"
OUT = REPO / "episodes-index.json"
CATALOG = REPO / "catalog.json"
sys.path.insert(0, str(REPO / "tools"))
from build_sqlite import _is_adult  # noqa: E402  (Decision 105: one adult predicate)


def _mature_gate():
    """Decision 105: the web has no mature setting, so the index it reads must
    already be the apps' default-off state. Episodes never passed through
    build_catalog_index — nine Playboy After Dark episodes were in this file
    while their series card was not in the public index (measured 2026-09-10).
    An episode is out when its own catalog row, its series card, or its own
    title trips the ONE predicate."""
    by = {}
    if CATALOG.exists():
        try:
            for it in json.loads(CATALOG.read_text(encoding="utf-8")).get("items", []):
                by[it.get("archiveID")] = it
        except Exception:  # noqa: BLE001
            by = {}

    def out(aid, slug, ep_title, series_title):
        card = by.get(f"series:{slug}") or by.get(slug)
        if card is not None and _is_adult(card):
            return True
        row = by.get(aid)
        if row is not None and _is_adult(row):
            return True
        return bool(_is_adult({"title": ep_title or "", "collections": []})
                    or _is_adult({"title": series_title or "", "collections": []}))
    return out


def main() -> int:
    eps = []
    mature = _mature_gate()
    withheld = 0
    for f in sorted(SERIES_DIR.glob("*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        slug = d.get("seriesID") or f.stem
        series_title = d.get("title") or slug
        seen = set()
        for season in d.get("seasons", []):
            for ep in season.get("episodes", []):
                aid = ep.get("archiveID")
                if not (ep.get("downloadURL") and aid) or aid in seen:
                    continue   # only playable episodes with a real id, once each
                seen.add(aid)
                if mature(aid, slug, ep.get("title"), series_title):
                    withheld += 1
                    continue
                eps.append([
                    aid, slug, series_title, ep.get("seasonNumber"), ep.get("episodeNumber"),
                    ep.get("title"), ep.get("stillURL"), ep.get("year"),
                ])
    out = {
        "fields": ["archiveID", "slug", "series", "season", "episode", "title", "still", "year"],
        "count": len(eps),
        "episodes": eps,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[episode-index] wrote {OUT.name}: {len(eps):,} episodes "
          f"({OUT.stat().st_size/1_000_000:.1f} MB); {withheld} mature withheld", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
