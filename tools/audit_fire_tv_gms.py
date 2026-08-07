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

# The AMAZON variant is the one that must be clean — the google variant is
# SUPPOSED to contain Cast. Prefer amazon artifacts; fall back to unflavored
# ones for older builds.
DEFAULT_CANDIDATES = [
    "android/app/build/outputs/bundle/amazonRelease/app-amazon-release.aab",
    "android/app/build/outputs/apk/amazon/release/app-amazon-release.apk",
    "android/app/build/outputs/apk/amazon/debug/app-amazon-debug.apk",
    "android/app/build/outputs/bundle/release/app-release.aab",
    "android/app/build/outputs/apk/release/app-release.apk",
    "android/app/build/outputs/apk/debug/app-debug.apk",
]

# Negative control: the google variant must CONTAIN what amazon must not.
GOOGLE_CANDIDATES = [
    "android/app/build/outputs/bundle/googleRelease/app-google-release.aab",
    "android/app/build/outputs/apk/google/release/app-google-release.apk",
    "android/app/build/outputs/apk/google/debug/app-google-debug.apk",
]

# Each is load-bearing for casting: the framework, our receiver registration,
# the system route button, and the registered receiver's App ID.
GOOGLE_EXPECTED = [
    "com/google/android/gms/cast/framework",
    "CastOptionsProvider",
    "androidx/mediarouter/app/MediaRouteButton",
    "58AF34C3",
]

CATALOG = Path("android/gradle/libs.versions.toml")
BUILD_FILE = Path("android/app/build.gradle.kts")


# A GMS dependency is only dangerous for Fire TV when a configuration that
# reaches the AMAZON variant consumes it. `googleImplementation(...)` is
# correct and expected once the store flavors exist.
GOOGLE_SCOPED = re.compile(r'^\s*"?google[A-Za-z]*"?\s*\(')


def check_sources() -> list[str]:
    """Declared dependencies that would reach the amazon variant.

    NOTE: a coordinate sitting in the version catalog links NOTHING — only a
    dependency *configuration* does. So the catalog is ignored and the build
    file is checked for GMS pulled in on a configuration that is not scoped to
    the google flavor.
    """
    hits = []
    if not BUILD_FILE.exists():
        return hits
    for n, line in enumerate(BUILD_FILE.read_text().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("#"):
            continue
        if not GMS_COORDS.search(line) and "cast" not in line.lower():
            continue
        # Is it a dependency line at all, and is it google-scoped?
        if "(" not in stripped:
            continue
        if GOOGLE_SCOPED.match(line):
            continue          # googleImplementation(...) — correct
        if GMS_COORDS.search(line) or "libs.play.services" in line or "media3.cast" in line:
            hits.append(f"{BUILD_FILE}:{n}: {stripped}")
    return hits


def mapping_for(target: Path) -> Path | None:
    """The R8 mapping for a build output, if that variant was minified.

    Release builds run R8 with `isMinifyEnabled = true`, which RENAMES library
    classes — `androidx.mediarouter.app.MediaRouteButton` becomes `x62`. A raw
    dex substring search therefore reports a class as ABSENT when it is merely
    renamed, and this audit false-FAILED its own negative control the first time
    it was pointed at a release artifact (it had only ever seen debug builds,
    where nothing is renamed). Worse in the other direction: a renamed GMS class
    would slip past the amazon check as a false PASS. The mapping file records
    every ORIGINAL name verbatim, so it is the reliable index for a minified
    artifact.

    android/app/build/outputs/{bundle/googleRelease/x.aab, apk/google/release/…}
      → android/app/build/outputs/mapping/googleRelease/mapping.txt
    """
    parts = target.parts
    if "outputs" not in parts:
        return None
    base = Path(*parts[: parts.index("outputs") + 1])
    variant = target.parent.name                      # e.g. googleRelease
    cands = [base / "mapping" / variant / "mapping.txt"]
    # apk/google/release/… → the variant is the two path segments joined
    if len(parts) >= 3 and target.parent.name in ("release", "debug"):
        flavor = target.parent.parent.name
        cands.append(base / "mapping" / f"{flavor}{target.parent.name.capitalize()}"
                     / "mapping.txt")
    return next((c for c in cands if c.exists()), None)


def check_present(target: Path, expected: list[str]) -> list[str]:
    """Inverse of check_artifact: return the expected markers that are ABSENT.

    Searches the dex AND, when the variant was minified, the R8 mapping's
    original names — otherwise renaming reads as removal (see mapping_for)."""
    zf = zipfile.ZipFile(target)
    blob = b"".join(zf.read(n) for n in zf.namelist() if n.endswith(".dex"))
    mapping = mapping_for(target)
    mtext = mapping.read_text(errors="ignore") if mapping else ""
    missing = []
    for e in expected:
        if e.encode() in blob:
            continue
        # Mapping records dotted original names ("androidx.mediarouter.app.X -> a:").
        if mtext and e.replace("/", ".") in mtext:
            continue
        missing.append(e)
    return missing


def check_artifact(target: Path) -> list[str]:
    """Compiled output — catches a TRANSITIVE pull no coordinate names.

    Checks the R8 mapping too when the variant was minified: a GMS class that
    R8 renamed would otherwise pass this audit while still shipping on Fire OS.
    """
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
    mapping = mapping_for(target)
    if mapping:
        mtext = mapping.read_text(errors="ignore")
        for prefix in GMS_PREFIXES:
            if prefix.replace("/", ".") in mtext:
                found.add(prefix)
    return sorted(found)


def main() -> int:
    print("Fire TV GMS audit (docs/TV-DESIGN.md §6.6)\n")

    failed = False

    declared = check_sources()
    if declared:
        failed = True
        print("FAIL: GMS/Firebase reaching the amazon variant:")
        for h in declared:
            print(f"  - {h}")
    else:
        print("OK: no un-flavor-scoped GMS dependency (googleImplementation is fine).")

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

    # NEGATIVE CONTROL. "amazon has no Cast" passes trivially if Cast was
    # removed from BOTH flavors — the audit would go green while casting was
    # silently dead everywhere. So assert the google artifact DOES carry Cast.
    # A test that cannot fail is not a test.
    google = next((Path(p) for p in GOOGLE_CANDIDATES if Path(p).exists()), None)
    if google is None:
        print("\nNOTE: no google artifact built — negative control skipped.")
        print("  Build it to make this audit meaningful:")
        print("    cd android && ./gradlew assembleGoogleDebug")
    else:
        print(f"\nNegative control — scanning {google} …")
        missing = check_present(google, GOOGLE_EXPECTED)
        if missing:
            failed = True
            print("FAIL: the google variant is MISSING Cast:")
            for m in missing:
                print(f"  - {m}")
            print("\nThe amazon result above is therefore meaningless. Casting")
            print("is broken on Play, or the flavor split has been undone.")
        else:
            print("OK: the google variant carries Cast — the split is real.")

    if failed:
        return 1
    print("\nPASS: Fire TV-safe (zero GMS) AND Cast present on google.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
