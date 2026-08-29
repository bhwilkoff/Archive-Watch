#!/usr/bin/env python3
"""
harvest_reviews.py — fetch archive.org reviews for items that have them, keep only
GENUINE reviews of the title (comment_fit scorer), and bake the top few into the
catalog `reviews` field for the app's Detail page.

We filter in the PIPELINE so every client just displays a clean set — no per-platform
filtering, no runtime LLM. Drops file/upload/quality talk ("what format is the audio",
"request a re-rip") and inappropriate/spam; keeps real reviews of the film. See
comment_fit.py for the scorer (validated against real reviews).

Per item with numReviews>0: GET /metadata/{id} -> reviews[], score each, keep the
fit ones, store the top --keep (by stars then fit) as
  reviews: [{reviewer, title, body, stars, date}]   (body clamped)
plus reviewsKept / reviewsScanned / reviewsHarvestedAt (resumable, --stale-days).

Run (catalog_release.py fetch first):
  python tools/harvest_reviews.py --limit 500
  python tools/harvest_reviews.py            # all items with reviews
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402
from comment_fit import score_review  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
BODY_MAX = 600
# How many kept reviews actually hit the cap, reported per run. Raising
# BODY_MAX costs bytes in every item_json and the .zz has a budget
# (Decision 046), so the decision wants EVIDENCE rather than a guess — this
# is the number that supplies it.
_TRUNCATED = [0, 0]   # [hit the cap, kept in total]


def _clip_body(text):
    """Cap a review body WITHOUT ending mid-word.

    `[:600]` cut wherever it landed, so a long review ended "…many insider j"
    — which reads as a bug rather than an excerpt, and is what the owner saw
    on the phone once the display clamp was lifted (2026-08-28). Backing up
    to the last space and marking the elision says the same thing honestly.
    """
    body = " ".join((text or "").split())
    _TRUNCATED[1] += 1
    if len(body) <= BODY_MAX:
        return body
    _TRUNCATED[0] += 1
    cut = body[:BODY_MAX]
    space = cut.rfind(" ")
    if space > BODY_MAX * 0.6:        # never strand a huge fragment
        cut = cut[:space]
    return cut.rstrip(" ,;:—-") + "…"


def _today():
    return datetime.date.today().isoformat()


def fetch_reviews(iaid, session, tries=3):
    """metadata reviews[] for one item; [] on persistent failure (API is flaky)."""
    for attempt in range(tries):
        try:
            r = session.get(A.ARCHIVE_META + iaid, headers={"User-Agent": A.UA}, timeout=25)
            r.raise_for_status()
            return r.json().get("reviews") or []
        except Exception:
            time.sleep(1.2 * (attempt + 1))
    return None                                       # signal "couldn't fetch"


def pick_reviews(raw, keep):
    """Score + filter raw reviews, return (kept_clean_list, scanned_count)."""
    fit = []
    for rv in raw:
        score, verdict = score_review(rv)
        if verdict == "keep":
            fit.append((score, rv))
    # best first: higher stars then higher fit (a 5-star genuine review leads)
    fit.sort(key=lambda sr: (sr[1].get("stars") or 0, sr[0]), reverse=True)
    out = []
    for score, rv in fit[:keep]:
        body = _clip_body(rv.get("reviewbody"))
        out.append({
            "reviewer": (rv.get("reviewer") or "").strip()[:60],
            "title": (rv.get("reviewtitle") or "").strip()[:120],
            "body": body,
            "stars": _stars(rv.get("stars")),         # normalize to int|null for clients
            "date": (rv.get("reviewdate") or "")[:10],
        })
    return out, len(raw)


def _stars(v):
    try:
        n = int(float(v))
    except (TypeError, ValueError):
        return None
    return n if 1 <= n <= 5 else None                 # 0 = a comment, not a rating


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="cap items processed (popularity-first)")
    ap.add_argument("--keep", type=int, default=6, help="max reviews to store per item")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--stale-days", type=int, default=29, help="re-scan items older than this")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[reviews] no catalog.json (catalog_release.py fetch first)"); return 2
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    today = _today()

    def needs(it):
        if (it.get("numReviews") or 0) < 1 or it.get("excluded"):
            return False
        d = it.get("reviewsHarvestedAt")
        if not d:
            return True
        try:
            return (datetime.date.fromisoformat(today) - datetime.date.fromisoformat(d)).days >= args.stale_days
        except ValueError:
            return True

    targets = [it for it in items if it.get("archiveID") and needs(it)]
    targets.sort(key=lambda it: it.get("numReviews") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[reviews] {len(targets)} items with reviews to scan (keep<= {args.keep})", flush=True)
    if not targets:
        return 0

    lock = threading.Lock()
    done = kept_total = 0

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    def work(it):
        raw = fetch_reviews(it["archiveID"], requests.Session())
        nonlocal done, kept_total
        if raw is None:                               # fetch failed — leave unmarked, retry next run
            with lock:
                done += 1
            return
        kept, scanned = pick_reviews(raw, args.keep)
        with lock:
            if kept:
                it["reviews"] = kept
            elif "reviews" in it:
                del it["reviews"]                     # previously-stored now all filtered out
            it["reviewsKept"] = len(kept)
            it["reviewsScanned"] = scanned
            it["reviewsHarvestedAt"] = today
            done += 1
            kept_total += len(kept)
            if done % 100 == 0 or done == len(targets):
                flush()
                print(f"[reviews] {done}/{len(targets)} · {kept_total} genuine reviews kept", flush=True)

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(work, it) for it in targets]
        for _ in as_completed(futs):
            pass
    flush()
    print(f"[reviews] done: scanned {done} items, kept {kept_total} genuine reviews", flush=True)
    hit, total = _TRUNCATED
    if total:
        print(f"[reviews] {hit}/{total} kept reviews hit the {BODY_MAX}-char cap "
              f"({100 * hit // total}%) — raise BODY_MAX only if this is high AND "
              f"the .zz still fits its budget (Decision 046)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
