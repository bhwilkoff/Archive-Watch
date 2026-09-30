#!/usr/bin/env python3
"""A printed renewal outranks Prelinger's public-domain standing; a government work stays kept.

2026-09-30: MGM's Escape (1940), Castle's News Parade of 1945 and Monogram's
Junior Prom sat in "prelinger", which audit_rights kept as safe_gov ahead of
every claim, so their renewals (Decision 151/157) were never applied."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_rights as A

EVID = {"source": "https://archive.org/details/x", "via": "renewal R421563"}
def item(aid, colls, evid=True, year=1940):
    d = {"archiveID": aid, "title": "Escape", "year": year, "contentType": "ephemeral", "collections": colls}
    if evid:
        d["copyrightClaimEvidence"] = EVID
    return d

cases = [
    ("a renewed studio film in Prelinger is hidden", item("p1", ["prelinger"]), "copyright_claim_evidence"),
    ("CONTROL: the same Prelinger film with no claim stays kept", item("p2", ["prelinger"], evid=False), "safe_gov"),
    ("CONTROL: a government film with a same-title claim stays kept", item("g1", ["usgovfilms"]), "safe_gov"),
    ("CONTROL: Prelinger AND a government collection stays kept", item("g2", ["prelinger", "fedflix"]), "safe_gov"),
    ("CONTROL: past the age line the claim has lapsed", item("p3", ["prelinger"], year=1925), "safe_gov"),
]
fails = 0
for name, it, want in cases:
    got = A.bucket(it)[0]
    ok = got == want
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f" (got {got})"))
sys.exit(1 if fails else 0)
