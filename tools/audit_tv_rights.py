#!/usr/bin/env python3
"""
audit_tv_rights.py — apply the rights audit to TELEVISION.

WHY THIS EXISTS. `audit_rights.py` (Decision 027) runs over `catalog.json`.
TV episodes are NOT catalog items — they live only in `series/*.json`, put
there by `backfill_tv_episodes.py`, which searches archive.org by show title
and applies no rights test at all. So every episode in every spine had never
been seen by the audit. The owner found it from the app: 2 Stupid Dogs, a
1993 Hanna-Barbera show, playing as public domain.

THE RULES ARE NOT NEW ONES. Every judgement here is the film audit's own:
`license_rescues()` for whether an uploader's licence can be trusted, `GOV`
for government/PD collections, `MODERN = 1978` for the cutoff Decision 027
set (which keeps the 1964-77 PD-by-defect era). Re-implementing them is what
Decision 105 forbids — ask the thing that owns the rule.

WHAT IT DOES. Report-first, like the film audit. `--apply` REMOVES the
offending episodes from the spines and deletes a spine left empty, because
the apps fetch `archivewatch.org/series/<slug>.json` DIRECTLY — filtering the
built database would not stop the file being served. Every removal is written
to a manifest, and git history is the undo.

  python tools/audit_tv_rights.py                 # report only
  python tools/audit_tv_rights.py --apply
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import audit_rights as AR  # noqa: E402

SERIES_DIR = REPO / "series"
CACHE = REPO / "shared" / "editorial" / "tv_rights_cache.json"
MANIFEST = REPO / "shared" / "editorial" / "tv_rights_removed.csv"
UA = "ArchiveWatch-RightsAudit/1.0 (+https://archivewatch.org)"

try:
    sys.stdout.reconfigure(line_buffering=True)
except AttributeError:  # pragma: no cover
    pass


def spine_year(d) -> int | None:
    y = d.get("yearStart")
    return y if isinstance(y, int) else None


def fetch(aid: str) -> dict:
    """Archive.org's own words about the item: licence, rights, collections."""
    url = "https://archive.org/metadata/" + urllib.parse.quote(str(aid))
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                m = (json.load(r) or {}).get("metadata", {}) or {}
            coll = m.get("collection") or []
            if isinstance(coll, str):
                coll = [coll]
            return {"licenseurl": m.get("licenseurl") or "",
                    "rights": m.get("rights") or "",
                    "collections": [str(c) for c in coll],
                    "ok": True}
        except Exception:  # noqa: BLE001
            time.sleep(1.5 * (attempt + 1))
    # A failed fetch is NEVER a hide (Decision 027: an unconfirmed item stays
    # visible). It is reported so it can be re-run.
    return {"licenseurl": "", "rights": "", "collections": [], "ok": False}


