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

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import attempt_ledger as L  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
# Every miss is recorded in `wpSynopsisTried` and waits 1, 7, then 30 days
# (attempt_ledger); ~670 misses used to be re-queried every week. A FILL is
# recorded too: if remediate rejects it, the item is a candidate again and
# must wait rather than fetch the same rejected text next week.
# Bump to retry every recorded miss once.
SYNOPSIS_VERSION = 1
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
    """({qid: enwiki page title}, error) from Wikidata sitelinks; error is "" on success."""
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
        return out, f"wikidata: {type(e).__name__}: {e}"[:160]
    return out, ""


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
    now = L.now_utc()
    cands, backoff, capped = L.partition(
        ((it, it.get("wpSynopsisTried")) for it in cands), now, SYNOPSIS_VERSION)
    print(L.summary("wp-synopsis", len(cands), len(backoff), [it.get("archiveID") for it in capped]),
          flush=True)
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

    def remember(qid, outcome, reason):
        for it in by_qid.get(qid, []):
            it["wpSynopsisTried"] = L.record(it.get("wpSynopsisTried"), outcome, reason,
                                             now, SYNOPSIS_VERSION)

    for i in range(0, len(qids), BATCH):
        chunk = qids[i:i+BATCH]
        titles, err = fetch_enwiki_titles(chunk)
        for qid in chunk:
            if qid not in titles:
                remember(qid, "error" if err else "no_match", err or "no enwiki sitelink")
        for qid, title in titles.items():
            extract = fetch_extract(title)
            if not extract or len(extract) < MIN_EXTRACT:
                remember(qid, "no_extract", f"{title}: no usable extract")
                continue
            remember(qid, "filled", f"{title}: filled; a candidate again means it was rejected")
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
    sys.exit(main())
