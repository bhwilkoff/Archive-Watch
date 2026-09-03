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
import re
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


def installer_messages(html):
    """Roku's real verdict lives in a JSON blob the page hands its own JS.

    Scraping the rendered HTML does not work: the page's JavaScript contains
    the words "error" and "success" in a comment, so any substring test over
    the raw response is true no matter what happened. Each message carries its
    own `type`, and that is the only trustworthy signal.
    """
    out = []
    for m in re.finditer(r'\{"text":"((?:[^"\\]|\\.)*)","text_type":"[^"]*","type":"([a-z]+)"\}', html):
        text = m.group(1).encode().decode("unicode_escape").strip()
        out.append((m.group(2), text))
    return out


def post_install(submit, zip_path=None):
    args = ["-F", f"mysubmit={submit}", "-F", f"passwd={PASS}"]
    args += ["-F", f"archive=@{zip_path}"] if zip_path else ["-F", "archive="]
    return dev_curl(*args, f"{DEV}/plugin_install", timeout=180)


def cmd_deploy(args):
    blob = zip_channel(args.dir)
    tmp = "/tmp/aw-roku.zip"
    open(tmp, "wb").write(blob)
    print(f"packaged {args.dir} → {len(blob)/1024:.0f} KB")

    out = post_install("Replace", tmp)
    msgs = installer_messages(out)
    # "Identical to previous version -- not replacing" compares against the
    # last UPLOAD, not the last successful INSTALL — so after a compile failure
    # a corrected build can be refused as identical while nothing is installed
    # at all. Delete and install fresh when that happens.
    if any("identical" in t.lower() for _, t in msgs):
        print("   (identical upload refused — deleting and installing fresh)")
        post_install("Delete")
        out = post_install("Install", tmp)
        msgs = installer_messages(out)

    errors = [t for kind, t in msgs if kind == "error"]
    if errors:
        print("DEPLOY FAILED:")
        for t in errors:
            for line in t.splitlines():
                if line.strip():
                    print("   ", line.strip())
        sys.exit(1)
    for kind, t in msgs:
        print("   ", t)
    print("deploy OK")


def cmd_playstate(_args):
    """Roku's OWN account of playback — the trustworthy oracle.

    A screenshot cannot prove a film is playing: on several Roku SoCs the video
    plane is not composited into `screencap`, so a black frame means nothing.
    `/query/media-player` reports the state, the codec, and a position that has
    to ADVANCE between samples, which is the only claim worth making.
    """
    import xml.etree.ElementTree as ET
    prev = None
    for i in range(3):
        xml = curl(f"{ECP}/query/media-player")
        try:
            root = ET.fromstring(xml)
        except Exception:
            print("media-player unavailable:", xml[:120]); return
        state = root.get("state"); err = root.get("error")
        posn = (root.findtext("position") or "?").strip()
        dur = (root.findtext("duration") or "?").strip()
        fmt_el = root.find("format")
        codec = f"{fmt_el.get('video')}/{fmt_el.get('audio')} {fmt_el.get('video_res')}" if fmt_el is not None else "?"
        moved = "" if prev is None else ("  advanced" if posn != prev else "  STALLED")
        print(f"state={state} error={err} position={posn} duration={dur} [{codec}]{moved}")
        prev = posn
        if i < 2:
            time.sleep(5)


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
    sub.add_parser("playstate").set_defaults(fn=cmd_playstate)
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
