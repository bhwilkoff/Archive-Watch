#!/usr/bin/env python3
"""More Like This, computed ONCE in the pipeline (2026-09-24).

Every platform ranked "related" its own way — contentType + era + popularity,
with tvOS alone adding director and collection — and none used what the
catalog knows best about how films connect: shared CAST (9,807 people appear
in two or more films), FRANCHISE (217 series), WRITER, and shared KEYWORDS.
This module scores those connections and names the strongest one, so every
client can show the same shelf and say why it is there.

Weights are per shared attribute; a keyword counts by its rarity (IDF), and a
keyword on more than KEYWORD_DF_CAP films says nothing ("silent film",
"black and white") and is ignored. A candidate must share at least one
MEANINGFUL link (score >= MIN_SCORE) — era and genre alone are not a reason.
"""
import math
import re
from collections import defaultdict

TV_TYPES = {"tv-series", "tv-episode", "tv-special", "commercial"}
PER_ITEM = 10
MIN_SCORE = 10
KEYWORD_DF_CAP = 300
# Many rare keywords must not add up to more than one person does: before the
# cap, "wager" + "fugitive" outranked Howard Hawks on His Girl Friday.
KEYWORD_PAIR_CAP = 24
CAST_BILLED = 6
W = {"franchise": 60, "director": 30, "cast": 14, "writer": 10,
     "keyword": 2.0, "subject": 1.5, "genre": 1.5, "decade": 2, "type": 3}
REASON_ORDER = ("franchise", "director", "cast", "writer", "keyword", "subject")


def _norm(s):
    return re.sub(r"\s+", " ", (s or "").strip().lower())


def _same_film_key(it):
    keys = {"t:" + re.sub(r"[^a-z0-9]", "", (it.get("title") or "").lower()) + f":{it.get('year')}"}
    if it.get("imdbID"):
        keys.add("i:" + it["imdbID"])
    return keys


# Uploader tags that say nothing about what a film is about: bare years and
# the archive's own housekeeping words. Measured in a random sample
# (2026-09-24): "complete", "rare" and "1926" linked Tarzan the Tiger to
# Black Friday and three unrelated 1928 films.
_SUBJECT_STOP = {
    "complete", "rare", "full", "movie", "movies", "film", "films", "video",
    "public domain", "classic", "classics", "old", "vintage", "hd", "sd",
    "full movie", "feature film", "feature", "short", "black and white",
    "b&w", "color", "english", "subtitles", "restored", "archive",
    "internet archive", "free", "watch", "download", "dvd", "vhs",
}


def _subjects(it):
    out = set()
    for s in it.get("subjects") or []:
        if isinstance(s, str):
            for x in s.split(";"):
                k = _norm(x)
                if len(k) > 2 and k not in _SUBJECT_STOP and not re.fullmatch(r"\d{4}s?", k):
                    out.add(k)
    return out


def _people(it):
    out = []
    for c in (it.get("cast") or [])[:CAST_BILLED]:
        if isinstance(c, dict):
            key = c.get("tmdbPersonID") or _norm(c.get("name"))
            name = c.get("name")
        else:
            key, name = _norm(c), c
        if key and name:
            out.append((key, name))
    return out


def _directors(it):
    d = it.get("director") or ""
    return [x.strip() for x in re.split(r",|&| and ", d) if x.strip()] if isinstance(d, str) else list(d)


def _writers(it):
    w = it.get("writer") or ""
    return [x.strip() for x in re.split(r",|&", w) if x.strip()] if isinstance(w, str) else list(w)


