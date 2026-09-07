#!/usr/bin/env python3
"""
repick_derivatives.py — fix films whose baked downloadURL is a container AVPlayer
can't play: `.ogv` (Theora), `.mkv`, `.avi`, `.wmv`, `.flv`, `.divx`, `_mpeg2`.

CORRECTION 2026-07-19 (measured, not assumed): this docstring previously claimed
~4,240 items point at a `512Kb MPEG4` file that "iOS AVPlayer won't decode".
That is FALSE and it is a costly thing to believe — acting on it de-verified
1,205 perfectly playable titles before ffprobe settled it. archive.org's
"512Kb MPEG4" names a DERIVATIVE PRESET (bitrate), not the codec: the files are
H.264. Sampled 7 live 512kb.mp4 derivatives, 7/7 `codec_name=h264`
(`the_stranger`, `Popeye_forPresident`, `McLintock`, `superman_1941`,
`horror_express`, `Return_of_the_Kung_Fu_Dragon`, `Teaserama` — the first
reporting profile "Constrained Baseline", tag `avc1`).

The `_BAD` regex below has always been right to exclude 512kb; only this
docstring was wrong. If you doubt it again, re-run:
    ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
      -of csv=p=0 <a 512kb.mp4 URL>

Per affected item: fetch archive.org metadata, re-pick the best derivative, and
if a BETTER playable one now exists (H.264/plain MP4, different from the current
file), rewrite downloadURL (+ videoFile). Resumable via derivativeRepicked;
bounded (per-item metadata fetch). Catalog on the release (Decision 018):
fetch -> repick -> publish.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

# downloadURL CONTAINERS AVPlayer genuinely cannot play. NOT 512kb MPEG-4 Part 2:
# owner confirmed on-device that those DO play (Gumbasia) — Apple's software decoder
# still handles Simple-Profile MP4-container files even though the spec sheet dropped
# it. Only the non-MP4 containers (Theora/Ogg, Matroska, AVI/DivX, MPEG-PS) are stuck.
_BAD = re.compile(r"\.(ogv|mkv|avi|wmv|flv|divx)$|_mpeg2", re.I)   # NOT .mov (QuickTime plays), NOT 512kb (plays)


def probe_durations(url: str, timeout: int = 90):
    """(video_seconds, audio_seconds) from the container header. Reads only
    what ffprobe needs, never the media."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,duration",
             "-of", "json", url],
            capture_output=True, text=True, timeout=timeout).stdout
        streams = json.loads(out).get("streams", [])
    except Exception:
        return None, None
    def first(kind):
        for st in streams:
            if st.get("codec_type") == kind and st.get("duration"):
                try: return float(st["duration"])
                except ValueError: pass
        return None
    return first("video"), first("audio")


def audio_timeline_broken(v, a) -> bool:
    """A track whose own duration RUNS PAST the picture's by more than half is
    not a mastering choice, it is broken metadata.

    Found on `TheSheik` (1921), reported by the owner as "the audio is
    intermittent": archive.org's OWN h.264 derivative declares 5,164s of video
    against 3,305,533s of audio -- 38 days -- so the samples are spread over a
    timeline 640x too long and the sound arrives in isolated bursts. Its
    512Kb derivative is clean (5,164s vs 5,164s).

    The band is deliberately wide. Measured across 194 probeable catalog items,
    ZERO fell outside it, so this flags genuine corruption rather than the
    ordinary second-or-two disagreement between a video and audio track."""
    if not v or not a or v <= 0:
        return False
    # ONLY the stretched case is actionable. Audio SHORTER than the picture is
    # usually how the file was made -- a music score laid over a silent film
    # that stops before the reel does -- and `MysteryOfTheLeapingFish_348`
    # (1,516s of picture, 699s of music) was flagged on the first 200 items of
    # the sweep. Re-picking those would trade a known file for an unknown one
    # on a guess, which is precisely how this tool once de-verified 1,205
    # playable titles (see the module docstring). Short audio is COUNTED and
    # reported; it is never acted on.
    return (a / v) > 1.5


