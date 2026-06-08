#!/usr/bin/env python3
"""
audit_rights.py — copyright/rights auditor for the Archive Watch catalog.

WHY: 96% of the catalog is labelled `public_domain`, but that label is
unreliable for modern titles — 7,400+ items are dated >=1978 yet marked PD
(e.g. "The Peanuts Movie" 2015, "Nosferatu" 2024, "Azaad" 2025). Before an App
Store submission we must NOT ship videos that are still under copyright. This
tool buckets every item by how confidently we can call it public domain, then
HIDES the genuinely-modern-copyrighted titles and RE-DATES the wrong-match
old-video ones.

Catalog-only signals can't tell a genuine creator-dedicated PD film (Sita Sings
the Blues, NASA, CC works) apart from an uploader who slapped a bogus PD claim on
a studio film — both read `rightsStatus=public_domain`. The ONLY authoritative
signal is the Archive item's OWN `licenseurl`, so the audit has a network
confirmation phase:

  publicdomain/zero (CC0)         genuine waiver           -> KEEP
  creativecommons.org/licenses/*  real CC license          -> KEEP
  publicdomain/mark               uploader CLAIM (bogus on  -> not a rescue
                                  modern studio films)
  old licenses/publicdomain       legit for 1929-1977       -> KEEP pre-1978 only
                                  PD-by-defect; misapplied      (post-1978 can't
                                  on modern works               lose copyright)
  none / rights text only         no dedication            -> not a rescue

The same fetch reads Archive `date` to re-anchor wrong-dated old films (Tier-2 of
Decision 026): a video Archive dates to 1955 but a title-match dated 2015 is a
wrong match — re-date to 1955 (clearing the wrong modern poster) and it leaves
the risk bucket entirely.

Copyright year tiers (US):
  < 1929          PD by age                               -> SAFE
  1929 .. 1963    needed renewal; many lapsed; Archive    -> PRESUMED PD (keep)
                  curatorial stance treats as PD
  1964 .. 1977    renewals automatic; likely still in     -> RENEWAL ZONE
                  copyright UNLESS PD-by-notice-defect        (report; many here
                  (Night of the Living Dead etc.)             ARE genuinely PD)
  >= 1978         1976 Act: copyright from creation       -> HIGH RISK (confirm
                                                              -> hide unless CC0/CC)

REPORT-FIRST. No flags = measure + print. Phases:
  python tools/audit_rights.py                  # report (uses cached confirmations)
  python tools/audit_rights.py --samples 8      # + examples
  python tools/audit_rights.py --confirm        # NETWORK: fetch Archive license+date
                                                #   for risk items, re-date wrong
                                                #   matches, annotate catalog (additive)
  python tools/audit_rights.py --apply          # write excluded=true on confirmed hides
  python tools/audit_rights.py --apply --renewal-hide   # also hide 1964-77 color risk

Catalog lives on the release (Decision 018): fetch -> confirm -> apply -> publish.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402  (_GOV_PD_COLLECTIONS, _clear_wrong_artwork, decade_of)

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

PD_BY_AGE = 1929
RENEWAL_ZONE_START = 1964
MODERN = 1978
COMMERCIAL_MODERN = 1995  # vintage-commercial cutoff; modern brand ads are copyrighted

GOV = R._GOV_PD_COLLECTIONS
EXTERNAL = {"tmdb", "omdb"}

MODERN_ID_RE = re.compile(
    r"youtube|(^|[-_])yt[-_]|ytdown|bandicam|obs[-_]|screen[-_.]?(recording|capture|cap)"
    r"|y-?2meta|2meta\.com|savefrom|light[-_]img|(^|[-_])img[-_]?\d{3,}"
    r"|recording[-_]?20[12]\d|capture[-_]?20[12]\d",
    re.I,
)
SLOP_TITLE_RE = re.compile(
    r"\bcompilation\b|\bmix\b|\bplaylist\b|commercial breaks?\b|\btandas?\b"
    r"|\blogos?\b|\d+\s*hour|full (recording|tape|broadcast)|\bdigital recording\b"
    r"|\bpart\s*\d+\b|\bseason\s*\d+\b|\b(ep|episode)\s*\d+\b|channel\s*\d+",
    re.I,
)


def colls(it):
    return {str(c).lower() for c in (it.get("collections") or [])}


def modern_id(it):
    return bool(MODERN_ID_RE.search(it.get("archiveID") or ""))


def is_commercial_slop(it):
    return bool(SLOP_TITLE_RE.search(it.get("title") or "")) or modern_id(it)


def license_rescues(lic: str | None, year: int | None) -> bool:
    """True if the Archive licenseurl is a genuine free dedication for this year.

    Order matters: the OLD-style URL `creativecommons.org/licenses/publicdomain/`
    contains the substring `creativecommons.org/licenses/`, so the PD checks MUST
    run before the generic CC-license check or a modern film carrying that old PD
    URL would be wrongly kept."""
    if not lic:
        return False
    l = lic.lower()
    if "publicdomain/zero" in l:        # CC0 — genuine waiver, any year
        return True
    if "publicdomain" in l:             # PD Mark / old-style bare PD claim —
        return isinstance(year, int) and year < MODERN   # credible only pre-1978
    if "creativecommons.org/licenses/" in l:   # real CC license (by/sa/nc/nd)
        return True
    return False


def bucket(it):
    """Return (bucket, action). action in {keep, fix, hide, report, confirm}.

    `confirm` = a modern PD-labelled item we have NOT yet checked against the
    Archive licenseurl; --apply will not hide it until --confirm has run.
    """
    rs = (it.get("rightsStatus") or "").lower()
    y = it.get("year")
    yi = y if isinstance(y, int) else None
    ct = it.get("contentType")
    cl = colls(it)

    # ---- always-safe ----
    if cl & GOV:
        return "safe_gov", "keep"
    if rs == "creative_commons":
        return "safe_cc", "keep"
    if license_rescues(it.get("archiveLicense"), yi):
        return "safe_archive_license", "keep"
    if yi is not None and yi < PD_BY_AGE:
        return "safe_pd_age", "keep"

    # ---- commercials: own surface; brand-ad licenseurl is uploader-applied,
    #      so it is NOT trusted to rescue. Curation rule: hide modern + slop. ----
    if ct == "commercial":
        if is_commercial_slop(it):
            return "commercial_slop", "hide"
        if yi is not None and yi >= COMMERCIAL_MODERN:
            return "commercial_modern_risk", "hide"
        if yi is None and modern_id(it):
            return "commercial_modern_risk", "hide"
        return "commercial_keep", "keep"

    # ---- non-commercial rights risk ----
    if yi is not None and yi >= MODERN:
        confirmed = it.get("rightsConfirmed")
        if it.get("colorMode") == "bw" and not confirmed:
            return "wrongmatch_bw", "fix"   # likely old video; --confirm re-dates
        return ("modern_copyright_confirmed", "hide") if confirmed else \
               ("modern_copyright_unconfirmed", "confirm")
    if yi is None:
        if modern_id(it):
            return "modern_noyear_risk", "hide"
        return "unknown_year", "keep"
    if RENEWAL_ZONE_START <= yi < MODERN:
        return ("renewal_zone_bw", "report") if it.get("colorMode") == "bw" \
               else ("renewal_zone", "report")
    return "presumed_pd", "keep"            # 1929-1963


HIDE_BUCKETS = {"modern_copyright_confirmed", "modern_noyear_risk",
                "commercial_modern_risk", "commercial_slop"}


def evidence_for(it, b):
    """Human-reviewable 'why this is rejected', from the item's OWN signals."""
    parts = []
    y, ad = it.get("year"), it.get("archiveDate")
    if b == "modern_copyright_confirmed":
        parts.append(f"year {y} >= {MODERN} (born copyrighted)")
        parts.append(f"archive_date={ad}" if ad is not None else "archive_date=unknown")
        parts.append(f"license={it.get('archiveLicense') or 'NONE'} (no CC0/CC dedication)")
    elif b == "commercial_modern_risk":
        parts.append(f"modern brand ad, year {y if y is not None else '?'} >= {COMMERCIAL_MODERN}")
        if y is None and modern_id(it):
            parts.append("modern-capture archiveID")
    elif b == "commercial_slop":
        t = it.get("title") or ""
        m = SLOP_TITLE_RE.search(t)
        parts.append(f"slop title match: {m.group(0)!r}" if m else "modern-capture/rip archiveID")
    elif b == "modern_noyear_risk":
        parts.append("no year + modern-capture/rip archiveID")
    if it.get("colorMode"):
        parts.append(f"color={it['colorMode']}")
    if it.get("tmdbID"):
        parts.append(f"tmdbID={it['tmdbID']}")
    if it.get("imdbID") or it.get("archiveImdb"):
        parts.append(f"imdb={it.get('imdbID') or it.get('archiveImdb')}")
    return "; ".join(parts)


