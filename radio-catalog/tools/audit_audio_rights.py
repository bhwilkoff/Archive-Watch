"""The audio rights audit: two ordered layers, hides before rescues, first match wins.

Owner, 2026-10-17: "I like the idea of moving to a 'take down request' model
for this, but a licensed model at $1000 per year is definitely not in keeping
with our regular process." So an unclaimed pre-1972 broadcast is KEPT
(`keep_unclaimed`), and hidden the moment a claim a reader can open appears;
no recording is kept on a paid licence.

Why that posture holds (docs/research/radio/02-rights.md §12, statute read
2026-10-17): 17 U.S.C. §1401(f)(5) bars statutory damages and fees unless the
owner filed a schedule; §1401(f)(3) applies the §512 safe harbor. The app
never calls `keep_unclaimed` public domain (Decision 153's lesson).

States, in the order a client must treat them:
    keep_clean        public domain, a PD dedication, or a government work
    keep_unclaimed    no claim found; removed on request
    hide_claim        a claim a reader can open (schedule, claimant, takedown,
                      renewal, post-1972, non-US origin)
    hide_unidentified no series or date to check a claim against
"""
import datetime
import re

FOREIGN = re.compile(
    r"\b(BBC|B\.B\.C\.|CBC|Canadian Broadcasting|Radio[- ]Canada|Australian Broadcasting|"
    r"ABC Australia|Grace Gibson|Springbok Radio|SABC|Radio New Zealand|NZBC|RTE Radio|"
    r"Radio Luxembourg)\b")
GOV_PRODUCER = re.compile(
    r"\b(Office of War Information|Voice of America|U\.?S\.? Treasury|Treasury Department|"
    r"Federal Civil Defense|United States Army|United States Navy|U\.?S\.? Army|U\.?S\.? Navy)\b", re.I)
ADAPTATION_SERIES = {"luxradiotheater", "screenguildtheater", "screenguildplayers", "academyawardtheater",
                     "screendirectorsplayhouse", "hollywoodstartime", "hollywoodradiotheater"}
POST_1972 = datetime.date(1972, 2, 15)


def norm_title(t):
    t = (t or "").lower()
    t = re.sub(r"^(the|a|an)\s+", "", t)
    return re.sub(r"[^a-z0-9]", "", t)


def pd_published_year(today=None):
    """Newest first-publication year freed by §1401(a)(2)(B)(ii): 1925 in 2026."""
    return (today or datetime.date.today()).year - 101


def rec_bucket(ep, ctx):
    """Recording layer. `ep`: dict with series_key, date (YYYY-MM-DD or None),
    title, recordings[{archive_id, file, item_text, collections, variant, is_dark}].
    `ctx`: the evidence indexes built by build_db."""
    key, date = ep["series_key"], ep.get("date")
    recs = ep["recordings"]
    ev = []

    for t in ctx["takedowns"]:
        if (t["scope"] == "series" and t["key"] == key) or \
           (t["scope"] in ("episode", "recording") and t["key"] in (ep["id"], *[r["archive_id"] for r in recs])):
            return "rec_takedown", [t]
    if recs and all(r.get("is_dark") for r in recs):
        return "rec_takedown", [{"source": "archive.org item is dark"}]

    sched = ctx["schedule_match"](ep)
    if sched:
        return "rec_schedule_claim", sched

    claim = ctx["claims"].get(key)
    if claim and claim["layer"] == "recording":
        return "rec_rights_holder_claim", [claim]

    if date and datetime.date.fromisoformat(date) >= POST_1972:
        return "rec_post_1972", [{"date": date}]
    if ctx["series_post_1972"].get(key):
        return "rec_post_1972", [ctx["series_post_1972"][key]]

    if ctx["series_foreign"].get(key):
        return "rec_foreign_origin", [ctx["series_foreign"][key]]

    if key in ctx["gov_series"]:
        return "rec_gov_work", [ctx["gov_series"][key]]
    for r in recs:
        m = GOV_PRODUCER.search(r.get("producer_text") or "")
        if m and not r.get("variant"):
            ev.append({"archive_id": r["archive_id"], "producer": m.group(0)})
    if ev and len(ev) == len(recs):
        return "rec_gov_work", ev

    if any("librivoxaudio" in (r.get("collections") or []) for r in recs) or ep.get("librivox"):
        return "rec_librivox", [{"source": "LibriVox: all recordings are public domain"}]

    for r in recs:
        lic = ctx["licence_evidence"].get(r["archive_id"]) or ctx["licence_evidence"].get(key)
        if lic:
            return "rec_cc_corroborated", [lic]

    for r in recs:
        pub = ctx["published_records"].get(r["archive_id"] + "/" + r["file"]) or ctx["published_records"].get(r["archive_id"])
        if pub and int(pub["year"]) <= pd_published_year(ctx.get("today")):
            return "rec_pd_published_age", [pub]

    if not key or (not date and not ep.get("num") and not ep.get("title")):
        return "rec_no_evidence", []
    return "rec_orphan_unclaimed", []


def work_bucket(ep, ctx):
    """Underlying-work layer: scripts and the stories or films they adapt."""
    key = ep["series_key"]
    claim = ctx["claims"].get(key)
    if claim and claim["layer"] == "work":
        return "work_script_claim", [claim]
    if key in ADAPTATION_SERIES and ep.get("date") and ep.get("title"):
        year = int(ep["date"][:4])
        for r in ctx["film_renewals"].get(norm_title(ep["title"]), []):
            if r["y"] <= year <= r["y"] + 6:
                return "work_adapted_renewed", [{"film": r["t"], "year": r["y"], "renewal": r["r"],
                                                 "registration": r["reg"],
                                                 "source": f"https://archive.org/details/{r['vol']}"}]
    return "work_none_found", []


REC_STATE = {
    "rec_takedown": "hide_claim", "rec_schedule_claim": "hide_claim", "rec_rights_holder_claim": "hide_claim",
    "rec_post_1972": "hide_claim", "rec_foreign_origin": "hide_claim",
    "rec_gov_work": "keep_clean", "rec_librivox": "keep_clean", "rec_cc_corroborated": "keep_clean",
    "rec_pd_published_age": "keep_clean",
    "rec_orphan_unclaimed": "keep_unclaimed", "rec_no_evidence": "hide_unidentified",
}
WORK_HIDES = {"work_script_claim", "work_adapted_renewed"}


def judge(ep, ctx):
    rb, rev = rec_bucket(ep, ctx)
    wb, wev = work_bucket(ep, ctx)
    state = REC_STATE[rb]
    if wb in WORK_HIDES and state != "hide_unidentified":
        state = "hide_claim"
    return {"rec_bucket": rb, "work_bucket": wb, "state": state, "evidence": rev + wev}
