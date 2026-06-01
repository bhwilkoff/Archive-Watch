#!/usr/bin/env python3
"""
cleanup_data.py — fix the small, concrete data issues the audit surfaced.

  • drop items with empty/1-char titles (garbage uploads)
  • null impossible years (outside 1888..present) + their decade
  • null absurd runtimes (<30s or >14h)
  • de-duplicate episodes that landed on the same (season, episode) within a
    series — keep the best copy (playable MP4 + still), preserve unnumbered
    "extras"

Idempotent. Operates on the committed catalogs + series files.

Usage:
    python tools/cleanup_data.py --dry-run
    python tools/cleanup_data.py
"""

import argparse
import glob
import json
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOGS = [REPO / "catalog.json", REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"]
SERIES_DIR = REPO / "series"
YEAR_MIN, YEAR_MAX = 1888, 2026   # first films .. present


def fix_catalog(path, dry):
    c = json.loads(path.read_text(encoding="utf-8"))
    out, f = [], Counter()
    for i in c["items"]:
        if len((i.get("title") or "").strip()) < 2:
            f["dropped_empty_title"] += 1
            continue
        y = i.get("year")
        if y and (y < YEAR_MIN or y > YEAR_MAX):
            if not dry:
                i["year"] = None
                i["decade"] = None
            f["nulled_bad_year"] += 1
        rt = i.get("runtimeSeconds")
        if rt and (rt < 30 or rt > 50000):
            if not dry:
                i["runtimeSeconds"] = None
            f["nulled_bad_runtime"] += 1
        out.append(i)
    if not dry:
        c["items"] = out
        if isinstance(c.get("stats"), dict):
            c["stats"]["totalItems"] = len(out)
        path.write_text(json.dumps(c, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"  [{path.name}] {dict(f)}")
    return f


def ep_score(e):
    mp4 = (e.get("downloadURL") or "").lower().endswith((".mp4", ".m4v", ".mov"))
    return (1 if mp4 else 0, 1 if e.get("stillURL") else 0, 1 if e.get("overview") else 0)


def dedup_series(dry):
    changed_files = dups = 0
    for fp in glob.glob(str(SERIES_DIR / "*.json")):
        d = json.loads(Path(fp).read_text(encoding="utf-8"))
        touched = False
        for s in d.get("seasons", []):
            best, extras = {}, []
            for e in s.get("episodes", []):
                n = e.get("episodeNumber")
                if n is None:
                    extras.append(e)
                    continue
                k = (e.get("seasonNumber"), n)
                if k in best:
                    dups += 1
                    touched = True
                    if ep_score(e) > ep_score(best[k]):
                        best[k] = e
                else:
                    best[k] = e
            ordered = sorted(best.values(),
                             key=lambda x: (x.get("episodeNumber") or 0)) + extras
            s["episodes"] = ordered
        if touched:
            changed_files += 1
            d["episodesCount"] = sum(len(s["episodes"]) for s in d.get("seasons", []))
            if not dry:
                Path(fp).write_text(json.dumps(d, ensure_ascii=False, indent=1),
                                    encoding="utf-8")
    print(f"  series: removed {dups} duplicate (S,E) episodes across "
          f"{changed_files} files")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    print(f"[cleanup]{' DRY-RUN' if args.dry_run else ''}")
    for p in CATALOGS:
        if p.exists():
            fix_catalog(p, args.dry_run)
    dedup_series(args.dry_run)
    print("[cleanup] done")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
