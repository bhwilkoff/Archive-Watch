#!/usr/bin/env python3
"""best_rating.py — the best rating each title has, and the rank Top Rated
orders by (Decision 171).

Owner, 2026-10-27: "Please make use of the best ratings available per content."
Three crowds rate what the catalog holds, and each covers different content:

  imdb     IMDb's users, by OMDb: most films, and (since this change) the
           series TVmaze or build_episode_wants can name on IMDb.
  tvmaze   TVmaze's users: a series' only rating when IMDb has none. TVmaze
           publishes no vote count.
  archive  archive.org's own reviewers (avgRating, 1-5 stars, numReviews):
           often the only rating an ephemeral film, newsreel or one-item
           series has.

A title's BEST rating is the one the largest crowd gave (IMDb wins a tie);
TVmaze, which says nothing about its crowd, is used only when no counted
rating exists. TMDb was measured and left out: of 57 sampled films with a
TMDb id and no IMDb rating, 31 had no TMDb votes and none had 20.

The RANK is how far that rating sits above its own crowd's average for the
same kind of title (series or not), in standard deviations, discounted for a
small crowd: z * v / (v + prior). So a big crowd's 8 outranks a tiny crowd's
9, and an archive.org reviewer's generous five stars are measured against
archive.org reviewers, not against IMDb. Unrated titles get no rank, and
every client sorts them after the rated ones.
"""

from __future__ import annotations

import math

# Votes at which a crowd's verdict is trusted halfway. IMDb's 100 separates a
# film people have rated from a curio with a dozen votes (Der Vierte kommt
# nicht, 9.2 from 13 votes, led Top Rated for feature films); archive.org
# reviews are rarer, so five reviews carry the same weight.
PRIOR = {"imdb": 100, "archive": 5}
# TVmaze publishes an average and no count: trusted halfway.
UNCOUNTED_CONFIDENCE = 0.5
SOURCES = ("imdb", "tvmaze", "archive")


def _num(v):
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0 else None


def is_series(it) -> bool:
    return (it.get("contentType") or "") == "tv-series"


def candidates(it):
    """[(source, rating on a 10-point scale, votes or None)] the item carries."""
    out = []
    r = _num(it.get("imdbRating"))
    if r is not None:
        out.append(("imdb", r, int(it.get("imdbVotes") or 0)))
    a, n = _num(it.get("avgRating")), int(it.get("numReviews") or 0)
    if a is not None and n > 0:
        out.append(("archive", round(a * 2, 2), n))
    t = _num(it.get("tvmazeRating"))
    if t is not None:
        out.append(("tvmaze", t, None))
    return out


def best(it):
    """(source, rating10, votes) of the largest crowd that rated the item, or None."""
    c = candidates(it)
    counted = [x for x in c if x[2] is not None]
    if counted:
        return max(counted, key=lambda x: (x[2], x[0] == "imdb"))
    return c[0] if c else None


def crowd_stats(items):
    """{(source, is_series): (mean, sd)} over the visible items' best ratings."""
    acc = {}
    for it in items:
        if it.get("excluded"):
            continue
        b = best(it)
        if b:
            acc.setdefault((b[0], is_series(it)), []).append(b[1])
    out = {}
    for k, xs in acc.items():
        m = sum(xs) / len(xs)
        sd = math.sqrt(sum((x - m) ** 2 for x in xs) / len(xs)) if len(xs) > 1 else 0.0
        out[k] = (m, sd)
    return out


def rank(it, stats):
    """The Top Rated sort key (higher first), or None when unrated."""
    b = best(it)
    if not b:
        return None
    src, r, v = b
    mean, sd = stats.get((src, is_series(it)), (r, 0.0))
    z = (r - mean) / sd if sd else 0.0
    conf = UNCOUNTED_CONFIDENCE if v is None else v / (v + PRIOR[src])
    return round(z * conf, 4)
