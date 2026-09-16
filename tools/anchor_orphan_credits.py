#!/usr/bin/env python3
"""
anchor_orphan_credits.py — grow the TMDb caches so remediate can tell a film's
OWN credits from another film's residue when the id is gone.

Why (2026-09-16, the metadata audit): `strip_unanchored_tmdb_residue` clears
TMDb credit rows (cast with `character`, the director that came with them,
release date, studios...) from any item with no surviving external id — a
NetZero reel titled "501" wore the 2008 Danish film's whole crew. The keep
side of that rule is `cast_residue_fixes`: credits stay when ≥3 names are the
cast of a TMDb film carrying the item's own title. That lookup is OFFLINE,
against shared/editorial/tmdb_cast_cache.json + tmdb_verify_cache.json, and
those caches only held films earlier tools had fetched — so All the Fine Young
Cannibals (1960) and Cold Turkey (1925) were about to lose correct credits.

This tool searches TMDb by the item's title (+year when it has one), reads the
credits of the best hit, and when ≥3 names agree with the item's cast writes
that film into both caches. It never touches the catalog and never restores an
id — a verifier removed the id for a reason it does not re-litigate.

Usage: python3 tools/anchor_orphan_credits.py [--limit N] [--dry-run]
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402
import tmdb_lib as T  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
CAST_CACHE = REPO / "shared/editorial/tmdb_cast_cache.json"
VERIFY_CACHE = REPO / "shared/editorial/tmdb_verify_cache.json"
TRIED = REPO / "shared/editorial/orphan_credits_tried.json"


def tmdb_rows(it):
    return [c for c in (it.get("cast") or []) if isinstance(c, dict)
            and (c.get("tmdbPersonID") or c.get("character") or c.get("order") is not None)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text())
    cc = json.loads(CAST_CACHE.read_text())
    vc = json.loads(VERIFY_CACHE.read_text())
    tried = json.loads(TRIED.read_text()) if TRIED.exists() else {}

    # Candidates = what remediate would clear today.
    probe = copy.deepcopy(cat["items"])
    anchored = R.cast_residue_fixes(probe, __import__("collections").Counter())
    cands = []
    for it in probe:
        if it.get("excluded") or it["archiveID"] in anchored or it["archiveID"] in tried:
            continue
        rows = tmdb_rows(it)
        if len(rows) < 3:
            continue
        # A yearless item cannot be anchored (the title search finds the
        # same-title film the wrong match came from) — do not fetch for it.
        if not isinstance(it.get("year"), int) and not re.search(r"(?<!\d)(1[89]\d\d|20\d\d)(?!\d)", it["archiveID"]):
            continue
        if R.strip_unanchored_tmdb_residue(copy.deepcopy(it)):
            cands.append((it["archiveID"], it.get("title") or "", it.get("year"),
                          {(r.get("name") or "").lower() for r in rows}))
    if args.limit:
        cands = cands[: args.limit]
    print(f"candidates with >=3 TMDb cast rows and no anchor: {len(cands)}")

    token = T.load_tmdb_token(SECRETS)
    if not token:
        sys.exit("no TMDB_BEARER_TOKEN")
    local = threading.local()

    def one(aid, title, year, names):
        if not hasattr(local, "sess"):
            local.sess = requests.Session()
        s = local.sess
        try:
            tid = T.search_movie(title, year, token, s) if year else None
            if not tid:
                tid = T.search_movie(title, None, token, s)
            if not tid:
                return aid, None, "no search hit"
            r = s.get(f"{T.TMDB_API}/movie/{tid}", params={"append_to_response": "credits"},
                      headers=T._headers(token), timeout=20)
            if not r.ok:
                return aid, None, f"detail {r.status_code}"
            d = r.json()
            cast = (d.get("credits") or {}).get("cast") or []
            got = {(c.get("name") or "").lower(): c for c in cast if c.get("name")}
            overlap = len(names & set(got))
            time.sleep(0.05)
            if overlap < 3:
                return aid, None, f"overlap {overlap} with {d.get('title')!r}"
            rd = (d.get("release_date") or "")[:4]
            entry = {n: {"p": c.get("profile_path"), "c": c.get("character")} for n, c in got.items()}
            return aid, (str(tid), d.get("title"), int(rd) if rd.isdigit() else None, entry), None
        except Exception as e:  # noqa: BLE001
            return aid, None, str(e)[:80]

    added = 0
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(one, *c) for c in cands]
        for i, f in enumerate(as_completed(futs), 1):
            aid, hit, why = f.result()
            tried[aid] = {"at": time.strftime("%Y-%m-%d"), "hit": bool(hit), "why": why}
            if hit:
                tid, title, year, entry = hit
                cc[tid] = entry
                vc[tid] = {"title": title, "year": year}
                added += 1
            if i % 100 == 0:
                print(f"  {i}/{len(cands)} anchored {added}")
    print(f"anchored {added} of {len(cands)}")
    if not args.dry_run:
        CAST_CACHE.write_text(json.dumps(cc, ensure_ascii=False))
        VERIFY_CACHE.write_text(json.dumps(vc, ensure_ascii=False))
        TRIED.write_text(json.dumps(tried, ensure_ascii=False, indent=0))
        print("caches written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
