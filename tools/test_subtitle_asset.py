#!/usr/bin/env python3
"""
test_subtitle_asset.py — the published VTT path is resolved from what the item
RECORDS, never from an assumed language.

THE INCIDENT (2026-09-11). Two auditors derived the path as the HLS master's
directory plus `/en.vtt`. `build_subtitle_assets.py` names the file after the
track's LANGUAGE, so for a zh/de/it track that asked for something never
written. `audit_dead_subtitles` read the 404 as a definitive death and cleared
`subtitleHLS` on 35 HEALTHY films — they kept captions on the web, which reads
the caption's own vttURL, and lost them in every app. `audit_subtitle_rate`
made the same guess and silently skipped every non-English track.

The FIRST case is the negative control: the ordinary English item must still
resolve to its own recorded URL, or a "fix" here would move every path in the
catalog.

Run:  python3 tools/test_subtitle_asset.py
"""

from __future__ import annotations

import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

from subtitle_asset import published_vtt_url  # noqa: E402

CASES = []
HLS = "https://archivewatch.org/subs/film/master.m3u8"


def check(name, got, want):
    CASES.append((name, got == want, got, want))


def main() -> int:
    # 1. CONTROL: an ordinary English item resolves to its recorded URL
    check("control: an English caption's own vttURL is used",
          published_vtt_url({"subtitleHLS": HLS, "captions": [
              {"lang": "en", "vttURL": "https://archivewatch.org/subs/film/en.vtt"}]}),
          "https://archivewatch.org/subs/film/en.vtt")

    # 2. THE INCIDENT: a non-English track resolves to ITS file, not en.vtt
    check("a zh track resolves to zh.vtt, never en.vtt",
          published_vtt_url({"subtitleHLS": HLS, "captions": [
              {"lang": "zh", "vttURL": "https://archivewatch.org/subs/film/zh.vtt"}]}),
          "https://archivewatch.org/subs/film/zh.vtt")

    # 3. no recorded URL: fall back on the LANGUAGE, which is how the files are named
    check("with no vttURL, the language names the sibling file",
          published_vtt_url({"subtitleHLS": HLS, "captions": [{"lang": "de"}]}),
          "https://archivewatch.org/subs/film/de.vtt")

    # 4. English is preferred when several tracks exist — the judge (Decision
    #    062) compares cue text against English audio.
    check("English wins over another language when both are published",
          published_vtt_url({"subtitleHLS": HLS, "captions": [
              {"lang": "fr", "vttURL": "https://archivewatch.org/subs/film/fr.vtt"},
              {"lang": "en", "vttURL": "https://archivewatch.org/subs/film/en.vtt"}]}),
          "https://archivewatch.org/subs/film/en.vtt")

    # 5. nothing recorded at all — en.vtt is the last resort, not the first guess
    check("an item with no captions falls back to en.vtt",
          published_vtt_url({"subtitleHLS": HLS}),
          "https://archivewatch.org/subs/film/en.vtt")

    # 6. no track at all is None, never a URL that cannot exist
    check("an item with no subtitleHLS resolves to nothing",
          published_vtt_url({"captions": [{"lang": "en", "vttURL": "x"}]}), None)

    # 7. "eng" counts as English (the catalog carries both spellings)
    check("a three-letter English code is still English",
          published_vtt_url({"subtitleHLS": HLS, "captions": [
              {"lang": "it", "vttURL": "https://archivewatch.org/subs/film/it.vtt"},
              {"lang": "eng", "vttURL": "https://archivewatch.org/subs/film/eng.vtt"}]}),
          "https://archivewatch.org/subs/film/eng.vtt")

    bad = 0
    for name, ok, got, want in CASES:
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            bad += 1
            print(f"      got:  {got!r}\n      want: {want!r}")
    print(f"\n{len(CASES) - bad}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
