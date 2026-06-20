#!/usr/bin/env python3
"""
build_subtitle_assets.py — turn archive.org caption files into web/Apple-ready
subtitle assets, hosted on GitHub Pages.

Why: Android side-loads archive.org's SRT directly (Decision 039), but WEB needs
a CORS-served VTT (archive.org sends none) and APPLE needs HLS (the only native
AVPlayerViewController subtitle path) with a WebVTT carrying X-TIMESTAMP-MAP.
GitHub Pages serves with CORS AND is fetchable by AVPlayer, so it's the one host
for both. This tool, per captioned item:
  1. downloads the archive.org SRT (from the catalog `captions` field),
  2. converts it to WebVTT — comma→dot AND fractional-seconds normalized to 3
     digits (archive ASR emits 2 e.g. "00:00:01,44"), plus the X-TIMESTAMP-MAP
     header AVPlayer's HLS requires,
  3. writes a tiny HLS set (master + single-segment video playlist pointing at
     the archive.org MP4 + a subtitle playlist pointing at the VTT),
  4. records on the item: `captions[].vttURL` (web) + `subtitleHLS` (Apple).
Output goes to `subs/<id>/` for the Pages deploy (deploy-pages.yml).

NOTE: the video playlist references the MP4 as a SINGLE VOD segment — simplest,
works for subtitle selection; a byte-range-segmented variant (parse the moov for
segment boundaries) is the resilience upgrade (Decision 039). Run in CI:
fetch catalog -> this tool -> publish catalog + deploy subs to Pages.

Run: python tools/build_subtitle_assets.py [--limit N] [--workers 8] [--probe ID]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SUBS_DIR = REPO / "subs"                      # deployed to Pages at /subs/
PAGES_BASE = "https://archivewatch.org/subs"

_TS = re.compile(r"(\d{1,2}):(\d{2}):(\d{2})[.,](\d{1,3})")


def _norm_ts(m):
    h, mm, ss, frac = m.groups()
    frac = (frac + "000")[:3]                 # 2-digit ASR fractions → ms
    return f"{int(h):02d}:{mm}:{ss}.{frac}"


def srt_to_vtt(srt: str) -> str:
    """Convert SRT → WebVTT. Normalizes timestamps (comma→dot, fraction→3-digit
    ms) and prepends the WEBVTT + X-TIMESTAMP-MAP header AVPlayer HLS needs."""
    body = srt.replace("\r\n", "\n").replace("\r", "\n").lstrip("﻿").strip()
    body = _TS.sub(_norm_ts, body)
    return "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n\n" + body + "\n"


def hls_manifests(mp4_url: str, runtime: int, langs):
    """(master.m3u8, video.m3u8, {lang: subs.<lang>.m3u8}). `langs` = list of
    (lang, label, vtt_filename). Single-segment VOD video playlist."""
    dur = max(int(runtime or 0), 1)
    media = []
    for i, (lang, label, _vtt) in enumerate(langs):
        default = "YES" if (lang == "en" or i == 0) else "NO"
        media.append(
            f'#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="{label}",'
            f'LANGUAGE="{lang}",AUTOSELECT=YES,DEFAULT={default},FORCED=NO,'
            f'URI="subs.{lang}.m3u8"')
    master = ("#EXTM3U\n#EXT-X-VERSION:6\n" + "\n".join(media) +
              '\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,SUBTITLES="subs"\nvideo.m3u8\n')
    video = (f"#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:{dur}\n"
             f"#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:{dur}.0,\n{mp4_url}\n#EXT-X-ENDLIST\n")
    subs = {}
    for lang, _label, vtt in langs:
        subs[lang] = (f"#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:{dur}\n"
                      f"#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:{dur}.0,\n{vtt}\n#EXT-X-ENDLIST\n")
    return master, video, subs


def safe_dir(archive_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", archive_id)


def build_for(item, session) -> str:
    caps = item.get("captions") or []
    if not caps or not item.get("downloadURL"):
        return "skip"
    sid = safe_dir(item["archiveID"])
    out = SUBS_DIR / sid
    base = f"{PAGES_BASE}/{sid}"
    langs = []
    for c in caps:
        text = None
        for attempt in range(3):              # archive.org 503s under load; retry
            try:
                r = session.get(c["url"], headers={"User-Agent": A.UA}, timeout=40)
                if r.status_code == 200 and r.text.strip():
                    text = r.text
                    break
                if r.status_code not in (429, 500, 502, 503, 504):
                    break                     # a real 404/permission error: give up
            except requests.RequestException:
                pass
            time.sleep(1.5 * (attempt + 1))   # linear backoff
        if text is None:
            continue
        vtt = text if c["url"].lower().endswith(".vtt") else srt_to_vtt(text)
        out.mkdir(parents=True, exist_ok=True)
        fname = f"{c['lang']}.vtt"
        (out / fname).write_text(vtt, encoding="utf-8")
        c["vttURL"] = f"{base}/{fname}"        # web reader uses this (CORS-OK)
        langs.append((c["lang"], c.get("label") or c["lang"].upper(), fname))
    if not langs:
        return "empty"
    master, video, subs = hls_manifests(item["downloadURL"], item.get("runtimeSeconds") or 0, langs)
    (out / "master.m3u8").write_text(master, encoding="utf-8")
    (out / "video.m3u8").write_text(video, encoding="utf-8")
    for lang, body in subs.items():
        (out / f"subs.{lang}.m3u8").write_text(body, encoding="utf-8")
    item["subtitleHLS"] = f"{base}/master.m3u8"   # Apple reader uses this
    return "built"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--probe", help="convert one archiveID + print, write nothing to catalog")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[subs-assets] no catalog.json (fetch first)"); return 2
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    session = requests.Session()

    if args.probe:
        it = next((i for i in items if i["archiveID"] == args.probe), None)
        if not it:
            print("not found"); return 1
        print(build_for(it, session))
        print("subtitleHLS:", it.get("subtitleHLS"))
        for c in it.get("captions") or []:
            print("  vttURL:", c.get("vttURL"))
        return 0

    targets = [i for i in items if (i.get("captions") and i.get("downloadURL")
                                    and not i.get("excluded")
                                    and not i.get("subtitleHLS"))]
    targets.sort(key=lambda i: i.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[subs-assets] {len(targets)} captioned items to build (workers {args.workers})", flush=True)

    tally = Counter(); lock = threading.Lock(); done = 0
    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":")); tmp.replace(CATALOG)
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(build_for, it, session) for it in targets]
        for fut in as_completed(futs):
            with lock:
                tally[fut.result()] += 1; done += 1
            if done % 200 == 0 or done == len(targets):
                flush(); print(f"[{done}/{len(targets)}] {dict(tally)}", flush=True)
    flush()
    print(f"[subs-assets] done: {dict(tally)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
