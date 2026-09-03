#!/usr/bin/env python3
"""Roku device harness — deploy, drive, and OBSERVE the channel on real hardware.

The owner's rule for this repo is that a platform is verified on the glass, never
by the app's own report (see docs/DEVICE-TESTING.md and the tvOS/Android
harnesses this one is modelled on). Roku gives us four channels, and this file
wraps all four so a run is one command:

  deploy   sideload a zip of roku/ via the developer web installer (digest auth)
  keys     press remote keys over ECP  (Home, Up, Down, Left, Right, Select, Back, …)
  type     enter text a character at a time through ECP Lit_ codes
  shot     pull a screenshot of the RUNNING DEV CHANNEL as a PNG/JPEG
  log      capture the BrightScript debug console (telnet 8085) for N seconds
  launch   launch the dev channel, optionally with deep-link params
  info     device-info, active-app, and the ECP mode

MEASURED CONSTRAINTS on this device (Streaming Stick 4K, Roku OS 15.3.4):

* **ECP must be PERMISSIVE.** With `ecp-setting-mode` = `limited`, `/keypress`
  returns **403** and `/query/apps` refuses outright, while `/query/device-info`
  and `/query/active-app` still answer — so a naive reachability check passes
  while every input is silently rejected. `info` prints the mode for exactly
  this reason. The setting lives on the device at
  Settings → System → Advanced system settings → Control by mobile apps →
  Network access → Permissive.
* **The screenshot utility only captures a sideloaded DEV channel.** With no dev
  channel installed it answers "Screenshot not ok" and `/pkgs/dev.jpg` 404s.
  That is not a broken harness; it means there is nothing of ours on screen.
* The debug console on 8085 is a plain telnet stream with NO request/response —
  it emits whatever the channel prints. It is our logcat, and the only way to
  read what the channel thinks it is doing.

Usage:
  python3 tools/roku.py info
  python3 tools/roku.py deploy [--dir roku]
  python3 tools/roku.py keys Home Down Down Select
  python3 tools/roku.py type "sherlock"
  python3 tools/roku.py shot NAME
  python3 tools/roku.py log 20
  python3 tools/roku.py launch [--params 'contentId=abc&mediaType=movie']

Env: AW_ROKU_HOST (default 10.0.0.155), AW_ROKU_PASS (default 8536).
"""
import argparse
import datetime
import io
import os
import socket
import subprocess
import sys
import time
import urllib.parse
import zipfile

HOST = os.environ.get("AW_ROKU_HOST", "10.0.0.155")
USER = os.environ.get("AW_ROKU_USER", "rokudev")
PASS = os.environ.get("AW_ROKU_PASS", "8536")
ECP = f"http://{HOST}:8060"
DEV = f"http://{HOST}"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QA_DIR = os.path.join(REPO, "build", "qa", f"roku-{datetime.date.today().isoformat()}")

# ECP key names we use. Roku also accepts Lit_<urlencoded char> for text.
KEYS = {"home": "Home", "rev": "Rev", "fwd": "Fwd", "play": "Play", "select": "Select",
        "left": "Left", "right": "Right", "down": "Down", "up": "Up", "back": "Back",
        "instantreplay": "InstantReplay", "info": "Info", "backspace": "Backspace",
        "search": "Search", "enter": "Enter", "star": "Info"}


def curl(*args, timeout=30, binary=False):
    r = subprocess.run(["curl", "-s", "--max-time", str(timeout), *args],
                       capture_output=True, timeout=timeout + 15)
    return r.stdout if binary else r.stdout.decode(errors="replace")


def dev_curl(*args, timeout=60, binary=False):
    """The developer web installer speaks HTTP DIGEST auth, not basic."""
    return curl("--digest", "-u", f"{USER}:{PASS}", *args, timeout=timeout, binary=binary)


# ------------------------------------------------------------------ commands

def cmd_info(_args):
    xml = curl(f"{ECP}/query/device-info")
    keep = ("model-name", "software-version", "ui-resolution", "ecp-setting-mode",
            "developer-enabled", "power-mode", "user-device-location")
    for line in xml.splitlines():
        tag = line.strip().lstrip("<").split(">")[0]
        if tag in keep:
            print(line.strip())
    mode = "permissive" if "<ecp-setting-mode>permissive" in xml else "LIMITED"
    if mode != "permissive":
        print("\n!! ECP is not permissive — /keypress will 403 and this harness cannot")
        print("   drive the remote. Settings > System > Advanced system settings >")
        print("   Control by mobile apps > Network access > Permissive")
    print("\nactive-app:", curl(f"{ECP}/query/active-app").replace("\n", " ")[:220])


def zip_channel(src_dir):
    """Zip the channel with the manifest at the ARCHIVE ROOT.

    Roku rejects a zip whose manifest sits inside a top-level folder — the
    installer reports a vague failure rather than naming the cause, so build
    the archive by walking the directory rather than zipping the folder.
    """
    buf = io.BytesIO()
    src = os.path.join(REPO, src_dir)
    if not os.path.isfile(os.path.join(src, "manifest")):
        raise SystemExit(f"no manifest at {src}/manifest — Roku needs it at the zip root")
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(src):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for f in files:
                if f.startswith(".") or f.endswith((".swp", ".orig")):
                    continue
                full = os.path.join(root, f)
                z.write(full, os.path.relpath(full, src))
    return buf.getvalue()


