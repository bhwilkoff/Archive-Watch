#!/usr/bin/env python3
"""iOS device harness — the atv_scenario.py twin for a physical iPhone.

The Apple TV harness reads the glass because tvOS gives no other oracle;
an iPhone gives two more (`devicectl` launches with env vars AND deep
links), but the JUDGEMENT stays external: a surface is right when the
SCREENSHOT says so, never when the app reports it drew.

Usage:
    python3 tools/ios_scenario.py shot home            # env-driven tab
    python3 tools/ios_scenario.py link item/<archiveID>
    python3 tools/ios_scenario.py sweep                # every reachable surface

Requires /tmp/awocr (swiftc -O tools/ScreenOCR/main.swift -o /tmp/awocr).
Device selection: AW_IOS_DEVICE (default = the iPhone 12 test rig).
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

DEVICE = os.environ.get("AW_IOS_DEVICE", "B4E756E2-CBFA-5F63-8CEE-21D226637AF7")
BUNDLE = "app.archivewatch.tvos"
XCRUN = ["xcrun", "devicectl"]
ENV = {**os.environ, "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"}
OUT = Path(os.environ.get("AW_IOS_OUT", "/tmp/ios-audit"))
OCR = "/tmp/awocr"


def run(args, timeout=180):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=ENV)


def terminate():
    run(XCRUN + ["device", "process", "terminate", "--device", DEVICE,
                 "--console", "--bundle-identifier", BUNDLE], timeout=60)


def launch(env=None, url=None, wait=9.0):
    """Launch cold. A relaunch is the only way to seed AW_START_* hooks."""
    args = XCRUN + ["device", "process", "launch", "--device", DEVICE,
                    "--terminate-existing"]
    if env:
        args += ["-e", json.dumps(env)]
    if url:
        args += ["--payload-url", url]
    args += [BUNDLE]
    r = run(args)
    ok = "Launched application" in (r.stdout + r.stderr)
    time.sleep(wait)
    return ok


def shot(name):
    OUT.mkdir(parents=True, exist_ok=True)
    p = OUT / f"{name}.png"
    r = run(XCRUN + ["device", "capture", "screenshot", "--device", DEVICE,
                     "--destination", str(p)], timeout=120)
    if not p.exists():
        print(f"  !! screenshot failed: {r.stderr.strip()[:160]}")
        return None
    return p


def ocr(png):
    """Vision OCR -> [{text,x,y,h}] in PIXEL coords of the capture."""
    if not Path(OCR).exists() or png is None:
        return []
    r = run([OCR, str(png)], timeout=120)
    try:
        return json.loads(r.stdout.strip().splitlines()[0]).get("allText", [])
    except Exception:
        return []


# ---------------------------------------------------------------- checks

# A clipped label is the defect this rig exists to find: the iPhone 12 is
# 390pt wide against the 15 Pro's 393 and has a NOTCH, not an island, so
# both the horizontal squeeze and the top inset differ from the reference
# device every other iOS screenshot in this repo was taken on.
def clipped(lines, margin=0.012):
    """Lines that run to the frame edge, or end in a truncation glyph.

    Coordinates are NORMALIZED (Vision, origin bottom-left), so the margin
    is a fraction of the frame, not pixels."""
    out = []
    for ln in lines:
        t = (ln.get("text") or "").strip()
        if not t:
            continue
        x, w = ln.get("x", 0.0), ln.get("w", 0.0)
        if t.endswith(("\u2026", "...")):
            out.append(("ellipsis", t))
        elif x <= margin or x + w >= 1.0 - margin:
            out.append(("edge", t))
    return out


SURFACES = [
    ("home", {"AW_START_TAB": "home"}, None),
    ("browse", {"AW_START_TAB": "browse"}, None),
    ("channels", {"AW_START_TAB": "channels"}, None),
    ("search", {"AW_START_TAB": "search"}, None),
    ("library", {"AW_START_TAB": "library"}, None),
    ("surprise", None, "archivewatch://surprise"),
    ("randomcategory", None, "archivewatch://randomcategory"),
]


def sweep(items=None):
    results = []
    for name, env, url in SURFACES:
        print(f"== {name}")
        launch(env=env, url=url)
        p = shot(name)
        lines = ocr(p)
        txt = [l["text"] for l in lines]
        print(f"   {len(txt)} text lines: {' | '.join(txt[:8])}")
        results.append((name, p, lines))
    for i, aid in enumerate(items or []):
        name = f"detail-{i}-{aid[:24]}"
        print(f"== {name}")
        launch(env={"AW_START_ITEM": aid})
        p = shot(name)
        lines = ocr(p)
        print(f"   {' | '.join(l['text'] for l in lines[:8])}")
        results.append((name, p, lines))
    return results


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sweep"
    if cmd == "shot":
        tab = sys.argv[2] if len(sys.argv) > 2 else "home"
        launch(env={"AW_START_TAB": tab})
        print(shot(tab))
    elif cmd == "link":
        launch(url="archivewatch://" + sys.argv[2])
        print(shot(sys.argv[2].replace("/", "-")))
    elif cmd == "item":
        launch(env={"AW_START_ITEM": sys.argv[2]})
        print(shot("item-" + sys.argv[2][:20]))
    else:
        sweep(sys.argv[2:])
