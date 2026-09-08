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
    # Instagram does not linkify captions, so it carries the bare domain
    # instead — see BARE_DOMAIN. Everywhere else the deep link is tappable and
    # a post that loses it sends nobody anywhere.
    want = "archivewatch.org" if plat in sp.BARE_DOMAIN else FILM["link"]
    check(f"{plat}: keeps a way to reach the film", want in text)

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

# ------------------------------------------------------------ caption shape
# Same sourced material everywhere; what differs is the ORDER. In a feed that
# shows the first line and hides the rest, the first line IS the post.
QUOTED = dict(FILM)
QUOTED["fragments"] = FILM["fragments"] + [
    {"kind": "line", "text": '"You have made a fool of me for the last time."'}]

shape = 0
for plat in ("bluesky", "instagram", "threads"):
    t = sp.compose(QUOTED, plat)
    shape += 1
    check(f"{plat}: the quote leads", t.startswith('"You have made'), t[:40])
    shape += 1
    check(f"{plat}: the title is credited once, not twice",
          t.count("The Phantom Creeps") == 1, f"{t.count('The Phantom Creeps')}x")

t = sp.compose(QUOTED, "mastodon")
shape += 1
check("mastodon: the title leads (descriptive culture, hashtag arrivals)",
      t.startswith("The Phantom Creeps"), t[:40])

t = sp.compose(QUOTED, "youtube")
shape += 1
check("youtube: the link is in the first 150 characters",
      QUOTED["link"] in t[:150], t[:60])

t = sp.compose(QUOTED, "instagram")
shape += 1
check("instagram: no untappable URL", "https://" not in t, t[-80:])
shape += 1
check("instagram: the domain still reaches the viewer", "archivewatch.org" in t)

# Without a quote there is nothing to lead with, and a synopsis must never be
# promoted to the first line — that would read as our own words about the film.
t = sp.compose(FILM, "bluesky")
shape += 1
check("no quote: the facts lead, never the synopsis",
      t.startswith("The Phantom Creeps"), t[:40])

shape += 1
check("every platform keeps a way to reach the film",
      all(("archivewatch.org" in sp.compose(QUOTED, p))
          for p in ("bluesky", "mastodon", "threads", "instagram", "youtube",
                    "facebook")))

# ------------------------------------------------- what the post SPENDS on
# Owner, on a Bluesky post that spent its 300 characters on a truncated review
# plus "Animation · 6 min · dir. …": "The post is almost meaningless and a lot
# of it is just meta-data about the movie."
LONG = dict(QUOTED)
LONG["fragments"] = FILM["fragments"] + [
    {"kind": "review", "text": '"' + ("When I was a young teenager I had read quite a lot of "
     "movie books and dreamed of the day I would finally see this film amongst "
     "others, while I was in college I seen many of the films on my list") + '"'},
    {"kind": "review_credit", "text": "— duane420, archive.org"}]

t = sp.compose(LONG, "bluesky")
shape += 1
check("a short post still names the film", "The Phantom Creeps" in t, t)
shape += 1
check("a short post still carries the link", LONG["link"] in t, t)
shape += 1
check("a quoted review keeps its attribution", "duane420" in t, t)
shape += 1
check("the quote is cut at a sentence end, not mid-clause",
      "while I was in…" not in t, t[:120])
shape += 1
check("no runtime or director on the tightest platform",
      "min" not in t.split("\n")[0] and "dir." not in t)

shape += 1
check("sentence_trim prefers a whole sentence",
      sp.sentence_trim('"One. Two three four five six seven."', 20) == '"One."',
      repr(sp.sentence_trim('"One. Two three four five six seven."', 20)))
shape += 1
check("sentence_trim keeps the quote marks",
      sp.sentence_trim('"One. Two three four."', 40).endswith('"'))
shape += 1
check("sentence_trim leaves a short text alone",
      sp.sentence_trim("Short.", 40) == "Short.")
shape += 1
check("sentence_trim refuses to leave a scrap",
      sp.sentence_trim('"Supercalifragilistic expialidocious wordiness"', 20) is None)

shape += 1
check("youtube is where the runtime and kind belong",
      "78 min" in sp.compose(LONG, "youtube"))
shape += 1
check("and they are NOT on bluesky", "78 min" not in sp.compose(LONG, "bluesky"))

# ------------------------------------------------------- what actually went
# `format` drives the metrics comparison "does a moving picture beat a card".
# Derived from bool(video) it LIED the first time it mattered: Bluesky refused
# the video, posted the card, and the ledger recorded "video".
import inspect
shape += 1
check("the ledger records the format the platform took, not the one offered",
      'skip if skip in ("video", "card")' in inspect.getsource(sp.main))
for adapter in (sp.post_bluesky, sp.post_mastodon, sp.post_threads,
                sp.post_instagram, sp.post_youtube, sp.post_facebook):
    src = inspect.getsource(adapter)
    shape += 1
    check(f"{adapter.__name__} reports which format it posted",
          '"video"' in src or '"card"' in src)

# ---------------------------------------------------------------- cadence
# "Daily" is five decisions, not one (SOCIAL-GROWTH §2). The guard that
# matters most is the LAST one: a platform added to `plan` with no CADENCE
# entry would silently post every day, which is exactly the undifferentiated
# scheduling this table exists to end.
extra = 0
for plat, days in sp.CADENCE.items():
    extra += 1
    check(f"{plat} cadence is a real week", days and max(days) <= 6 and min(days) >= 0,
          str(sorted(days)))

extra += 1
check("instagram sits in the 6-9/week growth band", 6 <= len(sp.CADENCE["instagram"]) <= 9)
extra += 1
check("threads sits in its 2-5/week band", 2 <= len(sp.CADENCE["threads"]) <= 5)
extra += 1
check("mastodon never exceeds one a day", len(sp.CADENCE["mastodon"]) <= 7)
extra += 1
check("threads keeps the strongest weekdays",
      {1, 2, 3} <= sp.CADENCE["threads"], str(sorted(sp.CADENCE["threads"])))
extra += 1
check("posts_today reads the table",
      all(sp.posts_today("threads", d) == (d in sp.CADENCE["threads"]) for d in range(7)))
extra += 1
check("an unlisted platform is never silently silenced",
      all(sp.posts_today("tiktok", d) for d in range(7)))

# Every platform the poster can reach must be in the table.
import inspect
src = inspect.getsource(sp.main)
named = {n for n in ("bluesky", "mastodon", "threads", "instagram",
                     "facebook", "youtube") if f'("{n}"' in src}
extra += 1
# A vacuous pass is the failure mode here: an empty `named` is a subset of
# everything, so the count is asserted before the membership.
check("the plan was actually read", len(named) == 6, str(sorted(named)))
extra += 1
check("every platform in the plan has a cadence", named <= set(sp.CADENCE),
      str(named - set(sp.CADENCE)))

total = 5*3 + 4 + shape + extra
print(f"\n{total - fails}/{total} passed")
sys.exit(0 if fails == 0 else 1)