def write_rejected_report(items, path):
    """CSV manifest of every item that WOULD be / IS hidden, with the Archive's
    own evidence per row so a human can open the page and confirm the video is
    the modern/copyrighted title we claim. Sorted by popularity (most-seen first)
    + a SUSPECT flag on rows whose Archive date looks OLD (possible wrong hide)."""
    import csv
    rejected = [(it, bucket(it)[0]) for it in items if bucket(it)[0] in HIDE_BUCKETS]
    rejected.sort(key=lambda r: (r[0].get("popularityScore") or 0), reverse=True)
    suspect = 0
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["archiveID", "archive_url", "title", "contentType", "stored_year",
                    "archive_date", "archive_license", "colorMode", "imdbID", "tmdbID",
                    "downloadURL", "bucket", "SUSPECT_old_video", "evidence"])
        for it, b in rejected:
            ad = it.get("archiveDate")
            # A hidden item that might actually be an OLD video (so our "modern"
            # claim could be a wrong match) — flag for manual review:
            #  * Archive itself dates it pre-1978, or
            #  * it's frame-verified B&W with NO corroborating Archive date
            #    (the modern label then rests only on a fuzzy title match).
            is_suspect = b == "modern_copyright_confirmed" and (
                (isinstance(ad, int) and ad < MODERN)
                or (it.get("colorMode") == "bw" and ad is None)
            )
            if is_suspect:
                suspect += 1
            w.writerow([
                it["archiveID"], f"https://archive.org/details/{it['archiveID']}",
                it.get("title") or "", it.get("contentType") or "", it.get("year"),
                ad if ad is not None else "", it.get("archiveLicense") or "",
                it.get("colorMode") or "", it.get("imdbID") or it.get("archiveImdb") or "",
                it.get("tmdbID") or "", it.get("downloadURL") or "", b,
                "SUSPECT" if is_suspect else "", evidence_for(it, b),
            ])
    print(f"[report] wrote {path}: {len(rejected)} rejected rows "
          f"({suspect} flagged SUSPECT_old_video for manual review)")
    return len(rejected), suspect


