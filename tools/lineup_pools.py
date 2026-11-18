#!/usr/bin/env python3
"""
lineup_pools.py — who may appear in Cartoon Mode's marathon and in Party Play.

Computed once, here, over the whole catalog (Decision 050), and published as
`item_shelves` rows (`lineup-cartoon`, `lineup-party`) in the apps' DB. Each
app reads the list and shuffles it. The Cartoon Marathon on Roku and the web,
and the web's Party Play, draw on channel-pools.json instead
(build_channel_pools.py serves Cartoon Classics whole); Roku's Party Play
samples the whole index.

The apps used to build both on the device from the most popular few hundred
titles (Cartoon Mode: 250 drawn from the top 600 cartoons; Party Play: the top
220 of 620 candidates), so 1,243 qualifying cartoons and ~1,065 party titles
were reached by a few hundred. The rules are the clients' own, unchanged:
  - cartoon: animation, playable, designed artwork, not silent, no scary
    subject (KidsContent.cartoonPool / CartoonMode.kt)
  - party: animation, short film or the Animation genre; playable, designed
    artwork, not silent, not black and white, 15 minutes or less, and either
    animation or a visual subject word (AppStore.partyLineup / TvPartyScreen.kt)
Neither carries a title that may not be recommended (Decision 149) or an
adult one.
"""

CARTOON = "lineup-cartoon"
PARTY = "lineup-party"

SCARY = ("horror", "war", "nightmare", "death", "ghost story", "macabre")

PARTY_VISUAL = (
    "abstract", "experimental", "avant-garde", "avant garde", "psychedelic",
    "kaleidoscope", "surreal", "animation", "animated", "cartoon", "color",
    "colour", "technicolor", "dance", "ballet", "music", "musical", "light",
    "fireworks", "nature", "scenic", "travelogue", "landscape", "flowers",
    "garden", "ocean", "underwater", "aquarium", "space", "nasa", "aurora",
    "fractal", "mandala", "op art", "oil", "liquid", "paint", "art", "visual",
    "fantasia", "rhythm", "geometric", "neon", "carnival", "parade",
)

PARTY_MAX_SECONDS = 15 * 60


def _designed_art(it) -> bool:
    # Catalog.Item.hasDesignedArtwork: hasRealArtwork ?? (artworkSource != "archive")
    v = it.get("hasRealArtwork")
    return bool(v) if v is not None else it.get("artworkSource") != "archive"


def _eligible(it) -> bool:
    return bool(it.get("downloadURL") and not it.get("excluded") and not it.get("isAdult")
                and not it.get("noRecommend") and _designed_art(it)
                and it.get("isSilentFilm") is not True)


def cartoon(it) -> bool:
    if it.get("contentType") != "animation" or not _eligible(it):
        return False
    blob = [str(g).lower() for g in (it.get("genres") or []) + (it.get("subjects") or [])]
    return not any(s in g for g in blob for s in SCARY)


def party(it) -> bool:
    ct = it.get("contentType")
    if ct not in ("animation", "short-film") and "Animation" not in (it.get("genres") or []):
        return False
    if not _eligible(it) or it.get("colorMode") == "bw":
        return False
    r = it.get("runtimeSeconds")
    if r and r > PARTY_MAX_SECONDS:
        return False
    if ct == "animation":
        return True
    blob = " ".join(str(s) for s in (it.get("genres") or []) + (it.get("subjects") or [])
                    + [it.get("title") or ""]).lower()
    return any(k in blob for k in PARTY_VISUAL)


def lineups_for(it) -> list:
    return [s for s, rule in ((CARTOON, cartoon), (PARTY, party)) if rule(it)]
