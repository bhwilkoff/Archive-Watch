#!/usr/bin/env python3
"""Cartoon Mode and Party Play membership (lineup_pools.py): each rule with a
control that must produce the opposite verdict."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lineup_pools as L  # noqa: E402

fails = 0


def check(name, ok):
    global fails
    print(("PASS " if ok else "FAIL ") + name)
    fails += 0 if ok else 1


def cartoon(**kw):
    base = {"archiveID": "c", "title": "Popeye", "contentType": "animation", "runtimeSeconds": 420,
            "downloadURL": "https://x/c.mp4", "hasRealArtwork": True, "colorMode": "color",
            "genres": ["Animation"], "subjects": ["cartoon"]}
    return {**base, **kw}


check("a playable color cartoon with art is in Cartoon Mode", L.cartoon(cartoon()))
check("control: one with a scary subject is not", not L.cartoon(cartoon(subjects=["horror"])))
check("nor a silent one", not L.cartoon(cartoon(isSilentFilm=True)))
check("nor one without designed art", not L.cartoon(cartoon(hasRealArtwork=False)))
check("nor one that may not be recommended", not L.cartoon(cartoon(noRecommend=True)))
check("nor one with no file", not L.cartoon(cartoon(downloadURL=None)))
check("art falls back to the source when the flag is absent",
      L.cartoon(cartoon(hasRealArtwork=None, artworkSource="tmdb"))
      and not L.cartoon(cartoon(hasRealArtwork=None, artworkSource="archive")))
check("a black-and-white cartoon stays in Cartoon Mode", L.cartoon(cartoon(colorMode="bw")))

check("a color cartoon is in Party Play", L.party(cartoon()))
check("control: a black-and-white one is not", not L.party(cartoon(colorMode="bw")))
check("nor one over 15 minutes", not L.party(cartoon(runtimeSeconds=16 * 60)))
short = cartoon(contentType="short-film", genres=["Documentary"], subjects=["travelogue"], title="Sea")
check("a short with a visual subject is in Party Play", L.party(short))
check("control: a short with none is not", not L.party({**short, "subjects": ["lecture"]}))
check("a feature film is never in Party Play", not L.party({**short, "contentType": "feature-film",
                                                            "genres": ["Drama"]}))
check("lineups_for names both for a color cartoon",
      L.lineups_for(cartoon()) == [L.CARTOON, L.PARTY])

print(f"\n{fails} failure(s)")
sys.exit(1 if fails else 0)
