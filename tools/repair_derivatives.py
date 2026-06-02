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


# Set by main(): also re-pick non-.ia.mp4 uploader originals for faststart.
FASTSTART = False
# Uploader-original formats that are often non-faststart (moov at EOF) → slow
# start. Worth re-checking for an Archive .ia.mp4 derivative under --faststart.
_ORIGINAL_FMT = ("mpeg4", "divx", "3gp", "msvideo", "avi")


def needs_repair(url, fmt=None):
    if not url:
        return False
    u = url.lower().split("?")[0]
    if u.startswith("https://www.loc.gov") or "/loc/" in u:
        return False
    if not u.endswith(PLAYABLE_EXT):
        return True   # .ogv / .mkv / .avi — unplayable, always repair
    # --faststart: an uploader original (.mp4 but NOT Archive's .ia.mp4) may
    # have a faststart .ia.mp4 derivative now; ensure_playable will swap if so
    # and no-op otherwise. Scope to original-like formats to bound the work.
    if FASTSTART and not u.endswith(".ia.mp4"):
        return any(t in (fmt or "").lower() for t in _ORIGINAL_FMT)
    return False


def repair_item(it, throttle, stats):
    """Mutate a catalog item / episode in place. Returns True if changed."""
    aid = it.get("archiveID") or ""
    if aid.startswith("loc:"):
        return False
    if not needs_repair(it.get("downloadURL"), (it.get("videoFile") or {}).get("format")):
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
    ap.add_argument("--faststart", action="store_true",
                    help="also re-pick non-.ia.mp4 uploader originals (mpeg4/divx) "
                         "for an Archive faststart derivative (slow but improves start latency)")
    args = ap.parse_args()

    global FASTSTART
    FASTSTART = args.faststart

    stats = {"candidates": 0, "fixed": 0, "no_mp4": 0}
    budget = args.limit or 10**9

    # 1) Catalogs. The bundled seed catalog.json is no longer in git (Decision
    # 018) — only process catalogs that exist on disk.
    catalogs = {}
    for path in (FULL_CATALOG, SEED_CATALOG):
        if path.exists():
            catalogs[path] = json.loads(path.read_text(encoding="utf-8"))

    changed_files = set()
    for path, cat in catalogs.items():
        for it in cat["items"]:
            if stats["candidates"] >= budget:
                break
            if needs_repair(it.get("downloadURL"), (it.get("videoFile") or {}).get("format")) \
                    and not (it.get("archiveID") or "").startswith("loc:"):
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
                    if needs_repair(ep.get("downloadURL"), (ep.get("videoFile") or {}).get("format")):
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