def verdict(year: int | None, meta: dict) -> tuple[str, str]:
    """(keep|remove|unconfirmed, why) — using the FILM audit's own rules."""
    if not meta.get("ok"):
        return "unconfirmed", "archive.org did not answer"
    if year is None or year < AR.MODERN:
        return "keep", f"pre-{AR.MODERN}"
    cl = {c.lower() for c in meta["collections"]}
    if cl & AR.GOV:
        return "keep", "government / public-domain collection"
    lic = meta["licenseurl"]
    # votes=None: a spine carries no IMDb footprint, so the commercial
    # override cannot fire. That is the documented residual class in
    # license_rescues, and it errs toward KEEPING, which is the safe side.
    if AR.license_rescues(lic, year, None):
        return "keep", f"licence: {lic}"
    return "remove", (f"{year}, no free licence"
                      + (f" (licence claim: {lic})" if lic else " and none claimed"))


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="remove the offending episodes; without it, report only")
    ap.add_argument("--workers", type=int, default=5,
                    help="archive.org rate-limits the IP on bursts; keep this low")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    spines = {}
    for f in sorted(SERIES_DIR.glob("*.json")):
        try:
            spines[f] = json.loads(f.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue

    # Only MODERN shows need a licence check; the rest are kept by the same
    # rule the film audit uses, without a network call.
    need = {}
    for f, d in spines.items():
        y = spine_year(d)
        if y is None or y < AR.MODERN:
            continue
        for s in d.get("seasons") or []:
            for e in s.get("episodes") or []:
                aid = e.get("archiveID")
                if aid:
                    need.setdefault(str(aid), y)
    ids = sorted(need)
    if args.limit:
        ids = ids[: args.limit]
    print(f"[tv-rights] spines {len(spines)}, modern items to confirm {len(ids)}")

    cache = {}
    if CACHE.exists():
        try:
            cache = json.loads(CACHE.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            cache = {}
    todo = [i for i in ids if i not in cache or not cache[i].get("ok")]
    print(f"[tv-rights] cached {len(ids) - len(todo)}, fetching {len(todo)}")

    done = 0
    with cf.ThreadPoolExecutor(args.workers) as ex:
        for aid, meta in zip(todo, ex.map(fetch, todo)):
            cache[aid] = meta
            done += 1
            if done % 100 == 0:
                print(f"[tv-rights]   {done}/{len(todo)}")
                CACHE.parent.mkdir(parents=True, exist_ok=True)
                CACHE.write_text(json.dumps(cache), encoding="utf-8")
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache), encoding="utf-8")

    removed_rows, kept, unconfirmed = [], 0, 0
    drop_ids = {}
    for aid, year in need.items():
        v, why = verdict(year, cache.get(aid, {"ok": False}))
        if v == "remove":
            drop_ids[aid] = why
        elif v == "unconfirmed":
            unconfirmed += 1
        else:
            kept += 1

    changed_files = emptied = eps_removed = 0
    for f, d in spines.items():
        y = spine_year(d)
        if y is None or y < AR.MODERN:
            continue
        hit = False
        for s in d.get("seasons") or []:
            keep_eps = []
            for e in s.get("episodes") or []:
                aid = str(e.get("archiveID") or "")
                if aid in drop_ids:
                    removed_rows.append((f.stem, d.get("title"), y, aid,
                                         e.get("title"), drop_ids[aid]))
                    eps_removed += 1
                    hit = True
                else:
                    keep_eps.append(e)
            s["episodes"] = keep_eps
        if not hit:
            continue
        d["seasons"] = [s for s in (d.get("seasons") or []) if s.get("episodes")]
        left = sum(len(s.get("episodes") or []) for s in d["seasons"])
        d["episodesCount"] = left
        changed_files += 1
        if left == 0:
            emptied += 1
        if args.apply:
            if left == 0:
                f.unlink()
            else:
                f.write_text(json.dumps(d, ensure_ascii=False,
                                        separators=(",", ":")), encoding="utf-8")

    print()
    print(f"  items judged REMOVE : {len(drop_ids)}")
    print(f"  items kept          : {kept}")
    print(f"  unconfirmed (kept)  : {unconfirmed}")
    print(f"  episodes removed    : {eps_removed}")
    print(f"  spines touched      : {changed_files}  (emptied and deleted: {emptied})")
    if not args.apply:
        print("\n  REPORT ONLY — nothing written. Re-run with --apply.")

    if removed_rows:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        import csv
        with MANIFEST.open("w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["spine", "show", "year", "archiveID", "episode", "why"])
            w.writerows(removed_rows)
        print(f"  manifest -> {MANIFEST.relative_to(REPO)}")
        shows = {}
        for slug, show, yr, aid, ep, why in removed_rows:
            shows.setdefault((yr, show), 0)
            shows[(yr, show)] += 1
        print("\n  largest removals:")
        for (yr, show), n in sorted(shows.items(), key=lambda x: -x[1])[:15]:
            print(f"     {yr}  {str(show)[:40]:40s} {n:4d} eps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
