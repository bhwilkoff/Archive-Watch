#!/usr/bin/env python3
"""What captions does a viewer actually get, per Apple platform, per film?

The app has three caption tiers and they are NOT equally available:

    1. PUBLISHED subtitle files (uploader/SubDL/SubSource/OpenSubtitles) —
       every platform, every OS version, via the native subtitle menu.
    2. On-device live transcription (SpeechAnalyzer, 26+) — iOS/macOS ONLY;
       tvOS ships the API but no speech models (Decision 060).
    3. System-generated subtitles (27+) — all four platforms, but only for a
       film played on a PLAIN url (Decision 067) and only when the system does
       not decline the audio (Decision 063).

Coverage claims about "subtitles" that ignore the platform axis are therefore
wrong for someone: a film that is captioned on an iPhone can be blank on the
same person's Apple TV. This measures the real matrix from the live catalog so
the number quoted for each platform is the number that platform actually has.

Read-only: fetches the catalog, never publishes, takes no lock.

Usage:
    python tools/catalog_release.py fetch     # if no local catalog.json
    python tools/audit_caption_tiers.py [--json out.json]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SOUND_ERA = 1930   # matches auto_captions.py — before this a film is overwhelmingly silent


def classify(it: dict) -> str | None:
    """One bucket per visible, playable film. None = not a caption subject."""
    if it.get("excluded") or not it.get("downloadURL"):
        return None
    if it.get("contentType") == "tv-series":     # cards aren't playable; episodes are items
        return None
    if it.get("captions") or it.get("subtitleHLS"):
        return "published"
    if (it.get("isSilentFilm") or it.get("contentType") == "silent-film"
            or (it.get("year") is not None and it["year"] < SOUND_ERA)):
        # A silent film with no track is CORRECT: no tier should ever caption
        # it — fabricated dialogue is the worst outcome available (039b).
        return "silent"
    return "bare"   # sound-era, no track: the generated/transcription candidates


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", help="also write the matrix as JSON")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("no catalog.json — run: python tools/catalog_release.py fetch", file=sys.stderr)
        return 2

    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = data["items"] if isinstance(data, dict) else data

    counts = {"published": 0, "silent": 0, "bare": 0}
    langs: dict[str, int] = {}
    for it in items:
        bucket = classify(it)
        if bucket is None:
            continue
        counts[bucket] += 1
        if bucket == "published":
            for c in it.get("captions") or []:
                lang = c.get("lang") or "?"
                langs[lang] = langs.get(lang, 0) + 1

    total = sum(counts.values())
    sound = total - counts["silent"]

    def pct(n, d=None):
        d = d or total
        return f"{100 * n / d:.1f}%" if d else "—"

    print(f"Visible playable films: {total:,}  "
          f"(sound-era {sound:,}, silent {counts['silent']:,})\n")
    print(f"  published subtitle file : {counts['published']:>7,}  "
          f"({pct(counts['published'])} of all, {pct(counts['published'], sound)} of sound-era)")
    print(f"  bare (sound, no track)  : {counts['bare']:>7,}  "
          f"({pct(counts['bare'])}) — the generated-subtitles population")
    print(f"  silent (correctly none) : {counts['silent']:>7,}  ({pct(counts['silent'])})")
    if langs:
        top = sorted(langs.items(), key=lambda kv: -kv[1])[:8]
        print("  published languages     : "
              + ", ".join(f"{l}={n:,}" for l, n in top))

    # The matrix a viewer actually experiences. "generated*" because the
    # system declines audio it cannot hear well — the ceiling, not a promise.
    published, bare = counts["published"], counts["bare"]
    print(f"""
What a sound-era film shows, by platform and OS ({sound:,} films):

  platform / OS        published({published:,})   bare({bare:,})
  tvOS 26              native menu       NOTHING (no speech models, D060)
  tvOS 27              native menu       generated* (plain-url path, D067)
  iOS/iPadOS 26        native menu       live transcription overlay
  iOS/iPadOS 27        native menu       generated*, else live transcription
  macOS 26             native menu       live transcription overlay
  macOS 27             native menu       generated*, else live transcription

  * offered by the system only when it does not decline the audio (D063);
    published files are additionally JUDGED against the audio and shifted or
    replaced when wrong (D062).
""")

    if args.json:
        Path(args.json).write_text(json.dumps(
            {"total": total, "sound": sound, **counts, "languages": langs},
            indent=2), encoding="utf-8")
        print(f"matrix -> {args.json}")

    # The audit's actionable line: the bare population is what Decision 067
    # newly serves on 27, and what the free-subtitle harvest keeps shrinking.
    print(f"[caption-tiers] published={published} bare={bare} silent={counts['silent']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
