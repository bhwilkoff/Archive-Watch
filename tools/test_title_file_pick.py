#!/usr/bin/env python3
"""pick_video plays the file named for the title in a multi-work item (archive_lib.title_files)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A

def f(name, size, src="original", fmt="MPEG4"):
    return {"name": name, "size": str(size), "source": src, "format": fmt}

felix = [f("April Maze (1930).mp4", 10), f("Felix Finds Out (1924).mp4", 90),
         f("April Maze (1930).ogv", 9, "derivative", "Ogg Video")]
one = [f("nosferatu_512kb.mp4", 50, "derivative", "512Kb MPEG4"), f("Nosferatu.mp4", 900, "original", "MPEG4")]
foreign = [f("Brzdac (1921).mp4", 10), f("Brzdac (1921).ogv", 9, "derivative", "Ogg Video")]
cases = [
    ("multi-work item plays the title's file", A.pick_video(felix, "April Maze")["name"], "April Maze (1930).mp4"),
    ("a year in the title does not block the match", A.pick_video(felix, "April Maze (1930)")["name"], "April Maze (1930).mp4"),
    ("CONTROL: no title keeps largest-wins", A.pick_video(felix)["name"], "Felix Finds Out (1924).mp4"),
    ("CONTROL: one work keeps the tier ranking", A.pick_video(one, "Nosferatu")["name"], "nosferatu_512kb.mp4"),
    ("CONTROL: no file named for the title falls back", A.pick_video(foreign, "The Kid")["name"], "Brzdac (1921).mp4"),
    ("CONTROL: a short title never matches by containment", len(A.title_files(felix, "Ma")), 0),
]
fails = 0
for name, got, want in cases:
    ok = got == want
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f" (got {got!r})"))
print(f"{len(cases) - fails}/{len(cases)}")
sys.exit(1 if fails else 0)
