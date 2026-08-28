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


def judge(paths):
    """T1 verdict over a directory of screenshots: who clips, and where.

    Poster ARTWORK legitimately runs to the edge of a scrolling shelf, so a
    hit is only reported for text the app itself drew — judged by height,
    since chrome type is small and poster lettering is large."""
    verdicts = []
    for p in sorted(paths):
        lines = ocr(Path(p))
        hits, peeks = [], []
        for ln in lines:
            t = (ln.get("text") or "").strip()
            if not t or ln.get("h", 0) > 0.030:      # big = poster art
                continue
            x, w = ln.get("x", 0.0), ln.get("w", 0.0)
            # A LEFT-edge cut is always a defect: no padded layout starts a
            # line at x=0. A right-edge cut is usually a horizontally
            # scrolling row's intended peek, so it is reported, not failed.
            if x <= 0.010:
                hits.append(t)
            elif x + w >= 0.990:
                peeks.append(t)
        verdicts.append((Path(p).name, hits))
        mark = "CLIP" if hits else "ok  "
        note = ' | '.join(h[:30] for h in hits[:3]) or \
               ("peek: " + ' | '.join(p[:22] for p in peeks[:2]) if peeks else "")
        print(f"  {mark} {Path(p).name:44s} {note}")
    bad = [v for v in verdicts if v[1]]
    print(f"\n{len(verdicts) - len(bad)}/{len(verdicts)} clean; {len(bad)} clipping")
    return verdicts


def measure(paths, width_pt=1366.0, max_chars=80, max_control=480.0):
    """IPAD-DESIGN §7.1 + §7.2: how long is the longest line of prose, and is
    any control wider than a primary action should be?

    Character count, not width, is the measure that matters — it is what a
    reader's eye actually has to track — but the width is printed too, since
    that is the number a `frame(maxWidth:)` is written in."""
    bad = 0
    for p in sorted(paths):
        lines = ocr(Path(p))
        prose = [l for l in lines
                 if len((l.get("text") or "").strip()) > 25 and l.get("h", 0) < 0.020]
        if not prose:
            print(f"  --   {Path(p).name:40s} (no prose)")
            continue
        worst = max(prose, key=lambda l: len(l["text"]))
        chars = len(worst["text"].strip())
        pts = worst.get("w", 0.0) * width_pt
        over = chars > max_chars
        bad += 1 if over else 0
        print(f"  {'OVER' if over else 'ok  '} {Path(p).name:40s} "
              f"{chars:3d} chars / {pts:5.0f}pt   {worst['text'][:44]}")
    print(f"\n{len(list(paths)) - bad} within measure; {bad} over {max_chars} chars")
    return bad


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sweep"
    if cmd == "measure":
        args = sys.argv[2:]
        files = []
        for a in args:
            q = Path(a)
            files += sorted(str(f) for f in q.glob("*.png")) if q.is_dir() else [a]
        sys.exit(1 if measure(files) else 0)
    if cmd == "judge":
        args = sys.argv[2:]
        files = []
        for a in args:
            q = Path(a)
            files += sorted(str(f) for f in q.glob("*.png")) if q.is_dir() else [a]
        judge(files)
        sys.exit(0)
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
