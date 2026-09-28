#!/usr/bin/env python3
"""
test_runtime_match_gate.py — a match whose film the file cannot be is cleared.

The defect: `gov.archives.arc.38638` "Bomber" (1941), a 9-minute Office for
Emergency Management short, wore Warner Bros.' Dive Bomber (1941, 132 min) —
poster, Errol Flynn, Michael Curtiz, Max Steiner, the tagline, and a place in
the Home hero. Every verifier tier abstained because the YEARS agree.

The rule needs two signals (runtime AND title), so the spared cases matter as
much as the caught one: a surviving fragment of the right film, a serial
chapter, an upload that declared its own IMDb id.

The CONTROL runs the same catch through `remediate` with the gate removed and
requires it to FAIL — otherwise this file proves nothing about the wiring.

Run: python3 tools/test_runtime_match_gate.py
"""
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


def bomber():
    """The live item, verbatim in the fields that matter (2026-09-28)."""
    return {
        "archiveID": "gov.archives.arc.38638", "title": "Bomber", "year": 1941,
        "decade": 1940, "contentType": "newsreel", "runtimeSeconds": 588,
        "fileRuntimeSeconds": 588, "collections": ["FedFlix", "usgovfilms"],
        "imdbID": "tt0033537", "tmdbID": 65587, "canonicalTitle": "Dive Bomber",
        "akaTitles": ["Bombarderos en picado"], "matchVerdict": "unverifiable",
        "posterURL": "https://image.tmdb.org/t/p/w780/2my6RE1UuD7M3I0gwrToUUosyUQ.jpg",
        "backdropURL": "https://image.tmdb.org/t/p/w1280/5EjoUHdoePpgZlkXgdsnhBJSP1O.jpg",
        "artworkSource": "tmdb", "hasRealArtwork": True,
        "synopsis": "A military surgeon teams with a ranking navy flyer ...",
        "synopsisSource": "tmdb", "metaSource": "tmdb",
        "tagline": "WINGS TO THE WIND...EYES TO THE SKIES!",
        "studios": ["Warner Bros. Pictures"], "composer": "Max Steiner",
        "releaseDate": "1941-08-30", "imdbRating": 6.5, "imdbVotes": 2127,
        "cast": [{"name": "Errol Flynn", "character": "Douglas S. Lee",
                  "order": 0, "tmdbPersonID": 8724}],
        # 132 min, as the committed OMDb cache also says for tt0033537 — carried
        # here so the test does not depend on that cache's contents.
        "runtimeWasSeconds": 7920,
    }


print("the matcher's same-year lookalike is caught")
rc = R.runtime_contradicts_match(bomber())
check("Bomber vs Dive Bomber contradicts", rc == (588, 7920), repr(rc))

print("\nthrough remediate, the other film's identity is gone")
items = [bomber()]
R.remediate(items)
it = items[0]
check("verdict is cleared_runtime", it.get("matchVerdict") == "cleared_runtime", it.get("matchVerdict"))
check("the evidence is recorded", it.get("matchRuntimeConflict") == [588, 7920])
check("Dive Bomber's poster is gone (the item's own art may replace it)",
      "image.tmdb.org" not in (it.get("posterURL") or "") and it.get("artworkSource") != "tmdb",
      repr(it.get("posterURL")))
for f in ("imdbID", "tmdbID", "backdropURL", "canonicalTitle", "tagline",
          "studios", "composer", "releaseDate", "imdbVotes", "synopsis"):
    check(f"Dive Bomber's {f} is gone", not it.get(f), repr(it.get(f)))
check("Errol Flynn's credit is gone", not any(c.get("tmdbPersonID") for c in it.get("cast") or []))
check("the item's own year survives", it.get("year") == 1941)
check("the cleared verdict is registered for the residue strip",
      "cleared_runtime" in R._CLEARED)

print("\nwhat must be spared")


def variant(**kw):
    x = bomber()
    x.update(kw)
    return x


check("a fragment carrying the film's own title (Tokyo March, 27 of 101 min)",
      R.runtime_contradicts_match(variant(
          title="Tôkyô kôshinkyoku", canonicalTitle="Tokyo March",
          akaTitles=["Tokyo koshin-kyoku"], fileRuntimeSeconds=1620,
          runtimeWasSeconds=6060, imdbID=None)) is None)
check("a serial chapter against the whole serial",
      R.runtime_contradicts_match(variant(
          title="Undersea Kingdom: Chapter 1 - Beneath the Ocean Floor",
          canonicalTitle="Sharad of Atlantis", imdbID=None)) is None)
check("a serial named as one in parentheses",
      R.runtime_contradicts_match(variant(
          title="The Green Hornet Strikes Again! (serial)", imdbID=None,
          canonicalTitle="A Volta do Besouro Verde")) is None)
check("an upload that declared its own IMDb id (Decision 026 Tier 1)",
      R.runtime_contradicts_match(variant(matchVerdict="verified")) is None)
check("a runtime that came from the match, not the file",
      R.runtime_contradicts_match(variant(fileRuntimeSeconds=None)) is None)
check("a same-length copy", R.runtime_contradicts_match(
    variant(fileRuntimeSeconds=7800)) is None)
check("a short-to-short gap under twenty minutes", R.runtime_contradicts_match(
    variant(fileRuntimeSeconds=300, runtimeWasSeconds=1200, imdbID=None)) is None)

print("\ncontrol: the same catch with the gate removed must FAIL")
real = R.runtime_contradicts_match
R.runtime_contradicts_match = lambda it: None
try:
    ctl = [bomber()]
    R.remediate(ctl)
finally:
    R.runtime_contradicts_match = real
check("without the gate, Dive Bomber's poster stays (the control bites)",
      "image.tmdb.org" in (ctl[0].get("posterURL") or "")
      and ctl[0].get("matchVerdict") != "cleared_runtime",
      repr((ctl[0].get("posterURL"), ctl[0].get("matchVerdict"))))

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
