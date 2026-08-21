#!/usr/bin/env python3
"""The health check must email on a real break and stay quiet otherwise.

GitHub sends an email on every workflow failure, so the urgency predicate is
the thing that decides whether the owner is interrupted. It has to alarm on a
genuine failure and stay silent when a fix has already shipped and only the
schedule has yet to confirm it — faststart-derivatives is MONTHLY, so without
the second half the check sits red for eleven days over a bug fixed on
2026-08-09.

The negative controls are the point: if a deferred finding ever suppresses a
real one, this catches it.
"""
import sys
sys.path.insert(0, "tools")
from audit_workflow_health import urgent_findings

CASES = [
    ("genuine FAILED, no newer dispatch", [("FAILED", "x", "boom", False)], 1),
    ("FAILED with a fix in flight",       [("FAILED", "x", "boom", True)],  0),
    ("KILLED with a fix in flight",       [("KILLED", "x", "boom", True)],  0),
    ("KILLED, no newer dispatch",         [("KILLED", "x", "boom", False)], 1),
    ("BROKEN, no newer dispatch",         [("BROKEN", "x", "boom", False)], 1),
    ("DROPPED is never urgent",           [("DROPPED", "x", "q", False)],   0),
    ("STALE is never urgent",             [("STALE", "x", "q", False)],     0),
    ("SILENT is never urgent",            [("SILENT", "x", "q", False)],    0),
    # The one that must never regress: a deferred finding sitting alongside a
    # real one must NOT silence the real one.
    ("deferred + real together",          [("FAILED", "a", "x", True),
                                           ("FAILED", "b", "y", False)],    1),
]

ok = True
for name, findings, want in CASES:
    got = len(urgent_findings(findings))
    good = got == want
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'} {name} (urgent={got}, want={want})")

print("\nALL PASS" if ok else "\nFAILURES")
sys.exit(0 if ok else 1)
