#!/usr/bin/env python3
"""Find VERIFIABLE evidence that a kept title is still under US copyright.

Owner, 2026-09-28: "If we have verifiable copyright claims on movies or TV
shows, we should work to remove those items from the database. If we truly
don't know about the copyright status, then they can stay because of that
ambiguity." audit_rights hides a title in the `copyright_claim_evidence`
bucket when it carries `copyrightClaimEvidence`; this tool is what sets it.
Only evidence a reader can open counts:

  1. US Copyright Office public records (publicrecords.copyright.gov, the
     open JSON search the site itself uses): a RENEWAL (class RE) of a
     MOTION PICTURE whose title is this title and whose original
     registration ("Renewal registration for: LP...") is within a year of
     this title's year. Renewals for works published 1950-63 were filed from
     1978 on and are online; earlier ones are not. A post-1978 PA
     registration is NOT evidence about an old film: it registers new
     material (Plan 9 from Outer Space's trailer and a 2007 colorized
     version are both there, and Plan 9 is public domain).
  2. Wikidata: copyright status (P6216) = copyrighted (Q50423863) on the
     title's item (its wikidataQID, or the item whose Internet Archive ID
     P724 is this archiveID), with a reference, not ended (no P582 end time
     in the past), applying to the United States (P1001 = US or worldwide,
     or no jurisdiction on a film whose country of origin P495 is the US) —
     and no current US public-domain statement and no licence (P275) on the
     same item. "Copyrighted" with a Creative Commons licence is FREE
     (Apartment 5A, Spirit Chaser).

Measured 2026-09-28 before shipping: 0 of 20 public-domain canon films
(Night of the Living Dead, Charade, Plan 9, Carnival of Souls, McLintock!...)
matched source 1, and 3 of 3 known renewals did.

Only titles the audit KEEPS and whose year is past the age line are checked
(a pre-1930 "copyrighted" on Wikidata is stale: Rival Romeos, 1928). Results
ride on the catalog: `copyrightClaimEvidence` for a claim, `copyrightChecked`
(date) for none, so a re-run skips what it checked within RECHECK_DAYS.
A person can clear a wrong match in
shared/editorial/copyright_evidence_overrides.json ({archiveID: reason});
audit_rights honors it.

    python3 tools/corroborate_copyright.py [--dry-run] [--limit N] [--budget-min M]
"""
import concurrent.futures as cf
import datetime as dt, json, re, sys, time, urllib.parse, urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_rights as AR  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
UA = "ArchiveWatch/1.0 (https://archivewatch.org; rights corroboration)"
USCO = "https://api.publicrecords.copyright.gov/search_service_external/simple_search_dsl"
USCO_RECORD = "https://publicrecords.copyright.gov/detailed-record/"
SPARQL = "https://query.wikidata.org/sparql"
RECHECK_DAYS = 90
# Bumped when the MATCH changes, so a title checked under an older rule is
# checked again now rather than after RECHECK_DAYS. 2: a "; motion picture
# photoplay" tail and the Office's own variant titles (Gentlemen Prefer
# Blondes' RE0000094825 was missed under 1), and 100 records a page, not 25:
# a popular title's renewal sits deep in its results (The Pink Panther's
# RE0000523059 is record 54 of 5,525), and popular is who renewed.
RULE = 2
CHECKED_BUCKETS = {"presumed_pd", "renewal_zone", "renewal_zone_bw", "unknown_year",
                   "safe_archive_license", "safe_cc", "commercial_keep"}
USCO_FIRST_YEAR = 1950     # renewals of earlier works were filed before 1978: not online
COPYRIGHTED, PUBLIC_DOMAIN = "Q50423863", "Q19652"
US, WORLDWIDE = "Q30", "Q13780930"


def norm_title(t):
    """Title key for comparing a record to a film: the part before an
    author/claimant tail ("Kiss me deadly.  By Parklane Pictures, Inc."),
    no leading article, letters and digits only."""
    t = (t or "").lower()
    t = re.split(r"\s+by\s+|\s*/\s*|\s+:\s*|\s*;\s*| a motion picture", t)[0]
    t = re.sub(r"^(the|a|an)\s+", "", t)
    return re.sub(r"[^a-z0-9]", "", t)


