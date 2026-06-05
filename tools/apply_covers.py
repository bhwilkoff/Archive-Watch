#!/usr/bin/env python3
"""
apply_covers.py — wire uploaded frame-extracted covers into the catalog (#86).

Reads the upload log written by upload_covers.py (archiveID -> hosted URL) and
sets posterURL / artworkSource='generated' / hasRealArtwork=True on the matching
catalog items. Additive and Decision-020-safe: it only fills items that still
lack real designed art, never overwrites a third-party poster, and never removes
items (asserts the count is unchanged).

Run inside the standard catalog write path (Decision 018):
    python tools/catalog_release.py fetch
    python tools/apply_covers.py            # mutates ./catalog.json in place
    python tools/remediate_catalog.py       # (optional, normal pipeline step)
    python tools/catalog_release.py publish
    # then dispatch publish-db to rebuild the app SQLite

Usage:
    python tools/apply_covers.py [--catalog catalog.json] [--uploaded tools/covers_out/uploaded.jsonl] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
UPLOADED = Path(__file__).resolve().parent / "covers_out" / "uploaded.jsonl"


def needs_cover(it: dict) -> bool:
    if it.get("hasRealArtwork") is True:
        return False
    src = it.get("artworkSource")
    if it.get("posterURL") and src not in (None, "", "archive", "none", "generated"):
        return False
    return True


def load_uploaded(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        sys.exit(f"[apply] no upload log at {path} — run upload_covers.py first")
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
            if rec.get("archiveID") and rec.get("url"):
                out[rec["archiveID"]] = rec["url"]
        except json.JSONDecodeError:
            continue
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", type=Path, default=CATALOG)
    ap.add_argument("--uploaded", type=Path, default=UPLOADED)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.catalog.exists():
        sys.exit(f"[apply] {args.catalog} not found — run `catalog_release.py fetch` first")

    urls = load_uploaded(args.uploaded)
    cat = json.load(open(args.catalog))
    items = cat["items"] if isinstance(cat, dict) else cat
    before = len(items)

    applied = skipped_have_art = missing_in_catalog = 0
    matched = set()
    for it in items:
        aid = it.get("archiveID")
        url = urls.get(aid)
        if not url:
            continue
        matched.add(aid)
        if not needs_cover(it):
            skipped_have_art += 1
            continue
        if not args.dry_run:
            it["posterURL"] = url
            it["artworkSource"] = "generated"
            it["hasRealArtwork"] = True
        applied += 1

    missing_in_catalog = len(set(urls) - matched)

    print(f"[apply] upload log: {len(urls)} covers")
    print(f"[apply] applied (newly real art): {applied}")
    print(f"[apply] skipped (already had real art): {skipped_have_art}")
    print(f"[apply] in log but not in catalog: {missing_in_catalog}")

    if args.dry_run:
        print("[apply] dry-run — no write")
        return 0

    assert len(items) == before, "item count changed — refusing to write (Decision 020)"
    if isinstance(cat, dict):
        cat.setdefault("stats", {})
    tmp = args.catalog.with_suffix(".json.tmp")
    json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
    tmp.replace(args.catalog)
    print(f"[apply] wrote {args.catalog} ({args.catalog.stat().st_size/1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
