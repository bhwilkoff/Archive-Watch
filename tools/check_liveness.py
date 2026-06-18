#!/usr/bin/env python3
"""
check_liveness.py — flag catalog items whose Archive item is dead, and refresh
stale download URLs for the ones that are still alive.

Why: items accumulate in the catalog with a downloadURL baked at ingest time
(Decision 023 / playback is catalog-first). When an Archive item is later
darkened, removed, or has its derivative re-derived under a new filename, the
baked URL 404s and the title "doesn't play at all" — and, worse, IMDb dedup
(build_sqlite.dedupe_by_imdb) can pick the DEAD copy as the single survivor and
HIDE the live duplicates (the Niagara Falls 1941 case: a dead
`niagara_falls_1941_202201` won the tiebreak over two playable copies).

What it does, per item (concurrent, resumable):
  * Fetch archive.org/metadata/{archiveID}.
  * DEAD  -> set excluded=true (reversible, Decision 027) + livenessReason, when
            the signal is DEFINITIVE: is_dark, an {"error": ...} body, no files,
            or no playable video derivative. dedupe_by_imdb skips excluded items
            (so a live sibling surfaces) and populate_items never inserts them.
  * ALIVE -> if the baked downloadURL's filename is gone but a current playable
            derivative exists, refresh downloadURL (+ runtimeSeconds). Clears any
            stale excluded/livenessDead WE set (never touches a rights exclusion).
  * UNREACHABLE (timeout / 5xx after retries) -> left UNCONFIRMED: not excluded,
            not marked checked, so the next run retries it. Never wrongly hide.

Every resolved item is marked `livenessChecked` so re-runs are cheap; --refresh
re-checks. Priority: IMDb-dedup-cluster members first (a dead winner there hides
live copies), then by popularity.

Run: python tools/check_liveness.py [--limit N] [--workers 12]
                                    [--clusters-only] [--refresh] [--dry-run]
Catalog I/O via the local catalog.json (catalog_release.py fetch first in CI).
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

# Marker keys we own (so --refresh / alive-recovery only touches OUR flags and
# never a rights-audit exclusion from audit_rights.py).
DEAD_FLAG = "livenessDead"


def metadata(iaid, session):
    """Return (status, json|None). status in {ok, dark, error, unreachable}.
    Retries transient failures so a busy node never reads as 'dead'."""
    last = "unreachable"
    for attempt in range(3):
        try:
            r = session.get(A.ARCHIVE_META + iaid,
                            headers={"User-Agent": A.UA}, timeout=30)
        except requests.RequestException:
            last = "unreachable"
            continue
        if r.status_code in (500, 502, 503, 504):
            last = "unreachable"
            continue
        if r.status_code == 404:
            return "error", None
        if r.status_code != 200:
            last = "unreachable"
            continue
        try:
            d = r.json()
        except ValueError:
            last = "unreachable"
            continue
        if isinstance(d, dict) and d.get("error"):
            return "error", None          # {"error": "unable to load metadata ..."}
        if isinstance(d, dict) and d.get("is_dark"):
            return "dark", d
        return "ok", d
    return last, None


def classify(it, session):
    """Return (verdict, info). verdict in
    {alive, dead, unreachable}; info carries a reason or a refreshed URL."""
    iaid = it.get("archiveID")
    if not iaid:
        return "unreachable", None
    status, d = metadata(iaid, session)
    if status == "unreachable":
        return "unreachable", None
    if status == "dark":
        return "dead", "dark"
    if status == "error":
        return "dead", "metadata_error"
    files = d.get("files") or []
    if not files:
        return "dead", "no_files"
    vf = A.pick_video(files)
    if not vf:
        return "dead", "no_playable_video"
    # Alive. Is the baked downloadURL still valid (filename present)?
    cur = A.download_url(iaid, vf.get("name"))
    refreshed = None
    if (it.get("downloadURL") or "") != cur:
        names = {f.get("name") for f in files}
        baked = (it.get("downloadURL") or "").rsplit("/", 1)[-1]
        baked = requests.utils.unquote(baked)
        if baked not in names:        # the exact baked file is gone -> repoint
            refreshed = (cur, A.runtime_from_file(vf))
    return "alive", refreshed


def cluster_priority(items):
    """archiveIDs whose IMDb id is shared by >1 non-excluded item — a dead one
    here hides its live siblings, so check these first."""
    by_imdb = defaultdict(list)
    for it in items:
        if it.get("excluded") or it.get(DEAD_FLAG):
            continue
        k = it.get("imdbID")
        if k:
            by_imdb[k].append(it.get("archiveID"))
    out = set()
    for k, v in by_imdb.items():
        if len(v) > 1:
            out.update(v)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--clusters-only", action="store_true",
                    help="only check items in multi-copy IMDb clusters")
    ap.add_argument("--refresh", action="store_true",
                    help="re-check items already marked livenessChecked")
    ap.add_argument("--dry-run", action="store_true", help="report only; write nothing")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[liveness] no catalog.json (run catalog_release.py fetch first)")
        return 2

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    prio = cluster_priority(items)

    def candidate(it):
        if not it.get("downloadURL"):
            return False
        # A rights-audit exclusion (no livenessDead flag) is final — skip it; we
        # only ever ADD a liveness exclusion or recover one WE set.
        if it.get("excluded") and not it.get(DEAD_FLAG):
            return False
        if args.clusters_only and it.get("archiveID") not in prio:
            return False
        return args.refresh or not it.get("livenessChecked")

    targets = [it for it in items if candidate(it)]
    # cluster members first, then popularity
    targets.sort(key=lambda it: (it.get("archiveID") in prio,
                                 it.get("popularityScore") or 0), reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[liveness] {len(targets)} items to probe "
          f"({sum(1 for it in targets if it.get('archiveID') in prio)} in IMDb clusters; "
          f"workers {args.workers}{' DRY-RUN' if args.dry_run else ''})", flush=True)

    tally = Counter()
    lock = threading.Lock()
    session = requests.Session()

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    def work(it):
        verdict, info = classify(it, session)
        if args.dry_run:
            return verdict
        if verdict == "unreachable":
            return verdict                       # leave unconfirmed; retry next run
        it["livenessChecked"] = True
        if verdict == "dead":
            it["excluded"] = True
            it[DEAD_FLAG] = True
            it["livenessReason"] = info
        elif verdict == "alive":
            # Recover an exclusion WE previously set (item came back / was a
            # transient false-dead); never clear a rights exclusion.
            if it.get(DEAD_FLAG):
                it.pop(DEAD_FLAG, None)
                it.pop("livenessReason", None)
                if it.get("excluded"):
                    it["excluded"] = False
            if info:
                it["downloadURL"], rt = info[0], info[1]
                if rt:
                    it["runtimeSeconds"] = rt
                return "alive_repointed"
        return verdict

    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(work, it) for it in targets]
        for fut in as_completed(futs):
            v = fut.result()
            with lock:
                tally[v] += 1
                done += 1
            if done % 200 == 0 or done == len(targets):
                if not args.dry_run:
                    flush()
                print(f"[{done}/{len(targets)}] {dict(tally)}", flush=True)
    if not args.dry_run:
        flush()
    print(f"[liveness] done: {dict(tally)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
