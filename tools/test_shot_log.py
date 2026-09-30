#!/usr/bin/env python3
"""Stock-footage shot logs leave uploader summaries (remediate_catalog._strip_shot_log)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

cases = [
    ("summary ahead of the log is kept",
     "Footage from the late 1930s, mostly in New York City, related to religious and racial prejudice. 06:40:55:18 CU sign on a park fence",
     "Footage from the late 1930s, mostly in New York City, related to religious and racial prejudice."),
    ("a log with no summary keeps its words",
     "Ducks on a farm. 11:26:50:19 VS Pekin ducks; hundreds of ducks.",
     "Ducks on a farm. Pekin ducks; hundreds of ducks."),
    ("to-be-logged notes go", "Some excellent shots to be logged. Fruits at market.", "Fruits at market."),
    ("a timecode range leaves no dash", "06:00:39:28 - 06:51:56:07 color silent 1939 World's Fair.", "color silent 1939 World's Fair."),
    ("CONTROL: a plot with a clock time is untouched", "The bomb is set for 11:30 and Joe has an hour to find it.",
     "The bomb is set for 11:30 and Joe has an hour to find it."),
    ("CONTROL: 'vs' in a title is untouched", "Johnson vs Jeffries, Reno, 1910.", "Johnson vs Jeffries, Reno, 1910."),
    ("CONTROL: an initial CU in a name is untouched", "A film about the CUNY campus.", "A film about the CUNY campus."),
]
fails = 0
for name, got_in, want in cases:
    got = R._strip_shot_log(got_in)
    ok = got == want
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  got  {got!r}"))
print(f"{len(cases) - fails}/{len(cases)}")
sys.exit(1 if fails else 0)
