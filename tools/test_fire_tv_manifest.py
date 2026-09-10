#!/usr/bin/env python3
"""
test_fire_tv_manifest.py — locks the Fire TV manifest gate.

Every case is drawn from the real aapt2 badging of the two APKs in the
2026-09-10 incident: `vc49` (minSdk 29), which the Amazon Appstore hid from
every Fire OS 7 device while users reported "incompatible", and `vc50`
(minSdk 23), the fix that had been built five weeks earlier and never
uploaded. The first case is the NEGATIVE CONTROL — the good binary must
still pass, or a gate that rejects everything would look like a working one.

Run:  python tools/test_fire_tv_manifest.py
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

from audit_fire_tv_manifest import findings_from_badging  # noqa: E402

CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


GOOD = """package: name='com.archivewatch.app' versionCode='50' versionName='1.42.6' compileSdkVersionCodename='17'
minSdkVersion:'23'
targetSdkVersion:'36'
application-label:'Archive Watch'
leanback-launchable-activity: name='app.archivewatch.android.MainActivity'
  uses-feature-not-required: name='android.hardware.touchscreen'
  uses-feature-not-required: name='android.software.leanback'
supports-screens: 'small' 'normal' 'large' 'xlarge'
native-code: 'arm64-v8a' 'armeabi-v7a' 'x86' 'x86_64'
"""


def variant(**edits) -> str:
    out = GOOD
    for old, new in edits.items():
        out = out.replace(old.replace("__", " "), new)
    return out


def main() -> int:
    # 1. the control: the fix that should have shipped
    check("control: the vc50 shape (minSdk 23) ships", findings_from_badging(GOOD), [])

    # 2. THE INCIDENT: minSdk 29 hides every Fire OS 7 device
    bad = GOOD.replace("minSdkVersion:'23'", "minSdkVersion:'29'")
    f = findings_from_badging(bad)
    check("minSdk 29 is a finding", len(f), 1)
    check("the finding names Fire OS 7", "Fire OS 7" in f[0], True)
    check("minSdk 28 (Fire OS 7 itself) is allowed",
          findings_from_badging(GOOD.replace("minSdkVersion:'23'", "minSdkVersion:'28'")), [])

    # 3. a REQUIRED feature removes the TV form factor
    req = GOOD.replace("  uses-feature-not-required: name='android.hardware.touchscreen'",
                       "  uses-feature: name='android.hardware.touchscreen'")
    f = findings_from_badging(req)
    check("a required touchscreen is a finding", len(f), 1)
    check("the finding names the feature", "touchscreen" in f[0], True)

    # 4. ABIs: Fire TV ships 32- and 64-bit userspaces
    check("dropping armeabi-v7a is a finding",
          len(findings_from_badging(GOOD.replace(
              "native-code: 'arm64-v8a' 'armeabi-v7a' 'x86' 'x86_64'",
              "native-code: 'arm64-v8a'"))), 1)
    check("no native code at all is fine (any ABI runs it)",
          findings_from_badging("\n".join(
              l for l in GOOD.splitlines() if not l.startswith("native-code"))), [])

    # 5. a TV app needs a leanback launcher
    check("no leanback launcher is a finding",
          len(findings_from_badging("\n".join(
              l for l in GOOD.splitlines()
              if "leanback-launchable-activity" not in l))), 1)

    # 6. a preview platform is a shape no store guarantees to accept
    check("a codename compileSdk is a finding",
          len(findings_from_badging(GOOD.replace(
              "compileSdkVersionCodename='17'", "compileSdkVersionCodename='Baklava'"))), 1)
    check("a numbered compileSdk is not", findings_from_badging(GOOD), [])

    bad = 0
    for name, ok, got, want in CASES:
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            bad += 1
            print(f"      got:  {got!r}\n      want: {want!r}")
    print(f"\n{len(CASES) - bad}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
