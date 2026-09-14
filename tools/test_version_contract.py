#!/usr/bin/env python3
"""
AppVersion.xcconfig is the ONE version number (Decision 101) — including on
Android.

The Android build carried `versionName = "1.42.6"` under a comment saying it
"tracks the Apple apps (AppVersion.xcconfig)". Nothing read that file, so the
literal drifted 88 patch versions behind: for weeks an Android user reporting a
problem named a version family that no longer existed, and a crash cluster on
1.42.6 could not be matched to the code that produced it.

The build now READS the file, which makes drift impossible by construction.
This guards the construction — someone typing a literal back in is exactly how
it happened the first time.

Run: python3 tools/test_version_contract.py   (exit 0 = pass)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fails = []


def check(ok, what, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {what}" + (f"  — {detail}" if detail and not ok else ""))
    if not ok:
        fails.append(what)


xc = (ROOT / "AppVersion.xcconfig").read_text()
m = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", xc, re.M)
check(m is not None, "AppVersion.xcconfig declares MARKETING_VERSION")
marketing = m.group(1) if m else ""

gradle = (ROOT / "android/app/build.gradle.kts").read_text()

check("versionName = marketingVersion" in gradle,
      "Android takes versionName from the shared file, not a literal")

# A literal would look like versionName = "1.2.3". Anything quoted is the bug.
lit = re.search(r'versionName\s*=\s*"', gradle)
check(lit is None, "...and no quoted versionName literal has crept back",
      lit.group(0) if lit else "")

check(re.search(r'rootProject\.file\("\.\./AppVersion\.xcconfig"\)', gradle) is not None,
      "...reading the file the Apple targets use")

# The read must FAIL rather than fall back: a default would restore the drift
# silently, which is the failure mode this whole file exists for.
check("error(" in gradle and "MARKETING_VERSION not found" in gradle,
      "a missing MARKETING_VERSION fails the build rather than defaulting")

print(f"\nmarketing version = {marketing}")
print(f"{len(fails)} failed" if fails else "all passed")
sys.exit(1 if fails else 0)
