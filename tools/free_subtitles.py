#!/usr/bin/env python3
"""
free_subtitles.py — fetch English subtitles from the FREE, on-demand community APIs
(SubDL + SubSource), per film, by IMDb id (Decision 039 Phase 3).

WHY this instead of a dump or OpenSubtitles.com: OpenSubtitles.com's API is effectively
paid (~20 free dl/day) and the full OpenSubtitles dump is 127 GB (no disk). SubDL +
SubSource are $0 with a free key, search per-film, and return tiny .srt files — so the
only disk used is the matched subtitles. No bulk download.

  - SubDL:     free key, search by imdb_id. ~2,000 req/day but ~300 DOWNLOADS/day/IP.
  - SubSource: free key, ~7,200 req/day (60/min) — the workhorse; ALSO supports imdb.

Both API specs are SOURCE-VERIFIED from maintained clients (subdl_api_cli;
moviecollection/sub-source .NET wrapper). The only envelope uncertainty (SubSource's
outer JSON wrapper) is handled by _unwrap() + revealed by `--probe`.

NETWORK: requests go through Node (tools/_http_fetch.mjs) because macOS system Python's
LibreSSL 2.8.3 can't TLS-handshake with Cloudflare (subdl/subsource are behind it).
Node's modern OpenSSL works. Requires `node` on PATH (Homebrew: /opt/homebrew/bin/node).

Auth (gitignored — NEVER commit):
  source tools/subtitle_keys.env      # exports SUBDL_API_KEY + SUBSOURCE_API_KEY

Run (catalog_release.py fetch first):
  python3 tools/free_subtitles.py --provider subdl     --probe tt0063350   # verify shape
  python3 tools/free_subtitles.py --provider subdl     --limit 300         # imdb head
  python3 tools/free_subtitles.py --provider subsource --limit 3000        # daily sweep
Then publish via the existing path (tar subs -> subtitle-assets release -> catalog
publish -> deploy-pages -> publish-db).
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
from collections import Counter
from pathlib import Path
from urllib.parse import quote, urlencode

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_subtitle_assets import srt_to_vtt, hls_manifests, safe_dir, PAGES_BASE, SUBS_DIR  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
UA = "ArchiveWatch/1.0 (https://archivewatch.org)"
NODE = shutil.which("node") or "/opt/homebrew/bin/node"
HELPER = Path(__file__).resolve().parent / "_http_fetch.mjs"


def http(method, url, headers=None, timeout=60):
    """GET/POST via Node (modern TLS). Returns (status:int, body:bytes)."""
    spec = {"method": method, "url": url, "headers": {"User-Agent": UA, **(headers or {})}}
    try:
        p = subprocess.run([NODE, str(HELPER)], input=json.dumps(spec),
                           capture_output=True, text=True, timeout=timeout)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return 0, b""
    if not p.stdout:
        return 0, b""
    try:
        r = json.loads(p.stdout)
    except ValueError:
        return 0, b""
    return r.get("status", 0), base64.b64decode(r.get("body_b64", "") or "")


def _last_cue_seconds(srt_text: str):
    import re
    times = re.findall(r"-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})", srt_text)
    if not times:
        return None
    h, m, s, ms = times[-1]
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def _pick_srt_from_zip(content: bytes):
    """Largest .srt member of a zip, decoded — or the raw bytes if it isn't a zip
    (SubDL unpack / direct .srt)."""
    try:
        zf = zipfile.ZipFile(io.BytesIO(content))
    except zipfile.BadZipFile:
        for enc in ("utf-8", "windows-1252", "iso-8859-1"):
            try:
                return content.decode(enc)
            except UnicodeDecodeError:
                continue
        return content.decode("utf-8", "replace")
    srts = [n for n in zf.namelist() if n.lower().endswith(".srt")]
    if not srts:
        return None
    raw = zf.read(max(srts, key=lambda n: zf.getinfo(n).file_size))
    for enc in ("utf-8", "windows-1252", "iso-8859-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", "replace")


def _unwrap(obj):
    """SubSource responses may be wrapped ({data:[...]}, {results:[...]}, etc.).
    Return the first list found among the common envelope keys, else [] / the list."""
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for k in ("data", "results", "subtitles", "movies", "found", "items"):
            v = obj.get(k)
            if isinstance(v, list):
                return v
            if isinstance(v, dict):
                inner = _unwrap(v)
                if inner:
                    return inner
    return []


def _json(body):
    try:
        return json.loads(body.decode("utf-8", "replace"))
    except ValueError:
        return None


# ------------------------------- SubDL provider -------------------------------
class SubDL:
    name = "subdl"
    SEARCH = "https://api.subdl.com/api/v1/subtitles"
    DL_BASE = "https://dl.subdl.com"

    def __init__(self, key):
        self.key = key

    def _search_url(self, imdb):
        return self.SEARCH + "?" + urlencode({
            "api_key": self.key, "imdb_id": imdb, "type": "movie",
            "languages": "EN", "subs_per_page": 10})

    def probe_search(self, item):
        return http("GET", self._search_url(item.get("imdbID") or "tt0000000"))

    def best_srt(self, item):
        imdb = item.get("imdbID")
        if not imdb:
            return None
        st, body = http("GET", self._search_url(imdb))
        if st != 200:
            return None
        data = _json(body) or {}
        for sub in (data.get("subtitles") or []):
            lang = (sub.get("lang") or sub.get("language") or "").lower()
            if lang not in ("english", "en", ""):
                continue
            u = sub.get("url") or ""
            if not u:
                continue
            full = u if u.startswith("http") else self.DL_BASE + u
            st2, zb = http("GET", full)
            if st2 != 200 or not zb:
                continue
            srt = _pick_srt_from_zip(zb)
            if srt and srt.strip():
                return srt
        return None


# ----------------------------- SubSource provider -----------------------------
class SubSource:
    """Current v1 REST API (GET + X-API-Key). imdb search supported; title+year
    fallback. Multi-step: movies/search -> movieId -> subtitles?movieId -> download."""
    name = "subsource"
    BASE = "https://api.subsource.net/api/v1"

    def __init__(self, key):
        self.key = key

    def _hdr(self):
        return {"X-API-Key": self.key} if self.key else {}

    def _search_url(self, item):
        imdb = item.get("imdbID")
        if imdb:
            return f"{self.BASE}/movies/search?" + urlencode({"searchType": "imdb", "imdb": imdb})
        title = item.get("title") or ""
        q = {"searchType": "text", "q": title}
        if item.get("year"):
            q["year"] = item["year"]
        return f"{self.BASE}/movies/search?" + urlencode(q)

    def probe_search(self, item):
        return http("GET", self._search_url(item), self._hdr())

    def best_srt(self, item):
        if not item.get("imdbID") and not item.get("title"):
            return None
        hdr = self._hdr()
        st, body = http("GET", self._search_url(item), hdr)
        if st != 200:
            return None
        movies = _unwrap(_json(body))
        if not movies:
            return None
        mid = movies[0].get("movieId") or movies[0].get("id")
        if not mid:
            return None
        st, body = http("GET", f"{self.BASE}/subtitles?" + urlencode(
            {"movieId": mid, "language": "english"}), hdr)
        if st != 200:
            return None
        for sub in _unwrap(_json(body))[:12]:
            sid = sub.get("subtitleId") or sub.get("id")
            if not sid:
                continue
            st2, zb = http("GET", f"{self.BASE}/subtitles/{sid}/download", hdr)
            if st2 != 200 or not zb:
                continue
            srt = _pick_srt_from_zip(zb)
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
    """Dump the RAW step-1 response so the JSON shape is verified against reality."""
    is_tt = str(ident).startswith("tt")
    item = {"imdbID": ident if is_tt else None, "title": None if is_tt else ident,
            "year": None, "archiveID": "PROBE", "downloadURL": "x", "runtimeSeconds": 0}
    print(f"[probe] {prov.name}: {ident}")
    st, body = prov.probe_search(item)
    print(f"[probe] step-1 HTTP {st}")
    print(f"[probe] raw: {body.decode('utf-8', 'replace')[:1500]}")
    srt = prov.best_srt(item)
    if srt:
        print(f"[probe] best_srt OK: {len(srt)} chars; last cue {_last_cue_seconds(srt)}s\n"
              f"--- first lines ---\n{srt[:200]}")
    else:
        print("[probe] best_srt returned None — paste the raw above and I'll fix the parser")


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

    if not Path(NODE).exists() and not shutil.which("node"):
        print("[subs] node not found (needed for TLS). brew install node"); return 2
    if not HELPER.exists():
        print(f"[subs] missing {HELPER}"); return 2

    if args.provider == "subdl":
        key = os.environ.get("SUBDL_API_KEY")
        if not key:
            print("[subs] SUBDL_API_KEY not set (source tools/subtitle_keys.env)"); return 2
        prov = SubDL(key)
    else:
        key = os.environ.get("SUBSOURCE_API_KEY")
        if not key:
            print("[subs] SUBSOURCE_API_KEY not set (source tools/subtitle_keys.env)"); return 2
        prov = SubSource(key)

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
        except Exception as e:
            print(f"[{n}] {it['archiveID']}: error {e!r}", flush=True)
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
        time.sleep(0.3)
    flush()
    print(f"[subs] done: {dict(tally)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
