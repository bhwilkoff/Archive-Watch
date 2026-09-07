#!/usr/bin/env python3
"""
build_people_index.py — an inverted cast index for the web viewer.

WHY THIS EXISTS. Web search could not find people. The index's search blob is
TMDb keywords and the director column (both now searched, see watch.js), but
CAST lives in the per-item detail shards — 256 files fetched one at a time as a
viewer opens a film. Nothing client-side can scan them, so an actor was
unfindable and a cast bubble on Detail led nowhere.

WHY A SIDECAR RATHER THAN A COLUMN. Folding cast into catalog-index.json would
put it on the cold-load path for every visitor, and the index is already fetched
on first paint. This file is requested ONLY when someone searches a person or
taps a cast bubble. Same shape as `aliases.json` (Decision 085), for the same
reason.

MEASURED on the live shards: 27,490 distinct people over 105,991 credits;
3.4 MB raw, 1.38 MB gzipped, which is what Pages actually serves.

Single-credit people are KEPT. They are half the names, and an actor with one
film in the archive is exactly the search a visitor is most likely to lose.

Run:
  python tools/build_people_index.py --details details --out people.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# details/<shard>.json record order (build_web_details.py). Cast is index 3.
D_CAST = 3

# A person with more credits than this is a studio regular (Mel Blanc: 222).
# The list is for a filmography page and a search result, and neither is served
# by 300 rows -- the cap bounds the file without bounding what is findable,
# since the NAME is still present and searchable either way.
MAX_PER_PERSON = 40


def person_name(entry) -> str | None:
    """Cast entries are ['Name', '/profile.jpg', tmdbID], but older shards
    carry a bare string. Both shapes appear in the live data, so both are read
    -- 1,879 names came only from the string form when this was measured."""
    if isinstance(entry, list) and entry:
        return entry[0] if isinstance(entry[0], str) else None
    if isinstance(entry, str):
        return entry
    return None


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--details", default=str(REPO / "details"))
    ap.add_argument("--out", default=str(REPO / "people.json"))
    args = ap.parse_args()

    dpath = Path(args.details)
    if not dpath.exists():
        print(f"[people] no {dpath} — nothing to build", file=sys.stderr)
        return 0

    people: dict[str, list[str]] = defaultdict(list)
    records = credits = 0
    for shard in sorted(dpath.glob("*.json")):
        try:
            data = json.loads(shard.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            print(f"[people] skipped unreadable {shard.name}: {exc}", file=sys.stderr)
            continue
        for aid, rec in data.items():
            records += 1
            cast = rec[D_CAST] if len(rec) > D_CAST else None
            if not cast:
                continue
            for entry in cast:
                if (name := person_name(entry)):
                    people[name].append(aid)
                    credits += 1

    # Sorted so a rebuild with unchanged data produces an unchanged file, which
    # is what lets the publish step's "did anything change" check mean anything.
    out = {name: sorted(set(ids))[:MAX_PER_PERSON]
           for name, ids in sorted(people.items())}

    payload = json.dumps(out, separators=(",", ":"), ensure_ascii=False)
    Path(args.out).write_text(payload, encoding="utf-8")
    print(f"[people] {len(out):,} people from {credits:,} credits across "
          f"{records:,} records -> {args.out} ({len(payload.encode())/1e6:.2f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