def cmd_deploy(args):
    blob = zip_channel(args.dir)
    tmp = "/tmp/aw-roku.zip"
    open(tmp, "wb").write(blob)
    print(f"packaged {args.dir} → {len(blob)/1024:.0f} KB")
    # "Replace" upgrades in place; "Install" is only correct on a clean device,
    # and using it over an existing dev channel is a common source of a deploy
    # that silently does nothing.
    out = dev_curl("-F", "mysubmit=Replace", "-F", f"archive=@{tmp}",
                   "-F", f"passwd={PASS}", f"{DEV}/plugin_install", timeout=180)
    low = out.lower()
    if "successful" in low or "received" in low:
        print("deploy OK")
    elif "identical" in low:
        print("deploy OK (identical to what is installed)")
    else:
        # Roku returns 200 with the failure INSIDE the page; never trust the code.
        msgs = [ln.strip() for ln in out.splitlines()
                if "error" in ln.lower() or "fail" in ln.lower()]
        print("DEPLOY FAILED:", (msgs[:4] or [out[:400]]))
        sys.exit(1)


def press(key, settle=0.9):
    name = KEYS.get(key.lower(), key)
    code = curl("-o", "/dev/null", "-w", "%{http_code}", "-X", "POST",
                f"{ECP}/keypress/{name}").strip()
    if code != "200":
        raise SystemExit(f"keypress {name} → HTTP {code} (is ECP permissive?)")
    time.sleep(settle)


def cmd_keys(args):
    for k in args.keys:
        press(k, settle=args.settle)
        print("pressed", k)


def cmd_type(args):
    for ch in args.text:
        press("Lit_" + urllib.parse.quote(ch), settle=0.35)
    print(f"typed {args.text!r}")


def cmd_shot(args):
    os.makedirs(QA_DIR, exist_ok=True)
    page = dev_curl("-F", "mysubmit=Screenshot", "-F", "archive=",
                    "-F", f"passwd={PASS}", f"{DEV}/plugin_inspect", timeout=90)
    if "Screenshot ok" not in page:
        print("screenshot not taken — is a DEV channel installed and running?")
        sys.exit(1)
    raw = dev_curl(f"{DEV}/pkgs/dev.jpg", timeout=90, binary=True)
    if len(raw) < 4000:
        print(f"screenshot came back empty ({len(raw)} bytes)")
        sys.exit(1)
    path = os.path.join(QA_DIR, args.name + ".jpg")
    open(path, "wb").write(raw)
    print(path, f"{len(raw)/1024:.0f} KB")


def cmd_log(args):
    """Drain the BrightScript console for N seconds. It is a push-only stream:
    nothing is sent, and whatever the channel printed arrives as it happens."""
    os.makedirs(QA_DIR, exist_ok=True)
    path = os.path.join(QA_DIR, "console.log")
    deadline = time.time() + args.seconds
    got = []
    try:
        s = socket.create_connection((HOST, 8085), timeout=5)
    except OSError as e:
        raise SystemExit(f"cannot reach the debug console on {HOST}:8085 — {e}")
    s.settimeout(2)
    while time.time() < deadline:
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        text = chunk.decode(errors="replace")
        got.append(text)
        sys.stdout.write(text)
        sys.stdout.flush()
    s.close()
    with open(path, "a") as f:
        f.write("".join(got))


def cmd_launch(args):
    app = args.app or "dev"
    url = f"{ECP}/launch/{app}"
    if args.params:
        url += "?" + args.params
    code = curl("-o", "/dev/null", "-w", "%{http_code}", "-X", "POST", url).strip()
    print(f"launch {app} → HTTP {code}")
    if code != "200":
        sys.exit(1)
    time.sleep(args.settle)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info").set_defaults(fn=cmd_info)
    d = sub.add_parser("deploy"); d.add_argument("--dir", default="roku"); d.set_defaults(fn=cmd_deploy)
    k = sub.add_parser("keys"); k.add_argument("keys", nargs="+")
    k.add_argument("--settle", type=float, default=0.9); k.set_defaults(fn=cmd_keys)
    t = sub.add_parser("type"); t.add_argument("text"); t.set_defaults(fn=cmd_type)
    s = sub.add_parser("shot"); s.add_argument("name"); s.set_defaults(fn=cmd_shot)
    l = sub.add_parser("log"); l.add_argument("seconds", type=int, nargs="?", default=15)
    l.set_defaults(fn=cmd_log)
    la = sub.add_parser("launch"); la.add_argument("--app", default="dev")
    la.add_argument("--params", default=""); la.add_argument("--settle", type=float, default=6)
    la.set_defaults(fn=cmd_launch)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
