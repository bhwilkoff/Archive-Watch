#!/usr/bin/env python3
"""
test_captioned_asset_shape.py — no Apple player may build a whole-film HLS
segment for a STREAMING title.

A single-segment HLS playlist (`#EXTINF:<whole duration>`) makes the entire
film AVFoundation's atomic buffering unit, so `preferredForwardBufferDuration`
is ignored and the whole MP4 comes into memory. Decision 070 measured that on
Apple TV and fixed tvOS; iOS and macOS kept the wrapper for another month, and
a viewer on a phone found it — The Grapes of Wrath, 2.19 GB, "plays for about
five minutes and then stops".

The MEASUREMENT lives in tools/test_captioned_buffer_growth.swift, which plays
both shapes and reads the buffer. This is the cheap network-free guard that
stops the shape coming back: the two loaders that serve such a playlist may be
referenced by nothing but their own file.

Run: python3 tools/test_captioned_asset_shape.py   (exit 0 = pass)
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "ArchiveWatch" / "ArchiveWatch"

# The loaders whose playlists declare one segment for the whole film.
WHOLE_FILM_LOADERS = ("CaptionedHLSLoader", "LocalSubtitleHLSLoader")

fails = []


def check(ok, what, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {what}" + (f"  — {detail}" if detail and not ok else ""))
    if not ok:
        fails.append(what)


def strip_comments(src: str) -> str:
    """A rule that counted its own explanation would pass forever. The comments
    above these branches NAME the loaders they replaced, on purpose."""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in src.splitlines())


players = sorted(p for p in APP.rglob("*.swift")
                 if p.name in {"PlayerView_iOS.swift", "PlayerWindow_macOS.swift",
                               "AVPlayerScreen.swift", "DetailView.swift"})
check(len(players) >= 3, "the player sources are where this expects them",
      f"found {[p.name for p in players]}")

for p in players:
    body = strip_comments(p.read_text())
    for loader in WHOLE_FILM_LOADERS:
        check(loader not in body,
              f"{p.name} builds no {loader} asset",
              f"still references {loader}")

# The negative control: the guard has to be able to SEE the thing it forbids,
# or it passes because its search is broken rather than because the code is
# clean. Assert it fires on a source that does use one.
planted = strip_comments("let (a, l) = CaptionedHLSLoader.makeAsset(hls: h, downloadURL: m)")
check(any(l in planted for l in WHOLE_FILM_LOADERS),
      "the guard detects a wrapper it is shown (negative control)")
# ...and that a mention in a COMMENT does not trip it.
commented = strip_comments("// replaced the CaptionedHLSLoader wrapper (Decision 118)")
check(not any(l in commented for l in WHOLE_FILM_LOADERS),
      "...and a comment naming the wrapper does not trip it")

# The overlay renderer the cues moved to must exist and take a parsed body.
offline = (APP / "Services" / "OfflineSubtitles.swift").read_text()
check("init?(vtt body: String)" in offline,
      "OfflineSubtitles parses a WebVTT body from anywhere")
check("static func published(" in offline,
      "...and fetches a published one")

print(f"\n{len(fails)} failed" if fails else "\nall passed")
sys.exit(1 if fails else 0)
