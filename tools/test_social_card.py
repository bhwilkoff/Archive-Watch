#!/usr/bin/env python3
"""
test_social_card.py — the card renderer must always TERMINATE.

The wrap() ellipsis loop shortened its last line with rsplit(" "), which
returns the string UNCHANGED when there is no space in it. Any single word
wider than the column therefore spun forever, and the renderer hung: a
ten-day rehearsal froze on "Die Nibelungen: Siegfried" and took the daily
workflow's whole job with it. A hang is the worst failure shape here because
it looks like slow work, not like a bug.

Every case below is timed. Checked to FAIL against the pre-fix loop, which is
the only way to know a regression test works.

Run: python3 tools/test_social_card.py
"""
import signal
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image, ImageDraw                                  # noqa: E402
import social_card as C                                           # noqa: E402

CASES = [
    ("a plain title", "Night Key", 400),
    ("the film that hung", "Die Nibelungen: Siegfried", 405),
    ("one word wider than the column", "Donaudampfschiffahrtsgesellschaft", 200),
    ("a single enormous word", "A" * 200, 180),
    ("a narrow column", "The Cabinet of Dr. Caligari", 60),
    ("an absurd column", "Anything at all", 12),
    ("empty", "", 300),
    ("only spaces", "     ", 300),
    ("unicode", "Les Aventures de Robinson Crusoé — Méliès, 1902", 300),
]

class Hang(Exception):
    pass


def _alarm(_sig, _frm):
    raise Hang()


def timed(fn, *a, limit: int = 3):
    """Run with a hard ceiling. Without this the test REPRODUCES the hang
    instead of reporting it — checked against the pre-fix renderer, where the
    suite itself froze rather than printing a failure. A test that hangs is a
    test nobody can read in CI."""
    signal.signal(signal.SIGALRM, _alarm)
    signal.alarm(limit)
    try:
        return fn(*a)
    finally:
        signal.alarm(0)


def main() -> int:
    draw = ImageDraw.Draw(Image.new("RGB", (1080, 1080)))
    font = C.font("Inter-Regular.ttf", 30)
    bad = 0
    for name, text, width in CASES:
        t0 = time.time()
        try:
            lines = timed(C.wrap, draw, text, font, width, 2)
            dt = time.time() - t0
        except Hang:
            print(f"  BAD  {name}: HUNG (no return in 3s)")
            bad += 1
            continue
        except Exception as e:                                     # noqa: BLE001
            print(f"  BAD  {name}: raised {e}")
            bad += 1
            continue
        if dt > 2.0:
            print(f"  BAD  {name}: took {dt:.1f}s (a hang)")
            bad += 1
            continue
        # It must also stay inside the column it was given.
        over = [l for l in lines if draw.textlength(l, font=font) > width + 1]
        if over and width > 40:
            print(f"  BAD  {name}: line overflows the column: {over[0][:40]!r}")
            bad += 1
            continue
        print(f"  ok   {name:32s} {dt*1000:5.1f}ms  {len(lines)} line(s)")

    # fit_title walks wrap() at a dozen sizes; the same hang lives there.
    t0 = time.time()
    try:
        timed(C.fit_title, draw, "Donaudampfschiffahrtsgesellschaft", 200, 70, 40, limit=5)
        dt = time.time() - t0
        print(f"  ok   fit_title on an unbreakable word  {dt*1000:5.1f}ms")
    except Hang:
        print("  BAD  fit_title HUNG"); bad += 1

    print(f"\n{'PASS' if bad == 0 else 'FAIL'} — {len(CASES)+1 - bad}/{len(CASES)+1}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
