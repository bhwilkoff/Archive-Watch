#!/usr/bin/env python3
"""The tvOS floor stays below 27 (Decision 148).

tvOS 27 dropped the Apple TV HD (2015) and Apple TV 4K 1st gen (2017); both
run tvOS 26. Every tvOS deployment target in the project must stay on 26.x, or
those boxes silently stop receiving the app.
"""
import re, sys
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "ArchiveWatch/ArchiveWatch.xcodeproj/project.pbxproj"

def floors(text):
    return [float(m) for m in re.findall(r"TVOS_DEPLOYMENT_TARGET = ([0-9.]+);", text)]

def ok(values):
    return bool(values) and all(v < 27 for v in values)

found = floors(PBX.read_text())
fails = 0
def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name); fails += not cond
check(f"every tvOS target is below 27 ({sorted(set(found))})", ok(found))
check("control: a 27.0 target is refused", not ok(floors("TVOS_DEPLOYMENT_TARGET = 26.0;\nTVOS_DEPLOYMENT_TARGET = 27.0;")))
check("control: no target at all is refused", not ok(floors("")))
sys.exit(1 if fails else 0)
