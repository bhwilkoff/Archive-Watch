#!/usr/bin/env python3
"""
audit_fire_tv_manifest.py — the Fire TV APK reaches Fire OS 7, or it does not
ship.

THE INCIDENT THIS EXISTS FOR (2026-09-10). Users reported Archive Watch as
"incompatible" on a Fire TV Stick 4K Max, on Fire Cubes and on several sticks.
Nothing was wrong with the app: the LIVE Amazon binary was `vc49` (1.3.485),
built before Decision 100 lowered the amazon flavor's floor, and it declares
**minSdkVersion 29**. Fire OS 7 is Android 9 — **API 28** — so every Fire OS 7
device in the fleet was filtered out by the store before a download could
start. Amazon's own Target-your-app page said so in one line that nobody was
reading: **Fire TV (98) — 38 selected**.

The fix (minSdk 23) had been built as `vc50` five weeks earlier and was never
uploaded. A fix that is not published is not a fix, and the store's device
count is the only place that difference is visible.

WHAT IS CHECKED, and why each one filters a device out of the Appstore:
  * minSdk <= 28              — anything higher loses the whole Fire OS 7
                                generation (Sticks, Cubes, most TV Editions).
  * every <uses-feature> optional — a required feature a TV lacks (touchscreen
                                above all) removes the TV form factor entirely.
  * armeabi-v7a AND arm64-v8a — Fire TV ships both 32- and 64-bit userspaces.
  * a leanback launcher activity — without one the app cannot appear on a TV.
  * not built against a PREVIEW platform — a canary compileSdk is a shape no
                                store guarantees to accept.

WHERE IT RUNS: `tools/submit-amazon.py` calls it before an upload can happen,
so a binary that would repeat the incident cannot be sent at all. Run it by
hand against any APK:

    python3 tools/audit_fire_tv_manifest.py path/to/app-amazon-release.apk

Exits non-zero on any finding. If the Android SDK's aapt2 cannot be found it
FAILS rather than passing — a check that cannot read must never look like a
check that passed (Decision 108).
"""

from __future__ import annotations

import glob
import os
import re
import subprocess
import sys
from pathlib import Path

# Fire OS -> Android API. Fire OS 7 is the generation the 2026-09-10 incident
# lost; it is still the majority of the installed Fire TV base.
FIRE_OS = {5: 22, 6: 25, 7: 28, 8: 30}
MAX_MIN_SDK = FIRE_OS[7]
NEEDED_ABIS = ("armeabi-v7a", "arm64-v8a")


def find_aapt2() -> str | None:
    roots = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"),
             str(Path.home() / "Library/Android/sdk"), "/usr/local/share/android-sdk"]
    for r in roots:
        if not r:
            continue
        hits = sorted(glob.glob(os.path.join(r, "build-tools", "*", "aapt2")))
        if hits:
            return hits[-1]
    return None


def badging(apk: str) -> str:
    tool = find_aapt2()
    if not tool:
        raise RuntimeError(
            "aapt2 not found (set ANDROID_HOME) — refusing to report a pass "
            "on a manifest this tool could not read")
    r = subprocess.run([tool, "dump", "badging", apk],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"aapt2 could not read {apk}: {r.stderr.strip()[:200]}")
    return r.stdout


def audit(apk: str) -> list:
    """Return a list of findings; empty means the APK may ship."""
    return findings_from_badging(badging(apk))


def findings_from_badging(out: str) -> list:
    """The rules, over aapt2's badging text. Split out so the gate is testable
    without an APK fixture (tools/test_fire_tv_manifest.py)."""
    findings = []

    m = re.search(r"minSdkVersion:'(\d+)'", out)
    if not m:
        findings.append("no minSdkVersion in the manifest")
    else:
        lo = int(m.group(1))
        if lo > MAX_MIN_SDK:
            worst = [f"Fire OS {v}" for v, api in sorted(FIRE_OS.items()) if api < lo]
            findings.append(
                f"minSdk {lo} > {MAX_MIN_SDK}: the Appstore hides this build from "
                f"{', '.join(worst)} devices (the 2026-09-10 incident)")

    required = re.findall(r"^\s*uses-feature: name='([^']+)'", out, re.M)
    for feat in required:
        findings.append(f"<uses-feature> {feat} is REQUIRED — every device "
                        f"without it is filtered out; declare required=\"false\"")

    native = re.search(r"native-code: (.+)", out)
    have = set(re.findall(r"'([^']+)'", native.group(1))) if native else set()
    if have:                       # no native code at all is fine: any ABI runs it
        for abi in NEEDED_ABIS:
            if abi not in have:
                findings.append(f"native code lacks {abi} — Fire TV ships both "
                                f"32- and 64-bit userspaces (have: {sorted(have)})")

    if "leanback-launchable-activity" not in out:
        findings.append("no leanback launcher activity — the app cannot appear "
                        "on a TV home screen")

    codename = re.search(r"compileSdkVersionCodename='([^']+)'", out)
    if codename and not codename.group(1).isdigit():
        findings.append(f"built against a PREVIEW platform "
                        f"(compileSdkVersionCodename={codename.group(1)})")

    return findings


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: audit_fire_tv_manifest.py path/to.apk", file=sys.stderr)
        return 2
    apk = sys.argv[1]
    if not os.path.exists(apk):
        print(f"no such APK: {apk}", file=sys.stderr)
        return 2
    try:
        findings = audit(apk)
    except RuntimeError as e:
        print(f"[fire-tv] CANNOT CHECK: {e}", file=sys.stderr)
        return 1
    if findings:
        print(f"[fire-tv] {os.path.basename(apk)} would lose devices:", file=sys.stderr)
        for f in findings:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print(f"[fire-tv] {os.path.basename(apk)}: reaches Fire OS 7+, all ABIs, "
          f"no required features, leanback launcher — OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
