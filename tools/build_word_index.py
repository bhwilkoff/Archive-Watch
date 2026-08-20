#!/usr/bin/env python3
"""build_word_index.py — forced-aligned WORD index for the Sentence Supercut (#9 Phase B).

Aligns each captioned film's KNOWN caption text to its audio (torchaudio MMS forced aligner,
wav2vec2 — runs on plain Linux, no Apple) to get exact per-word timestamps, and writes a `words`
table into subtitle.sqlite. The macOS composer then gets INSTANT, frame-accurate word boundaries
without a per-clip on-device speech pass.

Forced ALIGNMENT is NOT transcription: it places the words we ALREADY hold in time, so it cannot
hallucinate (Decision-039b stays satisfied — that retired *transcription* of unknown audio).

Per film: download the audio ONCE (ffmpeg → 16 kHz mono), then slice + align each cue. Resumable
(a `wordsAligned` marker per film), popularity-first.

  pip install torchaudio soundfile
  python3 tools/build_word_index.py --limit 800
"""
from __future__ import annotations
import argparse
import io
import re
import sqlite3
import subprocess
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def norm_words(text: str) -> list[str]:
    return [w for w in re.sub(r"[^a-z' ]", " ", text.lower()).split() if w]



def read_wav16k(path):
    """Load ffmpeg's 16 kHz mono wav as a torch tensor.

    NOT `torchaudio.load`. Recent torchaudio dispatches that call to
    `load_with_torchcodec`, which raises ImportError unless the separate
    `torchcodec` package is installed — and it is not here, so EVERY film failed
    at this line while the log blamed the download. soundfile is already a
    dependency, reads exactly this file, and adds no version coupling to torch.
    """
    import torch
    import soundfile
    data, _ = soundfile.read(path, dtype="float32", always_2d=True)
    return torch.from_numpy(data.T.copy())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=800, help="films to align this run")
    ap.add_argument("--db", default=str(REPO / "subtitle.sqlite"))
    ap.add_argument("--max-cues", type=int, default=2500,
                    help="skip items with more cues than this — they are "
                         "multi-hour compilations whose audio pull never lands")
    ap.add_argument("--max-minutes", type=float, default=0,
                    help="stop starting new films after this long and return "
                         "cleanly, so the CALLER still gets to publish. Without "
                         "it this job hit the 330-minute workflow timeout every "
                         "single day — 15 runs, 15 'cancelled', never once "
                         "reaching its publish step, so every day's alignment "
                         "was computed and then discarded.")
    args = ap.parse_args()

    import torch
    import torchaudio
    import numpy as np

    db = sqlite3.connect(args.db)
    db.execute("""CREATE TABLE IF NOT EXISTS words(
        archiveID TEXT, sourceURL TEXT, word TEXT, startSeconds REAL, endSeconds REAL)""")
    db.execute("CREATE INDEX IF NOT EXISTS words_aid ON words(archiveID, startSeconds)")
    db.execute("CREATE TABLE IF NOT EXISTS aligned(archiveID TEXT PRIMARY KEY)")

    bundle = torchaudio.pipelines.MMS_FA
    model = bundle.get_model()
    tokenizer = bundle.get_tokenizer()
    aligner = bundle.get_aligner()

    # Ordering by cue count DESC picks the LONGEST items first — multi-hour
    # compilations whose audio pull cannot finish, so the run burns its budget on
    # the three worst candidates and aligns nothing. Cap the cue count so the
    # queue is ordinary films.
    films = db.execute("""
        SELECT archiveID, sourceURL, count(*) c FROM cues
        WHERE archiveID NOT IN (SELECT archiveID FROM aligned)
        GROUP BY archiveID HAVING c <= ?
        ORDER BY c DESC LIMIT ?""", (args.max_cues, args.limit)).fetchall()
    films = [(a, u) for a, u, _c in films]

    # The work is already resumable per film (each commits and marks `aligned`),
    # so stopping early costs nothing — but only if the process EXITS, letting
    # the caller publish what was committed.
    deadline = (time.monotonic() + args.max_minutes * 60) if args.max_minutes else None
    stopped_early = False

    done = 0
    failed_dl = 0
    for aid, url in films:
        if deadline and time.monotonic() > deadline:
            stopped_early = True
            break
        cues = db.execute(
            "SELECT startSeconds, endSeconds, text FROM cues WHERE archiveID=? ORDER BY startSeconds",
            (aid,)).fetchall()
        # Download the whole audio once (16 kHz mono), retrying transient archive.org 5xx/node
        # weather (a fresh request load-balances to another node). A download that never succeeds
        # is NOT marked aligned, so it retries on a later run (not silently skipped forever).
        wav = None
        last_err = ""
        # A PER-FILM TIME CAP, not a smaller retry count. Retrying is right —
        # archive.org rotates storage nodes, so a fresh request often lands on a
        # healthy one (Decision 034) — but three attempts at a 900s ffmpeg
        # timeout is up to 45 minutes spent on ONE film that may never arrive,
        # out of a 240-minute budget. Measured on the 2026-08-19 run: 7 films
        # aligned, 14 downloads failed, budget exhausted at 7 of 400 selected.
        #
        # The in-run retries are also partly redundant: a film that never
        # downloads is left unaligned and picked up by a LATER run anyway. So
        # cap the total time any single film may consume and move on; the fast
        # failures (5xx answers in seconds) still get their three tries.
        film_deadline = time.monotonic() + 420
        for attempt in range(3):
            if attempt and time.monotonic() > film_deadline:
                last_err = last_err or "abandoned at the 420s per-film cap"
                break
            try:
                with tempfile.NamedTemporaryFile(suffix=".wav") as tf:
                    # A UA: archive.org answers some datacenter clients differently,
                    # and ffmpeg's default identifies nothing.
                    r = subprocess.run(
                        ["ffmpeg", "-nostdin", "-y",
                         "-user_agent", "ArchiveWatch/1.0 (+https://archivewatch.org)",
                         "-i", url, "-ac", "1", "-ar", "16000", "-vn", tf.name],
                        capture_output=True, timeout=900, check=True)
                    _ = r
                    wav = read_wav16k(tf.name)
                break
            except subprocess.CalledProcessError as e:
                # KEEP the reason. Discarding stderr is why "31 of 31 failed" sat
                # unexplained for a whole run.
                last_err = (e.stderr or b"").decode("utf-8", "replace").strip().splitlines()[-1:] or [""]
                last_err = last_err[0][:160]
                wav = None
            except subprocess.TimeoutExpired:
                last_err = "ffmpeg timed out after 900s"
                wav = None
            except Exception as e:
                last_err = f"{type(e).__name__}: {e}"[:160]
                wav = None
        if wav is None:
            # SILENT before this: three films failed here and the run reported
            # "+0 films" with no indication why, which is indistinguishable from
            # having nothing to do.
            #
            # And then it lied. Everything in this block was reported as an
            # "audio download failed", including the ImportError raised by
            # torchaudio.load() AFTER the download succeeded — which sent a whole
            # session chasing ffmpeg and archive.org while the real fault was a
            # missing Python package. Say which half failed.
            failed_dl += 1
            stage = "decode" if last_err.startswith(("ImportError", "RuntimeError")) else "download"
            print(f"[words] {aid[:44]}: audio {stage} failed — "
                  f"{last_err or 'no error captured'}", flush=True)
            continue   # transient — leave unaligned so a later run retries

        rows = []
        for s, e, text in cues:
            words = norm_words(text)
            if not words:
                continue
            a = max(0, int((s - 0.2) * 16000))
            b = min(wav.size(1), int((e + 0.3) * 16000))
            if b - a < 1600:
                continue
            seg = wav[:, a:b]
            try:
                with torch.inference_mode():
                    emission, _ = model(seg)
                spans = aligner(emission[0], tokenizer(words))
                ratio = seg.size(1) / emission.size(1) / bundle.sample_rate
                off = a / 16000.0
                for w, sp in zip(words, spans):
                    rows.append((aid, url, w, off + sp[0].start * ratio, off + sp[-1].end * ratio))
            except Exception:
                continue
        if rows:
            db.executemany("INSERT INTO words VALUES(?,?,?,?,?)", rows)
        db.execute("INSERT OR IGNORE INTO aligned VALUES(?)", (aid,))
        db.commit()
        done += 1
        if done % 10 == 0:
            print(f"[words] {done} films aligned…", flush=True)

    n = db.execute("SELECT count(*) FROM words").fetchone()[0]
    if stopped_early:
        print(f"[words] STOPPED EARLY at the {args.max_minutes:g}-minute budget "
              f"({done} of {len(films)} selected). The rest are picked up next run.")
    print(f"[words] +{done} films this run ({failed_dl} audio downloads failed); "
          f"{n} word timings total in {args.db}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
