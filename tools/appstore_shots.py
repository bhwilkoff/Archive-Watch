#!/usr/bin/env python3
"""
appstore_shots.py — the App Store screenshot set for every Apple simulator
surface, captured the same way: launch the Debug build onto a screen through
the app's own start doors (AW_START_TAB / AW_START_ITEM, no-ops in Release),
with AW_SHOWCASE=1 (Services/Showcase.swift: hero-tier rights, professional
art, no horror, most-voted first; personal rows hidden), wait for the art,
capture the display, and REFUSE a file whose pixel size is
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


def grab(udid, display):
    """A small grayscale copy of the display right now, or None."""
    tmp = OUT / ".probe.png"
    tmp.unlink(missing_ok=True)
    simctl("io", udid, "screenshot", f"--display={display}", str(tmp), timeout=60)
    try:
        return Image.open(tmp).convert("L").resize((200, 290))
    except Exception:
        return None
    finally:
        tmp.unlink(missing_ok=True)


def differs(a, b, by):
    from PIL import ImageChops, ImageStat
    return a is None or b is None or ImageStat.Stat(ImageChops.difference(a, b)).mean[0] > by


def wait_for_content(udid, display, limit, before=None):
    """Wait until the APP is on screen with its content: not the white launch
    screen, not the black "Loading the archive..." screen (~150 MB on a first
    launch), not whatever was showing before the launch (the springboard's
    mid-grey wallpaper passed a brightness test, 2026-10-08), and steady across
    two looks 15 s apart."""
    from PIL import ImageStat
    end = time.time() + limit
    prev = None
    while time.time() < end:
        img = grab(udid, display)
        if img is not None:
            luma = ImageStat.Stat(img).mean[0]
            if 12 < luma < 240 and differs(img, before, 12) and prev is not None and not differs(img, prev, 6):
                return True
            prev = img if 12 < luma < 240 else None
        time.sleep(15)
    return False


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
    from PIL import ImageStat
    luma = ImageStat.Stat(img.convert("L")).mean[0]
    if not 12 < luma < 240:
        dest.unlink()
        sys.exit(f"REFUSED {dest.name}: the frame is near-black or near-white (loading or launch screen), luma {luma:.0f}")
    return img.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("slot", choices=sorted(SIZES))
    ap.add_argument("--udid", default="booted")
    ap.add_argument("--only")
    ap.add_argument("--display", help="display uuid (Duo: inner or outer); default = the largest lit one")
    ap.add_argument("--suffix", default="", help="appended to file names, e.g. -outer")
    ap.add_argument("--reuse", action="store_true", help="the app is already running on Home; don't relaunch it")
    a = ap.parse_args()

    shots = TV_SET if a.slot == "tv" else PHONE_SET
    if a.only:
        wanted = [w.strip().lower() for w in a.only.split(",")]
        shots = [s for s in shots if any(w in s[0].lower() for w in wanted)]
    outdir = OUT / a.slot
    outdir.mkdir(parents=True, exist_ok=True)
    disp = a.display or max(displays(a.udid).items(), key=lambda kv: kv[1][0] * kv[1][1])[0]

    # Never kill the app mid-load: a kill during the first catalog download
    # (~150 MB, ~8 min on this Mac) throws the cache away and the next launch
    # starts over (2026-10-08). So Home first, waited out in full, then every
    # other screen as a relaunch onto the now-cached catalog (~2 min each).
    # Not `simctl openurl archivewatch://item/...`: each one raises the system's
    # "Open in Archive Watch?" prompt over the app. --reuse skips the first
    # launch when the app is already showing Home.
    before = {"img": None}

    def launch(env):
        simctl("terminate", a.udid, BUNDLE, timeout=20)
        time.sleep(3)
        before["img"] = grab(a.udid, disp)
        r = simctl("launch", a.udid, BUNDLE, env={**env, "SIMCTL_CHILD_AW_SHOWCASE": "1"}, timeout=180)
        if r.returncode != 0:
            sys.exit(f"launch failed: {r.stderr.strip()[:200]}")

    def shoot(name):
        if not wait_for_content(a.udid, disp, 900, before["img"]):
            sys.exit(f"{name}: the app never got past its loading screen in 15 minutes")
        time.sleep(ART_WAIT)
        size = capture(a.udid, disp, outdir / f"{name}{a.suffix}.png", SIZES[a.slot])
        print(f"{name}{a.suffix}.png {size[0]}x{size[1]}", flush=True)

    home = [s for s in shots if s[1] == "AW_START_TAB" and s[2] == "home"]
    films = [s for s in shots if s[1] == "AW_START_ITEM"]
    tabs = [s for s in shots if s not in home and s not in films]
    if not a.reuse:
        launch({"SIMCTL_CHILD_AW_START_TAB": "home"})
    for name, _, _ in home:
        shoot(name)
    for name, door, value in films + tabs:
        launch({f"SIMCTL_CHILD_{door}": value})
        shoot(name)

if __name__ == "__main__":
    main()
