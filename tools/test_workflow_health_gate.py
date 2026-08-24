#!/usr/bin/env python3
"""The health check must email on the failures NOTHING ELSE alerts, and stay quiet otherwise.

GitHub sends its own email on every failed run, so a FAILED finding has already
interrupted the owner — the auditor re-failing over it is a duplicate alert
repeated daily (Decision 093). The auditor's red X is reserved for the classes
with no other voice: BROKEN (green but produced nothing) and KILLED (cancelled
with publish skipped — GitHub never emails about cancelled runs). A finding
whose fix is already in flight (a later manual run succeeded) is reported, not
failed — faststart-derivatives is MONTHLY, and without that the check sits red
for eleven days over a bug already fixed.

The negative controls are the point: a deferred or merely-reported finding must
never suppress a real one.
"""
import sys
sys.path.insert(0, "tools")
from audit_workflow_health import urgent_findings

CASES = [
    # FAILED already sent its own GitHub email — reported here, never re-failed.
    ("FAILED already emailed (D093)",     [("FAILED", "x", "boom", False)], 0),
    ("FAILED with a fix in flight",       [("FAILED", "x", "boom", True)],  0),
    ("KILLED with a fix in flight",       [("KILLED", "x", "boom", True)],  0),
    ("KILLED, no newer dispatch",         [("KILLED", "x", "boom", False)], 1),
    ("BROKEN, no newer dispatch",         [("BROKEN", "x", "boom", False)], 1),
    ("DROPPED is never urgent",           [("DROPPED", "x", "q", False)],   0),
    ("STALE is never urgent",             [("STALE", "x", "q", False)],     0),
    ("SILENT is never urgent",            [("SILENT", "x", "q", False)],    0),
    # The ones that must never regress: neither a deferred finding nor a
    # merely-reported FAILED may silence a real urgent one beside it.
    ("deferred + real together",          [("KILLED", "a", "x", True),
                                           ("KILLED", "b", "y", False)],    1),
    ("reported FAILED beside real KILLED", [("FAILED", "a", "x", False),
                                            ("KILLED", "b", "y", False)],   1),
]

ok = True
for name, findings, want in CASES:
    got = len(urgent_findings(findings))
    good = got == want
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'} {name} (urgent={got}, want={want})")

print("\nALL PASS" if ok else "\nFAILURES")
sys.exit(0 if ok else 1)