# ---------------------------------------------------------------- network confirm
_lock = threading.Lock()
DATE_YEAR_RE = re.compile(r"(1[89]\d\d|20[0-2]\d)")


_UA = {"User-Agent": "ArchiveWatch-rights-audit/1.0 (ben@learningischange.com)"}


def fetch_archive(aid: str, timeout=20, retries=3):
    """Return (ok, licenseurl, year, imdb) from archive.org metadata.

    ok=False means the fetch FAILED (network/throttle) — the caller must NOT mark
    the item confirmed, else a transient failure would hide a film as 'no license'
    when we simply never reached the Archive. Retries with backoff on failure."""
    md = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(f"https://archive.org/metadata/{aid}", headers=_UA)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                md = json.load(r).get("metadata", {}) or {}
            break
        except Exception:
            if attempt == retries - 1:
                return False, None, None, None
            time.sleep(1.5 * (attempt + 1))
    if md is None:
        return False, None, None, None
    lic = md.get("licenseurl")
    if isinstance(lic, list):
        lic = lic[0] if lic else None
    # year from `date` (upload-independent; the work's date)
    yr = None
    for k in ("date", "year"):
        v = md.get(k)
        if isinstance(v, list):
            v = v[0] if v else None
        m = DATE_YEAR_RE.search(str(v or ""))
        if m:
            yr = int(m.group(1))
            break
    # imdb from external-identifier
    imdb = None
    ext = md.get("external-identifier")
    if ext:
        for e in (ext if isinstance(ext, list) else [ext]):
            m = re.search(r"(tt\d{6,9})", str(e))
            if m:
                imdb = m.group(1)
                break
    return True, lic, yr, imdb


