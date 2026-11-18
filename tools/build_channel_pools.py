#!/usr/bin/env python3
"""
build_channel_pools.py — each preset channel's program pool, the input of
build_channel_schedule.py (Decision 144), plus the commercials the clients
weave between programs and the Cartoon Marathon's queue (Roku, web).

Pool rules:
  - playable, not rights-excluded, not adult, not noRecommend, in the served index
  - matching contentType and/or genre; classroom and industrial films
    ("ephemeral") only on Documentary
  - ranked by the pipeline's own popularity score (build_sqlite._pop_score)
  - sized by HOURS (POOL_HOURS), not by a count of titles
  - animation: color leads, B&W/silent ~10% of the pool (Decision 025)
Plus a 60-item commercials pool for the between-program ad weave (#89).

Run in publish-db after the catalog fetch; commits alongside catalog-index.
"""

import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_sqlite import _pop_score  # noqa: E402
from build_channel_schedule import slot_seconds  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
INDEX = REPO / "catalog-index.json"
OUT = REPO / "channel-pools.json"
# The whole pool, read only by build_channel_schedule in the same publish-db
# step: never committed or served. channel-pools.json keeps each channel's best
# SERVED_LIMIT for web Party Play, except Cartoon Classics, which it serves
# whole: the Cartoon Marathon on Roku and the web shuffles that list, and
# drew 40 cartoons a session from 90.
FULL_OUT = REPO / "channel-pools-full.json"
SERVED_LIMIT = 90
SERVED_WHOLE = {"cartoon"}

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
    {"id": "docs",    "title": "Documentary",     "tagline": "Real stories",           "accent": "#3FA796", "genre": "Documentary"},
    {"id": "tv",        "title": "Classic TV",  "tagline": "Vintage television",   "accent": "#2D5BFF", "type": "tv-special"},
    {"id": "tv-comedy", "title": "TV Comedy",   "tagline": "Sitcoms & sketch",     "accent": "#E8A317", "type": "tv-special", "genre": "Comedy"},
    {"id": "tv-drama",  "title": "TV Drama",    "tagline": "Series drama",         "accent": "#FF5C35", "type": "tv-special", "genre": "Drama"},
    {"id": "tv-western","title": "TV Westerns", "tagline": "Saddle up, every hour","accent": "#C9A66B", "type": "tv-special", "genre": "Western"},
]

# A week of programming per channel. The pool was the top 90 titles, so Cartoon
# Classics cycled 15.5 hours and every cartoon aired about once a day.
POOL_HOURS = 168
BW_SHARE = 0.10
AD_LIMIT = 60


def visible(it):
    # noRecommend (Decision 149): a channel CHOOSES what plays, so a film that
    # may never be recommended never airs.
    return (not it.get("excluded") and not it.get("isAdult")
            and not it.get("noRecommend") and it.get("downloadURL"))


# The apps' browse rules (CatalogDB.browseSQL): a genre channel carries no
# television or commercials, and Documentary is the GENRE without animation
# (contentType "documentary" holds one film, so the channel was never built).
NOT_ON_GENRE_CHANNELS = {"tv-series", "tv-special", "tv-episode", "commercial"}


def matches(it, preset):
    if not preset.get("type") and it.get("contentType") in NOT_ON_GENRE_CHANNELS:
        return False
    # TMDb files social-guidance films under Drama and Crime, so "Health: Your
    # Posture" and "Boys Beware" led Drama Theater and Crime & Mystery.
    if (it.get("contentType") == "ephemeral" and not preset.get("type")
            and preset.get("genre") != "Documentary"):
        return False
    if preset.get("genre") == "Documentary" and it.get("contentType") == "animation":
        return False
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


def rank_key(it):
    # catalog.json's own popularityScore is the legacy 0-89 band, absent on
    # most items: Metropolis, The Kid and Sherlock Jr. sorted last and never
    # aired. _pop_score is the number the apps sort by (build_sqlite writes it
    # into the DB); the tiebreak is the DB queries' own.
    return (-_pop_score(it), -(it.get("imdbVotes") or 0), it.get("archiveID") or "")


def secs(it):
    return slot_seconds(it.get("runtimeSeconds"), it.get("contentType"))


def take_hours(ranked, hours):
    out, t = [], 0
    for it in ranked:
        if t >= hours * 3600:
            break
        out.append(it)
        t += secs(it)
    return out


def pool_for(preset, ranked):
    """`ranked` is the eligible catalog, best first."""
    matched = [i for i in ranked if matches(i, preset)]
    if preset.get("type") != "animation":
        return take_hours(matched, POOL_HOURS)
    # Color leads; B&W/silent ~10% (Decision 025). The old cut kept the first
    # 90 of color + B&W, so the B&W titles appended after 90 color ones never
    # survived it.
    color = take_hours([i for i in matched if not bw_or_silent(i)], POOL_HOURS * (1 - BW_SHARE))
    bw = take_hours([i for i in matched if bw_or_silent(i)], POOL_HOURS * BW_SHARE)
    return sorted(color + bw, key=rank_key)


def served_slice(preset, pool):
    """The channel-pools.json share of a pool: its best SERVED_LIMIT, keeping
    the animation pool's B&W share, or all of it for SERVED_WHOLE."""
    if preset["id"] in SERVED_WHOLE:
        return pool
    bw = [i for i in pool if bw_or_silent(i)]
    if preset.get("type") != "animation" or not bw or len(pool) <= SERVED_LIMIT:
        return pool[:SERVED_LIMIT]
    n_bw = max(1, round(SERVED_LIMIT * BW_SHARE))
    color = [i for i in pool if not bw_or_silent(i)]
    return sorted(color[:SERVED_LIMIT - n_bw] + bw[:n_bw], key=rank_key)


def main():
    items = json.loads(CATALOG.read_text())
    items = items["items"] if isinstance(items, dict) else items
    served = index_ids()
    before = sum(1 for i in items if visible(i))
    pool_src = [i for i in items if visible(i) and i.get("archiveID") in served]
    print(f"  eligible {before} -> {len(pool_src)} after gating on the served index")
    pool_src.sort(key=rank_key)

    channels, full = [], []
    for preset in PRESETS:
        pool = pool_for(preset, pool_src)
        if len(pool) < 5:
            print(f"  skip {preset['id']}: only {len(pool)} programs")
            continue
        head = {"id": preset["id"], "title": preset["title"],
                "tagline": preset["tagline"], "accent": preset["accent"]}
        channels.append({**head, "programs": [entry(i) for i in served_slice(preset, pool)]})
        full.append({**head, "programs": [entry(i) for i in pool]})
        print(f"  {preset['id']}: {len(pool)} programs, "
              f"{sum(secs(i) for i in pool) / 3600:.0f} h")

    rng = random.Random(20260612)   # stable file across runs with same catalog
    ads = [i for i in pool_src if i.get("contentType") == "commercial"]
    rng.shuffle(ads)

    def write(path, chans, **extra):
        path.write_text(json.dumps({
            "schema": 1,
            "channels": chans,
            "commercials": [entry(i) for i in ads[:AD_LIMIT]],
            **extra,
        }, ensure_ascii=False, separators=(",", ":")))
        print(f"wrote {path.name}: {len(chans)} channels, "
              f"{path.stat().st_size / 1e3:.0f} KB")

    write(OUT, channels)
    # What the scheduler's in-place repair may keep: a held program outside
    # this set has left the catalog (a rights hide, a takedown).
    write(FULL_OUT, full, eligible=sorted(i["archiveID"] for i in pool_src))
    return 0


if __name__ == "__main__":
    sys.exit(main())
