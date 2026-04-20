#!/usr/bin/env python3
"""
validate_export.py
------------------
Checks invariants on a freshly-exported catalog.json. Run AFTER
tools/export_catalog.py produces a new catalog. Reports pass/fail
on a curated set of app-level contracts.

Checks performed
  1. Every Editor's Pick in featured.json resolves to an item.
  2. Curator-identified silent films are still flagged silent-film.
  3. Every shelf in featured.json has at least min-count items
     (defaults to 1; configurable via --min-shelf-count).
  4. Every item with videoFile has a playable downloadURL.
  5. Items claiming hasRealArtwork=true actually have a posterURL.
  6. No duplicate archiveIDs.
  7. Required fields present on every item (title, archiveID).

Exit 0 = all passed. Exit 1 = at least one failure.
Usage
    python tools/validate_export.py \
        --catalog ArchiveWatch/ArchiveWatch/catalog.json \
        --featured featured.json
"""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path


# Works that the curator has historically tagged as silent in editorial picks,
# collection membership, or prose. If the new pipeline demotes any of these
# to "feature-film" (or similar), the silent classifier regressed.
EXPECTED_SILENT_HINTS = {
    # Collection → expected contentType
    "silenthalloffame":  "silent-film",
    "georgesmelies":     "silent-film",
    "silent_films":      "silent-film",
    "segundodechomon":   "silent-film",
}


def _load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def check_editors_picks(catalog, featured):
    """Every curated archiveID in featured.json's Editor's Picks must appear
    in the exported catalog. Allows deliberate removal only if the item is
    demonstrably broken (not validated here — the curator has to confirm)."""
    picks = []
    for shelf in featured.get("shelves", []):
        if shelf.get("type") == "curated":
            for item in shelf.get("items", []) or []:
                ia = item.get("archiveID") if isinstance(item, dict) else None
                if ia:
                    picks.append((shelf["id"], ia))
    catalog_ids = {i["archiveID"] for i in catalog["items"]}
    missing = [(sid, aid) for sid, aid in picks if aid not in catalog_ids]
    return missing


def check_silent_not_regressed(catalog):
    """Items whose collections include a known silent-only collection must
    still surface as contentType='silent-film' (pipeline's is_silent flag
    handles this when the exporter sets it)."""
    regressions = []
    for item in catalog["items"]:
        cols = set(item.get("collections") or [])
        for coll, expected in EXPECTED_SILENT_HINTS.items():
            if coll in cols and item.get("contentType") != expected:
                regressions.append({
                    "archiveID":  item["archiveID"],
                    "title":      item["title"],
                    "collection": coll,
                    "got":        item.get("contentType"),
                    "expected":   expected,
                })
                break
    return regressions


def check_shelf_populations(catalog, featured, min_count):
    """Every shelf defined in featured.json should have at least `min_count`
    items after export. Empty shelves mean either the query failed to
    translate or the source collection has no surviving items post-scoring."""
    shelf_items = {}  # shelf_id -> count
    for item in catalog["items"]:
        for s in item.get("shelves") or []:
            shelf_items[s] = shelf_items.get(s, 0) + 1
    underpopulated = []
    for shelf in featured.get("shelves", []):
        if shelf.get("type") == "seeded":
            continue  # seeded shelves are placeholders for future work
        count = shelf_items.get(shelf["id"], 0)
        if count < min_count:
            underpopulated.append({"shelf": shelf["id"], "count": count, "min": min_count})
    return underpopulated


def check_playable_items(catalog):
    """Any item with a videoFile should have a resolvable downloadURL.
    The pipeline's exporter pairs them but defensive check is cheap."""
    broken = []
    for item in catalog["items"]:
        if item.get("videoFile") and not item.get("downloadURL"):
            broken.append({"archiveID": item["archiveID"], "title": item["title"]})
    return broken


def check_artwork_consistency(catalog):
    """If hasRealArtwork=True there must be a posterURL to back it up."""
    inconsistent = []
    for item in catalog["items"]:
        if item.get("hasRealArtwork") and not item.get("posterURL"):
            inconsistent.append({"archiveID": item["archiveID"], "title": item["title"]})
    return inconsistent


def check_no_duplicate_ids(catalog):
    counter = Counter(i.get("archiveID") for i in catalog["items"])
    return [aid for aid, n in counter.items() if n > 1]


def check_required_fields(catalog):
    missing = []
    for idx, item in enumerate(catalog["items"]):
        for key in ("archiveID", "title", "contentType", "artworkSource", "shelves"):
            if item.get(key) is None:
                missing.append({"index": idx, "archiveID": item.get("archiveID"), "missing": key})
    return missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog",  default="ArchiveWatch/ArchiveWatch/catalog.json")
    ap.add_argument("--featured", default="featured.json")
    ap.add_argument("--min-shelf-count", type=int, default=1,
                    help="Minimum items per shelf to pass (default 1)")
    ap.add_argument("--fail-on-warn", action="store_true",
                    help="Treat warnings (underpopulated shelves) as failures")
    args = ap.parse_args()

    catalog_path  = Path(args.catalog)
    featured_path = Path(args.featured)
    if not catalog_path.exists() or not featured_path.exists():
        print(f"[validate] missing file: catalog={catalog_path.exists()} "
              f"featured={featured_path.exists()}", file=sys.stderr)
        sys.exit(2)

    catalog  = _load_json(catalog_path)
    featured = _load_json(featured_path)

    failures = []
    warnings = []

    missing_picks = check_editors_picks(catalog, featured)
    if missing_picks:
        failures.append(("editors_picks_missing", missing_picks))

    silent_regress = check_silent_not_regressed(catalog)
    if silent_regress:
        failures.append(("silent_regressed", silent_regress))

    underpop = check_shelf_populations(catalog, featured, args.min_shelf_count)
    if underpop:
        (failures if args.fail_on_warn else warnings).append(("shelves_underpopulated", underpop))

    broken_play = check_playable_items(catalog)
    if broken_play:
        failures.append(("videoFile_without_downloadURL", broken_play))

    artwork_mismatch = check_artwork_consistency(catalog)
    if artwork_mismatch:
        failures.append(("hasRealArtwork_without_posterURL", artwork_mismatch))

    dups = check_no_duplicate_ids(catalog)
    if dups:
        failures.append(("duplicate_archiveIDs", dups))

    missing_fields = check_required_fields(catalog)
    if missing_fields:
        failures.append(("missing_required_fields", missing_fields))

    # Report
    n = len(catalog.get("items", []))
    print(f"[validate] checked {n} items across {len(featured.get('shelves', []))} shelves")

    for name, samples in warnings:
        print(f"[warn] {name}: {len(samples)}")
        for s in samples[:5]:
            print(f"       {s}")

    for name, samples in failures:
        print(f"[FAIL] {name}: {len(samples)}")
        for s in samples[:8]:
            print(f"       {s}")

    if not failures:
        print("[validate] all checks passed ✓")
        sys.exit(0)
    sys.exit(1)


if __name__ == "__main__":
    main()
