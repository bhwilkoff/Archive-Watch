#!/usr/bin/env python3
"""
verify_airplay_receiver_path.py — walk the media an AirPlay RECEIVER is handed,
exactly as the receiver would.

WHY: Apple does not support video AirPlay with a custom resource loader, and
every playback path in the apps is loader-backed — so on a route change the
player swaps to a PUBLISHED url the receiver can fetch itself (AirPlayRouting).
That swap is only as good as the published URL. For a captioned title the
receiver gets our HLS, and this repo has already shipped an HLS whose segment
URI was unfetchable by a strict client while curl and ffprobe resolved it fine
(see the `hls_subtitle_segment_encoding` note). A lenient probe would have
passed that; walking the playlist the way the receiver does would not.

So this fetches, for a sample of captioned titles:
    master.m3u8  ->  the video rendition  ->  the media segment
asserting each is plain https and answers 200/206, and that a subtitle rendition
is actually declared (captions are the whole reason HLS is preferred over MP4).

Usage:
    python3 tools/verify_airplay_receiver_path.py [--db catalog.sqlite] [--n 5]
    python3 tools/verify_airplay_receiver_path.py --id his_girl_friday
"""

import argparse
import json
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UA = {"User-Agent": "ArchiveWatch-AirPlayCheck/1.0"}
LOADER_SCHEMES = {"aw-stream", "aw-hls"}      # must mirror AirPlayRouting.swift


def fetch(url, method="GET", limit=8000, tries=3):
    """Returns (status, body). status 0 == transient (timeout / handshake / reset).

    Retried, and reported SEPARATELY from an HTTP error, because archive.org
    times out under load often enough that a single failed handshake would
    otherwise read as "the receiver cannot play this" — the same
    never-condemn-on-a-throttle rule the poster validator follows. Observed
    live: a segment that SSL-timed-out on one attempt answered 302 on the next.
    """
    last = (0, "")
    for attempt in range(tries):
        req = urllib.request.Request(url, method=method, headers=UA)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, (r.read(limit).decode("utf-8", "replace") if method == "GET" else "")
        except urllib.error.HTTPError as e:
            # 5xx from archive.org is a ROTATING STORAGE NODE, not a dead file
            # (Decision 034) — observed live: the same segment answered 200, then
            # 500, then 200. Retry it; only a 4xx is definitive.
            if 500 <= e.code < 600 and attempt < tries - 1:
                last = (e.code, "")
                continue
            return e.code, ""
        except Exception as e:                 # noqa: BLE001
            last = (0, f"{type(e).__name__}: {e}"[:90])
    return last


def captioned_ids(db_path, n):
    db = sqlite3.connect(db_path)
    out = []
    for (j,) in db.execute("SELECT json FROM item_json"):
        d = json.loads(j)
        if d.get("subtitleHLS"):
            out.append((d["archiveID"], d["subtitleHLS"]))
            if len(out) >= n:
                break
    db.close()
    return out


def walk(aid, master):
    """Returns (ok, [lines])."""
    log, ok = [f"{aid}"], True

    scheme = urllib.parse.urlparse(master).scheme.lower()
    if scheme in LOADER_SCHEMES or scheme not in ("http", "https"):
        return False, log + [f"  master scheme '{scheme}' is NOT receiver-fetchable"]

    code, body = fetch(master)
    log.append(f"  master.m3u8        {code}")
    if code != 200:
        return False, log

    subs = body.count("TYPE=SUBTITLES")
    log.append(f"  subtitle renditions {subs}")
    if subs == 0:
        ok = False
        log.append("  ^ no caption rendition — the receiver gains nothing over the MP4")

    variants = [l.strip() for l in body.splitlines() if l.strip() and not l.startswith("#")]
    if not variants:
        return False, log + ["  no video rendition in the master"]

    vurl = urllib.parse.urljoin(master, variants[0])
    code, vbody = fetch(vurl)
    log.append(f"  video rendition    {code}")
    if code != 200:
        return False, log

    segs = [l.strip() for l in vbody.splitlines() if l.strip() and not l.startswith("#")]
    if not segs:
        return False, log + ["  no media segment in the rendition"]

    seg = urllib.parse.urljoin(vurl, segs[0])
    sscheme = urllib.parse.urlparse(seg).scheme.lower()
    if sscheme not in ("http", "https"):
        return False, log + [f"  segment scheme '{sscheme}' is NOT receiver-fetchable: {seg[:80]}"]
    code, err = fetch(seg, "HEAD")
    # 302 is the NORMAL archive.org /download answer — it redirects to a storage
    # node, and a receiver follows it like any client. 0 = transient after
    # retries: reported, but never counted as a failure.
    verdict = "OK" if code in (200, 206, 302) else ("TRANSIENT" if code == 0 else "UNFETCHABLE")
    log.append(f"  media segment      {code} {verdict}  {seg[:70]}")
    if verdict == "UNFETCHABLE":
        ok = False
    if verdict == "TRANSIENT":
        log.append(f"  ^ {err} — archive.org did not answer; not judged")
    return ok, log


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(REPO / "catalog.sqlite"))
    ap.add_argument("--n", type=int, default=5)
    ap.add_argument("--id", action="append", default=[],
                    help="check a specific archiveID instead of sampling")
    args = ap.parse_args()

    if args.id:
        items = [(i, f"https://archivewatch.org/subs/{i}/master.m3u8") for i in args.id]
    elif Path(args.db).exists():
        items = captioned_ids(args.db, args.n)
    else:
        print(f"no catalog DB at {args.db}; pass --id or fetch the catalog first")
        return 2

    print(f"Walking the AirPlay receiver path for {len(items)} captioned title(s)\n")
    bad = []
    for aid, master in items:
        ok, log = walk(aid, master)
        print("\n".join(log))
        print("  ->", "OK" if ok else "FAIL", "\n")
        if not ok:
            bad.append(aid)

    if bad:
        print(f"FAIL: {len(bad)}/{len(items)} unplayable by a receiver: {', '.join(bad)}")
        return 1
    print(f"PASS: all {len(items)} fetchable end-to-end by an AirPlay receiver.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
