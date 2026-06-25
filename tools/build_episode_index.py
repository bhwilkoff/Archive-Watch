#!/usr/bin/env python3
"""
build_episode_index.py — a small client-searchable index of TV EPISODES for the web viewer.

The web data plane (Decision 029) is catalog-index.json + the archive.org metadata API — it has
NO FTS and NO episodes (episodes live in series/*.json, fetched per-series at runtime). So the web
Search never found individual episodes. This emits `episodes-index.json` (served from Pages, like
catalog-index.json) — a compact array the viewer lazy-loads on first search and filters client-side,
then routes a hit to #/series/{slug}.

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
        for season in d.get("seasons", []):
            for ep in season.get("episodes", []):
                if not ep.get("downloadURL"):   # only playable episodes are worth surfacing
                    continue
                eps.append([
                    slug, series_title, ep.get("seasonNumber"), ep.get("episodeNumber"),
                    ep.get("title"), ep.get("stillURL"), ep.get("year"),
                ])
    out = {
        "fields": ["slug", "series", "season", "episode", "title", "still", "year"],
        "count": len(eps),
        "episodes": eps,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[episode-index] wrote {OUT.name}: {len(eps):,} episodes "
          f"({OUT.stat().st_size/1_000_000:.1f} MB)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
