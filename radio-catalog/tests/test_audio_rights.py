"""The audio rights audit, one case per bucket, each with an unflagged control.

    python3 tests/test_audio_rights.py
Broken-control record (2026-10-17): see radio-catalog/README.md "Tests".
"""
import datetime
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import audit_audio_rights as A

TODAY = datetime.date(2026, 10, 17)


def rec(**kw):
    r = {"archive_id": "item1", "file": "f.mp3", "item_text": "", "producer_text": "",
         "collections": ["oldtimeradio"], "variant": None, "is_dark": False, "creator": ""}
    r.update(kw)
    return r


def ep(**kw):
    e = {"id": "suspense|1942-06-17", "series_key": "suspense", "series_name": "Suspense",
         "date": "1942-06-17", "num": 1, "title": "The Burning Court", "recordings": [rec()]}
    e.update(kw)
    return e


def ctx(**kw):
    c = {"takedowns": [], "schedule_match": lambda e: [], "claims": {}, "series_post_1972": {},
         "series_foreign": {}, "gov_series": {}, "licence_evidence": {}, "published_records": {},
         "film_renewals": {}, "today": TODAY}
    c.update(kw)
    return c


CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def unclaimed_is_kept_not_called_public_domain():
    j = A.judge(ep(), ctx())
    assert (j["state"], j["rec_bucket"]) == ("keep_unclaimed", "rec_orphan_unclaimed"), j


@case
def takedown_by_series_hides():
    c = ctx(takedowns=[{"scope": "series", "key": "suspense", "claimant": "X"}])
    assert A.judge(ep(), c)["rec_bucket"] == "rec_takedown"
    assert A.judge(ep(series_key="escape"), c)["rec_bucket"] == "rec_orphan_unclaimed"


@case
def dark_item_hides():
    assert A.judge(ep(recordings=[rec(is_dark=True)]), ctx())["rec_bucket"] == "rec_takedown"


@case
def schedule_filing_hides():
    c = ctx(schedule_match=lambda e: [{"rights_owner": "Sony"}] if e["series_key"] == "cbsnews" else [])
    assert A.judge(ep(series_key="cbsnews"), c)["state"] == "hide_claim"
    assert A.judge(ep(), c)["state"] == "keep_unclaimed"


@case
def claimant_on_recording_hides():
    c = ctx(claims={"shadow": {"layer": "recording", "series": "The Shadow"}})
    assert A.judge(ep(series_key="shadow"), c)["rec_bucket"] == "rec_rights_holder_claim"


@case
def script_claim_hides_through_work_layer():
    c = ctx(claims={"loneranger": {"layer": "work", "series": "The Lone Ranger"}})
    j = A.judge(ep(series_key="loneranger"), c)
    assert (j["state"], j["work_bucket"]) == ("hide_claim", "work_script_claim"), j


@case
def post_1972_hides_by_date_and_by_series():
    assert A.judge(ep(date="1974-01-06"), ctx())["rec_bucket"] == "rec_post_1972"
    assert A.judge(ep(date="1972-02-14"), ctx())["rec_bucket"] == "rec_orphan_unclaimed"
    c = ctx(series_post_1972={"cbsrmt": {"earliest": "1974-01-06"}})
    assert A.judge(ep(series_key="cbsrmt", date=None), c)["rec_bucket"] == "rec_post_1972"


@case
def foreign_origin_hides():
    c = ctx(series_foreign={"paultemple": {"term": "BBC"}})
    assert A.judge(ep(series_key="paultemple"), c)["state"] == "hide_claim"


@case
def foreign_regex_does_not_take_bare_abc():
    assert not A.FOREIGN.search("ABC Radio Network, Hollywood")
    assert A.FOREIGN.search("CBC Radio: Rex Stout's Nero Wolfe")


@case
def government_series_is_clean():
    c = ctx(gov_series={"commandperformance": {"agency": "AFRS"}})
    assert A.judge(ep(series_key="commandperformance"), c)["state"] == "keep_clean"


@case
def government_producer_in_item_metadata_is_clean_but_not_an_afrs_copy():
    e = ep(recordings=[rec(producer_text="Office of War Information")])
    assert A.judge(e, ctx())["rec_bucket"] == "rec_gov_work"
    e = ep(recordings=[rec(producer_text="U.S. Army", variant="AFRS")])
    assert A.judge(e, ctx())["rec_bucket"] == "rec_orphan_unclaimed"


@case
def librivox_is_clean():
    assert A.judge(ep(recordings=[rec(collections=["librivoxaudio"])]), ctx())["state"] == "keep_clean"


@case
def corroborated_licence_is_clean_uploader_licence_is_not():
    c = ctx(licence_evidence={"item1": {"licence": "CC BY", "statement_url": "https://x"}})
    assert A.judge(ep(), c)["rec_bucket"] == "rec_cc_corroborated"
    assert A.judge(ep(recordings=[rec(item_text="licenseurl creativecommons by-nc-nd")]), ctx())["rec_bucket"] == "rec_orphan_unclaimed"


@case
def published_by_age_follows_the_calendar():
    assert A.pd_published_year(TODAY) == 1925
    c = ctx(published_records={"item1": {"year": 1925}})
    assert A.judge(ep(), c)["rec_bucket"] == "rec_pd_published_age"
    c = ctx(published_records={"item1": {"year": 1926}})
    assert A.judge(ep(), c)["rec_bucket"] == "rec_orphan_unclaimed"
    c = ctx(published_records={"item1": {"year": 1926}}, today=datetime.date(2027, 1, 1))
    assert A.judge(ep(), c)["rec_bucket"] == "rec_pd_published_age"


@case
def unidentified_is_hidden():
    j = A.judge(ep(series_key=None, date=None, num=None, title=None), ctx())
    assert j["state"] == "hide_unidentified", j


@case
def adapted_renewed_film_hides_lux_episode():
    ren = {A.norm_title("The Maltese Falcon"): [{"t": "THE MALTESE FALCON", "y": 1941, "r": "R1", "reg": "L1", "vol": "v"}]}
    e = ep(series_key="luxradiotheater", date="1943-02-08", title="The Maltese Falcon")
    assert A.judge(e, ctx(film_renewals=ren))["work_bucket"] == "work_adapted_renewed"
    e = ep(series_key="suspense", date="1943-02-08", title="The Maltese Falcon")
    assert A.judge(e, ctx(film_renewals=ren))["work_bucket"] == "work_none_found"
    e = ep(series_key="luxradiotheater", date="1938-02-08", title="The Maltese Falcon")
    assert A.judge(e, ctx(film_renewals=ren))["work_bucket"] == "work_none_found"


@case
def hides_run_before_rescues():
    c = ctx(gov_series={"x": {}}, series_foreign={"x": {"term": "BBC"}})
    assert A.judge(ep(series_key="x"), c)["rec_bucket"] == "rec_foreign_origin"


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except AssertionError as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
