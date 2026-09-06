#!/usr/bin/env python3
"""
build_channel_pools.py — emit channel-pools.json for the web viewer's Channels
guide (PARITY §5).

The apps build each preset channel's program pool with on-device CatalogDB
queries (genre/type, popularity top-90, playable). The web index carries no
runtime/genre columns, so the pools are precomputed here from the full
catalog.json and served from Pages; the BROWSER then runs the same
date-seeded ChannelScheduler (JS port) so the schedule anchors to the
viewer's LOCAL 6 AM broadcast day exactly like the apps.

Pool rules mirror the Swift ChannelsView.rebuild():
  - playable (downloadURL present), not rights-excluded, not adult
  - matching contentType and/or genre, popularity top-90
  - animation pool: color-emphasized, B&W/silent capped at ~10% (Decision 025)
Plus a 60-item commercials pool for the between-program ad weave (#89).

Run in publish-db after the catalog fetch; commits alongside catalog-index.
"""

import json
import random
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
INDEX = REPO / "catalog-index.json"
OUT = REPO / "channel-pools.json"

PRESETS = [
    {"id": "drama",   "title": "Drama Theater",   "tagline": "The big stories",        "accent": "#FF5C35", "genre": "Drama"},
    {"id": "comedy",  "title": "Comedy Hour",     "tagline": "Laughs around the clock","accent": "#E8A317", "genre": "Comedy"},
    {"id": "noir",    "title": "Crime & Mystery", "tagline": "Shadows and suspects",   "accent": "#2D5BFF", "genre": "Crime"},
    {"id": "thrill",  "title": "Thriller",        "tagline": "Edge of your seat",      "accent": "#0047FF", "genre": "Thriller"},
    {"id": "horror",  "title": "Horror",          "tagline": "After dark",             "accent": "#7C5BBA", "genre": "Horror"},
    {"id": "western", "title": "Western Trail",   "tagline": "The frontier rolls on",  "accent": "#C9A66B", "genre": "Western"},
    {"id": "scifi",   "title": "Sci-Fi Theater",  "tagline": "Worlds beyond",          "accent": "#3FA796", "genre": "Science Fiction"},
    {"id": "silent",  "title": "Silent Cinema",   "tagline": "The age before sound",   "accent": "#C9A66B", "type": "silent-film"},
    {"id": "cartoon", "title": "Cartoon Classics","tagline": "Animation all day",      "accent": "#FF4D8D", "type": "animation"},
    {"id": "news",    "title": "Newsreel Desk",   "tagline": "History as it broke",    "accent": "#8A8F98", "type": "newsreel"},
    {"id": "docs",    "title": "Documentary",     "tagline": "Real stories",           "accent": "#3FA796", "type": "documentary"},
    {"id": "tv",        "title": "Classic TV",  "tagline": "Vintage television",   "accent": "#2D5BFF", "type": "tv-special"},
    {"id": "tv-comedy", "title": "TV Comedy",   "tagline": "Sitcoms & sketch",     "accent": "#E8A317", "type": "tv-special", "genre": "Comedy"},
    {"id": "tv-drama",  "title": "TV Drama",    "tagline": "Series drama",         "accent": "#FF5C35", "type": "tv-special", "genre": "Drama"},
    {"id": "tv-western","title": "TV Westerns", "tagline": "Saddle up, every hour","accent": "#C9A66B", "type": "tv-special", "genre": "Western"},
]

POOL_LIMIT = 90
AD_LIMIT = 60


def visible(it):
    return (not it.get("excluded") and not it.get("isAdult")
            and it.get("downloadURL"))


def matches(it, preset):
    if t := preset.get("type"):
        if it.get("contentType") != t:
            return False
    if g := preset.get("genre"):
        if g not in (it.get("genres") or []):
            return False
    return True


def bw_or_silent(it):
    if it.get("colorMode") == "color":
        return False
    if it.get("colorMode") == "bw" or it.get("isSilentFilm"):
        return True
    y = it.get("year")
    return bool(y and y < 1930)


def entry(it):
    return [it["archiveID"], it.get("title") or it["archiveID"],
            it.get("runtimeSeconds"), it["downloadURL"],
            it.get("contentType")]


def index_ids() -> set:
    """The ids the SERVED index actually carries.

    catalog.json keeps every copy of a film, including the ones the duplicate
    merge collapsed away (Decision 040/085); the index keeps only survivors.
    Building the pools from catalog.json therefore scheduled programmes under
    ids the index does not carry, and selecting one on the Roku loaded nothing
    and left the PREVIOUS film's Detail on screen. Measured 2026-09-06: 400 of
    1,218 programmes — 32.8% of the guide — every one of them a merged-away id.

    The index is the gatekeeper for every client that reads it (its own build
    says so). This is Decision 105's rule one surface over: do not
    re-implement the membership test, ask the thing that owns it.
    """
    if not INDEX.exists():
        raise SystemExit(f"{INDEX.name} is missing — build it before the pools; "
                         "an ungated pool schedules films the guide cannot open")
    rows = json.loads(INDEX.read_text())["items"]
    return {str(r[0]) for r in rows}


def main():
    items = json.loads(CATALOG.read_text())
    items = items["items"] if isinstance(items, dict) else items
    served = index_ids()
    before = sum(1 for i in items if visible(i))
    pool_src = [i for i in items if visible(i) and i.get("archiveID") in served]
    print(f"  eligible {before} -> {len(pool_src)} after gating on the served index")
    pool_src.sort(key=lambda i: -(i.get("popularityScore") or 0))

    channels = []
    for preset in PRESETS:
        matched = [i for i in pool_src if matches(i, preset)]
        if preset.get("type") == "animation":
            # Color leads; B&W/silent capped at ~10% (Decision 025).
            color = [i for i in matched if not bw_or_silent(i)]
            bw = [i for i in matched if bw_or_silent(i)]
            cap = max(3, int(len(color[:POOL_LIMIT]) * 0.10))
            matched = color[:POOL_LIMIT] + bw[:cap]
        pool = matched[:POOL_LIMIT]
        if len(pool) < 5:
            print(f"  skip {preset['id']}: only {len(pool)} programs")
            continue
        channels.append({
            "id": preset["id"], "title": preset["title"],
            "tagline": preset["tagline"], "accent": preset["accent"],
            "programs": [entry(i) for i in pool],
        })
        print(f"  {preset['id']}: {len(pool)} programs")

    rng = random.Random(20260612)   # stable file across runs with same catalog
    ads = [i for i in pool_src if i.get("contentType") == "commercial"]
    rng.shuffle(ads)

    OUT.write_text(json.dumps({
        "schema": 1,
        "channels": channels,
        "commercials": [entry(i) for i in ads[:AD_LIMIT]],
    }, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {OUT.name}: {len(channels)} channels, "
          f"{OUT.stat().st_size / 1e3:.0f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
