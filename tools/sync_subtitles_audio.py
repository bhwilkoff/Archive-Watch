#!/usr/bin/env python3
"""Re-time provably-mistimed subtitle files against the film's own audio.

The second half of Decision 080. `audit_subtitle_rate.py` proves a file is
mistimed (its last cue ends after the film does) and `fix_subtitle_rate.py`
repairs the telecine subset arithmetically. Everything else — a file that
overruns by an amount no single ratio explains, or one whose end credits hide
the ratio (Earth vs. the Flying Saucers itself reads 1.0366, not 1.0427) —
needs the actual audio, and that is what ffsubsync is for: it aligns the cue
timeline against voice activity, so it recovers BOTH a constant offset and a
framerate scale in one pass.

Unlike Decision 064's sweep this needs NO speech models — ffsubsync is VAD,
not recognition — so it can run on a hosted runner. What it costs is the
audio, and the design keeps that cheap and safe on a full disk:

  * ffmpeg reads the MP4 over HTTP and writes ONLY an 8kHz mono WAV
    (~30 MB/hour instead of a ~500 MB download kept on disk),
  * exactly one film is on disk at a time and it is deleted immediately,
  * popularity-first and resumable via a verdicts JSONL, like every other
    sweep here.

Nothing is trusted blind. A correction is written only when the result still
has every cue, stays monotonic, starts at or after zero, and now ends INSIDE
the runtime — the same physics gate that governs the arithmetic path. A file
ffsubsync cannot improve is left exactly as published.

Usage:
  gh release download subtitle-assets -p subs.tar.gz -O subs.tar.gz
  mkdir -p work && tar xzf subs.tar.gz -C work
  python3 tools/sync_subtitles_audio.py --subs work/subs \
      --findings tools/subtitle_rate_findings.csv --verdicts verdicts.jsonl [--limit N]
  python3 tools/fix_subtitle_sync.py publish --subs work/subs
"""
import argparse, csv, json, os, re, shutil, subprocess, sqlite3, tempfile
from pathlib import Path

CUE_END = re.compile(r"-->\s*(\d+):(\d\d):(\d\d)[.,](\d\d\d)")
CUE_START = re.compile(r"(?m)^(\d+):(\d\d):(\d\d)[.,](\d\d\d)\s*-->")

MAX_END_RATIO = 1.005      # must now land inside the film
MIN_END_RATIO = 0.50       # a file ending before half the runtime is a wrong file


def secs(groups):
    h, m, s, ms = (int(x) for x in groups)
    return h * 3600 + m * 60 + s + ms / 1000


def cue_bounds(text):
    ends = [secs(g) for g in CUE_END.findall(text)]
    starts = [secs(g) for g in CUE_START.findall(text)]
    return starts, ends


def extract_audio(url, wav_path, timeout):
    """Pull ONLY the audio, decoded to the 8kHz mono WAV ffsubsync wants.

    ffmpeg range-reads the remote MP4, so the film is never stored. `-vn`
    drops video before it is decoded, which is where the time would go.
    """
    cmd = ["ffmpeg", "-v", "error", "-y",
           "-user_agent", "ArchiveWatch-pipeline (subtitle sync)",
           "-i", url, "-vn", "-ac", "1", "-ar", "8000", "-f", "wav", str(wav_path)]
    subprocess.run(cmd, check=True, timeout=timeout,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def validate(original_text, new_text, runtime):
    o_starts, o_ends = cue_bounds(original_text)
    n_starts, n_ends = cue_bounds(new_text)
    if len(n_ends) != len(o_ends):
        return f"cue count changed ({len(o_ends)} -> {len(n_ends)})"
    if not n_ends:
        return "no cues"
    if n_starts and n_starts[0] < -0.001:
        return "starts before zero"
    if any(b < a - 0.001 for a, b in zip(n_starts, n_starts[1:])):
        return "non-monotonic"
    end = max(n_ends)
    if end > runtime * MAX_END_RATIO:
        return f"still overruns ({end:.0f}s vs {runtime}s)"
    if end < runtime * MIN_END_RATIO:
        return f"ends far too early ({end:.0f}s vs {runtime}s)"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--subs", required=True)
    ap.add_argument("--findings", default="tools/subtitle_rate_findings.csv")
    ap.add_argument("--verdicts", default="subtitle_audio_verdicts.jsonl")
    ap.add_argument("--db", default="/tmp/catalog.sqlite",
                    help="published catalog DB, for each film's downloadURL")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--audio-timeout", type=int, default=900)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    subs = Path(args.subs)
    done = set()
    if os.path.exists(args.verdicts):
        for line in open(args.verdicts):
            try:
                done.add(json.loads(line)["id"])
            except Exception:
                pass

    rows = [r for r in csv.DictReader(open(args.findings))
            if r["verdict"] == "overruns" and r["archiveID"] not in done]
    rows.sort(key=lambda r: -float(r.get("pop") or 0))
    if args.limit:
        rows = rows[: args.limit]

    db = sqlite3.connect(args.db)
    urls = dict(db.execute(
        "SELECT archiveID, json_extract(json,'$.downloadURL') FROM item_json"))

    print(f"{len(rows)} to sync ({len(done)} already decided)", flush=True)
    fixed = failed = rejected = 0

    for r in rows:
        aid, runtime = r["archiveID"], int(r["runtime"])
        vtt = subs / aid / "en.vtt"
        url = urls.get(aid)
        if not vtt.is_file() or not url:
            print(f"  SKIP {aid}: missing {'vtt' if not vtt.is_file() else 'url'}", flush=True)
            continue

        original = vtt.read_text(encoding="utf-8", errors="replace")
        with tempfile.TemporaryDirectory() as tmp:
            wav = Path(tmp) / "a.wav"
            out = Path(tmp) / "out.vtt"
            try:
                extract_audio(url, wav, args.audio_timeout)
            except subprocess.TimeoutExpired:
                print(f"  AUDIO-TIMEOUT {aid}", flush=True)
                failed += 1
                continue
            except subprocess.CalledProcessError as e:
                msg = (e.stderr or b"").decode()[-120:].replace("\n", " ")
                print(f"  AUDIO-FAIL {aid}: {msg}", flush=True)
                failed += 1
                continue
            try:
                subprocess.run(["ffsubsync", str(wav), "-i", str(vtt), "-o", str(out)],
                               check=True, timeout=600,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                print(f"  SYNC-FAIL {aid}: {type(e).__name__}", flush=True)
                failed += 1
                continue
            new_text = out.read_text(encoding="utf-8", errors="replace")

        problem = validate(original, new_text, runtime)
        verdict = {"id": aid, "runtime": runtime,
                   "before": float(r["lastCue"]),
                   "after": max(cue_bounds(new_text)[1] or [0])}
        if problem:
            verdict["result"] = "rejected"
            verdict["reason"] = problem
            print(f"  REJECT {aid[:42]:42} {problem}", flush=True)
            rejected += 1
        else:
            verdict["result"] = "fixed"
            print(f"  FIX    {aid[:42]:42} ends {verdict['before']:.0f}s -> "
                  f"{verdict['after']:.0f}s (runtime {runtime}s)", flush=True)
            if not args.dry_run:
                vtt.write_text(new_text, encoding="utf-8")
            fixed += 1
        if not args.dry_run:
            with open(args.verdicts, "a") as f:
                f.write(json.dumps(verdict) + "\n")

    print(f"\nfixed {fixed} | rejected {rejected} | failed {failed}")
    if fixed and not args.dry_run:
        print(f"publish with: python3 tools/fix_subtitle_sync.py publish --subs {subs}")


if __name__ == "__main__":
    main()
