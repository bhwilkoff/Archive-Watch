#!/usr/bin/env python3
"""The iPhone/iPad floor stays at iOS 18 (docs/research/IOS-FLOOR.md).

iOS 26 dropped the iPhone XS, XS Max and XR; iOS 18 runs on them, and on every
phone iOS 17 does. Raising the floor above 18 would cut them off with no error
anywhere, so the app, widget and UI-test targets must stay at 18.x or lower.
(The Top Shelf target is tvOS-only; its IPHONEOS setting is not a floor.)
"""
import re, sys
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "ArchiveWatch/ArchiveWatch.xcodeproj/project.pbxproj"
IOS_BUNDLES = ("app.archivewatch.tvos", "app.archivewatch.tvos.widgets", "app.archivewatch.tvos.uitests")

def floors(text):
    out = []
    for m in re.finditer(r"isa = XCBuildConfiguration;(.*?)\n\t\t\};", text, re.S):
        body = m.group(1)
        bid = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", body)
        tgt = re.search(r"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);", body)
        if bid and tgt and bid.group(1).strip('"') in IOS_BUNDLES:
            out.append(float(tgt.group(1)))
    return out

def ok(values):
    return len(values) >= len(IOS_BUNDLES) and all(v < 19 for v in values)

found = floors(PBX.read_text())
fails = 0
def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name); fails += not cond
check(f"every iOS target is at 18.x or lower ({sorted(set(found))})", ok(found))
cfg = lambda b, t: f"isa = XCBuildConfiguration;\n PRODUCT_BUNDLE_IDENTIFIER = {b};\n IPHONEOS_DEPLOYMENT_TARGET = {t};\n\t\t}};"
control = "\n".join(cfg(b, "18.0") for b in IOS_BUNDLES[1:]) + "\n" + cfg(IOS_BUNDLES[0], "26.0")
check("control: an app target at 26.0 is refused", not ok(floors(control)))
check("control: no targets at all is refused", not ok(floors("")))
sys.exit(1 if fails else 0)
