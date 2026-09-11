#!/usr/bin/env python3
"""
test_dead_caption_urls.py — a dead subtitle leaves no published URL behind.

THE DEFECT (measured 2026-09-11). `audit_dead_subtitles` probes published
tracks and on a 404 removes `subtitleHLS`, so the Apple apps stop offering a
caption that cannot load. It strips caption ENTRIES only when their source is
None/"published" — so a `subdl` or `archive` entry survives carrying the
`vttURL` of the file that just 404'd, and `build_web_details` emits any
caption that has one.

Measured on the live catalog: 43 visible films — Criss Cross, Hitchcock's The
Man Who Knew Too Much, Clark Gable's The Painted Desert among them — were
advertising a subtitle menu on the web whose file 404s today, while the Apple
apps correctly showed none. The apps were never missing those captions; the
web was inventing them.

The FIRST case is the negative control: an item with a healthy published
track must keep its vttURL, or this rule would strip captions from every
film in the catalog.

Run:  python3 tools/test_dead_caption_urls.py
"""

from __future__ import annotations

import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

from remediate_catalog import clear_dead_caption_urls  # noqa: E402

CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


def cap(**kw):
    base = {"lang": "en", "label": "English", "source": "subdl",
            "url": "https://subdl.example/x.srt",
            "vttURL": "https://archivewatch.org/subs/x/en.vtt"}
    base.update(kw)
    return base


def main() -> int:
    # 1. THE CONTROL: a healthy item is untouched.
    healthy = {"archiveID": "ok", "subtitleHLS": "https://.../master.m3u8",
               "captions": [cap()]}
    check("control: a healthy item keeps its published URL",
          (clear_dead_caption_urls([healthy]), healthy["captions"][0].get("vttURL")),
          ((0, 0), "https://archivewatch.org/subs/x/en.vtt"))

    # 2. an item with no subtitleDead marker at all is untouched
    plain = {"archiveID": "p", "captions": [cap()]}
    check("control: an unmarked item is untouched", clear_dead_caption_urls([plain]), (0, 0))

    # 3. THE DEFECT: dead track, surviving subdl caption, dead vttURL
    dead = {"archiveID": "d", "subtitleDead": 404, "captions": [cap()]}
    check("a dead item's published URL is cleared", clear_dead_caption_urls([dead]), (1, 0))
    check("...and the caption SURVIVES, so it can be re-published",
          (len(dead["captions"]), dead["captions"][0].get("vttURL"),
           dead["captions"][0]["url"]),
          (1, None, "https://subdl.example/x.srt"))

    # 4. a caption with no source url left is dropped — nothing to re-fetch
    orphan = {"archiveID": "o", "subtitleDead": 410,
              "captions": [{"lang": "en", "vttURL": "https://archivewatch.org/subs/o/en.vtt"}]}
    check("a caption with no source url is dropped", clear_dead_caption_urls([orphan]), (1, 1))
    check("...and the empty captions field is removed entirely",
          "captions" in orphan, False)

    # 5. an item RE-PUBLISHED since the death is never stripped: the guard is
    #    subtitleHLS being present again.
    revived = {"archiveID": "r", "subtitleDead": 404,
               "subtitleHLS": "https://.../master.m3u8", "captions": [cap()]}
    check("a re-published item is protected by its subtitleHLS",
          (clear_dead_caption_urls([revived]), revived["captions"][0].get("vttURL")),
          ((0, 0), "https://archivewatch.org/subs/x/en.vtt"))

    # 6. every source is treated the same — the original bug was sparing some
    arch = {"archiveID": "a", "subtitleDead": 404,
            "captions": [cap(source="archive"), cap(source="subdl", lang="de")]}
    check("both archive and subdl entries lose the dead URL",
          clear_dead_caption_urls([arch]), (2, 0))

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
