#!/usr/bin/env python3
"""Network-free guard for tools/corroborate_copyright.py and its audit bucket.

Owner, 2026-09-28: "If we have verifiable copyright claims on movies or TV
shows, we should work to remove those items from the database. If we truly
don't know about the copyright status, then they can stay because of that
ambiguity." Fixtures are shaped like the real Copyright Office records and
Wikidata rows seen that day (Kiss Me Deadly's RE0000168113; Plan 9's trailer
and colorized-version PA registrations; Charade's song renewal).

Run: python3 tools/test_copyright_evidence.py   (exit 0 = pass)
"""
import datetime as dt, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_rights as A
import corroborate_copyright as C

fails = 0
def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    fails += not cond


def record(cls, work, title, orig_year=None, pid="voyager_1", reg="RE0000168113"):
    r = {"registration_class": cls, "type_of_work": work, "title_concatenated": title,
         "public_records_id": pid, "registration_number": reg,
         "claimants_list": [{"claimant_full_name": "United Artists Corporation (PWH)"}],
         "registration_number_list": [{"registration_number": reg}]}
    if orig_year:
        r["registration_number_list"].append({"registration_date": f"{orig_year}-04-20 ",
                                              "registration_number": "LP0000004659 /",
                                              "copyright_number_display_text": "Renewal registration for:"})
    return {"hit": r}


# ---- the Copyright Office matcher ----
kiss = [record("RE", "motion_picture", "Kiss me deadly.  By Parklane Pictures, Inc.", 1955)]
ev = C.renewal_in(kiss, "Kiss Me Deadly", 1955)
check("a motion-picture renewal of the same title and year is evidence", bool(ev))
check("  ...and names the renewal and the original registration",
      ev and "RE0000168113" in ev["via"] and "LP0000004659" in ev["via"] and ev["source"].endswith("voyager_1"))
check("a leading article does not break the match", bool(C.renewal_in(kiss, "The Kiss Me Deadly", 1955)))
check("an original registration five years away is another film", not C.renewal_in(kiss, "Kiss Me Deadly", 1960))
plan9 = [record("PA", "motion_picture", "Plan nine from outer space :trailer."),
         record("PA", "motion_picture", "Plan 9 From Outer Space.", reg="PA0001633215")]
check("a post-1978 PA registration (trailer, colorized version) is NOT a claim on the film",
      not C.renewal_in(plan9, "Plan 9 from Outer Space", 1959))
song = [record("RE", "music", "Charade.  From Charade.  w Johnny Mercer, m Henry Mancini.", 1963)]
check("a renewal of the film's SONG is not a claim on the film", not C.renewal_in(song, "Charade", 1963))
check("a different title is not a match",
      not C.renewal_in([record("RE", "motion_picture", "Kiss me Kate.", 1955)], "Kiss Me Deadly", 1955))
# Gentlemen Prefer Blondes (1953): the Office titles it "Gentlemen prefer
# blondes; motion picture photoplay." with a variant title of the bare name;
# rule 1 compared only the full title and missed RE0000094825.
gpb = record("RE", "motion_picture", "Gentlemen prefer blondes; motion picture photoplay.", 1953,
             reg="RE0000094825")
check("a '; motion picture photoplay' tail does not hide a renewal",
      bool(C.renewal_in([gpb], "Gentlemen Prefer Blondes", 1953)))
gpbv = record("RE", "motion_picture", "Photoplay no. 12.", 1953, reg="RE0000094825")
gpbv["hit"]["title_variant_title_list"] = {"title_variant_title": ["Gentlemen prefer blondes"]}
check("the Office's own variant title is a match", bool(C.renewal_in([gpbv], "Gentlemen Prefer Blondes", 1953)))
check("  ...but a different film behind a semicolon is not",
      not C.renewal_in([record("RE", "motion_picture", "Gentlemen marry brunettes; motion picture photoplay.", 1953)],
                       "Gentlemen Prefer Blondes", 1953))
check("  ...and the dramatization (not a motion picture) still is not",
      not C.renewal_in([record("RE", "dramatic_work", "Gentlemen prefer blondes.  Dramatization: Kristen Sergel.", 1953)],
                       "Gentlemen Prefer Blondes", 1953))
old_rule = {"copyrightChecked": "2026-09-28"}
check("a title checked under rule 1 is due again under rule 2",
      (old_rule.get("copyrightRule") or 1) < C.RULE)

# Control: a matcher that accepts any registration with the title would hide
# Plan 9 — the fixture really does discriminate.
naive = any(C.norm_title(h["hit"]["title_concatenated"]) == C.norm_title("Plan 9 From Outer Space")
            for h in plan9)
check("control: a title-only matcher WOULD have matched public-domain Plan 9", naive)