def compute_related(items, eligible=lambda it: True):
    """{archiveID: [(relatedID, score, reason), ...]} for every eligible item.

    `reason` is a short machine phrase: "franchise:<name>", "director:<name>",
    "cast:<name>", "writer:<name>", "keyword:<kw>" — the strongest shared link.
    Clients render it in their own words (or not at all)."""
    pool = [it for it in items if eligible(it) and (it.get("contentType") or "") not in TV_TYPES]
    by_id = {it["archiveID"]: it for it in pool}
    inv = defaultdict(lambda: defaultdict(list))   # kind -> key -> [aid]
    feats = {}
    kw_df = defaultdict(int)
    for it in pool:
        for k in set(it.get("keywords") or []):
            kw_df[_norm(k)] += 1
        for k in _subjects(it):
            kw_df["s:" + k] += 1
    n = max(1, len(pool))
    for it in pool:
        a = it["archiveID"]
        f = {
            "franchise": [(_norm(it.get("franchise")), it.get("franchise"))] if it.get("franchise") else [],
            "director": [(_norm(d), d) for d in _directors(it)],
            "cast": _people(it),
            "writer": [(_norm(w), w) for w in _writers(it)],
            "keyword": [(_norm(k), k) for k in set(it.get("keywords") or [])
                        if 2 <= kw_df[_norm(k)] <= KEYWORD_DF_CAP],
            # archive.org's own subject tags: the only descriptive signal on
            # most shorts, ephemera and newsreels TMDb never reaches (6,360 of
            # the 7,582 films with no shelf, 2026-09-24). Weaker than a
            # keyword, same rarity weighting and df cap, and they share the
            # keyword pair cap so tags cannot outweigh a person.
            "subject": [("s:" + k, k) for k in _subjects(it)
                        if 2 <= kw_df["s:" + k] <= KEYWORD_DF_CAP],
        }
        feats[a] = f
        for kind, pairs in f.items():
            for key, _ in pairs:
                inv[kind][key].append(a)
    out = {}
    for a, f in feats.items():
        it = by_id[a]
        score = defaultdict(float)
        kw_score = defaultdict(float)
        best = {}   # rid -> (weight, reason)
        for kind, pairs in f.items():
            for key, label in pairs:
                others = inv[kind][key]
                if len(others) > 2000:
                    continue
                w0 = W[kind] * (math.log(n / kw_df[key]) if kind in ("keyword", "subject") else 1.0)
                for r in others:
                    if r == a:
                        continue
                    # Per candidate: this used to overwrite `w` itself, so one
                    # capped candidate shrank the weight for every later one.
                    w = w0
                    if kind in ("keyword", "subject"):
                        room = KEYWORD_PAIR_CAP - kw_score[r]
                        if room <= 0:
                            continue
                        w = min(w, room)
                        kw_score[r] += w
                    score[r] += w
                    if kind in ("franchise", "director", "cast", "writer") or w >= 8:
                        if r not in best or REASON_ORDER.index(kind) < REASON_ORDER.index(best[r][1].split(":")[0]) \
                                or (kind == best[r][1].split(":")[0] and w > best[r][0]):
                            best[r] = (w, f"{kind}:{label}")
        ranked = []
        me = _same_film_key(it)
        g0 = set(it.get("genres") or [])
        d0 = it.get("decade") or ((it.get("year") or 0) // 10 * 10)
        for r, s in score.items():
            o = by_id[r]
            # Never itself: a re-upload that survived the merge, or the same
            # IMDb title, is another COPY, not another film.
            if _same_film_key(o) & me:
                continue
            s += W["genre"] * len(g0 & set(o.get("genres") or []))
            if d0 and d0 == (o.get("decade") or ((o.get("year") or 0) // 10 * 10)):
                s += W["decade"]
            if (o.get("contentType") or "") == (it.get("contentType") or ""):
                s += W["type"]
            # A shelf entry must have a NAMED reason: a person, a series, or a
            # tag rare enough to count. Several faint signals (genre, decade,
            # type, a common tag) summed past MIN_SCORE and put Volcano
            # Eruptions under Nuremberg with an empty reason.
            if s < MIN_SCORE or r not in best:
                continue
            # a light quality prior so, among equals, the film people watch wins
            s += min(3.0, math.log10(1 + (o.get("popularityScore") or 0)))
            ranked.append((r, round(s, 1), best.get(r, (0, "keyword:"))[1]))
        ranked.sort(key=lambda x: -x[1])
        seen, kept = set(me), []
        for r, s, why in ranked:
            k = _same_film_key(by_id[r])
            if k & seen:
                continue          # one copy of each film on the shelf
            seen |= k
            kept.append((r, s, why))
            if len(kept) == PER_ITEM:
                break
        if kept:
            out[a] = kept
    return out


if __name__ == "__main__":
    import json, sys, time
    cat = json.load(open(sys.argv[1]))["items"]
    keep = None
    if len(sys.argv) > 2 and sys.argv[2].endswith(".sqlite"):
        import sqlite3
        keep = {r[0] for r in sqlite3.connect(sys.argv.pop(2)).execute("select archiveID from items")}
    t = time.time()
    rel = compute_related(cat, eligible=lambda it: not it.get("excluded")
                          and (keep is None or it["archiveID"] in keep))
    print(f"{len(rel):,} items with related films in {time.time() - t:.1f}s")
    titles = {i["archiveID"]: f'{i.get("title")} ({i.get("year")})' for i in cat}
    for q in sys.argv[2:]:
        hit = next((i for i in cat if i["archiveID"] in rel and (i.get("title") or "").lower() == q.lower()), None)
        if not hit:
            print("no", q); continue
        print(f"\n== {titles[hit['archiveID']]}")
        for r, s, why in rel.get(hit["archiveID"], []):
            print(f"   {s:6} {titles[r][:48]:50} {why}")
