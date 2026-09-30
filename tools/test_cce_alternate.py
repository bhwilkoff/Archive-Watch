#!/usr/bin/env python3
"""A printed renewal is found under a film's alternate title, and says so.

2026-09-30: The Spy in Black was renewed as U-Boat 29, Q Planes as Clouds Over
Europe; the claim check read only the displayed title."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import corroborate_copyright as C

fails = 0
def check(name, ok):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name)

spy = {"title": "The Spy in Black", "year": 1939, "akaTitles": ["U-Boat 29"]}
hit = C.cce_renewal_any(spy)
check("found under the alternate title", bool(hit) and "U-Boat 29" in hit["via"])
check("CONTROL: the same film with no alternate titles is not found",
      C.cce_renewal_any({"title": "The Spy in Black", "year": 1939}) is None)
check("CONTROL: an alternate title in another year is not found",
      C.cce_renewal_any({"title": "The Spy in Black", "year": 1955, "akaTitles": ["U-Boat 29"]}) is None)
check("CONTROL: the displayed title still matches first, with no alternate note",
      "alternate" not in (C.cce_renewal_any({"title": "Double Indemnity", "year": 1944}) or {"via": "alternate"})["via"])
sys.exit(1 if fails else 0)
