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
  * UNPLAYABLE -> the metadata lists a derivative, but a ranged GET of its first
            KB shows it is not a playable video (404/410 on the file itself, a
            0-byte body, an HTML/JSON error page, or a container signature that
            doesn't match the extension). Same reversible excluded=true +
            playbackDead. Metadata liveness is NOT playability: a listed .mp4
            can be empty or truncated, and nothing downstream noticed until a
            user pressed play.
  * UNREACHABLE (timeout / 5xx after retries) -> left UNCONFIRMED: not excluded,
            not marked checked, so the next run retries it. Never wrongly hide.
            archive.org answers 503 for a missing item and throttles under load,
            so only 404/410 on the file is treated as definitive.

Two independent markers: `livenessChecked` (metadata) and `playbackVerified` +
`playbackCheckedAt` (bytes). The whole back catalog predates the probe, so those
items are live-but-unverified and still need a first probe; --reprobe-days (90)
re-verifies afterwards, since a URL that dies AFTER its check would otherwise
never be re-probed. Priority: IMDb-dedup-cluster members first (a dead winner
there hides live copies), then by popularity — so Home-facing titles verify
first.

Run: python tools/check_liveness.py [--limit N] [--workers 12]
                                    [--clusters-only] [--refresh] [--dry-run]
                                    [--no-probe] [--reprobe-days 90]
Catalog I/O via the local catalog.json (catalog_release.py fetch first in CI).
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
from collections import Counter, defaultdict
from datetime import date
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
PLAYBACK_DEAD_FLAG = "playbackDead"

# Byte-probe constants. Metadata liveness (the item exists, a derivative is
# listed) is NOT the same as playability — a listed .mp4 can be 0 bytes or a
# truncated/HTML error body, and nothing downstream would notice until a user
# pressed play. Only 404/410 is definitive; 403/429/5xx/timeouts are transient
# (archive.org throttles) and are left UNCONFIRMED, never wrongly hidden — the
# same discipline validate_posters.py uses for images.
PROBE_BYTES = 1024
PLAYBACK_DEAD_CODES = {404, 410}

# Container signatures, checked against the first KB. Keyed by extension so an
# unrecognised/exotic extension is never failed for lack of a signature.
CONTAINER_SIGS = {
    ".mp4": lambda b: b[4:8] == b"ftyp",
    ".m4v": lambda b: b[4:8] == b"ftyp",
    ".mov": lambda b: b[4:8] in (b"ftyp", b"moov", b"mdat", b"wide", b"free"),
    ".mkv": lambda b: b.startswith(b"\x1a\x45\xdf\xa3"),
    ".webm": lambda b: b.startswith(b"\x1a\x45\xdf\xa3"),
    ".ogv": lambda b: b.startswith(b"OggS"),
    ".avi": lambda b: b.startswith(b"RIFF"),
}


def probe_playable(url, session, timeout=25):
    """Ranged GET of the first KB of the actual video. Returns
    (ok: bool|None, reason: str|None) — None means transient/unknown, so the
    caller leaves the item unverified and retries next run.

    Reads at most PROBE_BYTES and closes: a storage node that ignores the
    Range header answers 200 with the WHOLE file, and streaming without a cap
    would pull gigabytes per item.
    """
    r = None
    try:
        r = session.get(url, headers={"User-Agent": A.UA,
                                      "Range": f"bytes=0-{PROBE_BYTES - 1}",
                                      "Accept": "video/*,*/*"},
                        stream=True, timeout=timeout, allow_redirects=True)
        if r.status_code in PLAYBACK_DEAD_CODES:
            return False, f"derivative_http_{r.status_code}"
        if r.status_code not in (200, 206):
            return None, None                      # throttle / 5xx -> retry
        head = r.raw.read(PROBE_BYTES, decode_content=True) or b""
        if len(head) == 0:
            return False, "empty_file"
        ctype = (r.headers.get("Content-Type") or "").lower()
        if ctype.startswith(("text/html", "application/json")):
            return False, "error_page_not_video"
        ext = "." + url.rsplit(".", 1)[-1].lower().split("?")[0] if "." in url else ""
        sig = CONTAINER_SIGS.get(ext)
        if sig and not sig(head):
            return False, f"bad_container{ext}"
        return True, None
    except requests.RequestException:
        return None, None
    finally:
        if r is not None:
            r.close()


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


def classify(it, session, probe=True):
    """Return (verdict, info, playback). verdict in
    {alive, dead, unplayable, unreachable}; info carries a reason or a
    refreshed URL; playback is True (bytes verified), a reason string (hard
    fail), or None (not probed / transient — leave unverified, retry)."""
    iaid = it.get("archiveID")
    if not iaid:
        return "unreachable", None, None
    status, d = metadata(iaid, session)
    if status == "unreachable":
        return "unreachable", None, None
    if status == "dark":
        return "dead", "dark", None
    if status == "error":
        return "dead", "metadata_error", None
    files = d.get("files") or []
    if not files:
        return "dead", "no_files", None
    vf = A.pick_video(files)
    if not vf:
        return "dead", "no_playable_video", None
    # Alive. Is the baked downloadURL still valid (filename present)?
    cur = A.download_url(iaid, vf.get("name"))
    refreshed = None
    if (it.get("downloadURL") or "") != cur:
        names = {f.get("name") for f in files}
        baked = (it.get("downloadURL") or "").rsplit("/", 1)[-1]
        baked = requests.utils.unquote(baked)
        if baked not in names:        # the exact baked file is gone -> repoint
            refreshed = (cur, A.runtime_from_file(vf))
    if not probe:
        return "alive", refreshed, None
    # The metadata says a derivative exists; confirm the BYTES are a real video.
    ok, reason = probe_playable(refreshed[0] if refreshed else (it.get("downloadURL") or cur),
                                session)
    if ok is False:
        return "unplayable", reason, reason
    return "alive", refreshed, (True if ok else None)


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
    ap.add_argument("--no-probe", action="store_true",
                    help="metadata only; skip the byte-level playability probe")
    ap.add_argument("--reprobe-days", type=int, default=90,
                    help="re-verify playback for items last verified longer ago "
                         "than this (0 = never re-verify)")
    args = ap.parse_args()

    today = date.today().isoformat()

    def playback_stale(it):
        """A URL that dies AFTER its check would otherwise never be re-probed."""
        if args.reprobe_days <= 0:
            return False
        when = it.get("playbackCheckedAt")
        if not when:
            return True
        try:
            age = (date.today() - date.fromisoformat(str(when))).days
        except ValueError:
            return True
        return age >= args.reprobe_days

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
        if args.refresh or not it.get("livenessChecked"):
            return True
        # Liveness (metadata) and playability (bytes) are separate markers: the
        # whole back catalog was checked metadata-only before the probe existed,
        # so those items are live-but-unverified and still need a first probe.
        return not args.no_probe and playback_stale(it)

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
        verdict, info, playback = classify(it, session, probe=not args.no_probe)
        if args.dry_run:
            return verdict
        if verdict == "unreachable":
            return verdict                       # leave unconfirmed; retry next run
        it["livenessChecked"] = True
        if verdict == "dead":
            it["excluded"] = True
            it[DEAD_FLAG] = True
            it["livenessReason"] = info
            return verdict
        if verdict == "unplayable":
            # Metadata listed a derivative, but its bytes aren't a playable
            # video. Same reversible mechanism as a dead item.
            it["excluded"] = True
            it[PLAYBACK_DEAD_FLAG] = True
            it["playbackReason"] = info
            it["playbackVerified"] = False
            it["playbackCheckedAt"] = today
            return verdict
        # alive
        # Recover an exclusion WE previously set (item came back / was a
        # transient false-dead); never clear a rights exclusion.
        for flag, reason_key in ((DEAD_FLAG, "livenessReason"),
                                 (PLAYBACK_DEAD_FLAG, "playbackReason")):
            if it.get(flag):
                it.pop(flag, None)
                it.pop(reason_key, None)
                if it.get("excluded"):
                    it["excluded"] = False
        if playback is True:
            it["playbackVerified"] = True
            it["playbackCheckedAt"] = today
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
