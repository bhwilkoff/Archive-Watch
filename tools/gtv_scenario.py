#!/usr/bin/env python3
"""Google TV on-device scenario harness — the adb twin of atv_scenario.py.

The owner's Google TV (10.0.0.55, paired 2026-08-27) is the oracle. Evidence
channels, all external to the app (the atv_external_observation_harness rule):
screenshots + OCR (/tmp/awocr), the uiautomator focus tree, and logcat.

Lessons this file encodes (each cost a failed run on 2026-08-27):
- CONNECT FIRST, every run: the TLS wireless-debugging port ROTATES after
  sleep; classic port 5555 is stable but the connection itself drops between
  commands. connect() tries 5555, then re-resolves via `adb mdns services`.
- NAVIGATE BY THE TREE, never by step counts: focus enters the nav rail at
  the VERTICALLY NEAREST item (a tall Home hero lands you on Channels, not
  Home), so a blind LEFT/DOWN/CENTER script labels its screenshots wrong.
  Every press is followed by a focus-bounds read; goto_tab walks until the
  focused rail row's center-y is inside the target band.
- `input tap` is INERT on the TV profile — motion events are not part of the
  focus grammar. The D-pad is the only input channel.

Usage:
  python3 tools/gtv_scenario.py rail_walk          # capture + OCR-assert all tabs
  python3 tools/gtv_scenario.py shot NAME          # one screenshot into the QA dir
  python3 tools/gtv_scenario.py focus              # print the focused node
"""
import datetime
import os
import re
import subprocess
import sys
import time

ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
HOST = "10.0.0.55"
PKG = "com.archivewatch.app.debug"
QA_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "build", "qa", f"gtv-{datetime.date.today().isoformat()}")
OCR = "/tmp/awocr"

# Rail rows by center-y at 1080p (measured from the device 2026-08-27).
RAIL = {
    "home": 106, "browse": 222, "channels": 338, "search": 454,
    "library": 570, "surprise": 686, "settings": 802,
}
RAIL_BAND = 55       # ± tolerance for "focused row is this tab"
RAIL_X_MAX = 400     # a focused node left of this is in the rail

_serial = None


def sh(*args, timeout=30, binary=False):
    r = subprocess.run(list(args), capture_output=True, timeout=timeout)
    return r.stdout if binary else r.stdout.decode(errors="replace")


def connect():
    """Return an adb serial, reconnecting however the device is reachable."""
    global _serial
    for attempt in ("cached", "5555", "mdns", "5555-again"):
        if attempt == "cached" and _serial:
            pass
        elif attempt in ("5555", "5555-again"):
            sh(ADB, "connect", f"{HOST}:5555")
            _serial = f"{HOST}:5555"
        else:
            out = sh(ADB, "mdns", "services")
            m = re.search(r"GZ25\S*\s+_adb-tls-connect\._tcp\.?\s+"
                          rf"{re.escape(HOST)}:(\d+)", out)
            if not m:
                continue
            sh(ADB, "connect", f"{HOST}:{m.group(1)}")
            _serial = f"{HOST}:{m.group(1)}"
        probe = sh(ADB, "-s", _serial, "shell", "echo", "ok")
        if "ok" in probe:
            return _serial
    raise SystemExit(f"cannot reach {HOST} over adb (is the device awake?)")


def adbs(*args, timeout=30, binary=False):
    return sh(ADB, "-s", connect(), *args, timeout=timeout, binary=binary)


def press(key, settle=1.2):
    adbs("shell", "input", "keyevent", key)
    time.sleep(settle)


def focused_bounds():
    """(l, t, r, b) of the focused node, or None. Never trust one dump — the
    tree is briefly empty during transitions; retry once."""
    for _ in range(2):
        adbs("shell", "uiautomator", "dump", "/sdcard/ui.xml")
        xml = adbs("shell", "cat", "/sdcard/ui.xml")
        for m in re.finditer(r"<node[^>]*>", xml):
            n = m.group(0)
            if 'focused="true"' in n:
                b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
                if b:
                    return tuple(int(x) for x in b.groups())
        time.sleep(1.0)
    return None


def rail_tab_at(bounds):
    if not bounds or bounds[0] > RAIL_X_MAX:
        return None
    cy = (bounds[1] + bounds[3]) // 2
    for name, y in RAIL.items():
        if abs(cy - y) <= RAIL_BAND:
            return name
    return None


def goto_tab(target, max_steps=14):
    """Walk focus onto the rail, then to the target row, then select it."""
    target = target.lower()
    for _ in range(6):                       # reach the rail
        b = focused_bounds()
        if rail_tab_at(b):
            break
        press("KEYCODE_DPAD_LEFT")
    for _ in range(max_steps):               # walk to the target row
        b = focused_bounds()
        cur = rail_tab_at(b)
        if cur is None:
            press("KEYCODE_DPAD_LEFT")
            continue
        if cur == target:
            press("KEYCODE_DPAD_CENTER", settle=4.0)
            return True
        order = list(RAIL)
        press("KEYCODE_DPAD_DOWN" if order.index(cur) < order.index(target)
              else "KEYCODE_DPAD_UP")
    return False


