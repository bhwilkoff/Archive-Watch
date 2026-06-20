#!/usr/bin/env python3
"""
whisper_subtitles.py — generate English subtitles for catalog films that have NO
archive.org captions, by transcribing the film's OWN audio with whisper.cpp.

PHASE 4 of Decision 039 (the coverage backbone). archive.org auto-captions only a
slice of the catalog (~15%); the films are public domain, so we may transcribe the
rest ourselves and own the output freely (no API cap, unlike OpenSubtitles). Per
target it: picks the smallest archive.org derivative carrying audio, streams it
through ffmpeg to a 16 kHz mono WAV, runs whisper-cli (Metal-accelerated on Apple
Silicon — ~10-20x realtime with small.en), writes a WebVTT + the tiny HLS set into
`subs/<id>/` (the SAME layout build_subtitle_assets emits, so the existing
publish/deploy path serves it to every platform), and records on the item:
`captions:[{lang:en, source:"whisper", vttURL, ...}]` + `subtitleHLS`.

This is a Mac-first, resumable, popularity-first BATCH (like the cover protocol,
Decision 023/024): whisper.cpp + Metal is Apple-Silicon only, and the audio pull
is bandwidth-heavy, so it runs unattended on the owner's Mac under `caffeinate`,
not in CI. Resumable via the catalog's `captions` field + `whisper_manifest.jsonl`.

Skips: silent films (no dialogue), items already captioned, the excluded set, and
items with no audio-bearing derivative. NEVER transcribes a non-PD item (the rights
gate is upstream — excluded items are filtered out).

Setup (once):
  brew install whisper-cpp ffmpeg
  mkdir -p ~/.cache/whisper && curl -L \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin \
    -o ~/.cache/whisper/ggml-small.en.bin

Run (catalog_release.py fetch first):
  python tools/whisper_subtitles.py --limit 500 --model ~/.cache/whisper/ggml-small.en.bin
Then publish (reuses the existing path):
  tar czf subs.tar.gz subs && gh release upload subtitle-assets subs.tar.gz --clobber
  python tools/remediate_catalog.py && python tools/catalog_release.py publish
  gh workflow run deploy-pages.yml ; gh workflow run publish-db.yml
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402
from build_subtitle_assets import hls_manifests, safe_dir, PAGES_BASE, SUBS_DIR  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
MANIFEST = REPO / "tools" / "whisper_manifest.jsonl"   # resumable log (gitignored)

# Silent cinema has no dialogue to transcribe; commercials/ephemera are low value
# and noisy. Everything else with audio is fair game.
SKIP_TYPES = {"silent-film"}

# Derivative formats that carry an audio track, smallest/most-efficient first.
_AUDIO_PREF = ["VBR MP3", "MP3", "64Kbps MP3", "Ogg Vorbis", "512Kb MPEG4",
               "Ogg Video", "h.264", "MPEG4", "MPEG2"]


def pick_audio_file(meta):
    """Return the archive.org filename of the smallest derivative with audio."""
    files = meta.get("files") or []
    cand = []
    for f in files:
        fmt = f.get("format", "")
        if fmt in _AUDIO_PREF:
            try:
                size = int(f.get("size") or 0)
            except ValueError:
                size = 0
            # rank by format preference, then size (smallest wins)
            cand.append((_AUDIO_PREF.index(fmt), size or 1 << 60, f["name"]))
    if not cand:
        return None
    cand.sort()
    return cand[0][2]


# whisper.cpp non-speech markers that must never reach the screen.
_NONSPEECH = re.compile(r"^\[[A-Z_ ]+\]$")        # [BLANK_AUDIO], [MUSIC], [SILENCE]


def clean_vtt(vtt: str) -> tuple[str, int]:
    """Normalize whisper.cpp VTT for our HLS path and return (vtt, real_cue_count).
    whisper emits a bare 'WEBVTT' header (AVPlayer's HLS needs X-TIMESTAMP-MAP),
    a leading space on each cue line, and `[BLANK_AUDIO]`/`[MUSIC]` cues during
    silence — drop those whole cues so nothing but speech is shown."""
    body = vtt.replace("\r\n", "\n").strip()
    if body.startswith("WEBVTT"):
        body = body[len("WEBVTT"):].lstrip("\n")
    out, real = [], 0
    for block in body.split("\n\n"):
        lines = [ln.strip() for ln in block.split("\n") if ln.strip()]
        if not lines:
            continue
        ts = next((i for i, ln in enumerate(lines) if "-->" in ln), None)
        if ts is None:
            continue
        text = [ln for ln in lines[ts + 1:] if not _NONSPEECH.match(ln)]
        if not text:                              # silence-only cue → drop
            continue
        out.append(lines[ts] + "\n" + "\n".join(text))
        real += 1
    vtt = "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n\n" + "\n\n".join(out) + "\n"
    return vtt, real


def transcribe(item, model, session, keep_wav=False) -> str:
    """Generate subs/<id>/ for one item. Returns a status string."""
    iaid = item["archiveID"]
    try:
        meta = A.archive_meta(iaid, session)
    except Exception:
        return "unreachable"
    fname = pick_audio_file(meta)
    if not fname:
        return "no-audio"
    audio_url = A.download_url(iaid, fname)

    sid = safe_dir(iaid)
    out = SUBS_DIR / sid
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "a.wav"
        # Stream-transcode just the audio to 16 kHz mono (whisper's native input);
        # ffmpeg pulls only what it needs from the remote progressive file.
        ff = subprocess.run(
            ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
             "-i", audio_url, "-vn", "-ac", "1", "-ar", "16000",
             "-c:a", "pcm_s16le", str(wav), "-y"],
            capture_output=True, text=True, timeout=2400)
        if ff.returncode != 0 or not wav.exists() or wav.stat().st_size < 32000:
            return "audio-fail"
        stem = Path(td) / "out"
        wh = subprocess.run(
            ["whisper-cli", "-m", model, "-f", str(wav), "-ovtt",
             "-of", str(stem), "--language", "en", "--no-prints"],
            capture_output=True, text=True, timeout=7200)
        vtt_path = stem.with_suffix(".vtt")
        if wh.returncode != 0 or not vtt_path.exists():
            return "whisper-fail"
        raw = vtt_path.read_text(encoding="utf-8")
        if keep_wav:
            (out).mkdir(parents=True, exist_ok=True)
            (out / "_debug.wav").write_bytes(wav.read_bytes())

    vtt, cues = clean_vtt(raw)
    if cues < 3:                                  # near-silent / non-speech only
        return "empty"

    out.mkdir(parents=True, exist_ok=True)
    (out / "en.vtt").write_text(vtt, encoding="utf-8")
    base = f"{PAGES_BASE}/{sid}"
    langs = [("en", "English (auto)", "en.vtt")]
    master, video, subs = hls_manifests(item["downloadURL"], item.get("runtimeSeconds") or 0, langs)
    (out / "master.m3u8").write_text(master, encoding="utf-8")
    (out / "video.m3u8").write_text(video, encoding="utf-8")
    (out / "subs.en.m3u8").write_text(subs["en"], encoding="utf-8")

    vtt_url = f"{base}/en.vtt"
    item["captions"] = [{"lang": "en", "label": "English (auto)", "format": "vtt",
                         "url": vtt_url, "vttURL": vtt_url, "source": "whisper"}]
    item["subtitleHLS"] = f"{base}/master.m3u8"
    item["captionsChecked"] = True
    item["whisperGenerated"] = True
    return f"built_{cues}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--model", default=os.path.expanduser("~/.cache/whisper/ggml-small.en.bin"))
    ap.add_argument("--min-pop", type=int, default=0, help="only items at/above this popularityScore")
    ap.add_argument("--types", default="", help="comma-list to restrict contentType (default: all non-silent)")
    ap.add_argument("--probe", help="transcribe one archiveID, keep the wav, write nothing to catalog")
    args = ap.parse_args()

    if not Path(args.model).exists():
        print(f"[whisper] model not found: {args.model}\n  download ggml-small.en.bin (see header)")
        return 2
    if not CATALOG.exists():
        print("[whisper] no catalog.json (catalog_release.py fetch first)")
        return 2

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    session = requests.Session()

    if args.probe:
        it = next((i for i in items if i["archiveID"] == args.probe), None)
        if not it:
            print("not found"); return 1
        print(transcribe(it, args.model, session, keep_wav=True))
        print("subtitleHLS:", it.get("subtitleHLS"))
        return 0

    only = {t.strip() for t in args.types.split(",") if t.strip()}

    def candidate(it):
        if not it.get("downloadURL") or it.get("excluded"):
            return False
        if it.get("captions"):                    # already captioned (any source)
            return False
        ct = it.get("contentType")
        if ct in SKIP_TYPES or ct == "tv-series":
            return False
        if only and ct not in only:
            return False
        if (it.get("popularityScore") or 0) < args.min_pop:
            return False
        return True

    targets = [it for it in items if candidate(it)]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[whisper] {len(targets)} films to transcribe (model {Path(args.model).name})", flush=True)

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    from collections import Counter
    tally = Counter()
    mf = open(MANIFEST, "a")
    for n, it in enumerate(targets, 1):
        status = transcribe(it, args.model, session)
        key = status.split("_")[0]
        tally[key] += 1
        mf.write(json.dumps({"id": it["archiveID"], "status": status}) + "\n"); mf.flush()
        if status.startswith("built"):
            print(f"[{n}/{len(targets)}] {it['archiveID']}: {status}", flush=True)
        if n % 25 == 0 or n == len(targets):
            flush()
            print(f"[{n}/{len(targets)}] {dict(tally)}", flush=True)
    flush()
    print(f"[whisper] done: {dict(tally)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
