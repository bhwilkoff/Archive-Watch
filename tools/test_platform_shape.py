#!/usr/bin/env python3
"""
test_platform_shape.py — each platform gets the post IT wants, not one post
with five character limits.

The rules encoded here are measured 2026 platform behaviour, not taste:

  * Instagram enforces a HARD 5-hashtag limit (Dec 2025). Exceeding it is not
    neutral — the tags are ignored or the post is penalised.
  * Mastodon has NO algorithm and NO recommendation feed, so hashtags are the
    ONLY way a stranger finds a post. Before this change Mastodon got ZERO
    hashtags while Instagram got five: exactly backwards.
  * Bluesky is chronological, hook-driven, and 300 characters. A tag wall
    spends the whole budget on noise.

Composed from the SHIPPED tool.
"""
import importlib.util, pathlib, sys

spec_ = importlib.util.spec_from_file_location(
    "sp", pathlib.Path(__file__).with_name("social_post.py"))
sp = importlib.util.module_from_spec(spec_); spec_.loader.exec_module(sp)

FILM = {"id": "x", "title": "The Phantom Creeps", "year": 1939,
        "contentType": "feature-film", "genres": ["Science Fiction", "Horror"],
        "slot": "now-showing", "date": "2026-09-08",
        "link": "https://archivewatch.org/item/ThePhantomCreeps",
        "fragments": [{"kind": "meta", "text": "1939 · Feature film · 78 min"},
                      {"kind": "synopsis", "text": "Bela Lugosi builds a robot and a great deal of trouble follows."},
                      {"kind": "rights", "text": "Published in 1939, in the public domain in the United States."}]}

fails = 0
def check(name, ok, detail=""):
    global fails
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}{'  — ' + detail if detail else ''}")

for plat in ("instagram", "mastodon", "bluesky", "threads", "youtube"):
    text = sp.compose(FILM, plat)
    n = text.count("#")
    # .get, not [], so a platform MISSING from the policy fails loudly with a
    # readable verdict instead of a KeyError traceback.
    cap = sp.TAG_MAX.get(plat, 0)
    check(f"{plat}: within its own tag budget ({n} <= {cap})", n <= cap, f"{n} tags")
    check(f"{plat}: fits the character limit", len(text) <= sp.LIMITS[plat],
          f"{len(text)}/{sp.LIMITS[plat]}")
    check(f"{plat}: keeps the link", FILM["link"] in text)

# The specific regressions this exists to prevent.
ig = sp.compose(FILM, "instagram")
check("instagram never exceeds the hard 5-tag limit", ig.count("#") <= 5)
mast = sp.compose(FILM, "mastodon")
check("mastodon DOES get hashtags (its only discovery route)", mast.count("#") >= 3,
      f"{mast.count('#')} tags")
bsky = sp.compose(FILM, "bluesky")
check("bluesky stays lean on tags", bsky.count("#") <= 2, f"{bsky.count('#')} tags")

# Budget is spent on the SPECIFIC tags first, not the generic pair.
two = sp.tags_for(FILM, 2)
check("a small budget buys specificity first",
      any(t in ("#ScienceFiction", "#Horror") for t in two), str(two))

total = 5*3 + 4
print(f"\n{total - fails}/{total} passed")
sys.exit(0 if fails == 0 else 1)
