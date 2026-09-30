#!/usr/bin/env python3
"""Uploaders' rights claims leave summaries (remediate_catalog._strip_rights_assertions)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

cases = [
    ("a bare claim goes", "THIS SHORT IS IN THE PUBLIC DOMAIN.", ""),
    ("the claim goes, the plot stays",
     "Charley Chase fakes madness to escape a marriage. This film is safely in THE PUBLIC DOMAIN",
     "Charley Chase fakes madness to escape a marriage."),
    ("library boilerplate goes", "Farm scenes. Works not in the public domain cannot be commercially exploited without permission of the copyright owner.",
     "Farm scenes."),
    ("a Rights: label goes", "A parade downtown. Rights: Material in the public domain.", "A parade downtown."),
    ("the adjective goes, the sentence stays", "A PUBLIC DOMAIN short with Larry Semon and Stan Laurel.",
     "A short with Larry Semon and Stan Laurel."),
    ("a library record keeps its description",
     "Description: Scenes at Marshall School in Sacramento. Source: 1 Reel of 1: Film: 16mm Accession Number: 2008/022 Rights: Public domain.",
     "Scenes at Marshall School in Sacramento."),
    ("CONTROL: a film ABOUT the public domain stays", "A documentary about the public domain and the history of copyright law.",
     "A documentary about the public domain and the history of copyright law."),
    ("CONTROL: a plot with no rights talk is untouched", "A poet dreams of Harun al-Rashid.", "A poet dreams of Harun al-Rashid."),
]
fails = 0
for name, src, want in cases:
    got = R._strip_rights_assertions(src)
    ok = got == want
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  got {got!r}"))
sys.exit(1 if fails else 0)