def renewal_in(records, title, year):
    """The first record that is verifiable renewal evidence for (title, year)."""
    want = norm_title(title)
    if not want or not isinstance(year, int):
        return None
    for h in records or []:
        r = h.get("hit", h)
        if r.get("registration_class") != "RE" or r.get("type_of_work") != "motion_picture":
            continue
        variants = (r.get("title_variant_title_list") or {}).get("title_variant_title") or []
        if isinstance(variants, str):
            variants = [variants]
        if want not in {norm_title(t) for t in [r.get("title_concatenated"), *variants]}:
            continue
        for x in r.get("registration_number_list", []):
            if "Renewal registration for" not in (x.get("copyright_number_display_text") or ""):
                continue
            m = re.match(r"(\d{4})", (x.get("registration_date") or "").strip())
            if m and abs(int(m.group(1)) - year) <= 1:
                claimant = ((r.get("claimants_list") or [{}])[0].get("claimant_full_name") or "").strip()
                return {"source": USCO_RECORD + r.get("public_records_id", ""),
                        "via": f"US Copyright Office renewal {r.get('registration_number')} of "
                               f"{(x.get('registration_number') or '').strip(' /')} ({m.group(1)})",
                        "claimant": claimant}
    return None


def usco_search(title):
    url = USCO + "?" + urllib.parse.urlencode({"page_number": 1, "query": title,
                                               "field_type": "title", "records_per_page": 100})
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
            return json.load(urllib.request.urlopen(req, timeout=30)).get("data", [])
        except Exception:  # noqa: BLE001
            time.sleep(3 * (attempt + 1))
    return None   # a failed check is not a verdict (Decision 027)


def wikidata_claims(qids, ias):
    """{("item", qid) | ("ia", archiveID): evidence} for claims that pass the rule."""
    body = """
      ?item p:P6216 ?st . ?st ps:P6216 ?status .
      OPTIONAL { ?st pq:P1001 ?jur . }
      OPTIONAL { ?st pq:P582 ?end . }
      OPTIONAL { ?st prov:wasDerivedFrom ?r . OPTIONAL { ?r pr:P854 ?url . } }
      OPTIONAL { ?item wdt:P495 ?country . }
      OPTIONAL { ?item wdt:P275 ?lic . }"""
    rows = []

    def run(query):
        data = urllib.parse.urlencode({"query": query, "format": "json"}).encode()
        for attempt in range(3):
            try:
                req = urllib.request.Request(SPARQL, data=data, headers={
                    "User-Agent": UA, "Accept": "application/sparql-results+json",
                    "Content-Type": "application/x-www-form-urlencoded"})
                return json.load(urllib.request.urlopen(req, timeout=120))["results"]["bindings"]
            except Exception as e:  # noqa: BLE001
                print(f"  [wikidata] {e} (attempt {attempt + 1})", flush=True)
                time.sleep(5 * (attempt + 1))
        return []

    sel = "?item ?st ?status ?jur ?end ?r ?url ?country ?lic"
    for i in range(0, len(qids), 200):
        vals = " ".join("wd:" + q for q in qids[i:i + 200])
        rows += [("item", r) for r in run(f"SELECT {sel} WHERE {{ VALUES ?item {{{vals}}} {body} }}")]
        time.sleep(1)
    for i in range(0, len(ias), 200):
        vals = " ".join(json.dumps(a) for a in ias[i:i + 200])
        rows += [("ia", r) for r in run(f"SELECT ?ia {sel} WHERE {{ VALUES ?ia {{{vals}}} ?item wdt:P724 ?ia . {body} }}")]
        time.sleep(1)
    return judge_wikidata(rows, dt.date.today())


