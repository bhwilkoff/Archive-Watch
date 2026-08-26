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


# --- What actually came down the wire ------------------------------------------
#
# Subtitle sites serve whatever the uploader posted: UTF-16 SRT, cp1252 SRT, and
# frequently a ZIP or RAR of the .srt rather than the .srt itself. Reading that
# with `requests`' `r.text` — which guesses a charset and cheerfully decodes a
# BINARY as latin-1 — produced files that passed every check here and rendered
# NOTHING in a player:
#   • a UTF-16 SRT became `ÿþ1\x00\n\x00...` mojibake, so the timestamp regex
#     matched nothing, the commas stayed, and the WEBVTT header was pasted on top
#     of unparseable bytes (measured: "Osaka Elegy", "The Crusades");
#   • a RAR archive was published verbatim as `en.vtt`, header and all
#     ("Face of Terror" — the file literally begins `Rar!\x1a\x07`).
# The CC button appeared and there were no subtitles behind it, which is exactly
# what the owner reported.

_ARCHIVE_MAGIC = ((b"Rar!\x1a\x07", "rar"), (b"PK\x03\x04", "zip"),
                  (b"\x1f\x8b", "gzip"), (b"7z\xbc\xaf\x27\x1c", "7z"))


def decode_subtitle(raw: bytes):
    """(text, note) from RAW BYTES — never `requests.text`. Returns (None, why)
    when the payload is not usable subtitle text."""
    if not raw or not raw.strip():
        return None, "empty"
    for magic, kind in _ARCHIVE_MAGIC:
        if raw.startswith(magic):
            if kind == "zip":                      # extract the first sub inside
                import io as _io
                import zipfile
                try:
                    z = zipfile.ZipFile(_io.BytesIO(raw))
                    for n in z.namelist():
                        if n.lower().endswith((".srt", ".vtt", ".ass", ".ssa")):
                            return decode_subtitle(z.read(n))
                except Exception:                  # noqa: BLE001
                    pass
            return None, f"archive:{kind}"         # rar/7z/gzip: never publish raw
    # BOM-first, because a UTF-16 file decoded as UTF-8/latin-1 looks like text
    # but parses as nothing.
    for bom, enc in ((b"\xff\xfe\x00\x00", "utf-32"), (b"\x00\x00\xfe\xff", "utf-32"),
                     (b"\xff\xfe", "utf-16"), (b"\xfe\xff", "utf-16"),
                     (b"\xef\xbb\xbf", "utf-8-sig")):
        if raw.startswith(bom):
            try:
                return raw.decode(enc), enc
            except Exception:                      # noqa: BLE001
                break
    # No BOM: a NUL-heavy body is UTF-16 that lost its mark.
    if raw[:400].count(b"\x00") > 40:
        for enc in ("utf-16-le", "utf-16-be"):
            try:
                return raw.decode(enc), enc
            except Exception:                      # noqa: BLE001
                continue
    for enc in ("utf-8", "cp1252", "latin-1"):
        try:
            return raw.decode(enc), enc
        except UnicodeDecodeError:
            continue
    return None, "undecodable"


def _reading_need(words: int) -> float:
    return max(1.0, words / 2.5)