def screenshot(name):
    os.makedirs(QA_DIR, exist_ok=True)
    path = os.path.join(QA_DIR, f"{name}.png")
    data = adbs("exec-out", "screencap", "-p", timeout=60, binary=True)
    with open(path, "wb") as f:
        f.write(data)
    return path


def ocr(path):
    if not os.path.exists(OCR):
        return ""
    return sh(OCR, path, timeout=60)


def launch(deep_link=None, force_stop=False):
    if force_stop:
        adbs("shell", "am", "force-stop", PKG)
        time.sleep(2)
    if deep_link:
        adbs("shell", "am", "start", "-a", "android.intent.action.VIEW",
             "-d", deep_link, PKG)
    else:
        adbs("shell", "monkey", "-p", PKG, "-c",
             "android.intent.category.LEANBACK_LAUNCHER", "1")
    time.sleep(15)


def logcat_app(lines=200):
    pid = adbs("shell", "pidof", PKG).strip()
    if not pid:
        return ""
    return adbs("shell", "logcat", "-d", f"--pid={pid}", "-t", str(lines))


# ---------------------------------------------------------------- scenarios

# Text that must be on the glass for each tab — OCR-asserted, not assumed.
TAB_EXPECT = {
    "browse": ["Browse", "titles"],
    "channels": ["Channels"],
    "search": ["Search titles"],
    "library": ["Library"],
    "surprise": ["Surprise"],
    "settings": ["Settings"],
}


def _keycap_map():
    """label -> bounds for the search keyboard's keycaps, from the live tree."""
    adbs("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    xml = adbs("shell", "cat", "/sdcard/ui.xml")
    keys = {}
    for m in re.finditer(r'<node[^>]*text="([A-Z0-9]|SPACE|DEL)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*>', xml):
        label = m.group(1)
        keys[label] = tuple(int(x) for x in m.group(2, 3, 4, 5))
    return keys


def type_text(text):
    """Type on the TV search keycap keyboard, CLOSED-LOOP: after every press
    the focused bounds are re-read and compared to the target key — blind
    keycap arithmetic has failed every time it was tried (2026-08-27, twice).
    Focus must already be somewhere on the keyboard (the screen claims the
    first keycap on entry)."""
    keys = _keycap_map()
    for ch in text.upper():
        label = "SPACE" if ch == " " else ch
        if label not in keys:
            print(f"  type_text: no keycap for {label!r}; have {sorted(keys)[:8]}…")
            return False
        tl, tt, tr, tb = keys[label]
        tx, ty = (tl + tr) // 2, (tt + tb) // 2
        for _ in range(30):
            b = focused_bounds()
            if not b:
                return False
            cx, cy = (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
            if tl <= cx <= tr and tt <= cy <= tb:
                press("KEYCODE_DPAD_CENTER", settle=0.8)
                break
            if cx < 440:
                # Fell out of the keyboard onto the nav rail (the col-0 LEFT
                # exit, §3.4) — step back in before any other correction.
                press("KEYCODE_DPAD_RIGHT", settle=0.6)
                continue
            dy, dx = ty - cy, tx - cx
            # Move along the axis with the larger error; never press LEFT
            # while already in the target column band (col-0 would exit).
            if abs(dy) > (tb - tt) / 2 and abs(dy) >= abs(dx) / 3:
                press("KEYCODE_DPAD_DOWN" if dy > 0 else "KEYCODE_DPAD_UP", settle=0.6)
            elif abs(dx) > (tr - tl) / 2:
                press("KEYCODE_DPAD_RIGHT" if dx > 0 else "KEYCODE_DPAD_LEFT", settle=0.6)
            else:
                press("KEYCODE_DPAD_DOWN" if dy > 0 else "KEYCODE_DPAD_UP", settle=0.6)
        else:
            print(f"  type_text: could not reach {label!r}")
            return False
    return True


def rail_walk():
    launch(force_stop=True)
    results = []
    shot = screenshot("walk-00-home")
    text = ocr(shot)
    ok = "Home" in text or "Popular" in text
    results.append(("home", ok, shot))
    for tab, expects in TAB_EXPECT.items():
        reached = goto_tab(tab)
        shot = screenshot(f"walk-{tab}")
        text = ocr(shot)
        ok = reached and all(e.lower() in text.lower() for e in expects)
        results.append((tab, ok, shot))
        print(f"  [{'PASS' if ok else 'FAIL'}] {tab}: reached={reached} "
              f"expect={expects}", flush=True)
        # BACK only after PUSHED routes (Surprise/Settings): §1.7 makes Back
        # from a TAB ROOT exit the app entirely — the first harness run
        # pressed it after Browse and spent the rest of the walk navigating
        # the launcher.
        if tab in ("surprise", "settings"):
            press("KEYCODE_BACK", settle=2.0)
    passed = sum(1 for _, ok, _ in results if ok)
    print(f"RESULT: {passed}/{len(results)} tabs verified — shots in {QA_DIR}")
    return 0 if passed == len(results) else 1


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "rail_walk"
    if cmd == "rail_walk":
        return rail_walk()
    if cmd == "shot":
        p = screenshot(sys.argv[2] if len(sys.argv) > 2 else "shot")
        print(p)
        print(ocr(p)[:400])
        return 0
    if cmd == "focus":
        b = focused_bounds()
        print("focused:", b, "rail tab:", rail_tab_at(b))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
