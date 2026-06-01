#!/usr/bin/env python3
"""
repair_derivatives.py — swap unplayable derivatives for H.264 MP4.

~2,900 catalog items + some kept-series episodes have a `.ogv` (Ogg Theora)
— or rarer `.mkv`/`.avi` — `downloadURL`. AVPlayer cannot decode those, so
they play as a black screen on device. These entries are stale: the item's
MP4 derivative usually didn't exist when first ingested (Archive derives
asynchronously) but exists now (e.g. SteamboatWillie offers both MPEG4 +
Ogg; we stored the Ogg).

This pass re-queries Archive metadata for every item/episode whose
`downloadURL` isn't a playable format and swaps in the best H.264 MP4
derivative. Idempotent: already-MP4 entries are skipped, so it's cheap to
re-run and safe as a recurring CI guard for newly-derived MP4s.

Targets: catalog.json + the bundled seed + series/*.json episodes.
loc.gov items (loc: ids, already MP4) are skipped.

Usage:
  python tools/repair_derivatives.py --dry-run
  python tools/repair_derivatives.py --limit 50 --dry-run
  python tools/repair_derivatives.py
"""

import argparse
import glob
import json
import sys
import time
from pathlib import Path

# Reuse the validated re-pick logic from the TV builder.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_canonical_tv import ensure_playable, PLAYABLE_EXT  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
SERIES_DIR = REPO / "series"


def needs_repair(url):
    if not url:
        return False
    u = url.lower().split("?")[0]
    if u.startswith("https://www.loc.gov") or "/loc/" in u:
        return False
    return not u.endswith(PLAYABLE_EXT)


def repair_item(it, throttle, stats):
    """Mutate a catalog item / episode in place. Returns True if changed."""
    aid = it.get("archiveID") or ""
    if aid.startswith("loc:"):
        return False
    if not needs_repair(it.get("downloadURL")):
        return False
    stats["candidates"] += 1
    new_url, new_vf, changed, ok = ensure_playable(aid, it.get("downloadURL"),
                                                    it.get("videoFile"))
    time.sleep(throttle)
    if changed and ok:
        it["downloadURL"] = new_url
        it["videoFile"] = new_vf
        stats["fixed"] += 1
        return True
    if not ok:
        stats["no_mp4"] += 1   # item genuinely has no MP4 derivative
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="cap candidates (testing)")
    ap.add_argument("--throttle", type=float, default=0.25)
    ap.add_argument("--skip-series", action="store_true")
    args = ap.parse_args()

    stats = {"candidates": 0, "fixed": 0, "no_mp4": 0}
    budget = args.limit or 10**9

    # 1) Catalogs (dedupe re-picks across the two files by archiveID cache —
    # ensure_playable already caches Archive metadata per id this process).
    catalogs = {}
    for path in (FULL_CATALOG, SEED_CATALOG):
        catalogs[path] = json.loads(path.read_text(encoding="utf-8"))

    changed_files = set()
    for path, cat in catalogs.items():
        for it in cat["items"]:
            if stats["candidates"] >= budget:
                break
            if needs_repair(it.get("downloadURL")) and not (it.get("archiveID") or "").startswith("loc:"):
                if repair_item(it, args.throttle, stats):
                    changed_files.add(path)
        print(f"[repair] {path.name}: candidates so far={stats['candidates']} "
              f"fixed={stats['fixed']} no-mp4={stats['no_mp4']}", flush=True)

    # 2) Series episodes (kept non-canonical series still carry .ogv).
    series_changed = 0
    if not args.skip_series:
        for f in sorted(glob.glob(str(SERIES_DIR / "*.json"))):
            if stats["candidates"] >= budget:
                break
            d = json.loads(Path(f).read_text(encoding="utf-8"))
            touched = False
            for s in d.get("seasons", []):
                for ep in s.get("episodes", []):
                    if stats["candidates"] >= budget:
                        break
                    if needs_repair(ep.get("downloadURL")):
                        if repair_item(ep, args.throttle, stats):
                            touched = True
            if touched and not args.dry_run:
                Path(f).write_text(json.dumps(d, ensure_ascii=False, indent=1),
                                   encoding="utf-8")
                series_changed += 1

    print(f"\n[repair] candidates={stats['candidates']} fixed={stats['fixed']} "
          f"no-mp4-available={stats['no_mp4']} series-files-changed={series_changed}")

    if not args.dry_run:
        for path in changed_files:
            cat = catalogs[path]
            if isinstance(cat.get("stats"), dict):
                cat["stats"]["totalItems"] = len(cat["items"])
            path.write_text(json.dumps(cat, ensure_ascii=False, indent=2),
                            encoding="utf-8")
            print(f"[repair] wrote {path.name}")
    else:
        print("[repair] dry-run: nothing written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