def _merge_rapid_cues(vtt: str) -> tuple[str, int]:
    """Merge rapid-fire fragments that extension alone can never make readable.

    pace_vtt's 1.0s floor is capped by the NEXT cue's start, so in dense
    dialogue — cues starting 0.3-0.5s apart — the floor is unachievable by
    extending into empty space: there is no empty space. Measured on Impact
    (w1-impact-verify): the correctly-timed, paced file still held 112 cues
    under 1.0s and 187 three-in-3s windows, and the glass faithfully showed
    every burst. The professional fix is the subtitler's: combine contiguous
    short fragments into one cue.

    A merge happens only when ALL of:
      * the cue's available span (next.start - start) is under its reading
        time — extension cannot fix it,
      * the gap to the next cue is <= 0.75s — same continuous speech,
      * the combined body stays modest (<= 3 lines, <= 120 chars).

    Two one-line fragments that fit a standard 42-char line join into one
    line; anything else stacks. Cue count CHANGES here, deliberately — every
    caller wants readability, none asserts count after pacing (the sync
    tools validate before pacing, and the app re-fetches whatever is
    published).
    """
    lines = vtt.splitlines()
    stamp_idx = [i for i, l in enumerate(lines) if _RANGE.search(l)]
    if len(stamp_idx) < 2:
        return vtt, 0

    first = stamp_idx[0]
    header_end = first
    if header_end > 0 and lines[header_end - 1].strip():
        header_end -= 1                    # the cue's identifier line
    header = lines[:header_end]

    def secs(h, m_, s_, ms):
        return int(h or 0) * 3600 + int(m_) * 60 + int(s_) + int(ms.ljust(3, "0")) / 1000

    cues = []
    for li in stamp_idx:
        m = _RANGE.search(lines[li])
        g = m.groups()
        settings = lines[li][m.end():].strip()
        body = []
        for nxt in lines[li + 1:]:
            if not nxt.strip() or _RANGE.search(nxt):
                break
            body.append(nxt.rstrip())
        cues.append({"start": secs(g[0], g[1], g[2], g[3]),
                     "end": secs(g[4], g[5], g[6], g[7]),
                     "settings": settings, "body": body})

    merged = 0
    i = 0
    while i < len(cues) - 1:
        c, n = cues[i], cues[i + 1]
        avail = n["start"] - c["start"]
        words = len(" ".join(c["body"]).split())
        gap = n["start"] - c["end"]
        total_lines = len(c["body"]) + len(n["body"])
        total_chars = sum(len(l) for l in c["body"] + n["body"])
        if (avail < _reading_need(words) and gap <= 0.75
                and total_lines <= 3 and total_chars <= 120):
            if (len(c["body"]) == 1 and len(n["body"]) == 1
                    and len(c["body"][0]) + len(n["body"][0]) + 1 <= 42):
                body = [c["body"][0] + " " + n["body"][0]]
            else:
                body = c["body"] + n["body"]
            cues[i] = {"start": c["start"], "end": max(c["end"], n["end"]),
                       "settings": c["settings"], "body": body}
            del cues[i + 1]
            merged += 1
            continue                       # the merged cue may still be short
        i += 1

    if not merged:
        return vtt, 0

    def stamp(t):
        ms = int(round((t - int(t)) * 1000))
        t = int(t)
        return f"{t // 3600:02d}:{(t % 3600) // 60:02d}:{t % 60:02d}.{ms:03d}"

    out = list(header)
    if out and out[-1].strip():
        out.append("")
    for k, c in enumerate(cues, 1):
        out.append(str(k))
        tail = f" {c['settings']}" if c["settings"] else ""
        out.append(f"{stamp(c['start'])} --> {stamp(c['end'])}{tail}")
        out.extend(c["body"])
        out.append("")
    return "\n".join(out) + "\n", merged


def pace_vtt(vtt: str) -> tuple[str, int]:
    """Stop a caption being replaced before it can be read.

    Two faults are common in sourced subtitles and both make a viewer race the
    screen: cues that OVERLAP (the next appears while the current line is still
    being spoken) and cues held for less time than the line takes to read. The
    owner reported exactly this behaviour, and it applies to human-sourced
    subtitles as much as to generated ones.

    Fixes, conservatively — a cue is only ever EXTENDED into empty space, never
    shortened, and never pushed past the cue that follows it:
      * merge rapid-fire fragments no extension could make readable
        (see _merge_rapid_cues — the burst fix)
      * clamp any end that runs past the next start (kills overlap)
      * extend a too-short cue toward the next start, up to its reading time
        (~2.5 words/second, the usual subtitle guideline)

    Returns (vtt, number_of_cues_adjusted).
    """
    vtt, merged = _merge_rapid_cues(vtt)
    lines = vtt.splitlines()
    stamps = [(i, m) for i, l in enumerate(lines) if (m := _RANGE.search(l))]
    if len(stamps) < 2:
        return vtt, 0

    def secs(h, m_, s_, ms):
        return int(h or 0) * 3600 + int(m_) * 60 + int(s_) + int(ms.ljust(3, "0")) / 1000

    def stamp(t):
        ms = int(round((t - int(t)) * 1000))
        t = int(t)
        return f"{t // 3600:02d}:{(t % 3600) // 60:02d}:{t % 60:02d}.{ms:03d}"

    cues = []
    for idx, (li, m) in enumerate(stamps):
        g = m.groups()
        start, end = secs(g[0], g[1], g[2], g[3]), secs(g[4], g[5], g[6], g[7])
        body = []
        for nxt in lines[li + 1:]:
            if not nxt.strip() or _RANGE.search(nxt):
                break
            body.append(nxt)
        cues.append({"line": li, "start": start, "end": end,
                     "words": len(" ".join(body).split())})

    changed = 0
    for i, c in enumerate(cues):
        nxt = cues[i + 1]["start"] if i + 1 < len(cues) else None
        new_end = c["end"]
        if nxt is not None and new_end > nxt:
            new_end = nxt                              # overlap -> clamp
        need = _reading_need(c["words"])
        if new_end - c["start"] < need:                # too brief -> extend
            room = nxt if nxt is not None else c["start"] + need
            new_end = min(c["start"] + need, room)
        if abs(new_end - c["end"]) > 0.01:
            lines[c["line"]] = f"{stamp(c['start'])} --> {stamp(new_end)}"
            changed += 1
    return "\n".join(lines) + "\n", changed + merged


