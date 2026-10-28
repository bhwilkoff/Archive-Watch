#!/usr/bin/env python3
"""
test_copyright_sibling.py — a copyright claim on a film hides every copy of it.

The defect (audit 2026-10-28): the copyright tiers judge each upload by its
own record, so Gilda (1946, renewed by Columbia) was hidden in one copy and
served as gilda-1946_202106; The Hidden Fortress and El ocaso de una vida the
same. The claim belongs to the film (its imdbID).

Controls: a copy listed in copyright_evidence_overrides.json, a copy in a
government collection, a copy with a corroborated free licence, a copy of a
different film. The apply path is run end to end on a temp catalog, and a
second apply after the claim is withdrawn must un-hide (the reconcile).

Run: python3 tools/test_copyright_sibling.py
"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_rights as A  # noqa: E402

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


A.copyright_overrides.ids = {"gilda_override_copy"}
CLAIM = {"via": "Copyright Office renewal RE0000012345", "source": "https://publicrecords.copyright.gov/x"}


def film(aid, **kw):
    it = {"archiveID": aid, "title": "Gilda", "year": 1946, "imdbID": "tt0038559",
          "contentType": "feature-film", "collections": ["feature_films"], "rightsStatus": "public_domain"}
    it.update(kw)
    return it


source = film("gilda-1946", copyrightClaimEvidence=CLAIM, excluded=True)
copy = film("gilda-1946_202106")
items = [source, copy,
         film("gilda_override_copy"),
         film("gilda_gov_copy", collections=["usgovfilms"]),
         film("gilda_cc_copy", rightsCorroborated=True,
              archiveLicense="https://creativecommons.org/publicdomain/zero/1.0/"),
         film("other_film", imdbID="tt0000001", title="Other")]
sib = A.copyright_siblings(items)
check("the claimed copy is the film's claim", sib.get("tt0038559", (None,))[0] == "copyright_claim_evidence")
check("its own bucket alone keeps the other copy (the defect)", A.bucket(copy)[1] == "keep", A.bucket(copy))
check("with the film's claim it hides, under the claim's own registered bucket",
      A.bucket_in(copy, sib) == ("copyright_claim_evidence", "hide"), A.bucket_in(copy, sib))
check("...and the claim is traced to the copy it came from",
      A.sibling_claim(copy, sib) == ("copyright_claim_evidence", "gilda-1946"))
check("the source keeps its own bucket", A.bucket_in(source, sib)[0] == "copyright_claim_evidence")
check("a copy a person cleared stays (control)", A.bucket_in(items[2], sib)[1] == "keep")
check("the claimed copy's own bucket is not a sibling claim", A.sibling_claim(source, sib) is None)
check("a government copy stays (control)", A.bucket_in(items[3], sib)[1] == "keep")
check("a corroborated free licence stays (control)", A.bucket_in(items[4], sib)[1] == "keep")
check("a different film stays (control)", A.bucket_in(items[5], sib)[1] == "keep")
check("every copyright-class bucket is registered, so --apply keeps it hidden",
      A.COPYRIGHT_CLASS <= A.HIDE_BUCKETS)
over = A.copyright_siblings([film("gilda_override_copy", copyrightClaimEvidence=CLAIM), copy])
check("an overridden copy is not a source either", "tt0038559" not in over)
for b in ("renewed_copyright_classic", "renewal_zone_commercial", "modern_copyright_confirmed"):
    check(f"{b} is a copyright-class source", b in A.COPYRIGHT_CLASS)

hx = {"title": "Horror Express", "imdbID": "tt0068713", "contentType": "feature-film",
      "collections": ["feature_films"], "imdbVotes": 13285}
hx_src = dict(hx, archiveID="horror_express_ipod", year=1976)       # misdated: misses the list
hx_copy = dict(hx, archiveID="HorrorExpress1972", year=1972, imdbVotes=None)
check("a misdated copy is hidden on its footprint (its own verdict)",
      A.bucket(hx_src)[0] == "renewal_zone_commercial", A.bucket(hx_src))
hsib = A.copyright_siblings([hx_src, hx_copy])
check("...but a film on the PD-by-defect list is not a source for its other copies",
      A.bucket_in(hx_copy, hsib)[1] != "hide", A.bucket_in(hx_copy, hsib))
check("control: the same film off the list would be",
      A.bucket_in(dict(hx_copy, title="Horror Expres"),
                  A.copyright_siblings([dict(hx_src, title="Horror Expres"), dict(hx_copy, title="Horror Expres")]))[1] == "hide")

print("\napply end to end on a temp catalog, then the reconcile")
with tempfile.TemporaryDirectory() as d:
    cat = Path(d) / "catalog.json"
    cat.write_text(json.dumps({"items": items}))
    A.CATALOG = cat
    argv = sys.argv
    sys.argv = ["audit_rights.py", "--apply", "--report-rejected", str(Path(d) / "r.csv")]
    try:
        A.main()
        got = {i["archiveID"]: i for i in json.loads(cat.read_text())["items"]}
        check("apply hides the uncovered copy", got["gilda-1946_202106"].get("excluded") is True
              and got["gilda-1946_202106"].get("rightsAudit") == "copyright_claim_evidence"
              and got["gilda-1946_202106"].get("copyrightClaimFrom") == "gilda-1946",
              {k: got["gilda-1946_202106"].get(k) for k in ("excluded", "rightsAudit", "copyrightClaimFrom")})
        check("apply leaves the cleared copy visible", not got["gilda_override_copy"].get("excluded"))
        check("the manifest names the copy", "gilda-1946_202106" in (Path(d) / "r.csv").read_text())
        data = json.loads(cat.read_text())
        for i in data["items"]:
            i.pop("copyrightClaimEvidence", None)       # the claim is withdrawn
        cat.write_text(json.dumps(data))
        A.main()
        got = {i["archiveID"]: i for i in json.loads(cat.read_text())["items"]}
        check("withdrawn claim: the copy is un-hidden on the next apply, and the trace goes",
              not got["gilda-1946_202106"].get("excluded")
              and "copyrightClaimFrom" not in got["gilda-1946_202106"], got["gilda-1946_202106"].get("rightsAudit"))
    finally:
        sys.argv = argv

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
