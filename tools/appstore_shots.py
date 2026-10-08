#!/usr/bin/env python3
"""
appstore_shots.py — the App Store screenshot set for every Apple simulator
surface, captured the same way: launch the Debug build onto a screen through
the app's own start doors (AW_START_TAB / AW_START_ITEM, no-ops in Release),
wait for the art, capture the display, and REFUSE a file whose pixel size is
not one App Store Connect accepts for that slot.

    python3 tools/appstore_shots.py <slot> [--udid UDID] [--only NAME]

Slots (App Store Connect's own names; sizes from its screenshot
specifications, read 2026-10-08):

    iphone   "iPhone with Dynamic Island (medium display)"  1206x2622  (REQUIRED)
    duo      "iPhone Duo"  inner 2007x2853 / 2853x2007, outer 1398x2034 / 2034x1398
    ipad     "iPad 13-inch display"                         2064x2752
    tv       "Apple TV"                                     3840x2160

The Mac set is tools/mac-shotset.sh (a window framed on a 16:10 canvas).

The Duo's pose is set in Device Hub (tools/duo_pose.js) before its shots;
simctl has no hinge control. Captures flatten any alpha channel, which App
Store Connect refuses (its release notes, 2026-07-08).

Output: ~/Desktop/ArchiveWatch-AppStore-Screenshots-2026-10/<slot>/NN-name.png
— upload assets, regenerable, kept out of git like the earlier sets.
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

BUNDLE = "app.archivewatch.tvos"
DEV = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
OUT = Path.home() / "Desktop/ArchiveWatch-AppStore-Screenshots-2026-10"
ART_WAIT = int(os.environ.get("ART_WAIT", "30"))

SIZES = {
    "iphone": {(1206, 2622), (1179, 2556)},
    "duo": {(2007, 2853), (2853, 2007), (1398, 2034), (2034, 1398)},
    "ipad": {(2064, 2752), (2752, 2064), (2048, 2732), (2732, 2048)},
    "tv": {(3840, 2160), (1920, 1080)},
}

# (file name, door, value). Films are from the hero tier (heroSafe in the
# catalog index) — the same rights bar as the Home marquee.
PHONE_SET = [
    ("01-Home", "AW_START_TAB", "home"),
    ("02-Detail-Metropolis", "AW_START_ITEM", "metropolis-1927-4-k-u-rnemls-bwry"),
    ("03-Channels", "AW_START_TAB", "channels"),
    ("04-Detail-TheGeneral", "AW_START_ITEM", "TheGeneral720p1926"),
    ("05-Browse", "AW_START_TAB", "browse"),
    ("06-Detail-ATripToTheMoon", "AW_START_ITEM", "a-trip-to-the-moon-1902-tmdbid-775"),
    ("07-Detail-TheKid", "AW_START_ITEM", "turner_video_9"),
]
TV_SET = [
    ("01-Home", "AW_START_TAB", "home"),
    ("02-Channels", "AW_START_TAB", "channels"),
    ("03-Detail-Metropolis", "AW_START_ITEM", "metropolis-1927-4-k-u-rnemls-bwry"),
    ("04-Detail-TheGeneral", "AW_START_ITEM", "TheGeneral720p1926"),
    ("05-Movies", "AW_START_TAB", "movies"),
    ("06-Collections", "AW_START_TAB", "collections"),
    ("07-TVShows", "AW_START_TAB", "tvShows"),
    ("08-Detail-SherlockJr", "AW_START_ITEM", "sherlockjr1924_201909"),
    ("09-Surprise", "AW_START_TAB", "surprise"),
]


def simctl(*args, env=None, timeout=120):
    try:
        return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True,
                              env={**os.environ, "DEVELOPER_DIR": DEV, **(env or {})},
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", f"simctl {args[0]} timed out after {timeout}s")


def displays(udid):
    """{display uuid: (w, h)} for the device's framebuffer displays."""
    out = simctl("io", udid, "enumerate").stdout.split("Port:")
    found = {}
    for block in out:
        if "Display class: 0" not in block:
            continue
        lines = dict(l.strip().split(": ", 1) for l in block.splitlines() if ": " in l)
        found[lines["UUID"]] = (int(lines["Default width"]), int(lines["Default height"]))
    return found


def capture(udid, display, dest: Path, allowed):
    dest.unlink(missing_ok=True)
    r = simctl("io", udid, "screenshot", f"--display={display}", str(dest), timeout=60)
    if not dest.exists() or dest.stat().st_size == 0:
        sys.exit(f"capture failed for {dest.name}: {r.stderr.strip()[:200]}")
    img = Image.open(dest)
    if img.size not in allowed:
        dest.unlink()
        sys.exit(f"REFUSED {dest.name}: {img.size} is not an App Store size for this slot {sorted(allowed)}")
    if img.mode != "RGB":
        img.convert("RGB").save(dest, "PNG")
    if img.convert("L").getextrema()[1] < 16:
        dest.unlink()
        sys.exit(f"REFUSED {dest.name}: the frame is black (display off or still booting)")
    return img.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("slot", choices=sorted(SIZES))
    ap.add_argument("--udid", default="booted")
    ap.add_argument("--only")
    ap.add_argument("--display", help="display uuid (Duo: inner or outer); default = the largest lit one")
    ap.add_argument("--suffix", default="", help="appended to file names, e.g. -outer")
    a = ap.parse_args()

    shots = TV_SET if a.slot == "tv" else PHONE_SET
    if a.only:
        shots = [s for s in shots if a.only.lower() in s[0].lower()]
    outdir = OUT / a.slot
    outdir.mkdir(parents=True, exist_ok=True)
    disp = a.display or max(displays(a.udid).items(), key=lambda kv: kv[1][0] * kv[1][1])[0]

    for name, door, value in shots:
        simctl("terminate", a.udid, BUNDLE, timeout=20)
        r = simctl("launch", a.udid, BUNDLE, env={f"SIMCTL_CHILD_{door}": value}, timeout=180)
        if r.returncode != 0:
            sys.exit(f"launch failed for {name}: {r.stderr.strip()[:200]}")
        time.sleep(ART_WAIT)
        size = capture(a.udid, disp, outdir / f"{name}{a.suffix}.png", SIZES[a.slot])
        print(f"{name}{a.suffix}.png {size[0]}x{size[1]}")
    simctl("terminate", a.udid, BUNDLE, timeout=20)


if __name__ == "__main__":
    main()