_RANGE = re.compile(
    r"(?:(\d{1,3}):)?(\d{1,2}):(\d{2})[.,](\d{1,3})\s*-->\s*"
    r"(?:(\d{1,3}):)?(\d{1,2}):(\d{2})[.,](\d{1,3})")

_CUE = re.compile(r"\d{1,2}:\d{2}:\d{2}[.,]\d{1,3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[.,]\d{1,3}")


_EN_STOPWORDS = {"the", "and", "you", "that", "this", "with", "have", "what", "your"}


def _english_stopword_rate(vtt: str):
    """(rate, words). Measured 2026-08-26 over the published corpus: genuine
    English tracks run 0.13-0.14; Swedish/Portuguese/Czech/Italian/Spanish
    files mislabeled as en all read <= 0.001. Six SERVED cards were shipping
    non-English text as their en track (Patterns in Swedish, Manos in
    Spanish, One-Eyed Jacks + Niagara in Portuguese, Princess Iron Fan in
    Czech, The General Line in Italian) — found by cross-file vocabulary
    disagreement between dup siblings, invisible to every physics gate."""
    stop = total = 0
    for line in vtt.splitlines():
        if "-->" in line or line.startswith(("WEBVTT", "X-TIMESTAMP")) or "::cue" in line:
            continue
        for w in re.findall(r"[a-zà-öø-ÿ']{2,}", line.lower()):
            total += 1
            stop += w in _EN_STOPWORDS
    return (stop / total if total else 0), total


def validate_vtt(vtt: str, runtime: int, lang: str | None = None):
    if lang == "en":
        rate, words = _english_stopword_rate(vtt)
        if words >= 200 and rate < 0.04:
            return False, f"labeled en but text is not English (stopword rate {rate:.3f})"
    return _validate_vtt_body(vtt, runtime)


def _validate_vtt_body(vtt: str, runtime: int):
    """(ok, why). The guard that was missing: parse what we are about to publish
    and refuse it unless it is really cues that really span the film. Every
    defect above would have been caught here."""
    cues = _CUE.findall(vtt)
    if len(cues) < 5:
        return False, f"only {len(cues)} cues"
    last = _TS.findall(vtt)
    if not last:
        return False, "no timestamps"
    h, m, s, _f = last[-1]
    end = int(h) * 3600 + int(m) * 60 + int(s)
    if runtime > 600:
        # A track that stops a third of the way in is for a different cut. Allow
        # a little past the runtime (credits, differing masters).
        if end < 0.55 * runtime:
            return False, f"cues end at {100 * end // runtime}% of runtime"
        if end > 1.25 * runtime:
            return False, f"cues run to {100 * end // runtime}% of runtime"
    return True, f"{len(cues)} cues"


def encode_segment_url(url: str) -> str:
    """Percent-encode the path of an MP4 URL so it is a VALID HLS segment URI.
    AVFoundation strictly rejects a segment URI containing raw spaces/()/# (it
    fails the whole item with "resource unavailable"), while lenient parsers
    (ffprobe/curl/Python-requests) resolve it — which is exactly why raw-URL
    playlists passed every probe yet never played on Apple TV. Encodes space,
    (, ), # etc.; keeps / and any existing %XX (safe='/%')."""
    from urllib.parse import quote
    m = re.match(r"^(https?://[^/]+)(/.*)$", url or "", re.I)
    if not m:
        return url
    host, path = m.groups()
    return host + quote(path, safe="/%")


