#!/usr/bin/env python3
"""TV-G6 compliance audit — 64-bit support + 16 KB page-size alignment.

Google's TV app quality requirement TV-G6 went LIVE 2026-08-01: a TV app must
support both 32-bit and 64-bit architectures AND comply with 16 KB page sizes.
It is not automatically satisfied — it depends on how every bundled native
library was linked, so it must be measured, not assumed (docs/TV-DESIGN.md
§6.4, Decision 047).

A 64-bit ELF is 16 KB-compliant when every PT_LOAD segment has p_align >= 16384.
We parse the ELF program headers directly so this runs anywhere Python does —
no NDK, no llvm-objdump, no Android SDK.

Usage:
    python3 tools/audit_tv_g6.py [path/to/app.apk|.aab]

Exits non-zero on any violation so CI can gate on it.
"""

from __future__ import annotations

import collections
import struct
import sys
import zipfile
from pathlib import Path

PT_LOAD = 1
PAGE_16K = 16 * 1024

DEFAULT_CANDIDATES = [
    "android/app/build/outputs/bundle/release/app-release.aab",
    "android/app/build/outputs/apk/release/app-release.apk",
    "android/app/build/outputs/apk/debug/app-debug.apk",
]

ABIS_64 = {"arm64-v8a", "x86_64"}
ABIS_32 = {"armeabi-v7a", "x86"}


def min_load_alignment(data: bytes) -> tuple[bool, int]:
    """Return (is_64bit, smallest PT_LOAD p_align) for an ELF image."""
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF image")
    is64 = data[4] == 2
    if is64:
        phoff = struct.unpack_from("<Q", data, 0x20)[0]
        phentsize = struct.unpack_from("<H", data, 0x36)[0]
        phnum = struct.unpack_from("<H", data, 0x38)[0]
        align_off, align_fmt = 0x30, "<Q"
    else:
        phoff = struct.unpack_from("<I", data, 0x1C)[0]
        phentsize = struct.unpack_from("<H", data, 0x2A)[0]
        phnum = struct.unpack_from("<H", data, 0x2C)[0]
        align_off, align_fmt = 0x1C, "<I"

    aligns = []
    for i in range(phnum):
        off = phoff + i * phentsize
        if struct.unpack_from("<I", data, off)[0] != PT_LOAD:
            continue
        aligns.append(struct.unpack_from(align_fmt, data, off + align_off)[0])
    return is64, (min(aligns) if aligns else 0)


def abi_of(entry: str) -> str:
    """lib/<abi>/x.so (APK) or base/lib/<abi>/x.so (AAB)."""
    parts = entry.split("/")
    return parts[parts.index("lib") + 1] if "lib" in parts else "?"


def main() -> int:
    if len(sys.argv) > 1:
        target = Path(sys.argv[1])
    else:
        target = next((Path(p) for p in DEFAULT_CANDIDATES if Path(p).exists()), None)
        if target is None:
            print("No build output found. Build first, e.g.:")
            print("  cd android && ./gradlew assembleRelease")
            return 2

    if not target.exists():
        print(f"ERROR: {target} does not exist")
        return 2

    print(f"TV-G6 audit: {target}\n")
    zf = zipfile.ZipFile(target)
    sos = [n for n in zf.namelist() if "/lib/" in f"/{n}" and n.endswith(".so")]

    if not sos:
        print("No native libraries bundled — 16 KB page-size rule is trivially met.")
        print("WARNING: also means no ABI split; confirm this is expected.")
        return 0

    abis = collections.Counter(abi_of(n) for n in sos)
    print(f"{len(sos)} native libraries across ABIs: {dict(abis)}\n")

    violations = []
    for name in sorted(sos):
        is64, align = min_load_alignment(zf.read(name))
        # The 16 KB rule constrains 64-bit images; 32-bit ones are reported for
        # completeness but never fail the gate.
        ok = (not is64) or align >= PAGE_16K
        if not ok:
            violations.append((name, align))
        print(f"  [{'OK  ' if ok else 'FAIL'}] {name}")
        print(f"         {'64' if is64 else '32'}-bit, min PT_LOAD align = {align} "
              f"({align // 1024} KB)")

    have64 = sorted(ABIS_64 & set(abis))
    have32 = sorted(ABIS_32 & set(abis))
    print(f"\n64-bit ABIs: {have64 or 'NONE'}")
    print(f"32-bit ABIs: {have32 or 'NONE'}")

    failed = False
    if not have64:
        print("\nFAIL: TV-G6 requires 64-bit support; no 64-bit ABI present.")
        failed = True
    if violations:
        print(f"\nFAIL: {len(violations)} library/libraries are not 16 KB-aligned:")
        for name, align in violations:
            print(f"  - {name} (align {align})")
        print("\nFix: bump the owning AndroidX/third-party dependency to a build "
              "linked with -Wl,-z,max-page-size=16384. Dependency bumps have "
              "lead time — do not leave this to submission day.")
        failed = True

    if failed:
        return 1

    print("\nPASS: TV-G6 satisfied (64-bit present, every 64-bit PT_LOAD >= 16 KB).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
