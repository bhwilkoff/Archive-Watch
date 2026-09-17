#!/usr/bin/env python3
"""EVERY rights bucket must have a human explanation, in the host's language.

Watch Together Studio refuses films the rights audit has not cleared, and §3.4
requires each refusal to SAY something the host can act on — "films published
between 1964 and 1977 had their copyrights renewed automatically" teaches
something true about the public domain; a raw bucket name teaches nothing.

This is the guard that stops that promise decaying. It caught the first leak
on real data: `Voyage to the Planet of Prehistoric Women` (1967) returned
`renewal_zone_bw`, which `StudioRights.explain` had no case for, so the sheet
showed the viewer the internal name. `renewal_zone` had a case; its
black-and-white sibling did not.

A contract that spans two languages and agrees only by string needs a test
that reads BOTH (the Decision-116 lesson). Buckets are enumerated from
audit_rights.py itself, so a new one fails here rather than leaking to a host.

  python3 tools/test_studio_rights_coverage.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
AUDIT = ROOT / "tools/audit_rights.py"
RIGHTS = ROOT / "ArchiveWatch/ArchiveWatch/Studio/StudioRights.swift"

# Every shape `bucket()` returns a name in: a bare tuple and a parenthesised
# conditional tuple. Both forms are in the file today.
PATTERNS = [
    re.compile(r'return\s+"([a-z_0-9]+)"\s*,\s*"(?:keep|fix|hide|report|confirm)"'),
    re.compile(r'return\s+\(\s*"([a-z_0-9]+)"\s*,\s*"(?:keep|fix|hide|report|confirm)"\s*\)'),
    re.compile(r'else\s+\(\s*"([a-z_0-9]+)"\s*,\s*"(?:keep|fix|hide|report|confirm)"\s*\)'),
]


def audit_buckets() -> set[str]:
    text = AUDIT.read_text(encoding="utf-8")
    found: set[str] = set()
    for p in PATTERNS:
        found |= set(p.findall(text))
    # Names that only ever appear in the HIDE/confirm sets are still verdicts a
    # client can read off an item, so include them.
    for name in re.findall(r'"(modern_copyright_\w+|renewal_zone\w*)"', text):
        found.add(name)
    return found


def explained() -> set[str]:
    text = RIGHTS.read_text(encoding="utf-8")
    # `case "a", "b":` and `case "a":` inside explain(bucket:)
    start = text.index("static func explain(")
    end = text.index("\n    }", start)
    body = text[start:end]
    return set(re.findall(r'"([a-z_0-9]+)"', body))


# Buckets that are ALLOWED at every tier never reach `explain`, so they need
# no sentence. Everything else does, including the ones `strict` would admit —
# at the shipping `guaranteed` tier those are refusals.
ALWAYS_ALLOWED = {"safe_pd_age"}


def main() -> int:
    buckets = audit_buckets() - ALWAYS_ALLOWED
    covered = explained()
    if not buckets:
        print("FAIL: found no buckets in audit_rights.py — the patterns have drifted")
        return 1
    missing = sorted(b for b in buckets if b not in covered)
    print(f"audit_rights produces {len(buckets)} bucket names; "
          f"StudioRights.explain names {len(covered)}")
    if missing:
        print("\nFAIL — these buckets would show a host their raw internal name:")
        for m in missing:
            print(f"  • {m}")
        print("\nAdd a case to StudioRights.explain(bucket:) in the host's language.")
        return 1
    print("PASS: every rights bucket has a human explanation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
