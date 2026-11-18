#!/usr/bin/env python3
"""Channel pools (build_channel_pools.py): the rules, each with a control that
must produce the opposite verdict."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_channel_pools as P  # noqa: E402

fails = 0


def check(name, ok):
    global fails
    print(("PASS " if ok else "FAIL ") + name)
    fails += 0 if ok else 1


def item(aid, ctype="feature-film", genres=("Drama",), minutes=90, **kw):
    return {"archiveID": aid, "title": aid, "contentType": ctype, "genres": list(genres),
            "runtimeSeconds": minutes * 60, "downloadURL": f"https://x/{aid}.mp4", **kw}


def preset(pid):
    return next(p for p in P.PRESETS if p["id"] == pid)


def ids(pool):
    return [i["archiveID"] for i in pool]


# Ranking: the pipeline's score, not catalog.json's legacy popularityScore.
# Metropolis-shaped: no legacy score, a large audience. Its rival: a legacy 89
# and nothing else.
famous = item("famous", downloads=200_000, imdbVotes=150_000, numReviews=40, avgRating=4.6)
legacy = item("legacy", popularityScore=89)
ranked = sorted([legacy, famous], key=P.rank_key)
check("a film with a large audience and no legacy score ranks first", ids(ranked)[0] == "famous")
old = sorted([legacy, famous], key=lambda i: -(i.get("popularityScore") or 0))
check("control: the old popularityScore sort put it last", ids(old)[0] == "legacy")

# Fit: classroom and industrial films are Documentary's, not Drama's.
guidance = item("guidance", ctype="ephemeral", genres=("Drama", "Documentary"), minutes=10)
check("an ephemeral film tagged Drama is not on Drama Theater", not P.matches(guidance, preset("drama")))
check("control: a feature film tagged Drama is", P.matches(item("f"), preset("drama")))
check("the same ephemeral film is on Documentary", P.matches(guidance, preset("docs")))

# Depth: a week of programming, not 90 titles.
features = sorted([item(f"d{i:04}", downloads=10_000 - i) for i in range(400)], key=P.rank_key)
pool = P.pool_for(preset("drama"), features)
hours = sum(P.secs(i) for i in pool) / 3600
short_of = (sum(P.secs(i) for i in pool[:-1])) / 3600
check(f"the pool holds {P.POOL_HOURS} h ({len(pool)} films, {hours:.1f} h) and no more than it needs",
      hours >= P.POOL_HOURS > short_of)
check("control: that is more than the old 90 titles", len(pool) > 90)
check("the pool is the best of the channel, in rank order", ids(pool) == ids(features[:len(pool)]))

# Animation: color leads, B&W about a tenth (Decision 025).
cartoons = sorted([item(f"c{i:04}", ctype="animation", genres=(), minutes=7,
                        colorMode="color", downloads=50_000 - i) for i in range(2000)]
                  + [item(f"b{i:04}", ctype="animation", genres=(), minutes=7,
                          colorMode="bw", downloads=80_000 - i) for i in range(800)], key=P.rank_key)
cpool = P.pool_for(preset("cartoon"), cartoons)
bw_share = sum(P.secs(i) for i in cpool if P.bw_or_silent(i)) / sum(P.secs(i) for i in cpool)
check(f"B&W is about a tenth of the cartoon pool ({bw_share:.0%})", 0.08 <= bw_share <= 0.12)
by_rank = P.take_hours(cartoons, P.POOL_HOURS)
rank_share = sum(P.secs(i) for i in by_rank if P.bw_or_silent(i)) / sum(P.secs(i) for i in by_rank)
check(f"control: by rank alone, B&W would be {rank_share:.0%} of it", rank_share > 0.5)

# The served file keeps each channel's best 90, and the cartoon share with it.
served = P.served_slice(preset("cartoon"), cpool)
check("the served cartoon list holds 90", len(served) == P.SERVED_LIMIT)
check("and keeps B&W in it", 0 < sum(P.bw_or_silent(i) for i in served) < len(served) / 2)
check("a genre channel serves its first 90", ids(P.served_slice(preset("drama"), pool)) == ids(pool[:90]))

print(f"\n{fails} failure(s)")
sys.exit(1 if fails else 0)
