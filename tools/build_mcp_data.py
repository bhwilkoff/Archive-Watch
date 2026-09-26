#!/usr/bin/env python3
"""
build_mcp_data.py — the small files the assistant endpoint reads
(worker/src/mcp.js; ORPHANED-FILMS #4).

The Worker runs on Cloudflare's free plan: 10 ms of CPU a request, so it can
never parse the 6 MB catalog index. Instead the pipeline publishes the index
cut two ways, each file a few KB, and the Worker fetches only what one call
needs:

  mcp/films/<fnv>.json  id -> [title, year, contentType, minutes, director,
                        genres, rating10, votes]; sharded by the SAME FNV-1a
                        low byte as details/<fnv>.json, so one hash finds both.
  mcp/words/<abc>.json  word of the title, the director or the first three
                        billed cast -> [[id, votes], ...], sharded by the
                        word's first three characters (a two-letter word is
                        its own shard). Cast comes from the
                        published details/ shards when they are given
                        (--details): the index carries no cast, and people
                        look for Keaton, not for Clyde Bruckman.

Everything comes from catalog-index.json, which is already the public
gatekeeper (Decision 105): what is not there is not in Archive Watch, and
the endpoint cannot answer with anything the apps would not show.

    python3 tools/build_mcp_data.py --out _site
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
import unicodedata
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FLOOR = 10000
STOP = {"the", "a", "an", "of", "and", "in", "on", "to", "de", "la", "le", "el"}


def fnv_shard(s: str) -> str:
    h = 0x811C9DC5
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return format(h & 0xFF, "02x")


def words(text: str) -> list[str]:
    # Must match mcp.js words(): NFKD, strip marks, lowercase, [a-z0-9]+.
    t = unicodedata.normalize("NFKD", text or "")
    t = "".join(c for c in t if not unicodedata.combining(c)).lower()
    return [w for w in re.findall(r"[a-z0-9]+", t) if len(w) >= 2 and w not in STOP]


def load_cast(details_dir: Path | None) -> dict:
    cast = {}
    if not details_dir:
        return cast
    for f in details_dir.glob("*.json"):
        for aid, rec in json.loads(f.read_text(encoding="utf-8")).items():
            names = [c[0] if isinstance(c, list) else c for c in (rec[3] or [])[:3]]
            if names:
                cast[aid] = " ".join(n for n in names if n)
    return cast


def build(index: dict, cast: dict | None = None) -> tuple[dict, dict]:
    cast = cast or {}
    f = {name: i for i, name in enumerate(index["fields"])}
    films = collections.defaultdict(dict)
    word_ix = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in index["items"]:
        if r[f["contentType"]] == "tv-episode":
            continue
        aid = r[f["id"]]
        votes = int(r[f["votes"]] or 0)
        films[fnv_shard(aid)][aid] = [
            r[f["title"]], r[f["year"]], r[f["contentType"]], r[f["minutes"]],
            r[f["director"]], (r[f["genres"]] or "").split("|") if r[f["genres"]] else [],
            r[f["rating10"]], votes]
        for w in set(words(r[f["title"]]) + words(r[f["director"]] or "")
                     + words(cast.get(aid, ""))):
            word_ix[w[:3]][w].append([aid, votes])
    for shard in word_ix.values():
        for lst in shard.values():
            lst.sort(key=lambda x: -x[1])
    return films, word_ix


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--out", default=str(REPO / "_site"))
    ap.add_argument("--details", default=None, help="the built details/ shard directory")
    args = ap.parse_args()
    index = json.loads(Path(args.index).read_text(encoding="utf-8"))
    cast = load_cast(Path(args.details) if args.details else None)
    films, word_ix = build(index, cast)
    total = sum(len(v) for v in films.values())
    out = Path(args.out) / "mcp"
    for sub, data in (("films", films), ("words", word_ix)):
        d = out / sub
        d.mkdir(parents=True, exist_ok=True)
        for key, doc in data.items():
            (d / f"{key}.json").write_text(
                json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[mcp-data] {total} films in {len(films)} shards; {len(word_ix)} word shards; "
          f"cast for {len(cast)}")
    if total < FLOOR:
        print(f"[mcp-data] refusing: {total} films is under the floor of {FLOOR}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
