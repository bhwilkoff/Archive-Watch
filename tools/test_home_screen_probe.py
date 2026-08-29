#!/usr/bin/env python3
"""Guard for the guard: does frame_is_home_screen() actually detect anything?

It returned False for EVERY frame from the day it was ported until 2026-08-29,
so the foreground check it exists to perform never ran once — and nothing
noticed, because "not the home screen" is the answer a working probe gives
most of the time. A silent always-False is the worst failure a detector can
have: the harness keeps grading, and grades the wrong screen.

    python3 tools/test_home_screen_probe.py
"""
import json
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
import atv_scenario as A  # noqa: E402


def _fake_ocr(entries):
    """Stand in for the OCR binary, emitting ScreenOCR's REAL shape."""
    payload = json.dumps({"file": "x.png", "captionRegion": [], "allText": entries})
    return lambda *a, **k: SimpleNamespace(stdout=payload + "\n", stderr="", returncode=0)


def main():
    fails = []

    def check(name, entries, expect):
        A.sh = _fake_ocr(entries)
        got = A.frame_is_home_screen(Path("x.png"))
        ok = got is expect
        print(f"  {'PASS' if ok else 'FAIL'} {name} — expected {expect}, got {got}")
        if not ok:
            fails.append(name)

    # ScreenOCR emits DICTS. This is the shape that broke it: the port assumed
    # a list of strings, joined the dicts, raised TypeError, and swallowed it.
    home = [{"text": "Prime Video", "x": 0.1, "y": 0.5, "w": 0.1, "h": 0.02},
            {"text": "9:41 PM", "x": 0.8, "y": 0.9, "w": 0.05, "h": 0.02}]
    app = [{"text": "His Girl Friday", "x": 0.1, "y": 0.5, "w": 0.2, "h": 0.03},
           {"text": "Resume · 88 min", "x": 0.1, "y": 0.4, "w": 0.2, "h": 0.02}]

    check("tvOS home screen (dict entries)", home, True)
    check("the app's own Detail screen", app, False)
    # A plain list of strings is what the broken branch was reaching for; accept
    # it rather than crash, so a future OCR change degrades instead of lying.
    check("plain-string entries", ["Pluto TV", "9:41 PM"], True)
    check("empty frame", [], False)

    print("\nALL PASS" if not fails else f"\nFAILED: {', '.join(fails)}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
