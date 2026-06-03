#!/usr/bin/env python3
"""
enrich_wikidata_posters.py — Track B artwork: give items that have a Wikidata
QID but no real poster a Wikimedia Commons image (Wikidata P18), so they stop
showing an Archive first-frame thumbnail. Reaches ~3.4k items TMDb/OMDb can't
(many have no IMDb id). Operates on catalog.json (the CI catalog) — network-only,
so it runs in CI, not the dev sandbox.

Sets posterURL (Commons Special:FilePath, sized), artworkSource="commons",
hasRealArtwork=true. Idempotent: skips items that already have real artwork.

Usage:
  python tools/enrich_wikidata_posters.py --dry-run       # count candidates, no network
  python tools/enrich_wikidata_posters.py --limit 500     # enrich up to N (CI)
"""

import argparse
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
WD_API = "https://www.wikidata.org/w/api.php"
UA = "ArchiveWatch/1.0 (+https://github.com/bhwilkoff/Archive-Watch)"
BATCH = 50  # wbgetentities ids per request


def candidates(items):
    return [it for it in items
            if it.get("wikidataQID") and not it.get("hasRealArtwork")]


def commons_url(filename, width=600):
    return ("https://commons.wikimedia.org/wiki/Special:FilePath/"
            + urllib.parse.quote(filename.replace(" ", "_")) + f"?width={width}")


def fetch_p18(qids):
    """Return {qid: image_filename} for the P18 (image) claim of each QID."""
    ids = "|".join(qids)
    url = WD_API + "?" + urllib.parse.urlencode({
        "action": "wbgetentities", "ids": ids, "props": "claims",
        "format": "json", "languages": "en",
    })
    out = {}
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=40) as r:
            data = json.load(r)
        for qid, ent in (data.get("entities") or {}).items():
            claims = (ent.get("claims") or {}).get("P18") or []
            if claims:
                val = claims[0].get("mainsnak", {}).get("datavalue", {}).get("value")
                if isinstance(val, str) and val:
                    out[qid] = val
    except Exception as e:
        print(f"[wd-posters] batch error: {type(e).__name__}: {e}", flush=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="max items to enrich")
    ap.add_argument("--throttle", type=float, default=0.3)
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    cands = candidates(cat["items"])
    if args.limit:
        cands = cands[:args.limit]
    print(f"[wd-posters] candidates (QID + no real artwork): {len(cands)}", flush=True)
    if args.dry_run:
        for it in cands[:5]:
            print("  ", it.get("archiveID"), it.get("wikidataQID"), (it.get("title") or "")[:40])
        print("[wd-posters] dry-run, no network, nothing written")
        return 0

    by_qid = {}
    for it in cands:
        by_qid.setdefault(it["wikidataQID"], []).append(it)
    qids = list(by_qid)
    filled = 0
    for i in range(0, len(qids), BATCH):
        chunk = qids[i:i+BATCH]
        for qid, fname in fetch_p18(chunk).items():
            url = commons_url(fname)
            for it in by_qid.get(qid, []):
                it["posterURL"] = url
                it["artworkSource"] = "commons"
                it["hasRealArtwork"] = True
                filled += 1
        time.sleep(args.throttle)
    print(f"[wd-posters] filled posters: {filled}", flush=True)
    cat["items"] = cat["items"]  # mutated in place via by_qid references
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
    print(f"[wd-posters] wrote {CATALOG.name}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