def confirm_pass(cat, workers, limit):
    """NETWORK: fetch Archive license+date for items in confirm/fix/hide-modern
    buckets, annotate the catalog (additive, resumable via rightsConfirmed),
    and re-date wrong-dated old films (Tier-2)."""
    items = cat["items"]
    need_confirm = {"modern_copyright_unconfirmed", "wrongmatch_bw", "modern_noyear_risk"}
    targets = [it for it in items
               if bucket(it)[0] in need_confirm and not it.get("rightsConfirmed")]
    if limit:
        targets = targets[:limit]
    print(f"[confirm] fetching Archive metadata for {len(targets)} risk items "
          f"(workers={workers}) ...", flush=True)
    done = [0]
    redated = [0]
    rescued = [0]
    failed = [0]

    def work(it):
        ok, lic, ayr, imdb = fetch_archive(it["archiveID"])
        with _lock:
            if not ok:
                # fetch failed — leave UNCONFIRMED so a transient block never
                # causes a wrong hide; a re-run retries it (resumable).
                failed[0] += 1
                done[0] += 1
                return
            it["rightsConfirmed"] = True
            if lic:
                it["archiveLicense"] = lic
            if isinstance(ayr, int):
                it["archiveDate"] = ayr   # the work's own year per Archive — the
                                          # key verification signal for the report
            if imdb and not it.get("imdbID"):
                it["archiveImdb"] = imdb
            # Tier-2 re-date: Archive says the work is clearly old but it was
            # matched to a modern year -> wrong match. Re-date; clear a wrong
            # external poster.
            sy = it.get("year")
            if isinstance(ayr, int) and isinstance(sy, int) and ayr < MODERN and (sy - ayr) > 2:
                if (it.get("artworkSource") or "").lower() in EXTERNAL:
                    R._clear_wrong_artwork(it, ayr)
                else:
                    it["year"] = ayr
                    it["decade"] = R.decade_of(ayr)
                it["rightsAudit"] = "redated_from_archive"
                redated[0] += 1
            elif license_rescues(lic, sy):
                rescued[0] += 1
            done[0] += 1
            if done[0] % 250 == 0:
                print(f"[confirm]   {done[0]}/{len(targets)} "
                      f"(redated={redated[0]} rescued={rescued[0]} failed={failed[0]})", flush=True)
            if done[0] % 1000 == 0:   # checkpoint so a crash is resumable
                CATALOG.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")

    with ThreadPoolExecutor(max_workers=workers) as ex:
        for _ in as_completed([ex.submit(work, it) for it in targets]):
            pass
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
    print(f"[confirm] done: targets={len(targets)} confirmed={len(targets)-failed[0]} "
          f"failed={failed[0]} (left unconfirmed, retried next run) redated={redated[0]} "
          f"rescued_by_license={rescued[0]} -> wrote {CATALOG.name}", flush=True)