def judge_wikidata(rows, today):
    """Apply the evidence rule to SPARQL rows [(kind, binding)]. Pure: tested."""
    last = lambda r, k: r.get(k, {}).get("value", "").rsplit("/", 1)[-1]
    items = {}
    for kind, r in rows:
        key = (kind, r["ia"]["value"] if kind == "ia" else last(r, "item"))
        e = items.setdefault(key, {"item": r["item"]["value"], "st": {}, "country": set(), "lic": False})
        if "country" in r: e["country"].add(last(r, "country"))
        if "lic" in r: e["lic"] = True
        s = e["st"].setdefault(r["st"]["value"], {"status": last(r, "status"), "jur": set(),
                                                  "ended": False, "refs": set(), "urls": set()})
        if "jur" in r: s["jur"].add(last(r, "jur"))
        if "end" in r:
            try:
                s["ended"] = dt.date.fromisoformat(r["end"]["value"][:10]) <= today
            except ValueError:
                s["ended"] = True
        if "r" in r: s["refs"].add(r["r"]["value"])
        if "url" in r: s["urls"].add(r["url"]["value"])
    out = {}
    for key, e in items.items():
        if e["lic"]:
            continue
        live = [s for s in e["st"].values() if not s["ended"]]
        if any(s["status"] == PUBLIC_DOMAIN and (not s["jur"] or US in s["jur"]) for s in live):
            continue   # the record disagrees with itself: ambiguous, stays
        for s in live:
            if s["status"] != COPYRIGHTED or not s["refs"]:
                continue
            us = US in s["jur"] or WORLDWIDE in s["jur"] or (not s["jur"] and US in e["country"])
            if us:
                out[key] = {"source": sorted(s["urls"])[0] if s["urls"] else e["item"],
                            "via": "wikidata P6216 copyrighted (" +
                                   (", ".join(sorted(s["jur"])) or "US film, no jurisdiction") + ")",
                            "item": e["item"]}
                break
    return out


def _asked(it):
    return f"{it.get('title')}|{it.get('year')}"


def targets(items, today):
    cutoff = today - dt.timedelta(days=RECHECK_DAYS)
    out = []
    for it in items:
        if it.get("excluded") or it.get("copyrightClaimEvidence"):
            continue
        y = it.get("year")
        if not isinstance(y, int) or y < AR.PD_BY_AGE:
            continue
        if AR.bucket(it)[0] not in CHECKED_BUCKETS:
            continue
        seen = it.get("copyrightChecked")
        # The match is by title AND year, so a verdict belongs to the pair it was
        # made for: a corrected year or title is a new question (2026-09-29, the
        # 356 borrowed silent-era years remediate now replaces).
        asked = it.get("copyrightCheckedFor")
        if asked and asked != _asked(it):
            seen = None
        if seen and (it.get("copyrightRule") or 1) >= RULE:
            try:
                if dt.date.fromisoformat(seen) >= cutoff:
                    continue
            except ValueError:
                pass
        out.append(it)
    return out


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    limit = int(args[args.index("--limit") + 1]) if "--limit" in args else 0
    budget = float(args[args.index("--budget-min") + 1]) * 60 if "--budget-min" in args else 150 * 60
    start = time.time()
    today = dt.date.today()
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    todo = targets(cat["items"], today)
    if limit:
        todo = todo[:limit]
    now = today.isoformat()
    n_usco = n_wd = n_none = n_err = 0

    wd = wikidata_claims(sorted({it["wikidataQID"] for it in todo if it.get("wikidataQID")}),
                         sorted({it["archiveID"] for it in todo}))
    usco_todo = []
    for it in todo:
        e = wd.get(("item", it.get("wikidataQID"))) or wd.get(("ia", it["archiveID"]))
        if e:
            it["copyrightClaimEvidence"] = {**e, "at": now}
            n_wd += 1
        elif it["year"] >= USCO_FIRST_YEAR:
            usco_todo.append(it)
        else:
            it["copyrightChecked"] = now
            it["copyrightRule"] = RULE
            it["copyrightCheckedFor"] = _asked(it)
            n_none += 1

    def check(it):
        if time.time() - start > budget:
            return it, "skipped", None
        recs = usco_search(it["title"])
        if recs is None:
            return it, "error", None
        return it, "done", renewal_in(recs, it["title"], it["year"])

    with cf.ThreadPoolExecutor(2) as ex:        # polite: two in flight
        for it, state, ev in ex.map(check, usco_todo):
            if state == "done":
                if ev:
                    it["copyrightClaimEvidence"] = {**ev, "at": now}
                    n_usco += 1
                else:
                    it["copyrightChecked"] = now
                    it["copyrightRule"] = RULE
                    it["copyrightCheckedFor"] = _asked(it)
                    n_none += 1
            elif state == "error":
                n_err += 1
    if (n_usco or n_wd or n_none) and not dry:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[copyright] {len(todo):,} kept titles checked: {n_usco} renewed (Copyright Office), "
          f"{n_wd} copyrighted (Wikidata), {n_none} no claim found, {n_err} could not be checked"
          f"{' (dry run)' if dry else ''}", flush=True)


if __name__ == "__main__":
    main()
