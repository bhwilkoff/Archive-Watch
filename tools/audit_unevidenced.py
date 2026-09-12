#!/usr/bin/env python3
"""
audit_unevidenced.py — go and LOOK at every title we know nothing about.

THE INSTRUCTION (owner, 2026-09-11): "You need a full audit of every title in
this category... You should try to enrich each title within this category and
attempt to figure out its content rights so that we can keep it in the app.
But, if we see that someone has the copyright, it has to go. Having it within
the app will make it so that the app can get pulled from every single store."

THE COHORT. `audit_rights.unevidenced()` — visible items with no year, no
licence, no external match, no release date and no origin collection. 4,579 of
them on the 2026-09-11 catalog, 14.4% of everything shown. They were being
served as public domain on the strength of nothing at all.

WHY ENRICHMENT COMES FIRST. Most of these are not copyrighted; they are
UNKNOWN, and the two have been indistinguishable. archive.org usually holds
the facts our catalog is missing — the item's own `date`, its `licenseurl`,
its `rights` statement, and often an `external-identifier` carrying an IMDb
id. Reading that turns "we know nothing" into a verdict for most of the
cohort, and only what survives with evidence of a live copyright is hidden.

WHAT IT WRITES BACK. Only facts sourced from the archive.org item itself:
`year` (from its `date`), `archiveLicense` (from `licenseurl`), `imdbID`
(from `external-identifier`), plus `unevidencedCheckedAt` so a later run can
tell "checked and still blank" from "never checked". Nothing is invented, and
the rights verdict is left to audit_rights.bucket() as usual — this tool
supplies evidence, it does not judge.

    python3 tools/audit_unevidenced.py                 # report only
    python3 tools/audit_unevidenced.py --apply         # write the facts back
    python3 tools/audit_unevidenced.py --limit 200     # a slice, for a smoke test
"""

from __future__ import annotations

import argparse
import collections
import concurrent.futures as cf
import datetime
import json
import pathlib
import re
import sys
import urllib.request

REPO = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

from audit_rights import unevidenced, bucket  # noqa: E402

UA = {"User-Agent": "ArchiveWatch-pipeline (unevidenced audit; +https://archivewatch.org)"}
CATALOG = REPO / "catalog.json"

# A four-digit year anywhere in archive.org's `date`, which is wildly
# inconsistent: "1925", "1925-01-01", "circa 1940", "1963-07-04T00:00:00Z".
YEAR = re.compile(r"(1[89]\d\d|20[0-4]\d)")

# Phrases in an item's own `rights` field that assert a LIVE copyright. These
# hide regardless of anything else: the owner's bar is that a title someone
# holds the copyright to cannot be in the app at all.
CLAIMED = re.compile(
    r"all rights reserved|copyright \d{4}|\(c\)\s*\d{4}|©\s*\d{4}"
    r"|used (?:with |by )permission|licensed from|do not (?:re)?distribute"
    r"|for (?:personal|private) use only|not for (?:public )?(?:re)?broadcast",
    re.I)


def meta(archive_id: str):
    req = urllib.request.Request(
        f"https://archive.org/metadata/{archive_id}", headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except Exception:                       # transient — NEVER condemn on it
        return None


def read(it) -> dict:
    """Facts from the item's own archive.org record. `None` means the fetch
    failed, which is different from an empty record and must never be treated
    as a verdict."""
    d = meta(it["archiveID"])
    if d is None:
        return {"status": "unreachable"}
    md = d.get("metadata") or {}
    out = {"status": "read"}

    date = " ".join(str(md.get(k, "")) for k in ("date", "year", "publicdate", "addeddate"))
    # `publicdate`/`addeddate` are when the UPLOAD happened, never the work's
    # own date, so they are read only to spot a modern upload — the year we
    # keep must come from `date` or `year`.
    own = " ".join(str(md.get(k, "")) for k in ("date", "year"))
    m = YEAR.search(own)
    if m:
        out["year"] = int(m.group(1))

    lic = md.get("licenseurl") or ""
    if lic:
        out["licenseurl"] = lic
    rights = " ".join(str(md.get(k, "")) for k in ("rights", "usage", "notes"))
    if rights.strip():
        out["rights"] = rights.strip()[:300]
        if CLAIMED.search(rights):
            out["claimed"] = True

    ext = md.get("external-identifier") or []
    if isinstance(ext, str):
        ext = [ext]
    for e in ext:
        mm = re.search(r"(tt\d{6,9})", str(e))
        if mm:
            out["imdbID"] = mm.group(1)
            break
    if not out.get("imdbID"):
        for k in ("imdb", "imdb_id", "identifier-imdb"):
            v = str(md.get(k, ""))
            mm = re.search(r"(tt\d{6,9})", v)
            if mm:
                out["imdbID"] = mm.group(1)
                break
    out["collections"] = md.get("collection") or []
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--out", default=str(REPO / "ops" / "unevidenced-audit.json"))
    a = ap.parse_args()

    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = cat["items"]
    cohort = [i for i in items if not i.get("excluded") and unevidenced(i)]
    if a.limit:
        cohort = cohort[: a.limit]
    print(f"cohort: {len(cohort):,} visible items with no evidence of any kind",
          flush=True)

    found = {}
    done = 0
    with cf.ThreadPoolExecutor(max_workers=a.workers) as ex:
        for it, res in zip(cohort, ex.map(read, cohort)):
            found[it["archiveID"]] = res
            done += 1
            if done % 250 == 0:
                print(f"  read {done:,}/{len(cohort):,}", flush=True)

    tally = collections.Counter()
    rescued = claimed = still_blank = unreachable = 0
    today = datetime.date.today().isoformat()
    by_id = {i["archiveID"]: i for i in items}

    for aid, r in found.items():
        it = by_id[aid]
        if r.get("status") == "unreachable":
            unreachable += 1
            tally["unreachable"] += 1
            continue
        gained = False
        if a.apply:
            it["unevidencedCheckedAt"] = today
        if r.get("claimed"):
            claimed += 1
            tally["copyright_claimed"] += 1
            if a.apply:
                it["rightsClaimed"] = r.get("rights", "")[:200]
            continue
        if r.get("year"):
            gained = True
            if a.apply:
                it["year"] = r["year"]
        if r.get("licenseurl"):
            gained = True
            if a.apply:
                it["archiveLicense"] = r["licenseurl"]
        if r.get("imdbID"):
            gained = True
            if a.apply:
                it["imdbID"] = r["imdbID"]
        if gained:
            rescued += 1
            tally["enriched"] += 1
        else:
            still_blank += 1
            tally["still_no_evidence"] += 1

    print(f"\n  enriched (a real fact recovered):   {rescued:,}")
    print(f"  copyright asserted on the item:     {claimed:,}")
    print(f"  still nothing known:                {still_blank:,}")
    print(f"  unreachable (retry, never condemn): {unreachable:,}")

    pathlib.Path(a.out).write_text(json.dumps(
        {"generated": today, "cohort": len(cohort), "tally": dict(tally),
         "items": found}, indent=1), encoding="utf-8")
    print(f"  findings -> {a.out}")

    if a.apply:
        CATALOG.write_text(json.dumps(cat), encoding="utf-8")
        print("  catalog updated (run catalog_release.py publish to ship)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
