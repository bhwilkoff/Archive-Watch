#!/usr/bin/env python3
"""Phone player check on the paired Pixel 8a (real device, never an emulator).

Opens a title by deep link, taps Play by LABEL (found in the uiautomator
tree, never by coordinates), then captures the four states a user reported
broken on 2026-09-03: quiet playback (no chrome), controls visible, the
options sheet, and the Picture-in-Picture window. Prints the a11y nodes of
the player so the check can assert what is on screen.

  AW_PIXEL=10.0.0.175:<tls-port> python3 tools/pixel_player_test.py [archiveID]
"""
import os, re, subprocess, sys, time

ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
SER = os.environ.get("AW_PIXEL")
PKG = "com.archivewatch.app.debug"
OUT = os.environ.get("AW_OUT", "/tmp/pixel-player")


def sh(*a, binary=False):
    r = subprocess.run([ADB, "-s", SER, *a], capture_output=True, timeout=60)
    return r.stdout if binary else r.stdout.decode(errors="replace")


def tree():
    sh("shell", "rm", "-f", "/sdcard/ui.xml")
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    xml = sh("shell", "cat", "/sdcard/ui.xml")
    nodes = []
    for m in re.finditer(r"<node[^>]*>", xml):
        n = m.group(0)
        g = lambda k: (re.search(rf' {k}="([^"]*)"', n) or [None, ""])[1]
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        nodes.append((g("text"), g("content-desc"), g("resource-id").split("/")[-1],
                      tuple(int(x) for x in b.groups()) if b else None))
    return nodes


def find(label):
    for tx, cd, rid, b in tree():
        if b and (tx == label or cd == label or tx.startswith(label + " ")):
            return ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
    return None


def tap(label, settle=1.5):
    p = find(label)
    if not p:
        print(f"  !! no node labelled {label!r}"); return False
    sh("shell", "input", "tap", str(p[0]), str(p[1])); time.sleep(settle); return True


def shot(name):
    os.makedirs(OUT, exist_ok=True)
    png = os.path.join(OUT, name + ".png")
    open(png, "wb").write(sh("exec-out", "screencap", "-p", binary=True))
    subprocess.run(["sips", "-Z", "900", "-s", "format", "jpeg", "-s", "formatOptions", "55",
                    png, "--out", os.path.join(OUT, name + ".jpg")], capture_output=True)
    return png


def player_nodes():
    return [(tx or cd or rid, b) for tx, cd, rid, b in tree()
            if (tx or cd or "exo" in rid) and b]


def main():
    if not SER:
        raise SystemExit("set AW_PIXEL=host:port (resolve the TLS port via adb mdns services)")
    aid = sys.argv[1] if len(sys.argv) > 1 else "Moonbird_797"
    sh("shell", "am", "force-stop", PKG); time.sleep(1)
    sh("shell", "am", "start", "-a", "android.intent.action.VIEW",
       "-d", f"archivewatch://item/{aid}", PKG)
    for _ in range(10):
        time.sleep(2)
        if find("Play"): break
    print("detail nodes:", [n for n, _ in player_nodes()][:6])
    if not tap("Play", settle=12):
        raise SystemExit("Play button not found on Detail")
    shot("p1_quiet"); print("quiet:", player_nodes())
    sh("shell", "input", "tap", "540", "1300"); time.sleep(1.0)
    shot("p2_controls"); print("controls:", player_nodes())
    if tap("Player options", settle=2.0):
        shot("p3_sheet"); print("sheet:", [n for n, _ in player_nodes()])
        sh("shell", "input", "keyevent", "KEYCODE_BACK"); time.sleep(1)
    sh("shell", "input", "keyevent", "KEYCODE_HOME"); time.sleep(3)
    shot("p4_pip")
    print("pip windows:", re.findall(r"PictureInPicture.*", sh("shell", "dumpsys", "activity", "activities"))[:3])
    sh("shell", "am", "start", "-n", f"{PKG}/app.archivewatch.android.MainActivity"); time.sleep(3)
    sh("shell", "input", "keyevent", "KEYCODE_BACK")
    print("screens in", OUT)


if __name__ == "__main__":
    main()
