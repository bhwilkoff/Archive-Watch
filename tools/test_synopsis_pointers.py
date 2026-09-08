#!/usr/bin/env python3
"""
test_synopsis_pointers.py — an uploader's "see also" tail is not a synopsis.

Every REJECT here is a real trailing sentence from the live catalog. Every
KEEP is a sentence that merely mentions a source and must survive: the rule
drops pointers from the END, never description that happens to name Wikipedia.

Checked to FAIL against the untrimmed synopsis.

Run: python3 tools/test_synopsis_pointers.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from social_select import drop_pointers

ok = fail = 0


def check(name, got, want):
    global ok, fail
    if got == want:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}\n        got  {got!r}\n        want {want!r}")


BODY = ("Cry Danger is a 1951 film noir thriller, starring Dick Powell and "
        "Rhonda Fleming.")

check("the live Cry Danger tail goes",
      drop_pointers(BODY + " You can find out more about this movie from "
                    "Wikipedia . There is also a good review of the movie here "
                    "from the movie blog D for Doom ."), BODY)
check("one pointer sentence goes", drop_pointers(BODY + " For more, see IMDb."), BODY)
check("a visit-us tail goes", drop_pointers(BODY + " Visit our website here."), BODY)
check("a download tail goes",
      drop_pointers(BODY + " Download the full print here."), BODY)
check("a clean synopsis is untouched", drop_pointers(BODY), BODY)

# Description that names a source is not a pointer.
KEEP = (BODY + " Wikipedia records it as Robert Parrish's debut as a director.")
check("a sentence that merely names Wikipedia survives", drop_pointers(KEEP), KEEP)
KEEP2 = "The print here is the 1951 release version."
check("'here' about the PRINT is not a pointer", drop_pointers(KEEP2), KEEP2)
check("a synopsis that is ONLY a pointer is left alone rather than emptied",
      drop_pointers("You can find out more at Wikipedia."),
      "You can find out more at Wikipedia.")
check("empty stays empty", drop_pointers(""), "")

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
