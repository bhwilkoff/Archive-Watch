#!/usr/bin/env python3
"""
social_hear.py — does the audio at this moment actually say these words?

The reason this exists: the teaser burns a line of dialogue on screen and cuts
to the moment the subtitle file says it is spoken. That file is very often
wrong. This catalog's subtitles are largely machine transcription of optical
sound, and Decisions 062/064/080 exist because a published track can be
offset by seconds or by minutes — so "the cue at 109.3s" can name a line the
film speaks nowhere near there. The owner watched a teaser whose burned-in
caption was not what the actors were saying.

VAD is not enough here. `sync_subtitles_audio.py` uses ffsubsync, which aligns
a whole file against voice ACTIVITY — it can tell you somebody is talking, not
what they said, and "somebody is talking" is exactly what a wrong caption sits
on top of. So this recognises the words.

Decision 039b abandoned Whisper for GENERATING captions because it
hallucinates. Verifying is the opposite problem: a hallucinated transcript
simply fails to match and the teaser falls back to a shot cut. The failure
direction is safe, which is what makes the same tool appropriate here and
wrong there.

Scoring is deliberately loose about form and strict about substance: both
sides are reduced to CONTENT words (stopwords dropped — "the", "to", "you"
match everything), and the score is the fraction of the cue's content words
heard in the window. A 1940s optical track through a tiny model will not
transcribe cleanly; requiring exact words would reject every real line.

Run:
  python3 tools/social_hear.py --url <mp4> --start 109.3 --end 112.1 \
      --text "What do you say to the nice young man?"
"""
from __future__ import annotations

import sys as _sys
_sys.path.insert(0, __file__.rsplit('/', 1)[0])
from ffmpeg_limits import FFMPEG, FFPROBE  # noqa: E402

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# Words that match anything, so counting them inflates every score.
STOP = {
    "a", "an", "the", "and", "or", "but", "if", "of", "to", "in", "on", "at",
    "for", "with", "from", "by", "as", "is", "are", "was", "were", "be", "been",
    "am", "do", "does", "did", "have", "has", "had", "i", "you", "he", "she",
    "it", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his",
    "its", "our", "their", "this", "that", "these", "those", "not", "no",
    "so", "up", "out", "what", "who", "how", "why", "when", "where", "there",
    "here", "will", "would", "can", "could", "shall", "should", "may", "might",
    "just", "all", "any", "some", "one", "s", "t", "re", "ve", "ll", "d", "m",
}

PAD = 1.2          # seconds either side: a cue's stamps are approximate
MIN_CONTENT = 2    # below this there is nothing substantive to check


def words(text: str) -> list:
    return [w for w in re.findall(r"[a-z']+", (text or "").lower())]


def content(text: str) -> list:
    return [w.strip("'") for w in words(text)
            if w.strip("'") and w.strip("'") not in STOP and len(w.strip("'")) > 1]


def grab_audio(url: str, start: float, end: float, out: Path) -> bool:
    """The cue's window as 16 kHz mono WAV, read over HTTP.

    `-ss` BEFORE `-i` so ffmpeg seeks instead of decoding from the top of a
    two-hour film — the difference between a second and several minutes.
    """
    lo = max(0.0, start - PAD)
    r = subprocess.run(
        [*FFMPEG, "-y", "-nostdin", "-v", "error", "-ss", str(lo), "-i", url,
         "-t", str(max(1.0, (end - start) + 2 * PAD)),
         "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(out)],
        capture_output=True, text=True, timeout=420)
    return r.returncode == 0 and out.exists() and out.stat().st_size > 4000


_MODEL = None


def transcribe(wav: Path, model_size: str = "tiny.en") -> str:
    """Whatever the recogniser hears. Empty string when it cannot run at all —
    which the caller must treat as "unknown", never as "no match"."""
    global _MODEL
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        print("[hear] faster-whisper is not installed — cannot verify",
              file=sys.stderr)
        return ""
    if _MODEL is None:
        _MODEL = WhisperModel(model_size, device="cpu", compute_type="int8")
    segs, _ = _MODEL.transcribe(str(wav), language="en", beam_size=1,
                                condition_on_previous_text=False,
                                vad_filter=False)
    return " ".join(s.text for s in segs)


def hear(url: str, start: float, end: float, text: str,
         model_size: str = "tiny.en") -> dict:
    """Score how much of `text` is actually spoken in the window.

    Returns `score=None` when the check could not be MADE (no ffmpeg audio, no
    recogniser). None is not a failure — it means we do not know, and the
    caller decides. Conflating the two would silently disable the check the
    day a dependency goes missing.
    """
    want = content(text)
    if len(want) < MIN_CONTENT:
        return {"score": None, "heard": "", "why": "too few content words to check"}
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "cue.wav"
        if not grab_audio(url, start, end, wav):
            return {"score": None, "heard": "", "why": "could not read the audio"}
        heard = transcribe(wav, model_size)
    if not heard.strip():
        return {"score": None, "heard": "", "why": "the recogniser produced nothing"}
    got = set(content(heard))
    hits = sum(1 for w in want if w in got)
    return {"score": hits / len(want), "heard": heard.strip(),
            "why": f"{hits}/{len(want)} content words heard"}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", required=True)
    ap.add_argument("--start", type=float, required=True)
    ap.add_argument("--end", type=float, required=True)
    ap.add_argument("--text", required=True)
    ap.add_argument("--model", default="tiny.en")
    args = ap.parse_args()
    r = hear(args.url, args.start, args.end, args.text, args.model)
    print(f"want  : {args.text}")
    print(f"heard : {r['heard']}")
    print(f"score : {r['score']}  ({r['why']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
