#!/usr/bin/env python3
"""Cache the archive.org item's OWN date and credits for items whose external
match was cleared, so the build can tell which surviving fields the item
itself vouches for (remediate_catalog.scrub_cleared_match).

Owner, 2026-09-28: "All inaccurate information should be scrubbed from the
database. Unless it is somehow verified, keeping bad info on "junk uploads"
doesn't seem helpful to anyone."

    python3 tools/fetch_archive_own_meta.py --catalog catalog.json [--limit N]

Writes shared/editorial/archive_own_meta.json:
    {archiveID: {"year": int|null, "director": str|null, "creator": str|null,
                 "mentioned": [years stated in its own title/description]}}
Only items with a cleared match are fetched, and only once; a failed fetch is
not written, so the build treats that item as unjudged rather than unvouched.
Paced (a few requests a second): archive.org rate-limits an address that
storms its main host (memory: creation_studio_connection_discipline).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CACHE = REPO / "shared/editorial/archive_own_meta.json"
YEAR_RE = re.compile(r"\b(18[89]\d|19\d\d|20[0-2]\d)\b")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from remediate_catalog import is_cleared_match  # noqa: E402


def own_year(md: dict):
    for key in ("date", "year"):
        m = YEAR_RE.search(str(md.get(key) or ""))
        if m:
            return int(m.group(1))
    return None


def _first(v):
    if isinstance(v, list):
        v = v[0] if v else None
    return str(v).strip() if v else None


def fetch(aid: str):
    try:
        with urllib.request.urlopen(f"https://archive.org/metadata/{aid}/metadata",
                                    timeout=25) as r:
            md = json.load(r).get("result")
    except Exception:
        return aid, None
    if not isinstance(md, dict):
        return aid, None
    # Years the uploader's own title and description state ("Night of the
    # Living Dead (1968) ..." on an item with no `date` field).
    text = " ".join(str(v) for k in ("title", "description")
                    for v in (md.get(k) if isinstance(md.get(k), list) else [md.get(k)]) if v)
    mentioned = sorted({int(y) for y in YEAR_RE.findall(text)})[:20]
    # The upload's OWN title: the catalog's may have been overwritten by the
    # very match being judged (a stock clip "red dice falling" became "Red Dice").
    return aid, {"year": own_year(md), "director": _first(md.get("director")),
                 "creator": _first(md.get("creator")), "mentioned": mentioned,
                 "title": _first(md.get("title"))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--ids", help="a file of archiveIDs to fetch (or refresh for their title)")
    a = ap.parse_args()
    data = json.loads(Path(a.catalog).read_text())
    items = data["items"] if isinstance(data, dict) else data
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    # Visible items first: they are what a viewer reads.
    todo = [it["archiveID"] for it in sorted(items, key=lambda i: bool(i.get("excluded")))
            if is_cleared_match(it) and it["archiveID"] not in cache]
    if a.ids:
        todo = [x for x in Path(a.ids).read_text().split() if "title" not in cache.get(x, {})]
    if a.limit:
        todo = todo[:a.limit]
    print(f"[own-meta] {len(todo)} to fetch, {len(cache)} cached")
    done = failed = 0
    with ThreadPoolExecutor(a.workers) as ex:
        for i in range(0, len(todo), a.workers * 4):
            for aid, rec in ex.map(fetch, todo[i:i + a.workers * 4]):
                if rec is None:
                    failed += 1
                else:
                    cache[aid] = rec
                    done += 1
            CACHE.write_text(json.dumps(cache, indent=0, sort_keys=True, ensure_ascii=False))
            print(f"[own-meta] {done} fetched, {failed} failed", flush=True)
            time.sleep(1.0)
    print(f"[own-meta] fetched {done}, failed {failed}, cache now {len(cache)}")


if __name__ == "__main__":
    main()
