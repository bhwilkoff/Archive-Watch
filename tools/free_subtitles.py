#!/usr/bin/env python3
"""
free_subtitles.py — fetch English subtitles from the FREE, on-demand community APIs
(SubDL primary, SubSource secondary), per film, by IMDb id (Decision 039 Phase 3).

WHY this instead of a dump or OpenSubtitles.com: OpenSubtitles.com's API is effectively
paid (~20 free dl/day) and the full OpenSubtitles dump is 127 GB (no disk). SubDL +
SubSource are $0 with a free key, search per-film by id/title, and return tiny .srt
files — so the only disk used is the matched subtitles themselves. No bulk download.

  - SubDL:     free key, search by imdb_id, ~2,000 req/day but ~300 DOWNLOADS/day/IP.
               GET https://api.subdl.com/api/v1/subtitles -> JSON; each result `url`
               is a .zip under https://dl.subdl.com containing the .srt.
  - SubSource: free key, ~7,200 req/day (60/min) — the workhorse, but matches by
               title+year (weaker than imdb), so the SYNC GUARD matters more.

Run popularity-first; it sweeps the catalog over ~1-2 weeks and harvests whatever the
community actually has (a few thousand on top of the archive.org ASR backbone, mostly
the popular head). Obscure pre-1965 PD prints mostly won't be there — that's expected;
accurate-or-none is the standard.

Auth (gitignored env / CI secret — NEVER commit):
  export SUBDL_API_KEY=...        # free: subdl.com -> profile -> API
  export SUBSOURCE_API_KEY=...    # free: subsource.net -> profile (optional, for --provider subsource)

Run (catalog_release.py fetch first):
  python tools/free_subtitles.py --provider subdl --limit 300
  python tools/free_subtitles.py --provider subsource --limit 3000
Then publish via the existing path (tar subs -> subtitle-assets release -> catalog
publish -> deploy-pages -> publish-db), same as the other phases.

VERIFY-ON-FIRST-RUN: this sandbox couldn't reach api.subdl.com / api.subsource.net, so
the request/response shapes below are from each provider's published docs. The first
keyed run on the owner's Mac confirms them; the parse points are isolated in
_subdl_search/_subdl_fetch and _subsource_* and log raw payloads on mismatch.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import time
import zipfile
from collections import Counter
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_subtitle_assets import srt_to_vtt, hls_manifests, safe_dir, PAGES_BASE, SUBS_DIR  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
UA = "ArchiveWatch/1.0 (https://archivewatch.org)"


def _last_cue_seconds(srt_text: str):
    import re
    times = re.findall(r"-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})", srt_text)
    if not times:
        return None
    h, m, s, ms = times[-1]
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def _pick_srt_from_zip(content: bytes) -> str | None:
    """Return the largest .srt member of a zip, decoded."""
    try:
        zf = zipfile.ZipFile(io.BytesIO(content))
    except zipfile.BadZipFile:
        # some providers return the .srt directly, not zipped
        for enc in ("utf-8", "windows-1252", "iso-8859-1"):
            try:
                return content.decode(enc)
            except UnicodeDecodeError:
                continue
        return content.decode("utf-8", "replace")
    srts = [n for n in zf.namelist() if n.lower().endswith(".srt")]
    if not srts:
        return None
    name = max(srts, key=lambda n: zf.getinfo(n).file_size)
    raw = zf.read(name)
    for enc in ("utf-8", "windows-1252", "iso-8859-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", "replace")


# ------------------------------- SubDL provider -------------------------------
class SubDL:
    name = "subdl"
    SEARCH = "https://api.subdl.com/api/v1/subtitles"
    DL_BASE = "https://dl.subdl.com"

    def __init__(self, key):
        self.key = key
        self.s = requests.Session()
        self.s.headers.update({"User-Agent": UA, "Accept": "application/json"})

    def best_srt(self, item):
        """imdb_id search -> best English .srt text, or None."""
        imdb = item.get("imdbID")
        if not imdb:
            return None
        try:
            r = self.s.get(self.SEARCH, params={
                "api_key": self.key, "imdb_id": imdb, "type": "movie",
                "languages": "EN", "subs_per_page": 10}, timeout=30)
            if r.status_code != 200:
                return None
            data = r.json()
        except (requests.RequestException, ValueError):
            return None
        subs = data.get("subtitles") or []
        # English first; SubDL gives no download_count, so order is the API's relevance.
        for sub in subs:
            if (sub.get("language") or sub.get("lang") or "").lower() not in ("en", "english", ""):
                continue
            url = sub.get("url") or ""
            if not url:
                continue
            full = url if url.startswith("http") else self.DL_BASE + url
            try:
                z = self.s.get(full, timeout=40)
                if z.status_code != 200 or not z.content:
                    continue
            except requests.RequestException:
                continue
            srt = _pick_srt_from_zip(z.content)
            if srt and srt.strip():
                return srt
        return None


# ----------------------------- SubSource provider -----------------------------
class SubSource:
    """Title+year matching. Endpoint paths per the published docs / community wrapper;
    confirm on first keyed run (logs raw payloads on parse failure)."""
    name = "subsource"
    BASE = "https://api.subsource.net/api"

    def __init__(self, key):
        self.s = requests.Session()
        self.s.headers.update({"User-Agent": UA, "Accept": "application/json"})
        if key:
            self.s.headers["X-API-Key"] = key

    def best_srt(self, item):
        title = item.get("title") or ""
        if not title:
            return None
        try:
            r = self.s.get(f"{self.BASE}/searchMovie", params={"query": title}, timeout=30)
            if r.status_code != 200:
                return None
            found = (r.json().get("found") or r.json().get("results") or r.json())
        except (requests.RequestException, ValueError):
            return None
        movie = found[0] if isinstance(found, list) and found else None
        if not movie:
            return None
        link = movie.get("linkName") or movie.get("link") or movie.get("id")
        try:
            sr = self.s.get(f"{self.BASE}/getMovie", params={"movieName": link, "langs": "english"}, timeout=30)
            subs = (sr.json().get("subs") or sr.json().get("subtitles") or [])
        except (requests.RequestException, ValueError):
            return None
        for sub in subs[:10]:
            sub_id = sub.get("subId") or sub.get("id")
            if not sub_id:
                continue
            try:
                dl = self.s.get(f"{self.BASE}/downloadSub/{sub_id}", timeout=40)
                if dl.status_code != 200 or not dl.content:
                    continue
            except requests.RequestException:
                continue
            srt = _pick_srt_from_zip(dl.content)
            if srt and srt.strip():
                return srt
        return None


def write_assets(item, srt_text, source):
    sid = safe_dir(item["archiveID"])
    out = SUBS_DIR / sid
    out.mkdir(parents=True, exist_ok=True)
    (out / "en.vtt").write_text(srt_to_vtt(srt_text), encoding="utf-8")
    base = f"{PAGES_BASE}/{sid}"
    master, video, subs = hls_manifests(item["downloadURL"], item.get("runtimeSeconds") or 0,
                                         [("en", "English", "en.vtt")])
    (out / "master.m3u8").write_text(master, encoding="utf-8")
    (out / "video.m3u8").write_text(video, encoding="utf-8")
    (out / "subs.en.m3u8").write_text(subs["en"], encoding="utf-8")
    url = f"{base}/en.vtt"
    item["captions"] = [{"lang": "en", "label": "English", "format": "vtt",
                         "url": url, "vttURL": url, "source": source}]
    item["subtitleHLS"] = f"{base}/master.m3u8"
    item["captionsChecked"] = True
    item.pop("whisperGenerated", None)


def _probe(prov, ident):
    """Dump the RAW API response for one film so the response shape is verified
    against reality (not docs) before a full run. Run this FIRST on the owner's Mac."""
    print(f"[probe] {prov.name}: {ident}")
    item = {"imdbID": ident if str(ident).startswith("tt") else None,
            "title": None if str(ident).startswith("tt") else ident,
            "archiveID": "PROBE", "downloadURL": "x", "runtimeSeconds": 0}
    try:
        if prov.name == "subdl":
            r = prov.s.get(prov.SEARCH, params={
                "api_key": prov.key, "imdb_id": item["imdbID"], "type": "movie",
                "languages": "EN", "subs_per_page": 5}, timeout=30)
            print(f"[probe] search HTTP {r.status_code}")
            print(f"[probe] raw: {r.text[:1200]}")
        else:
            r = prov.s.get(f"{prov.BASE}/searchMovie", params={"query": item["title"]}, timeout=30)
            print(f"[probe] searchMovie HTTP {r.status_code}")
            print(f"[probe] raw: {r.text[:1200]}")
        srt = prov.best_srt(item)
        if srt:
            print(f"[probe] best_srt OK: {len(srt)} chars, last cue "
                  f"{_last_cue_seconds(srt)}s, first lines:\n{srt[:200]}")
        else:
            print("[probe] best_srt returned None (shape mismatch? paste the raw above)")
    except requests.exceptions.SSLError as e:
        print(f"[probe] SSL ERROR: {e}\n[probe] your python's TLS is too old for Cloudflare; "
              "run with a modern python (brew install python) or tell me and I'll switch to node.")
    except Exception as e:
        print(f"[probe] ERROR: {e!r}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--provider", choices=("subdl", "subsource"), required=True)
    ap.add_argument("--probe", metavar="IMDB_OR_TITLE",
                    help="dump the raw API response for one film and exit (verify shape first)")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--min-pop", type=int, default=0)
    ap.add_argument("--upgrade", action="store_true",
                    help="also replace machine (whisper/asr) captions")
    args = ap.parse_args()

    if args.provider == "subdl":
        key = os.environ.get("SUBDL_API_KEY")
        if not key:
            print("[subs] SUBDL_API_KEY not set (free: subdl.com -> profile -> API)"); return 2
        prov = SubDL(key)
    else:
        prov = SubSource(os.environ.get("SUBSOURCE_API_KEY"))

    if args.probe:
        _probe(prov, args.probe)
        return 0

    if not CATALOG.exists():
        print("[subs] no catalog.json (catalog_release.py fetch first)"); return 2
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    def candidate(it):
        if not it.get("downloadURL") or it.get("excluded"):
            return False
        if it.get("contentType") in ("tv-series", "silent-film"):
            return False
        if (it.get("popularityScore") or 0) < args.min_pop:
            return False
        # SubDL matches by imdb; SubSource by title.
        if args.provider == "subdl" and not it.get("imdbID"):
            return False
        caps = it.get("captions")
        if not caps:
            return True
        if args.upgrade:
            return all(c.get("source") in ("whisper", "archive-asr") for c in caps)
        return False

    targets = [it for it in items if candidate(it)]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[subs] {prov.name}: {len(targets):,} targets", flush=True)

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    tally = Counter()
    for n, it in enumerate(targets, 1):
        try:
            srt = prov.best_srt(it)
        except Exception as e:  # never let one item kill the sweep
            print(f"[{n}] {it['archiveID']}: error {e}", flush=True)
            tally["error"] += 1
            continue
        if not srt:
            tally["no-match"] += 1
            continue
        rt = it.get("runtimeSeconds") or 0
        last = _last_cue_seconds(srt)
        if rt and last and abs(last - rt) / rt > 0.10:
            tally["sync-reject"] += 1
            print(f"[{n}] {it['archiveID']}: SYNC-REJECT (last cue {int(last)}s vs runtime {rt}s)", flush=True)
            continue
        write_assets(it, srt, prov.name)
        tally["built"] += 1
        print(f"[{n}] {it['archiveID']}: built", flush=True)
        if tally["built"] % 25 == 0:
            flush()
        time.sleep(0.5)
    flush()
    print(f"[subs] done: {dict(tally)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
