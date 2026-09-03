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
# Default = the Google TV; AW_TV_HOST=10.0.0.139 targets the Fire TV Stick 4K
# (AFTKRT, Fire OS). Both use classic port 5555; only the Google TV also has
# the rotating TLS port, so the mdns fallback simply finds nothing on Fire.
HOST = os.environ.get("AW_TV_HOST", "10.0.0.55")
# Devices whose classic port 5555 never opens (the Pixel phone) connect via
# the rotating TLS port, resolved from mdns by serial prefix.
MDNS_SERIAL = os.environ.get("AW_TV_MDNS", "GZ25")
PKG = "com.archivewatch.app.debug"
QA_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "build", "qa", f"gtv-{datetime.date.today().isoformat()}")
OCR = "/tmp/awocr"

# Rail rows by center-y at 1080p (measured from the device 2026-08-27).
# The rail SCROLLS once it outgrew the panel (10 rows since Party joined),
# so fixed y-positions are meaningless — rows are identified by the LABEL
# text that sits inside the focused bounds instead.
RAIL_ORDER = ["home", "browse", "channels", "search", "library",
              "collections", "cartoons", "party", "surprise", "settings"]
RAIL_X_MAX = 440     # a focused node left of this is in the rail

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
            m = re.search(rf"{re.escape(MDNS_SERIAL)}\S*\s+_adb-tls-connect\._tcp\.?\s+"
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
        xml = _tree()
        for m in re.finditer(r"<node[^>]*>", xml):
            n = m.group(0)
            if 'focused="true"' in n:
                b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
                if b:
                    return tuple(int(x) for x in b.groups())
        time.sleep(1.0)
    return None


def _tree():
    # Delete-first: a failed dump otherwise serves a STALE file from some
    # earlier app's session (measured on the Pixel — the tree showed another
    # app entirely while ours was foreground).
    adbs("shell", "rm", "-f", "/sdcard/ui.xml")
    out = adbs("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    if "dumped" not in out.lower():
        return ""
    return adbs("shell", "cat", "/sdcard/ui.xml")


def rail_tab_at(bounds, xml=None):
    """The rail row under `bounds`, identified by the label text inside it."""
    if not bounds or bounds[0] > RAIL_X_MAX:
        return None
    xml = xml or _tree()
    for m in re.finditer(
            r'<node[^>]*text="(Home|Browse|Channels|Search|Library|Collections|'
            r'Cartoons|Party|Surprise|Settings)"[^>]*'
            r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*>', xml):
        label = m.group(1).lower()
        t_, b_ = int(m.group(3)), int(m.group(5))
        cy = (t_ + b_) // 2
        if bounds[1] <= cy <= bounds[3]:
            return label
    return None


def goto_tab(target, max_steps=14):
    """Walk focus onto the rail, then to the target row, then select it.

    The rail is HIDDEN while a route is pushed (Detail/Player/Surprise…), so
    if LEFT never finds it, press BACK to pop back to a tab root and retry —
    without this, one accidental Select strands the whole walk (measured on
    the fresh-install gate run)."""
    target = target.lower()
    for attempt in range(3):
        found = False
        for _ in range(6):                   # reach the rail
            b = focused_bounds()
            if rail_tab_at(b):
                found = True
                break
            press("KEYCODE_DPAD_LEFT")
        if found:
            break
        press("KEYCODE_BACK", settle=2.0)    # pop a pushed route hiding the rail
    for _ in range(max_steps):               # walk to the target row
        b = focused_bounds()
        cur = rail_tab_at(b)
        if cur is None:
            press("KEYCODE_DPAD_LEFT")
            continue
        if cur == target:
            press("KEYCODE_DPAD_CENTER", settle=4.0)
            return True
        press("KEYCODE_DPAD_DOWN" if RAIL_ORDER.index(cur) < RAIL_ORDER.index(target)
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
    # The device idles into the system screensaver; a launch fired into that
    # state goes nowhere (measured: a deep link left the backdrop picker on
    # screen). Wake + dismiss first.
    adbs("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(1.5)
    # Insecure keyguards dismiss; a secure one (the Pixel) is prevented from
    # re-engaging instead: `svc power stayon true` is set on the phone, so
    # after the owner's ONE unlock the screen never sleeps. Never ask for
    # repeated unlocks (owner, 2026-08-28).
    adbs("shell", "wm", "dismiss-keyguard")
    time.sleep(1.0)
    adbs("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1.5)
    if force_stop:
        adbs("shell", "am", "force-stop", PKG)
        time.sleep(2)
    if deep_link:
        adbs("shell", "am", "start", "-a", "android.intent.action.VIEW",
             "-d", deep_link, PKG)
    else:
        # Explicit component, not monkey: Fire OS accepts the monkey launch
        # but never foregrounds the app (measured 2026-08-28); am start -n
        # works on both platforms.
        adbs("shell", "am", "start", "-n", f"{PKG}/app.archivewatch.android.MainActivity")
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
    "collections": ["Collections"],
    "cartoons": ["Cartoon"],
    "party": ["Party Play"],
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
    # A fresh install downloads the full catalog — wait for Home CONTENT
    # before walking, or the loading anchor's focus layout misleads goto_tab.
    for _ in range(12):
        text = ocr(screenshot("walk-00-home"))
        if "Loading" not in text:
            break
        time.sleep(10)
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
        if tab in ("collections", "cartoons", "party", "surprise", "settings"):
            press("KEYCODE_BACK", settle=2.0)
    passed = sum(1 for _, ok, _ in results if ok)
    print(f"RESULT: {passed}/{len(results)} tabs verified — shots in {QA_DIR}")
    return 0 if passed == len(results) else 1


# ---------------------------------------------------------------- audit verbs
# One adb round-trip per Bash call is what makes an element-level audit
# affordable: every verb below prints the external evidence it gathered
# (focused node, on-glass text, log lines) so a step and its proof are one
# command. Added for docs/ANDROID-TV-AUDIT.md (2026-09-03).

def focused_node():
    """The focused node's (bounds, text, content-desc, class) or None."""
    for _ in range(2):
        xml = _tree()
        for m in re.finditer(r"<node[^>]*>", xml):
            n = m.group(0)
            if 'focused="true"' in n:
                b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
                t = re.search(r' text="([^"]*)"', n)
                d = re.search(r' content-desc="([^"]*)"', n)
                c = re.search(r' class="([^"]*)"', n)
                if b:
                    return (tuple(int(x) for x in b.groups()),
                            t.group(1) if t else "", d.group(1) if d else "",
                            c.group(1) if c else "")
        time.sleep(1.0)
    return None


def texts_inside(bounds, xml=None):
    """Text nodes drawn INSIDE `bounds` — a Compose chip/tile is an unlabeled
    View in the tree; its label is a sibling text node, so the focused
    element is identified by whatever text sits within its box."""
    xml = xml or _tree()
    l, t, r, b = bounds
    found = []
    for m in re.finditer(r"<node[^>]*>", xml):
        n = m.group(0)
        tx = re.search(r' text="([^"]*)"', n)
        bb = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        if not tx or not tx.group(1) or not bb:
            continue
        x0, y0, x1, y1 = (int(v) for v in bb.groups())
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        if l <= cx <= r and t <= cy <= b:
            found.append(tx.group(1))
    return found


def print_focus():
    n = focused_node()
    if not n:
        print("focused: NONE")
        return
    b, t, d, c = n
    inside = texts_inside(b)
    print(f"focused: {b} text={t!r} desc={d!r} inside={inside[:4]} rail={rail_tab_at(b)}")


def tree_nodes(focusable_only=True):
    """Every (text|desc, bounds, focusable, focused) node in the live tree."""
    xml = _tree()
    out = []
    for m in re.finditer(r"<node[^>]*>", xml):
        n = m.group(0)
        f = 'focusable="true"' in n
        if focusable_only and not f:
            continue
        t = re.search(r' text="([^"]*)"', n)
        d = re.search(r' content-desc="([^"]*)"', n)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        label = (t.group(1) if t else "") or (d.group(1) if d else "")
        out.append((label, tuple(int(x) for x in b.groups()) if b else None,
                    f, 'focused="true"' in n))
    return out


def ocr_text(path):
    """Flat text of everything OCR found in the shot, top-to-bottom."""
    import json
    raw = ocr(path)
    lines = []
    for ln in raw.splitlines():
        try:
            j = json.loads(ln)
        except ValueError:
            continue
        for line in sorted(j.get("allText", []), key=lambda l: -l["y"]):
            lines.append(line["text"])
    return "\n".join(lines)


def app_log(grep=None, lines=400):
    out = logcat_app(lines)
    if grep:
        out = "\n".join(l for l in out.splitlines() if re.search(grep, l))
    return out


def launch_with(extras):
    """am start with the verification extras (focus log, start tab/route)."""
    adbs("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(1.0)
    adbs("shell", "am", "force-stop", PKG)
    time.sleep(1.5)
    adbs("shell", "logcat", "-c")
    args = ["shell", "am", "start", "-n", f"{PKG}/app.archivewatch.android.MainActivity",
            "--ez", "aw_focus_log", "true"] + extras
    print(adbs(*args).strip())


def find_text(label, xml=None):
    """Bounds of the first on-screen text node matching `label` (exact, then
    case-insensitive substring)."""
    xml = xml or _tree()
    nodes = []
    for m in re.finditer(r"<node[^>]*>", xml):
        n = m.group(0)
        tx = re.search(r' text="([^"]*)"', n)
        bb = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        if tx and tx.group(1) and bb:
            nodes.append((tx.group(1), tuple(int(v) for v in bb.groups())))
    for t, b in nodes:
        if t == label:
            return b
    for t, b in nodes:
        if label.lower() in t.lower():
            return b
    return None


def go(label, max_steps=40):
    """Move focus onto the element whose label text is `label`, CLOSED-LOOP
    (the type_text discipline generalised): after every press the focused
    bounds are re-read; done when the label's centre sits inside them.
    A focused node that has wandered onto the rail steps back Right first."""
    target = find_text(label)
    if not target:
        # A LazyRow composes only what is on screen: scan the focused row
        # Right, then Left, until the label is drawn.
        for key, n in (("KEYCODE_DPAD_RIGHT", 14), ("KEYCODE_DPAD_LEFT", 28)):
            for _ in range(n):
                press(key, settle=0.6)
                target = find_text(label)
                if target:
                    break
            if target:
                break
    if not target:
        print(f"  go: no on-screen text matching {label!r}")
        return False
    tl, tt, tr, tb = target
    tx, ty = (tl + tr) // 2, (tt + tb) // 2
    for _ in range(max_steps):
        b = focused_bounds()
        if not b:
            return False
        if b[0] <= tx <= b[2] and b[1] <= ty <= b[3]:
            return True
        cx, cy = (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
        if cx < RAIL_X_MAX <= tx:
            press("KEYCODE_DPAD_RIGHT", settle=0.7)
            continue
        dy, dx = ty - cy, tx - cx
        if abs(dy) > (b[3] - b[1]) / 2:
            press("KEYCODE_DPAD_DOWN" if dy > 0 else "KEYCODE_DPAD_UP", settle=0.7)
        elif abs(dx) > 4:
            press("KEYCODE_DPAD_RIGHT" if dx > 0 else "KEYCODE_DPAD_LEFT", settle=0.7)
        else:
            return True
        # The layout may have scrolled; re-resolve the target.
        target = find_text(label) or target
        tl, tt, tr, tb = target
        tx, ty = (tl + tr) // 2, (tt + tb) // 2
    print(f"  go: could not reach {label!r}")
    return False


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "rail_walk"
    if cmd in ("go", "select"):
        ok = go(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 40)
        if ok and cmd == "select":
            press("KEYCODE_DPAD_CENTER", settle=float(os.environ.get("AW_SELECT_WAIT", "3")))
        print(("reached " if ok else "MISSED ") + sys.argv[2])
        print_focus()
        return 0 if ok else 1
    a = sys.argv[2:]
    if cmd == "rail_walk":
        return rail_walk()
    if cmd == "shot":
        p = screenshot(a[0] if a else "shot")
        print(p)
        print(ocr_text(p))
        return 0
    if cmd == "focus":
        print_focus()
        return 0
    if cmd == "press":
        # press KEY [count] [settle]  e.g. press DPAD_DOWN 3 0.8
        key = a[0] if a[0].startswith("KEYCODE_") else "KEYCODE_" + a[0]
        n = int(a[1]) if len(a) > 1 else 1
        settle = float(a[2]) if len(a) > 2 else 1.0
        for _ in range(n):
            press(key, settle=settle)
        print_focus()
        return 0
    if cmd == "keys":
        # keys DPAD_DOWN DPAD_RIGHT DPAD_CENTER ... (1s settle each), then focus
        for k in a:
            press(k if k.startswith("KEYCODE_") else "KEYCODE_" + k, settle=1.0)
        print_focus()
        return 0
    if cmd == "longpress":
        # a D-pad long press = key down, hold, key up
        key = a[0] if a and a[0].startswith("KEYCODE_") else "KEYCODE_" + (a[0] if a else "DPAD_CENTER")
        adbs("shell", "input", "keyevent", "--longpress", key)
        time.sleep(1.5)
        print_focus()
        return 0
    if cmd == "tree":
        for label, b, f, focused in tree_nodes(focusable_only="--all" not in a):
            print(("* " if focused else "  ") + f"{label!r} {b}")
        return 0
    if cmd == "launch":
        launch_with(a)
        time.sleep(float(os.environ.get("AW_LAUNCH_WAIT", "12")))
        print_focus()
        return 0
    if cmd == "link":
        adbs("shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", a[0], PKG)
        time.sleep(8)
        print_focus()
        return 0
    if cmd == "type":
        ok = type_text(a[0])
        print("typed" if ok else "TYPE FAILED")
        print_focus()
        return 0 if ok else 1
    if cmd == "log":
        print(app_log(a[0] if a else "AWFOCUS|AWTV|AWHOME", int(a[1]) if len(a) > 1 else 400))
        return 0
    if cmd == "tab":
        ok = goto_tab(a[0])
        print("reached" if ok else "NOT REACHED")
        print_focus()
        return 0 if ok else 1
    if cmd == "ocr":
        print(ocr_text(a[0]))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
