#!/usr/bin/env python3
"""The picker must never return a file archive.org marks `private`.

Locks Decision 104. Run it, and then check it FAILS with the guard line
removed from archive_lib.pick_video — a regression test nobody has seen fail
is a test nobody knows works.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import archive_lib as A

CASES = [
    # name, files, expected picked name (None = nothing playable)
    ("the real cubanc_000437 shape — every mp4 private", [
        {"name": "cubanc_000437_access.HD.ia.mp4", "format": "h.264", "source": "derivative",
         "size": "105500090", "private": "true"},
        {"name": "cubanc_000437_access.HD.mp4", "format": "MPEG4", "source": "original",
         "size": "1473221144", "private": "true"},
    ], None),
    ("a public derivative beside a private original is still playable", [
        {"name": "film.mp4", "format": "h.264", "source": "derivative", "size": "50"},
        {"name": "master.mp4", "format": "MPEG4", "source": "original", "size": "9999",
         "private": "true"},
    ], "film.mp4"),
    ("private must not win its tier on size", [
        {"name": "big.mp4", "format": "h.264", "source": "derivative", "size": "9999",
         "private": "true"},
        {"name": "small.mp4", "format": "h.264", "source": "derivative", "size": "10"},
    ], "small.mp4"),
    ("unmarked files are untouched", [
        {"name": "a.mp4", "format": "h.264", "source": "derivative", "size": "10"},
    ], "a.mp4"),
    ("private:false is not private", [
        {"name": "a.mp4", "format": "h.264", "source": "derivative", "size": "10",
         "private": "false"},
    ], "a.mp4"),
]

fails = 0
for label, files, want in CASES:
    got = A.pick_video(files)
    name = got.get("name") if got else None
    ok = name == want
    print(f"{'PASS' if ok else 'FAIL'}  {label}\n      picked={name!r} want={want!r}")
    if not ok:
        fails += 1
print(f"\n{len(CASES) - fails}/{len(CASES)} passed")
sys.exit(1 if fails else 0)