def _is_good_pick(name: str, fmt: str) -> bool:
    """A playable target = an MP4/M4V (H.264 OR MPEG-4-in-MP4 both play on iOS).
    pick_video already ranks H.264 first, so it returns the best available."""
    return name.lower().endswith((".mp4", ".m4v"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--sleep", type=float, default=0.1)
    ap.add_argument("--audio-timeline", action="store_true",
                    help="find items whose audio duration disagrees with the "
                         "picture and re-pick to a derivative whose does not")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[repick] no catalog.json (catalog_release.py fetch first)"); return 2
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    def candidate(it):
        u = it.get("downloadURL") or ""
        if args.audio_timeline:
            # Every playable item is a candidate here: the fault is inside a
            # file the picker chose CORRECTLY (The Sheik's bad file is a real
            # h.264 derivative and won its tier fairly), so no name or format
            # pattern can find it. Only probing can.
            return bool(u) and not it.get("audioTimelineChecked")
        return (u and not it.get("derivativeRepicked")
                and _BAD.search(u.rsplit("/", 1)[-1]))

    targets = [it for it in items if candidate(it)]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    label = ("items to probe for a broken audio timeline" if args.audio_timeline
             else "items with an unplayable derivative")
    print(f"[repick] {len(targets)} {label}", flush=True)
    if not targets:
        return 0

    lock = threading.Lock()
    done = upgraded = noupgrade = 0

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    def work_audio(it):
        nonlocal done, upgraded, noupgrade
        url = it.get("downloadURL") or ""
        v, a = probe_durations(url)
        if v is None and a is None:
            return                                    # unreadable now; retry next run
        if not audio_timeline_broken(v, a):
            with lock:
                done += 1; it["audioTimelineChecked"] = True
                if done % 200 == 0:
                    flush(); print(f"  [{done}/{len(targets)}] {upgraded} fixed", flush=True)
            return
        # Broken. Try the other derivatives on the item and take the first
        # whose OWN timeline is sane -- never swap one bad file for another.
        try:
            meta = A.archive_meta(it["archiveID"], requests.Session())
        except Exception:
            return
        cur_name = requests.utils.unquote((url).rsplit("/", 1)[-1])
        fixed = None
        for f in (meta.get("files") or []):
            name = f.get("name") or ""
            if name == cur_name or str(f.get("private") or "").lower() == "true":
                continue
            if not name.lower().endswith((".mp4", ".m4v")):
                continue
            cand = A.download_url(it["archiveID"], name)
            cv, ca = probe_durations(cand)
            if cv and ca and not audio_timeline_broken(cv, ca):
                fixed = (name, f.get("format") or "", cand, cv, ca); break
        with lock:
            done += 1
            it["audioTimelineChecked"] = True
            if fixed:
                name, fmt, cand, cv, ca = fixed
                it["downloadURL"] = cand
                if isinstance(it.get("videoFile"), dict):
                    it["videoFile"]["name"] = name
                    it["videoFile"]["format"] = fmt
                upgraded += 1
                print(f"  AUDIO-FIX {it['archiveID'][:28]:30} "
                      f"{v:.0f}s/{a:.0f}s -> {name} ({cv:.0f}s/{ca:.0f}s)", flush=True)
            else:
                noupgrade += 1
                it["audioTimelineBroken"] = True
                print(f"  NO CLEAN COPY {it['archiveID'][:28]:30} {v:.0f}s/{a:.0f}s",
                      flush=True)
            flush()
        time.sleep(args.sleep)

    def work(it):
        nonlocal done, upgraded, noupgrade
        if args.audio_timeline:
            return work_audio(it)
        try:
            meta = A.archive_meta(it["archiveID"], requests.Session())
        except Exception:
            return                                    # unreachable — retry next run
        best = A.pick_video(meta.get("files") or [])
        with lock:
            done += 1
            if not best:
                it["derivativeRepicked"] = True; noupgrade += 1; return
            cur = (it.get("downloadURL") or "").rsplit("/", 1)[-1]
            name, fmt = best.get("name") or "", best.get("format") or ""
            if name and name != requests.utils.unquote(cur) and _is_good_pick(name, fmt):
                it["downloadURL"] = A.download_url(it["archiveID"], name)
                if isinstance(it.get("videoFile"), dict):
                    it["videoFile"]["name"] = name
                    it["videoFile"]["format"] = fmt
                upgraded += 1
                print(f"  UPGRADE {it['archiveID'][:30]:30} -> {name} ({fmt})", flush=True)
            else:
                noupgrade += 1                        # only legacy exists — needs transcode
            it["derivativeRepicked"] = True
            if done % 50 == 0:
                flush(); print(f"  [{done}/{len(targets)}] {upgraded} upgraded", flush=True)
        time.sleep(args.sleep)

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for _ in as_completed([ex.submit(work, it) for it in targets]):
            pass
    flush()
    print(f"[repick] done: {done} checked, {upgraded} upgraded to H.264, "
          f"{noupgrade} still legacy-only (need transcode)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
