#!/usr/bin/env python3
"""The rights gate must say the SAME THING on every platform.

`Studio/StudioRights.swift` (Apple) and `studio/StudioRights.kt` (Android) are
two copies of a safety-critical decision: which films may be broadcast to a
real person's YouTube or Twitch channel. Two copies drift, and the drift that
matters is not a crash — it is one platform quietly allowing a film the other
refuses, or two hosts being told different reasons for the same verdict.

So this compares them directly: the tier sets, the forbidden content types,
and every per-bucket sentence, character for character.

It also checks both against `tools/audit_rights.py`, because a bucket the
audit can emit and the clients have no sentence for falls to a default that
leaks an internal name at a viewer — which is how `renewal_zone_bw` reached a
user once (§9).

    python3 tools/test_studio_rights_parity.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "ArchiveWatch/ArchiveWatch/Studio/StudioRights.swift"
KOTLIN = ROOT / "android/app/src/main/java/app/archivewatch/android/studio/StudioRights.kt"
AUDIT = ROOT / "tools/audit_rights.py"

failures = []


def check(name, ok, detail=""):
    print(("  PASS  " if ok else "  FAIL  ") + name + ("" if ok else f" — {detail}"))
    if not ok:
        failures.append(name)


def swift_sentences(text):
    body = text[text.index("static func explain(bucket: String) -> String {"):]
    body = body[:body.index("\n    }\n")]
    out = {}
    for keys, sentence in re.findall(
            r'case ((?:"[a-z_]+"(?:, )?)+):\s*\n\s*return "([^"]+)"', body):
        for k in re.findall(r'"([a-z_]+)"', keys):
            out[k] = sentence
    return out


def kotlin_sentences(text):
    body = text[text.index("fun explain(bucket: String): String ="):]
    body = body[:body.index("\n    /**")]
    out = {}
    for keys, sentence in re.findall(
            r'((?:"[a-z_]+"(?:, )?)+) ->\s*\n\s*"([^"]+)"', body):
        for k in re.findall(r'"([a-z_]+)"', keys):
            out[k] = sentence
    return out


def main():
    swift = SWIFT.read_text()
    kotlin = KOTLIN.read_text()
    print("Rights gate — Apple vs Android\n")

    s = swift_sentences(swift)
    k = kotlin_sentences(kotlin)
    check("both files parse", bool(s) and bool(k), f"swift={len(s)} kotlin={len(k)}")

    only_swift = sorted(set(s) - set(k))
    only_kotlin = sorted(set(k) - set(s))
    check("the same buckets are explained on both", not only_swift and not only_kotlin,
          f"apple-only={only_swift} android-only={only_kotlin}")

    differing = [b for b in sorted(set(s) & set(k)) if s[b] != k[b]]
    check("every shared bucket has the IDENTICAL sentence", not differing,
          f"{differing}")
    for b in differing:
        print(f"        {b}\n          apple:   {s[b]}\n          android: {k[b]}")

    # The tiers, which decide what actually goes live.
    def tier_of(text, name, pattern):
        m = re.search(pattern, text, re.S)
        return set(re.findall(r'"([a-z_]+)"', m.group(1))) if m else set()

    s_guar = tier_of(swift, "swift", r'case \.guaranteed:\s*\n\s*return \[([^\]]+)\]')
    k_guar = tier_of(kotlin, "kotlin", r'GUARANTEED\(setOf\(([^)]+)\)\)')
    check("the guaranteed tier matches", s_guar == k_guar and s_guar == {"safe_pd_age"},
          f"apple={sorted(s_guar)} android={sorted(k_guar)}")

    s_strict = tier_of(swift, "swift", r'case \.strict:\s*\n\s*return \[([^\]]+)\]')
    k_strict = tier_of(kotlin, "kotlin", r'STRICT\(setOf\(([^)]+)\)\)')
    check("the strict tier matches", s_strict == k_strict,
          f"apple={sorted(s_strict)} android={sorted(k_strict)}")

    s_forbidden = tier_of(swift, "swift", r'forbiddenTypes: Set<String> = \[([^\]]+)\]')
    k_forbidden = tier_of(kotlin, "kotlin", r'forbiddenTypes = setOf\(([^)]+)\)')
    check("the never-broadcast content types match", s_forbidden == k_forbidden,
          f"apple={sorted(s_forbidden)} android={sorted(k_forbidden)}")

    # Every bucket the audit can actually emit needs a sentence, or a viewer
    # reads an internal name.
    if AUDIT.exists():
        emitted = set(re.findall(r'"(safe_[a-z_]+|presumed_pd|renewal_zone[a-z_]*|'
                                 r'renewed_[a-z_]+|modern_[a-z_]+|no_evidence|unknown_year|'
                                 r'uploader_[a-z_]+|wrongmatch_[a-z_]+|commercial_[a-z_]+|'
                                 r'copyrighted_trailer|excerpt)"', AUDIT.read_text()))
        # The tiers' own buckets are allowed through rather than explained.
        need = sorted(emitted - s_guar - s_strict)
        missing_apple = [b for b in need if b not in s]
        missing_android = [b for b in need if b not in k]
        check("every bucket the audit emits has an Apple sentence", not missing_apple,
              f"{missing_apple}")
        check("every bucket the audit emits has an Android sentence", not missing_android,
              f"{missing_android}")
        print(f"        ({len(emitted)} buckets found in audit_rights.py)")

    # The host warning is a safety sentence and drifts like any other.
    def one_string(text, pattern):
        m = re.search(pattern, text, re.S)
        if not m:
            return None
        return "".join(re.findall(r'"([^"]*)"', m.group(1)))

    s_warn = one_string(swift, r'hostWarning\s*=\s*(.*?)\n\n')
    k_warn = one_string(kotlin, r'val hostWarning: String =\s*(.*?)\n\n')
    check("both carry the host warning", bool(s_warn) and bool(k_warn),
          f"apple={bool(s_warn)} android={bool(k_warn)}")
    check("the host warning is IDENTICAL", s_warn == k_warn,
          f"\n          apple:   {s_warn}\n          android: {k_warn}")
    # It must actually warn about the two things the research found.
    for needle in ("automatic copyright", "interrupt", "score"):
        check(f"the warning mentions '{needle}'", needle in (s_warn or ""))

    # No internal name may reach a viewer through a normal verdict.
    leaky = [b for b, sentence in k.items() if b in sentence]
    check("no Android sentence leaks its own bucket name", not leaky, f"{leaky}")

    print()
    if failures:
        print("FAILED: " + ", ".join(failures))
        return 1
    print("The rights gate is identical on Apple and Android.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
