#!/usr/bin/env python3
"""
opensubtitles_subtitles.py — fetch HUMAN-made English subtitles from OpenSubtitles
for catalog films, by IMDb id (Decision 039 Phase 3 — the QUALITY layer).

archive.org ASR (Phase 1) + Whisper (Phase 4) give broad machine-transcribed
coverage; OpenSubtitles adds human-authored subtitles for the films people watch
most, where transcription quality matters. It's the QUALITY layer, not the
coverage lever: the free tier is capped (~20 downloads/day; VIP ~1000/day), so
this runs popularity-first and stops when the daily quota is spent — resumable
the next day. Non-commercial use + a back-link are OpenSubtitles' terms, which
Archive Watch satisfies (free app, Decision 010; attribution on the About screen).

Per target it searches /subtitles by imdb_id + languages=en, picks the best
human (non-machine, non-AI, most-downloaded) track, downloads it, converts SRT→
WebVTT, writes the same `subs/<id>/` HLS set the other phases emit, and records
`captions:[{... source:"opensubtitles"}]` + `subtitleHLS`. By default it only
fills UNCAPTIONED films; `--upgrade` also replaces machine (whisper/archive-asr)
captions on popular titles with the human version.

Auth (gitignored env / CI secret — NEVER commit):
  export OPENSUBTITLES_API_KEY=...           # required (register a free app key)
  export OPENSUBTITLES_USERNAME=... OPENSUBTITLES_PASSWORD=...   # optional, raises quota

Run (catalog_release.py fetch first):
  python tools/opensubtitles_subtitles.py --limit 20
Then publish via the existing path (tar subs -> subtitle-assets release ->
catalog publish -> deploy-pages -> publish-db), same as the other phases.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections import Counter
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_subtitle_assets import srt_to_vtt, hls_manifests, safe_dir, PAGES_BASE, SUBS_DIR  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

API = "https://api.opensubtitles.com/api/v1"
UA = "ArchiveWatch/1.0 (https://archivewatch.org)"
# Machine-translated subs are no better than our own Whisper, so we never spend a
# scarce download on one — humans only.
MACHINE_FLAGS = ("ai_translated", "machine_translated")


class OpenSubs:
    def __init__(self, api_key, username=None, password=None):
        self.s = requests.Session()
        self.s.headers.update({"Api-Key": api_key, "User-Agent": UA,
                               "Accept": "application/json"})
        self.token = None
        if username and password:
            r = self.s.post(f"{API}/login", json={"username": username, "password": password},
                            headers={"Content-Type": "application/json"}, timeout=30)
            if r.status_code == 200:
                self.token = r.json().get("token")
                self.s.headers["Authorization"] = f"Bearer {self.token}"
                print(f"[os] logged in (level {r.json().get('user', {}).get('level')})")
            else:
                print(f"[os] login failed ({r.status_code}); continuing key-only")

    def best_english(self, imdb_id):
        """Search by imdb id; return the best human English file_id, or None."""
        tt = imdb_id.lstrip("t") if imdb_id.startswith("tt") else imdb_id
        try:
            r = self.s.get(f"{API}/subtitles",
                           params={"imdb_id": tt, "languages": "en", "order_by": "download_count"},
                           timeout=30)
            if r.status_code != 200:
                return None
            data = r.json().get("data") or []
        except requests.RequestException:
            return None
        best = None
        for d in data:
            a = d.get("attributes") or {}
            if a.get("language") != "en":
                continue
            if any(a.get(f) for f in MACHINE_FLAGS):
                continue
            files = a.get("files") or []
            if not files or not files[0].get("file_id"):
                continue
            score = (a.get("download_count") or 0, a.get("ratings") or 0)
            if best is None or score > best[0]:
                best = (score, files[0]["file_id"],
                        bool(a.get("hearing_impaired")), a.get("download_count") or 0)
        return best

    def download(self, file_id):
        """POST /download → (srt_text, remaining_quota). remaining=-1 if unknown,
        None on hard failure (quota exhausted / error)."""
        try:
            r = self.s.post(f"{API}/download", json={"file_id": file_id},
                            headers={"Content-Type": "application/json"}, timeout=30)
        except requests.RequestException:
            return None, None
        if r.status_code == 406 or r.status_code == 429:
            return None, 0                       # quota exhausted for the day
        if r.status_code != 200:
            return None, -1
        j = r.json()
        remaining = j.get("remaining", -1)
        link = j.get("link")
        if not link:
            return None, remaining
        try:
            sub = self.s.get(link, timeout=40)
            if sub.status_code != 200 or not sub.text.strip():
                return None, remaining
            return sub.text, remaining
        except requests.RequestException:
            return None, remaining


def write_assets(item, srt_text):
    """SRT → subs/<id>/ (VTT + HLS) + record captions. Mirrors the other phases."""
    sid = safe_dir(item["archiveID"])
    out = SUBS_DIR / sid
    out.mkdir(parents=True, exist_ok=True)
    vtt = srt_to_vtt(srt_text)
    (out / "en.vtt").write_text(vtt, encoding="utf-8")
    base = f"{PAGES_BASE}/{sid}"
    langs = [("en", "English", "en.vtt")]
    master, video, subs = hls_manifests(item["downloadURL"], item.get("runtimeSeconds") or 0, langs)
    (out / "master.m3u8").write_text(master, encoding="utf-8")
    (out / "video.m3u8").write_text(video, encoding="utf-8")
    (out / "subs.en.m3u8").write_text(subs["en"], encoding="utf-8")
    url = f"{base}/en.vtt"
    item["captions"] = [{"lang": "en", "label": "English", "format": "vtt",
                         "url": url, "vttURL": url, "source": "opensubtitles"}]
    item["subtitleHLS"] = f"{base}/master.m3u8"
    item["captionsChecked"] = True
    item.pop("whisperGenerated", None)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="max items to attempt this run")
    ap.add_argument("--min-pop", type=int, default=0)
    ap.add_argument("--upgrade", action="store_true",
                    help="also replace machine (whisper/asr) captions on popular titles")
    args = ap.parse_args()

    key = os.environ.get("OPENSUBTITLES_API_KEY")
    if not key:
        print("[os] OPENSUBTITLES_API_KEY not set — see header"); return 2
    if not CATALOG.exists():
        print("[os] no catalog.json (catalog_release.py fetch first)"); return 2

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    api = OpenSubs(key, os.environ.get("OPENSUBTITLES_USERNAME"),
                   os.environ.get("OPENSUBTITLES_PASSWORD"))

    def candidate(it):
        if not it.get("downloadURL") or it.get("excluded") or not it.get("imdbID"):
            return False
        if it.get("contentType") in ("silent-film", "tv-series"):
            return False
        if (it.get("popularityScore") or 0) < args.min_pop:
            return False
        caps = it.get("captions")
        if not caps:
            return True
        if args.upgrade:                         # replace machine captions, skip human ones
            return all(c.get("source") in ("whisper", "archive-asr") for c in caps)
        return False

    targets = [it for it in items if candidate(it)]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[os] {len(targets)} targets ({'gaps + upgrades' if args.upgrade else 'gaps only'})", flush=True)

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    tally = Counter()
    for n, it in enumerate(targets, 1):
        best = api.best_english(it["imdbID"])
        if not best:
            tally["no-match"] += 1
            continue
        _score, file_id, hi, dl = best
        srt, remaining = api.download(file_id)
        if remaining == 0:
            print(f"[os] daily quota exhausted after {tally['built']} downloads — resume tomorrow", flush=True)
            break
        if not srt:
            tally["dl-fail"] += 1
            continue
        write_assets(it, srt)
        tally["built"] += 1
        print(f"[{n}] {it['archiveID']}: built (dl_count={dl}{' HI' if hi else ''}, quota left {remaining})", flush=True)
        flush()
        time.sleep(1)                            # be polite to the API
    flush()
    print(f"[os] done: {dict(tally)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