# ---- the Wikidata rule ----
TODAY = dt.date(2026, 9, 28)
def row(item, status, st="s1", jur=None, end=None, ref=True, url=None, country=None, lic=None, ia=None):
    b = {"item": {"value": "http://www.wikidata.org/entity/" + item},
         "st": {"value": st}, "status": {"value": "http://www.wikidata.org/entity/" + status}}
    if jur: b["jur"] = {"value": "http://www.wikidata.org/entity/" + jur}
    if end: b["end"] = {"value": end}
    if ref: b["r"] = {"value": "http://www.wikidata.org/reference/abc"}
    if url: b["url"] = {"value": url}
    if country: b["country"] = {"value": "http://www.wikidata.org/entity/" + country}
    if lic: b["lic"] = {"value": "http://www.wikidata.org/entity/" + lic}
    if ia: b["ia"] = {"value": ia}
    return ("ia" if ia else "item", b)

CCE = "https://archive.org/details/catalogofcopyrig3131213li/page/n117/mode/1up?q=R248101"
got = C.judge_wikidata([row("Q4898740", "Q50423863", jur="Q30", url=CCE)], TODAY)
check("copyrighted in the US, with a reference -> claim (Betty Boop's Museum)",
      got.get(("item", "Q4898740"), {}).get("source") == CCE)
check("no reference -> no claim",
      not C.judge_wikidata([row("Q1", "Q50423863", jur="Q30", ref=False)], TODAY))
check("an ended statement (Steamboat Willie, P582 2024-01-01) -> no claim",
      not C.judge_wikidata([row("Q816038", "Q50423863", jur="Q30", end="2024-01-01T00:00:00Z")], TODAY))
check("copyrighted AND a licence (Apartment 5A, CC) -> no claim: a licensed work is free",
      not C.judge_wikidata([row("Q112237547", "Q50423863", jur="Q13780930", lic="Q18199165")], TODAY))
check("copyrighted in Germany only (Nosferatu, Metropolis) -> no claim",
      not C.judge_wikidata([row("Q151895", "Q50423863", jur="Q183")], TODAY))
check("a live US public-domain statement beside the claim -> ambiguous, stays",
      not C.judge_wikidata([row("Q2", "Q50423863", st="a", jur="Q30"),
                            row("Q2", "Q19652", st="b", jur="Q30")], TODAY))
check("no jurisdiction on a US film, with a reference -> claim (Dead Man's Eyes)",
      bool(C.judge_wikidata([row("Q5245272", "Q50423863", country="Q30")], TODAY)))
check("no jurisdiction on a non-US film -> no claim",
      not C.judge_wikidata([row("Q3", "Q50423863", country="Q801")], TODAY))
check("worldwide -> claim", bool(C.judge_wikidata([row("Q4", "Q50423863", jur="Q13780930")], TODAY)))
check("found by Internet Archive ID keys on the archiveID",
      ("ia", "betty") in C.judge_wikidata([row("Q4898740", "Q50423863", jur="Q30", ia="betty")], TODAY))


# ---- the audit bucket ----
base = {"archiveID": "a", "title": "Kiss Me Deadly", "year": 1955, "contentType": "feature-film",
        "rightsStatus": "public_domain", "artworkSource": "tmdb", "tmdbID": 1}
EV = {"source": "https://publicrecords.copyright.gov/detailed-record/voyager_7065589",
      "via": "US Copyright Office renewal RE0000168113 of LP0000004659 (1955)"}
check("control: without evidence a 1955 film stays (presumed_pd)", A.bucket(base)[0] == "presumed_pd")
check("with verifiable evidence it hides (copyright_claim_evidence)",
      A.bucket({**base, "copyrightClaimEvidence": EV}) == ("copyright_claim_evidence", "hide"))
check("copyright_claim_evidence is a HIDE bucket", "copyright_claim_evidence" in A.HIDE_BUCKETS)
check("past the age line the claim has expired: a 1928 film stays (safe_pd_age)",
      A.bucket({**base, "year": 1928, "copyrightClaimEvidence": EV})[0] == "safe_pd_age")
gov = next(iter(A.GOV))
check("a US government work stays (safe_gov)",
      A.bucket({**base, "collections": [gov], "copyrightClaimEvidence": EV})[0] == "safe_gov")
A.copyright_overrides.ids = {"a"}
check("a person's override lets it stay",
      A.bucket({**base, "copyrightClaimEvidence": EV})[0] == "presumed_pd")
del A.copyright_overrides.ids

# ---- which titles are checked ----
items = [{**base, "archiveID": "keep"},
         {**base, "archiveID": "old", "year": 1925},
         {**base, "archiveID": "hidden", "excluded": True},
         {**base, "archiveID": "recent", "copyrightChecked": TODAY.isoformat(), "copyrightRule": C.RULE},
         {**base, "archiveID": "oldrule", "copyrightChecked": TODAY.isoformat()},
         {**base, "archiveID": "stale", "copyrightChecked": "2026-01-01"},
         {**base, "archiveID": "noyear", "year": None}]
ids = {it["archiveID"] for it in C.targets(items, TODAY)}
check("targets: kept, past the age line, and not checked recently under this rule",
      ids == {"keep", "stale", "oldrule"})

print(f"\n{'FAIL' if fails else 'PASS'}: {fails} failure(s)")
sys.exit(1 if fails else 0)
