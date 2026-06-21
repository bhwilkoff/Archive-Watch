#!/usr/bin/env python3
"""
harvest_community_signals.py — pull archive.org's built-in community / usage
signals onto every catalog item, for better popularity sorting and best-UPLOAD
selection (Decision 040). PHASE 0 of docs/research/archive-org-community-signals.md.

Adds these ADDITIVE fields per item (Swift/Kotlin models ignore unknown keys):
  downloads        all-time cumulative file fetches (advancedsearch)
  downloadsWeek    trailing 7-day downloads
  downloadsMonth   trailing 30-day downloads
  numFavorites     direct favourite count (NOT the fav-* collection hack)
  avgRating        0-5 community rating
  numReviews       review/comment count
  viewsAllTime     all-time item views (be-api views service)
  views30d         last-30-day views  (current watch momentum)
  views7d          last-7-day views
  signalsCheckedAt ISO date of this harvest (resumable / staleness)

It does NOT touch popularityScore — build_sqlite derives the sort score + the
best-copy score from these raw fields at DB-build time (so the source catalog
stays additive, Decision 020). Two data sources, both verified live 2026-06-21:
  - advancedsearch.php  batched `identifier:(id1 OR id2 ...)` → downloads/week/
    month/num_favorites/avg_rating/num_reviews
  - be-api.us.archive.org/views/v1/short/{id1},{id2},...  → all_time/30d/7d views

Mac- or CI-runnable; mutates the LOCAL catalog.json (CI fetches before / publishes
after, like enrich_subtitles). Resumable: re-running refreshes everything older
than --stale-days; a weekly cron keeps the whole catalog current (signals decay).

Run (catalog_release.py fetch first):
  python tools/harvest_community_signals.py --limit 500
  python tools/harvest_community_signals.py            # full pass (~10-15 min)
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
VIEWS_API = "https://be-api.us.archive.org/views/v1/short/"

# advancedsearch fields → catalog keys
_ADV_FIELDS = ["downloads", "week", "month", "num_favorites", "avg_rating", "num_reviews"]


def _today():
    # avoid importing datetime.now at module import for determinism in tests;
    # CI/Mac both have a real clock here.
    import datetime
    return datetime.date.today().isoformat()


def fetch_adv_batch(ids, session):
    """downloads/week/month/num_favorites/avg_rating/num_reviews for a batch of
    identifiers, keyed by identifier. One advancedsearch call per batch."""
    q = "identifier:(" + " OR ".join(ids) + ")"
    fl = "".join(f"&fl[]={f}" for f in ["identifier", *_ADV_FIELDS])
    url = f"{A.ADV_SEARCH}?q={requests.utils.quote(q)}{fl}&output=json&rows={len(ids)}"
    r = session.get(url, headers={"User-Agent": A.UA}, timeout=40)
    r.raise_for_status()
    out = {}
    for doc in r.json().get("response", {}).get("docs", []):
        out[doc["identifier"]] = doc
    return out


def fetch_views_batch(ids, session, tries=3):
    """all_time/last_30day/last_7day views for a batch, keyed by identifier. The
    be-api views service throws transient 502s under load — retry with backoff."""
    url = VIEWS_API + ",".join(ids)
    last = None
    for attempt in range(tries):
        try:
            r = session.get(url, headers={"User-Agent": A.UA}, timeout=40)
            r.raise_for_status()
            data = r.json()
            return data if isinstance(data, dict) else {}
        except Exception as e:                        # 502 / timeout / parse
            last = e
            time.sleep(1.0 * (attempt + 1))
    raise last


def apply_signals(it, adv, views):
    """Write the additive signal fields onto one item from the two responses."""
    if adv is not None:
        it["downloads"] = int(adv.get("downloads") or 0)
        it["downloadsWeek"] = int(adv.get("week") or 0)
        it["downloadsMonth"] = int(adv.get("month") or 0)
        it["numFavorites"] = int(adv.get("num_favorites") or 0)
        it["numReviews"] = int(adv.get("num_reviews") or 0)
        ar = adv.get("avg_rating")
        it["avgRating"] = round(float(ar), 2) if ar not in (None, "") else None
        it["signalsCheckedAt"] = _today()             # stamp only on real adv data
    if views is not None and views.get("have_data"):
        it["viewsAllTime"] = int(views.get("all_time") or 0)
        it["views30d"] = int(views.get("last_30day") or 0)
        it["views7d"] = int(views.get("last_7day") or 0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="cap items processed (popularity-first)")
    # advancedsearch silently returns 0 docs for an OR of >~50 ids (query-clause /
    # length limit), so 50 is the safe ceiling — verified live.
    ap.add_argument("--batch", type=int, default=50, help="ids per advancedsearch call (<=50)")
    ap.add_argument("--views-batch", type=int, default=40, help="ids per views call")
    ap.add_argument("--stale-days", type=int, default=6,
                    help="re-harvest items whose signalsCheckedAt is older than this")
    ap.add_argument("--sleep", type=float, default=0.3, help="pause between calls (be polite)")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[signals] no catalog.json (catalog_release.py fetch first)"); return 2
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    today = _today()

    def stale(it):
        d = it.get("signalsCheckedAt")
        if not d:
            return True
        # cheap lexical date compare; refresh if older than stale-days
        import datetime
        try:
            age = (datetime.date.fromisoformat(today) - datetime.date.fromisoformat(d)).days
        except ValueError:
            return True
        return age >= args.stale_days

    # Harvest an item if it never got download data yet (self-heals partial runs /
    # transient failures) or its signals are stale.
    targets = [it for it in items
               if it.get("archiveID") and (it.get("downloads") is None or stale(it))]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[signals] {len(targets)} items to harvest (of {len(items)}); "
          f"batch {args.batch}/views {args.views_batch}", flush=True)
    if not targets:
        return 0

    session = requests.Session()
    by_id = {it["archiveID"]: it for it in targets}
    ids = list(by_id)

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    done = 0
    # advancedsearch pass
    for i in range(0, len(ids), args.batch):
        chunk = ids[i:i + args.batch]
        try:
            adv = fetch_adv_batch(chunk, session)
        except Exception as e:
            print(f"[signals] adv batch failed ({e}); retrying smaller", flush=True)
            adv = {}
            for sid in chunk:                          # fall back one-by-one
                try:
                    adv.update(fetch_adv_batch([sid], session))
                except Exception:
                    pass
                time.sleep(args.sleep)
        for sid in chunk:
            apply_signals(by_id[sid], adv.get(sid), None)
        done += len(chunk)
        if done % (args.batch * 10) == 0:
            flush(); print(f"[signals] adv {done}/{len(ids)}", flush=True)
        time.sleep(args.sleep)
    flush()

    # views pass (separate endpoint, larger batches)
    vdone = 0
    for i in range(0, len(ids), args.views_batch):
        chunk = ids[i:i + args.views_batch]
        try:
            views = fetch_views_batch(chunk, session)
        except Exception as e:
            print(f"[signals] views batch failed ({e})", flush=True)
            views = {}
        for sid in chunk:
            v = views.get(sid)
            if v:
                apply_signals(by_id[sid], None, v)
        vdone += len(chunk)
        if vdone % (args.views_batch * 10) == 0:
            flush(); print(f"[signals] views {vdone}/{len(ids)}", flush=True)
        time.sleep(args.sleep)

    flush()
    # quick coverage report
    cov = sum(1 for it in targets if it.get("downloads") is not None)
    favs = sum(1 for it in targets if it.get("numFavorites"))
    rated = sum(1 for it in targets if it.get("avgRating"))
    vws = sum(1 for it in targets if it.get("views30d") is not None)
    print(f"[signals] done: downloads {cov}/{len(targets)} · favorites>0 {favs} · "
          f"rated {rated} · views {vws}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
