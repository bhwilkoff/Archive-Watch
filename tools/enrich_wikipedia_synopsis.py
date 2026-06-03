#!/usr/bin/env python3
"""
enrich_wikipedia_synopsis.py — Track B text quality: give items that have a
Wikidata QID but NO (or a short, low-quality) synopsis a real English Wikipedia
plot summary. Resolves QID -> enwiki sitelink (Wikidata wbgetentities) ->
Wikipedia REST summary extract. Reaches ~2.3k films, including ones with no
IMDb id that OMDb/TMDb can't enrich. Network-only -> runs in CI.

Sets synopsis (+ synopsisSource="wikipedia") only when the fetched extract is
meaningfully longer than the current text, so we never replace a good synopsis
with a worse one. Idempotent.

Usage:
  python tools/enrich_wikipedia_synopsis.py --dry-run     # count candidates, no network
  python tools/enrich_wikipedia_synopsis.py --limit 500   # enrich up to N (CI)
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
WP_SUMMARY = "https://en.wikipedia.org/api/rest_v1/page/summary/"
UA = "ArchiveWatch/1.0 (+https://github.com/bhwilkoff/Archive-Watch)"
BATCH = 50
SHORT = 120          # synopsis shorter than this is treated as low-quality
MIN_EXTRACT = 140    # only accept a Wikipedia extract at least this long


def _syn(it):
    v = it.get("synopsis")
    return (" ".join(v) if isinstance(v, list) else (v or "")).strip()


def candidates(items):
    return [it for it in items
            if it.get("wikidataQID") and len(_syn(it)) < SHORT]


def fetch_enwiki_titles(qids):
    """{qid: enwiki page title} from Wikidata sitelinks."""
    url = WD_API + "?" + urllib.parse.urlencode({
        "action": "wbgetentities", "ids": "|".join(qids),
        "props": "sitelinks", "format": "json",
    })
    out = {}
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=40) as r:
            data = json.load(r)
        for qid, ent in (data.get("entities") or {}).items():
            title = ((ent.get("sitelinks") or {}).get("enwiki") or {}).get("title")
            if title:
                out[qid] = title
    except Exception as e:
        print(f"[wp-synopsis] wd batch error: {type(e).__name__}: {e}", flush=True)
    return out


def fetch_extract(title):
    url = WP_SUMMARY + urllib.parse.quote(title.replace(" ", "_"), safe="")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.load(r)
        if d.get("type") == "disambiguation":
            return None
        return (d.get("extract") or "").strip() or None
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--throttle", type=float, default=0.2)
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    cands = candidates(cat["items"])
    if args.limit:
        cands = cands[:args.limit]
    print(f"[wp-synopsis] candidates (QID + no/short synopsis): {len(cands)}", flush=True)
    if args.dry_run:
        for it in cands[:5]:
            print("  ", it.get("archiveID"), it.get("wikidataQID"), repr(_syn(it)[:40]))
        print("[wp-synopsis] dry-run, no network, nothing written")
        return 0

    by_qid = {}
    for it in cands:
        by_qid.setdefault(it["wikidataQID"], []).append(it)
    qids = list(by_qid)
    filled = 0
    for i in range(0, len(qids), BATCH):
        titles = fetch_enwiki_titles(qids[i:i+BATCH])
        for qid, title in titles.items():
            extract = fetch_extract(title)
            if not extract or len(extract) < MIN_EXTRACT:
                continue
            for it in by_qid.get(qid, []):
                if len(extract) > len(_syn(it)) + 40:   # only if meaningfully better
                    it["synopsis"] = extract
                    it["synopsisSource"] = "wikipedia"
                    filled += 1
            time.sleep(args.throttle)
        time.sleep(args.throttle)
    print(f"[wp-synopsis] filled synopses: {filled}", flush=True)
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
    print(f"[wp-synopsis] wrote {CATALOG.name}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
