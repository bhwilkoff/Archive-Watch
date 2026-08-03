#!/usr/bin/env python3
"""Fire TV readiness audit — assert the Android build has ZERO Google Play
Services / Firebase dependencies.

Fire OS is an Android fork WITHOUT Google Play Services. Any GMS dependency
(Google sign-in, Maps, FCM, Play Billing, and above all **Cast**) fails at
runtime on a Fire TV device — usually as a crash on first use, not a build
error, which is why this has to be a gate rather than a code review.

Archive Watch is in the best possible position: as measured 2026-08-03 the
dependency set is entirely GMS-free (OkHttp, kotlinx-serialization, Coil,
Media3, androidx.sqlite). This script exists to KEEP it that way — the moment
the Cast sender lands (backlog C4) it must be excluded from the Fire variant,
and a silent transitive GMS pull would otherwise go unnoticed until a device
test (docs/TV-DESIGN.md §6.6, Decision 047).

Usage:
    python3 tools/audit_fire_tv_gms.py [path/to/app.apk|.aab]

Exits non-zero if any GMS/Firebase code is present.
"""

from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

# Package prefixes that only exist when Play Services is linked in.
GMS_PREFIXES = (
    "com/google/android/gms/",
    "com/google/firebase/",
    "com/google/android/play/core/",
)

# Version-catalog coordinates that pull GMS. Checked separately so the failure
# names the dependency, not just a class file.
GMS_COORDS = re.compile(
    r"com\.google\.android\.gms|com\.google\.firebase|"
    r"com\.google\.android\.play:core|play-services-|firebase-",
    re.I,
)

DEFAULT_CANDIDATES = [
    "android/app/build/outputs/bundle/release/app-release.aab",
    "android/app/build/outputs/apk/release/app-release.apk",
    "android/app/build/outputs/apk/debug/app-debug.apk",
]

CATALOG = Path("android/gradle/libs.versions.toml")
BUILD_FILE = Path("android/app/build.gradle.kts")


def check_sources() -> list[str]:
    """Declared dependencies — catches a GMS coordinate before it is ever built."""
    hits = []
    for path in (CATALOG, BUILD_FILE):
        if not path.exists():
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            stripped = line.strip()
            # Skip comments — this file's own prose mentions the packages.
            if stripped.startswith("#") or stripped.startswith("//"):
                continue
            if GMS_COORDS.search(line):
                hits.append(f"{path}:{n}: {stripped}")
    return hits


def check_artifact(target: Path) -> list[str]:
    """Compiled output — catches a TRANSITIVE pull no coordinate names."""
    zf = zipfile.ZipFile(target)
    found = set()
    for name in zf.namelist():
        if not name.endswith(".dex"):
            continue
        blob = zf.read(name)
        for prefix in GMS_PREFIXES:
            # DEX stores type descriptors as Lcom/google/...; a plain substring
            # search over the raw dex is enough to detect presence.
            if prefix.encode() in blob:
                found.add(prefix)
    return sorted(found)


def main() -> int:
    print("Fire TV GMS audit (docs/TV-DESIGN.md §6.6)\n")

    failed = False

    declared = check_sources()
    if declared:
        failed = True
        print("FAIL: GMS/Firebase coordinates declared:")
        for h in declared:
            print(f"  - {h}")
    else:
        print("OK: no GMS/Firebase coordinates declared in the build files.")

    if len(sys.argv) > 1:
        target = Path(sys.argv[1])
    else:
        target = next((Path(p) for p in DEFAULT_CANDIDATES if Path(p).exists()), None)

    if target is None:
        print("\nNOTE: no build output found; source check only.")
        print("Build first for the stronger transitive check:")
        print("  cd android && ./gradlew assembleRelease")
    else:
        print(f"\nScanning {target} …")
        present = check_artifact(target)
        if present:
            failed = True
            print("FAIL: GMS/Firebase classes present in the compiled output:")
            for p in present:
                print(f"  - {p}")
            print("\nThese crash on Fire OS. If this arrived with the Cast sender,")
            print("exclude Cast from the Fire variant (backlog C4/A24).")
        else:
            print("OK: no GMS/Firebase classes in the compiled output.")

    if failed:
        return 1
    print("\nPASS: the build is Fire TV-safe (zero Play Services dependency).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
