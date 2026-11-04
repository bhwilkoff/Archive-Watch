#!/usr/bin/env python3
"""One list, every kind of content (docs/TAKEDOWNS.md, Decision 175).

shared/editorial/takedowns.json holds one line per thing removed, keyed by:

    <item>            an archive.org item: its catalog card, and every episode
                      or file served from it
    <item>@<token>    one file of a whole-series item, and nothing else in it
    series:<slug>     a whole show: its card, spine and every episode

This repository is public, so a line holds a date and a case number and never
a person. Who asked is in the private case record (worker/src/takedown.js).

Run directly it strips the spines and reports what it removed; remediate_catalog
calls strip_spines on every build, so a spine rebuilt from TVmaze cannot bring
an episode back.
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SEP = "@"


def path(repo=None) -> Path:
    return (repo or REPO) / "shared/editorial/takedowns.json"


def load(repo=None) -> dict:
    p = path(repo)
    table = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
    return {k: v for k, v in table.items() if not k.startswith("_")}


def item_of(aid: str) -> str:
    return (aid or "").split(SEP, 1)[0]


def blocked(aid, table, source=None) -> bool:
    """True if this id is listed, or the item it lives in is. A listed file
    (`X@e01`) blocks that file alone: the item's other files stay."""
    if not aid:
        return False
    return aid in table or item_of(aid) in table or (source or "") in table


def strip_spines(table=None, repo=None) -> dict:
    """Remove listed episodes from series/*.json in place. A show left with no
    episodes, or listed itself, loses its spine file. Returns
    {"episodes": n, "emptied": [slug, ...]}."""
    repo = repo or REPO
    table = load(repo) if table is None else table
    out = {"episodes": 0, "emptied": []}
    if not table:
        return out
    for f in sorted((repo / "series").glob("*.json")):
        spine = json.loads(f.read_text(encoding="utf-8"))
        slug = spine.get("seriesID") or f.stem
        seasons = spine.get("seasons") or []
        had = sum(len(s.get("episodes") or []) for s in seasons)
        if f"series:{slug}" in table:
            out["episodes"] += had
            out["emptied"].append(slug)
            f.unlink()
            continue
        gone = 0
        for s in seasons:
            eps = s.get("episodes") or []
            keep = [e for e in eps
                    if not blocked(e.get("archiveID"), table, e.get("sourceID"))]
            gone += len(eps) - len(keep)
            s["episodes"] = keep
        if not gone:
            continue
        out["episodes"] += gone
        if gone == had:
            out["emptied"].append(slug)
            f.unlink()
            continue
        spine["seasons"] = [s for s in seasons if s.get("episodes")]
        if "episodesCount" in spine:
            spine["episodesCount"] = had - gone
        f.write_text(json.dumps(spine, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return out


def hidden_series_slugs(items) -> set:
    """Series under a claim a reader can open. Not every hidden card: 32 are hidden
    only for want of a year (`no_evidence`), which says nothing against the show,
    and dropping them took The Iron Claw (1916) and NASA's own series off the air."""
    return {it.get("seriesID") for it in items
            if str(it.get("archiveID") or "").startswith("series:") and it.get("excluded")
            and it.get("copyrightClaimEvidence")}


def drop_hidden_series(repo=None) -> int:
    """A series under a copyright claim still had its spine, so its episodes were in
    the DB, search and feeds behind a hidden card. publish-db runs this before it
    builds; the files stay in git, so a card that returns brings them back."""
    repo = repo or REPO
    cat = json.loads((repo / "catalog.json").read_text(encoding="utf-8"))
    n = 0
    for slug in hidden_series_slugs(cat["items"]):
        f = repo / "series" / f"{slug}.json"
        if slug and f.exists():
            f.unlink()
            n += 1
    return n


if __name__ == "__main__":
    if "--hidden-series" in sys.argv:
        print(f"spines of hidden series left out of this build: {drop_hidden_series()}")
        sys.exit(0)
    r = strip_spines()
    print(f"takedowns: {r['episodes']} episodes stripped, "
          f"{len(r['emptied'])} spines removed")
    sys.exit(0)
