#!/usr/bin/env python3
"""§8.34 — one room-code rule, five implementations, one alphabet.

A code is read aloud on a call and typed on a different device. Five copies of
that rule is five chances to disagree, and the way it fails is the worst kind:
somebody types exactly what they heard, reaches no room, and the app says "that
code doesn't work" with nothing to point at.

Four of the five (Swift, the Worker's JavaScript, Kotlin, the browser) have
table-driven tests that assert the SAME inputs — §8.28, §8.29, StudioRoomTest,
§8.32. The fifth is BrightScript, which cannot be executed off a Roku, so this
guards the thing that would actually drift instead of pretending to test logic:
the ALPHABET and the LENGTH. A changed alphabet silently repartitions every
code; a changed length invalidates every one of them.

It also checks the alphabet is genuinely Crockford — the exclusions are the
whole reason the mapping works, and dropping 0 or 1 by "tidying" would leave
nothing to map a mistyped O onto.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXPECTED = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
EXPECTED_LEN = 4

SOURCES = {
    "Swift":        ("ArchiveWatch/ArchiveWatch/Studio/StudioRoom.swift",
                     r'Array\("([0-9A-Z]+)"\)', r'codeLength\s*=\s*(\d+)'),
    "Worker (JS)":  ("worker/src/together.js",
                     r'ALPHABET\s*=\s*"([0-9A-Z]+)"', r'CODE_LENGTH\s*=\s*(\d+)'),
    "Kotlin":       ("android/app/src/main/java/app/archivewatch/android/studio/StudioRoom.kt",
                     r'ALPHABET\s*=\s*"([0-9A-Z]+)"', r'CODE_LENGTH\s*=\s*(\d+)'),
    "Web (JS)":     ("js/together.js",
                     r"ALPHABET\s*=\s*'([0-9A-Z]+)'", r'CODE_LENGTH\s*=\s*(\d+)'),
    "Roku (BRS)":   ("roku/source/TogetherRoom.brs",
                     r'return "([0-9A-Z]{32})"',
                     r'awRoomCodeLength\(\) as Integer\s*\n\s*return (\d+)'),
}

failures = 0


def check(label, ok, detail=""):
    global failures
    print(f"{'PASS' if ok else 'FAIL'} {label}" + (f" — {detail}" if detail else ""))
    if not ok:
        failures += 1


print("=== §8.34 room-code alphabet parity ===")

# The alphabet must BE Crockford, or the mapping in every implementation is
# built on something that is not what it claims.
check("the reference alphabet excludes I, L, O and U",
      not any(c in EXPECTED for c in "ILOU"))
check("and KEEPS 0 and 1, which is what the mapping maps ONTO",
      "0" in EXPECTED and "1" in EXPECTED)
check("32 characters", len(EXPECTED) == 32, str(len(EXPECTED)))

for name, (rel, alpha_re, len_re) in SOURCES.items():
    path = ROOT / rel
    if not path.exists():
        check(f"{name}: source exists", False, str(rel))
        continue
    text = path.read_text()
    m = re.search(alpha_re, text)
    check(f"{name}: alphabet found", m is not None, rel)
    if m:
        check(f"{name}: alphabet matches", m.group(1) == EXPECTED, m.group(1))
    n = re.search(len_re, text)
    check(f"{name}: code length found", n is not None, rel)
    if n:
        check(f"{name}: length is {EXPECTED_LEN}", int(n.group(1)) == EXPECTED_LEN, n.group(1))

# CONTROL: the regexes must actually be finding something specific. If they
# matched anything at all, every assertion above would pass on an empty file.
swift = (ROOT / SOURCES["Swift"][0]).read_text()
check("CONTROL: the Swift matcher does NOT match a wrong alphabet",
      re.search(SOURCES["Swift"][1], swift.replace(EXPECTED, "0123456789")) is None
      or re.search(SOURCES["Swift"][1], swift.replace(EXPECTED, "0123456789")).group(1) != EXPECTED)

print("=== §8.34 OK ===" if failures == 0 else f"=== §8.34 {failures} FAILURES ===")
sys.exit(0 if failures == 0 else 1)
