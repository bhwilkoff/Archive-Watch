#!/usr/bin/env python3
"""Reclaim VERIFIED orphan subtitle files — restore claims the catalog lost.

2026-08-26 finding: 1,912 published subs/<id>/ directories sit on SERVED
cards that carry no subtitleHLS claim, and ~70% of a sample are substantial
English tracks — films offering viewers no subtitles while a good file sits
one URL away. QC passes clean the CATALOG, never the published assets, so
claims die and files remain.

Reclaim is gated on MEASUREMENT, not provenance: the film's own audio is
transcribed on-device (tools/caption_gen_main.swift) and the orphan file
must agree with the transcript (vocabulary overlap from
tools/audit_wrong_film_subtitles.py). A file that matches what is spoken is
correct whatever its origin; one that doesn't stays orphaned. Correct pairs
measure 0.8+; the wrong-film pair (doa_ipod) measured 0.02.

Usage:
  python3 tools/audit_wrong_film_subtitles.py --transcripts /tmp/orphan-out \
      --out tools/orphan_reclaim_scores.csv
  python3 tools/catalog_release.py fetch
  python3 tools/reclaim_orphan_subtitles.py --scores tools/orphan_reclaim_scores.csv \
      [--threshold 0.6] [--apply]
  python3 tools/catalog_release.py publish   # then dispatch publish-db

Dry-run by default: prints what would be stamped. --apply edits catalog.json
in place (additive per Decision 020 — only the two claim fields plus an
evidence marker are written, and only on items with NO current claim).
"""
import argparse, csv, json, sys

BASE = "https://archivewatch.org/subs"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scores", required=True)
    ap.add_argument("--catalog", default="catalog.json")
    ap.add_argument("--threshold", type=float, default=0.6)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    eligible = {}
    for r in csv.DictReader(open(args.scores)):
        if r["verdict"] == "OK" and float(r["overlap"] or 0) >= args.threshold:
            eligible[r["archiveID"]] = float(r["overlap"])
    if not eligible:
        print("no rows meet the threshold; nothing to do")
        return 0

    cat = json.load(open(args.catalog))
    items = cat["items"] if isinstance(cat, dict) else cat
    stamped = skipped = 0
    for it in items:
        aid = it.get("archiveID")
        if aid not in eligible:
            continue
        if it.get("subtitleHLS") or it.get("captions"):
            skipped += 1          # something re-claimed it since; never clobber
            continue
        score = eligible[aid]
        print(f"  {'STAMP' if args.apply else 'would stamp':11} {aid[:44]:44} agreement={score:.2f}")
        if args.apply:
            url = f"{BASE}/{aid}/en.vtt"
            it["captions"] = [{"lang": "en", "label": "English", "format": "vtt",
                               "url": url, "vttURL": url,
                               "source": "reclaimed-verified",
                               "reclaimAgreement": score}]
            it["subtitleHLS"] = f"{BASE}/{aid}/master.m3u8"
        stamped += 1

    print(f"\n{'stamped' if args.apply else 'would stamp'} {stamped}, "
          f"skipped {skipped} (already re-claimed)")
    if args.apply and stamped:
        json.dump(cat, open(args.catalog, "w"), ensure_ascii=False,
                  separators=(",", ":"))
        print("catalog.json written — publish with tools/catalog_release.py publish")
    return 0


if __name__ == "__main__":
    sys.exit(main())