def hls_manifests(mp4_url: str, runtime: int, langs):
    """(master.m3u8, video.m3u8, {lang: subs.<lang>.m3u8}). `langs` = list of
    (lang, label, vtt_filename) or (lang, label, vtt_filename, characteristics).
    Single-segment VOD video playlist.

    The optional 4th element carries HLS media CHARACTERISTICS. Two of them are
    now understood by AVKit itself ("What's new in HTTP Live Streaming", WWDC26):
    `public.machine-generated` marks a rendition that was authored or translated
    programmatically, and `public.translation` marks one translated from another
    subtitle track. AVKit then labels them in its own subtitle menu — an English
    machine track shows as "English Generated", a Spanish translation of it as
    "Spanish Translated" — so a viewer can tell at a glance whether they are
    reading someone's work or a machine's.

    Every track we publish today is HUMAN (uploader files, SubDL, SubSource);
    archive.org's auto-ASR was dropped for hallucinating (Decision 043). So
    nothing gets this characteristic by default — claiming otherwise would be
    the same dishonesty in reverse. It exists for the machine-made and
    translated tracks that would otherwise be indistinguishable from human ones.
    """
    dur = max(int(runtime or 0), 1)
    mp4_url = encode_segment_url(mp4_url)
    media = []
    for i, entry in enumerate(langs):
        lang, label, _vtt = entry[0], entry[1], entry[2]
        characteristics = entry[3] if len(entry) > 3 else ""
        default = "YES" if (lang == "en" or i == 0) else "NO"
        chars = f'CHARACTERISTICS="{characteristics}",' if characteristics else ""
        media.append(
            f'#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="{label}",'
            f'LANGUAGE="{lang}",AUTOSELECT=YES,DEFAULT={default},FORCED=NO,'
            f'{chars}URI="subs.{lang}.m3u8"')
    master = ("#EXTM3U\n#EXT-X-VERSION:6\n" + "\n".join(media) +
              '\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,SUBTITLES="subs"\nvideo.m3u8\n')
    video = (f"#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:{dur}\n"
             f"#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:{dur}.0,\n{mp4_url}\n#EXT-X-ENDLIST\n")
    subs = {}
    for entry in langs:
        lang, vtt = entry[0], entry[2]
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
                if r.status_code == 200 and r.content.strip():
                    # BYTES, not r.text — see decode_subtitle.
                    text, note = decode_subtitle(r.content)
                    if text is None:
                        print(f"  [subs] {item['archiveID'][:38]} {c['lang']}: "
                              f"unusable payload ({note})", flush=True)
                    break
                if r.status_code not in (429, 500, 502, 503, 504):
                    break                     # a real 404/permission error: give up
            except requests.RequestException:
                pass
            time.sleep(1.5 * (attempt + 1))   # linear backoff
        if text is None:
            continue
        vtt = text if c["url"].lower().endswith(".vtt") else srt_to_vtt(text)
        # A .vtt from upstream still gets normalized: several arrive with SRT
        # comma timestamps, which a WebVTT parser rejects.
        if "-->" in vtt and "," in vtt:
            vtt = srt_to_vtt(vtt.split("\n\n", 1)[-1] if vtt.startswith("WEBVTT") else vtt)
        vtt, paced = pace_vtt(vtt)
        if paced:
            print(f"  [subs] {item['archiveID'][:38]} {c['lang']}: paced {paced} cues "
                  "(overlap / too brief to read)", flush=True)
        ok, why = validate_vtt(vtt, item.get("runtimeSeconds") or 0, lang=c["lang"])
        if not ok:
            print(f"  [subs] {item['archiveID'][:38]} {c['lang']}: rejected ({why})",
                  flush=True)
            continue
        out.mkdir(parents=True, exist_ok=True)
        fname = f"{c['lang']}.vtt"
        (out / fname).write_text(vtt, encoding="utf-8")
        c["vttURL"] = f"{base}/{fname}"        # web reader uses this (CORS-OK)
        langs.append((c["lang"], c.get("label") or c["lang"].upper(), fname))
    if not langs:
        # Nothing usable survived validation. Drop the claim entirely: a caption
        # entry with no playable file gives the viewer a CC button that shows
        # nothing, which is worse than no button at all — and reads to them as
        # "the subtitles are broken" (owner, 2026-08-09).
        item.pop("captions", None)
        item.pop("subtitleHLS", None)
        return "empty"
    # Keep only the tracks that were actually written and validated.
    kept = {l for l, _lbl, _f in langs}
    item["captions"] = [c for c in caps if c.get("lang") in kept and c.get("vttURL")]
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
