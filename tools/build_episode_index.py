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


def main() -> int:
    eps = []
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
          f"({OUT.stat().st_size/1_000_000:.1f} MB)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