# ----------------------------------------------------------------------- report
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=0)
    ap.add_argument("--json", help="write machine report here")
    ap.add_argument("--confirm", action="store_true",
                    help="NETWORK: fetch Archive license+date for risk items; annotate catalog")
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--limit", type=int, default=0, help="cap confirm targets (testing)")
    ap.add_argument("--apply", action="store_true",
                    help="write excluded=true on confirmed HIDE buckets")
    ap.add_argument("--renewal-hide", action="store_true",
                    help="with --apply, also hide 1964-77 color renewal-zone items")
    ap.add_argument("--report-rejected", metavar="PATH",
                    help="write a CSV manifest of every rejected item + Archive evidence")
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = cat["items"]
    n = len(items)

    if args.confirm:
        confirm_pass(cat, args.workers, args.limit)
        cat = json.loads(CATALOG.read_text(encoding="utf-8"))
        items = cat["items"]

    counts = collections.Counter()
    actions = collections.Counter()
    samples = collections.defaultdict(list)
    bucket_action = {}
    for it in items:
        b, act = bucket(it)
        counts[b] += 1
        actions[act] += 1
        bucket_action[b] = act
        if len(samples[b]) < max(args.samples, 6):
            samples[b].append(it)

    sev = {"hide": 0, "confirm": 1, "fix": 2, "report": 3, "keep": 4}
    order = sorted(counts.items(), key=lambda kv: (sev[bucket_action[kv[0]]], -kv[1]))

    print(f"=== RIGHTS AUDIT — {n} items ===")
    print(f"tiers: <{PD_BY_AGE} pd-age | {PD_BY_AGE}-{RENEWAL_ZONE_START-1} presumed-pd | "
          f"{RENEWAL_ZONE_START}-{MODERN-1} renewal-zone | >={MODERN} modern-risk | "
          f"commercials>={COMMERCIAL_MODERN} modern\n")
    print(f"{'bucket':30} {'count':>7}  action")
    for b, _ in order:
        a = bucket_action[b]
        flag = {"hide": "  <-- HIDE", "confirm": "  (needs --confirm)",
                "fix": "  <- re-date"}.get(a, "")
        print(f"  {b:28} {counts[b]:7}  {a}{flag}")
    print(f"\nACTION TOTALS: hide={actions['hide']}  confirm={actions['confirm']}  "
          f"fix={actions['fix']}  report={actions['report']}  keep={actions['keep']}")

    if args.samples:
        print("\n=== SAMPLES ===")
        for b, _ in order:
            print(f"\n[{b}] ({bucket_action[b]}) — {counts[b]}")
            for it in samples[b][:args.samples]:
                print(f"   {it.get('year')} | {it.get('colorMode') or '?':5} | "
                      f"{it.get('contentType'):12} | lic={(it.get('archiveLicense') or '-')[:34]:34} | "
                      f"{(it.get('title') or '')[:38]!r} | {it['archiveID'][:30]}")

    if args.json:
        Path(args.json).write_text(json.dumps({
            "total": n, "counts": dict(counts), "actions": dict(actions),
            "bucket_action": bucket_action,
        }, indent=2, ensure_ascii=False))
        print(f"\n[json] wrote {args.json}")

    if args.report_rejected:
        write_rejected_report(items, args.report_rejected)

    if not args.apply:
        unconf = counts.get("modern_copyright_unconfirmed", 0)
        if unconf:
            print(f"\n[!] {unconf} modern items NOT yet confirmed — run --confirm "
                  f"before --apply so genuine CC0/CC films aren't hidden.")
        print("[report-only] pass --apply to write excluded=true on confirmed hides")
        return 0

    # ---- APPLY ----
    HIDE = set(HIDE_BUCKETS)
    if args.renewal_hide:
        HIDE |= {"renewal_zone", "renewal_zone_bw"}
    hidden = 0
    for it in items:
        b, _ = bucket(it)
        if b in HIDE:
            it["excluded"] = True
            it["rightsAudit"] = b
            hidden += 1
    cat["items"] = items
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
    # Always emit the final rejection manifest alongside an apply.
    default_report = REPO / "tools" / "rejected_audit.csv"
    write_rejected_report(items, args.report_rejected or str(default_report))
    print(f"\n[apply] excluded={hidden} -> wrote {CATALOG.name}")
    print("[apply] now: build_sqlite.py && catalog_release.py publish && publish-db")
    return 0


if __name__ == "__main__":
    sys.exit(main())
