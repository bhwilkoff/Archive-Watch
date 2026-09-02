#!/usr/bin/env python3
"""Offline-downloads audit on REAL hardware (Decision 099).

Installs the build, runs `DownloadAudit` on the device (a real archive.org
transfer, a real file, a real AVPlayer decoding it off disk), and then
screenshots the two offline SURFACES and reads them with OCR — because a
console line saying a section rendered is the app reporting on itself, which
is exactly what docs/DEVICE-TESTING.md §4 says not to trust.

    python3 tools/download_audit.py iphone
    python3 tools/download_audit.py ipad
    python3 tools/download_audit.py mac        # the genuinely-offline run

The Mac run is the only one that can sever the network: a physical iPhone
cannot be put into airplane mode from here, so on iOS the offline PROOF is
structural — assert the URL handed to AVFoundation is `file://`, which cannot
reach the network — while the Mac switches Wi-Fi off for real.

Holds the device lease for the WHOLE run in ONE process (docs/DEVICE-TESTING
§2): taking it per invocation left gaps, and another session took the device
in one of them.
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import devlease  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
DEVELOPER_DIR = "/Applications/Xcode-beta.app/Contents/Developer"
ENV = {**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR}
BUNDLE = "app.archivewatch.tvos"
OCR = "/tmp/awocr"
OUT = Path(os.environ.get("AW_DL_OUT", "/tmp/download-audit"))

DEVICES = {
    "iphone": {"udid": "B4E756E2-CBFA-5F63-8CEE-21D226637AF7", "lease": "iphone",
               "name": "iPhone 12"},
    "ipad":   {"udid": "AC5377E9-6053-51DE-8E65-D88A4E9345FA", "lease": "ipad",
               "name": "iPad Pro 12.9"},
}


def run(args, timeout=900, **kw):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                          env=ENV, **kw)


# ---------------------------------------------------------------- build

def build(destination, derived):
    """Build and return the .app path. Greps for the VERDICT, never tails the log
    — a `| tail` once hid a BUILD FAILED and nearly had a fix called verified."""
    scheme = "Archive Watch Mac" if destination == "platform=macOS" else "ArchiveWatch"
    print(f"  building {scheme} for {destination} …")
    r = run(["xcodebuild", "-project", str(REPO / "ArchiveWatch/ArchiveWatch.xcodeproj"),
             "-scheme", scheme, "-destination", destination,
             "-configuration", "Debug", "-derivedDataPath", derived, "build"],
            timeout=1800)
    log = r.stdout + r.stderr
    if "** BUILD SUCCEEDED **" not in log:
        for line in log.splitlines():
            if re.match(r"^(e: |error: )|error: ", line):
                print("   ", line.strip()[:200])
        print("  !! BUILD FAILED")
        return None
    apps = [a for a in sorted(Path(derived, "Build/Products").rglob("*.app"))
            if a.parent.name.startswith("Debug") and "PlugIns" not in str(a)]
    return apps[0] if apps else None


# ---------------------------------------------------------------- device

def install(udid, app):
    r = run(["xcrun", "devicectl", "device", "install", "app", "--device", udid, str(app)])
    ok = "Installed" in (r.stdout + r.stderr) or r.returncode == 0
    print(f"  install: {'ok' if ok else 'FAILED'}")
    return ok


def installed_version(udid):
    """Read the version BACK OFF THE DEVICE. A stale build is invisible and
    explains symptoms it did not cause (the Apple TV sat three builds behind
    through an entire debugging session)."""
    r = run(["xcrun", "devicectl", "device", "info", "apps", "--device", udid,
             "--bundle-id", BUNDLE, "--json-output", "/tmp/awapps.json"])
    try:
        data = json.loads(Path("/tmp/awapps.json").read_text())
        for app in data["result"]["apps"]:
            if app.get("bundleIdentifier") == BUNDLE:
                return app.get("version") or app.get("shortVersionString")
    except Exception:
        pass
    return None


def launch_console(udid, env, seconds, marker="[AWDLAUDIT]"):
    """Launch attached to the console and stream until the SUMMARY line."""
    args = ["xcrun", "devicectl", "device", "process", "launch", "--device", udid,
            "--terminate-existing", "--console", "-e", json.dumps(env), BUNDLE]
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, env=ENV, bufsize=1)
    lines, deadline = [], time.time() + seconds
    try:
        while time.time() < deadline:
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                continue
            if marker in line:
                lines.append(line.rstrip())
                print("   ", line.rstrip())
                if "SUMMARY" in line:
                    break
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    return lines


def shot(udid, name):
    OUT.mkdir(parents=True, exist_ok=True)
    p = OUT / f"{name}.png"
    run(["xcrun", "devicectl", "device", "capture", "screenshot", "--device", udid,
         "--destination", str(p)], timeout=180)
    return p if p.exists() else None


def ocr_text(png):
    if png is None or not Path(OCR).exists():
        return []
    r = run([OCR, str(png)], timeout=180)
    try:
        return [t["text"] for t in
                json.loads(r.stdout.strip().splitlines()[0]).get("allText", [])]
    except Exception:
        return []


# ---------------------------------------------------------------- runs

def device_run(key):
    dev = DEVICES[key]
    udid, name = dev["udid"], dev["name"]
    results = []

    with devlease.lease(dev["lease"], task="offline downloads audit (D099)",
                        ttl=2400, wait=900):
        # iPhone and iPad build the SAME Debug-iphoneos product, so they share
        # one derived-data path — a second full rebuild buys nothing and this
        # dev Mac is an 8 GB machine that is also driving the device.
        dest = f"id={udid}"
        app = build(dest, "/tmp/aw_dl_ios")
        if app is None:
            return [("build", False, "BUILD FAILED")]
        if not install(udid, app):
            return [("install", False, "install failed")]
        version = installed_version(udid)
        expected = version_from_xcconfig()
        results.append(("device.version", version == expected,
                        f"{name} reports {version}, expected {expected}"))

        # A LOCKED device installs fine and refuses to launch, which arrives as
        # an empty console and an empty screenshot — i.e. as several unrelated
        # failures plus two VACUOUS passes (no OCR words means no clipped ones).
        # Name the condition once, here, and stop.
        probe = run(XCRUN + ["device", "process", "launch", "--device", udid,
                             "--terminate-existing", BUNDLE], timeout=180)
        if "Locked" in (probe.stdout + probe.stderr):
            results.append(("device.unlocked", False,
                            f"{name} is LOCKED — devicectl cannot launch on it, and "
                            "entering a passcode is an owner step "
                            "(docs/DEVICE-TESTING.md §7). Unlock it and re-run."))
            return results
        results.append(("device.unlocked", True, f"{name} accepted a launch"))

        print(f"  running the on-device audit on {name} (up to 6 min) …")
        lines = launch_console(udid, {"AW_DOWNLOAD_AUDIT": "1"}, seconds=420)
        results += parse_audit(lines)

        # The SURFACES, judged by OCR rather than by the app's own word — and
        # against a POPULATED list, because an empty section proves nothing
        # about the rows it would draw.
        print("  seeding a download for the UI pass …")
        kept = launch_console(udid, {"AW_DOWNLOAD_AUDIT": "prepare"}, seconds=480)
        kept_line = next((l for l in kept if "KEPT" in l), "")
        seeded = bool(kept_line)
        # The title of the film actually left on the device, so the UI check can
        # assert the ROW rather than the section chrome around it.
        parts = kept_line.split("|")
        kept_title = parts[1].strip() if len(parts) > 2 else ""
        results.append(("ui.seeded", seeded, kept_line.split("] ")[-1][:90]))

        print("  screenshotting the offline surfaces …")
        launch_env = {"AW_START_TAB": "library", "AW_FORCE_OFFLINE": "1"}
        subprocess.run(["xcrun", "devicectl", "device", "process", "launch",
                        "--device", udid, "--terminate-existing",
                        "-e", json.dumps(launch_env), BUNDLE],
                       capture_output=True, text=True, env=ENV, timeout=180)
        time.sleep(16)
        png = shot(udid, f"{key}-library-offline")
        words = ocr_text(png)
        text = " ".join(words).lower()
        # An unreadable capture is a failed observation, not a passing one.
        results.append(("ui.screenshotReadable", len(words) > 3,
                        f"{len(words)} text regions read from {png}"))
        results.append(("ui.offlineBanner", "offline" in text and "still play" in text,
                        f"OCR: {text[:110]}"))
        # The label must be WHOLE. A truncated scope is the defect this rig
        # exists to find, and OCR reads the ellipsis the eye skims past.
        clipped = [w for w in words if "…" in w or w.rstrip(".").lower() == "downloa"]
        results.append(("ui.scopeNotClipped", not clipped,
                        f"clipped labels: {clipped}" if clipped else "all five scopes whole"))
        results.append(("ui.downloadsSection", "downloads" in text,
                        f"screenshot {png}"))
        # Opening on Downloads is the offline promise: with a film present the
        # tab must land THERE, not on an empty Favorites grid.
        results.append(("ui.opensOnDownloads", "no favorites yet" not in text,
                        f"landed on: {text[:110]}"))
        # And the row must render THE FILM that was seeded, not just the section
        # chrome around it — matched on a distinctive word from its own title,
        # so a generic "mb" appearing anywhere on screen cannot carry the check.
        keyword = next((w.lower() for w in kept_title.split()
                        if len(w) > 4 and w.isalpha()), "")
        results.append(("ui.downloadRowRendered",
                        bool(keyword) and keyword in text and "no downloads yet" not in text,
                        f"looked for '{keyword}' from '{kept_title}' in: {text[:100]}"))

        print("  cleaning the device …")
        launch_console(udid, {"AW_DOWNLOAD_AUDIT": "cleanup"}, seconds=120)
    return results


def mac_binary():
    """The app's real executable.

    NOT `glob("*")` on Contents/MacOS: a Debug build also drops
    `__preview.dylib` there for SwiftUI previews, and globbing picked it —
    `OSError: [Errno 8] Exec format error`. Ask Info.plist which file is the
    executable.
    """
    app = build("platform=macOS", "/tmp/aw_dl_mac")
    if app is None:
        return None
    r = subprocess.run(["defaults", "read", str(Path(app, "Contents/Info")),
                        "CFBundleExecutable"], capture_output=True, text=True)
    name = r.stdout.strip() or app.stem
    return Path(app, "Contents/MacOS", name)


# THE severing. `networksetup -setairportpower en0 off` was the first idea and
# is a trap: this Mac's default route IS en0, so it would cut the agent session
# driving the test — with no way left to switch it back on. `sandbox-exec` denies
# the network to ONE PROCESS instead, which is both safer and a better
# experiment: the machine stays connected, so a pass cannot be explained by the
# network having been down for unrelated reasons.
#
# Verified before use: `curl` unsandboxed answers 200, the same curl under this
# profile cannot even resolve the host.
DENY_NET = ["sandbox-exec", "-p", "(version 1)(allow default)(deny network*)"]


def run_mac_audit(binary, mode, seconds=420, deny_network=False):
    """Launch the Mac app in an audit mode and stream its verdicts."""
    env = {**ENV, "AW_DOWNLOAD_AUDIT": mode}
    args = [str(binary)]
    if deny_network:
        args = DENY_NET + args
        env["AW_OFFLINE_KIND"] = "sockets"
    proc = subprocess.Popen(args, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, env=env, bufsize=1)
    lines, deadline = [], time.time() + seconds
    try:
        while time.time() < deadline:
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                continue
            if "[AWDLAUDIT]" in line:
                lines.append(line.rstrip())
                print("   ", line.rstrip())
                if "SUMMARY" in line:
                    break
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    return lines


def mac_run():
    """THE genuinely-severed run, and the machine stays online throughout.

    Phase 2 runs the app under a profile that denies it the network entirely,
    so "it played" cannot be a stream that was quietly still working. The audit
    carries its own negative control on top of that.
    """
    binary = mac_binary()
    if binary is None:
        return [("build", False, "BUILD FAILED")]

    print("  phase 1/3 — download a film (network up) and leave it on disk …")
    results = [(f"prepare.{n}", ok, d)
               for n, ok, d in parse_audit(run_mac_audit(binary, "prepare"))]
    if any(not ok for _, ok, _ in results):
        run_mac_audit(binary, "cleanup", seconds=90)
        return results

    try:
        print("  phase 2/3 — relaunch with the network DENIED to the process …")
        results += parse_audit(run_mac_audit(binary, "offline", seconds=300,
                                             deny_network=True))
    finally:
        print("  phase 3/3 — clean up …")
        run_mac_audit(binary, "cleanup", seconds=120)
    return results


def parse_audit(lines):
    out = []
    for line in lines:
        m = re.search(r"\[AWDLAUDIT\] (PASS|FAIL) (\S+) — (.*)", line)
        if m:
            out.append((m.group(2), m.group(1) == "PASS", m.group(3)))
    if not any(l for l in lines if "SUMMARY" in l):
        out.append(("audit.completed", False, "no SUMMARY line — the run did not finish"))
    return out


def version_from_xcconfig():
    text = (REPO / "AppVersion.xcconfig").read_text()
    return re.search(r"^MARKETING_VERSION = (\S+)", text, re.M).group(1)


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "iphone"
    print(f"== offline downloads audit: {target} ==")
    results = mac_run() if target == "mac" else device_run(target)
    print()
    failed = [r for r in results if not r[1]]
    for name, ok, detail in results:
        print(f"  {'PASS' if ok else 'FAIL'} {name} — {detail}")
    print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
