#!/usr/bin/env python3
"""
audit_series_episodes.py — find wrong-content episodes inside series/*.json.

The TV backfill matches Archive uploads to canonical episodes by title; three
real failure classes shipped to users before guards existed (a Facebook
transcript dump and a Murphy Brown episode inside All in the Family; a
South-Park-thumbnailed review vlog matched as an episode). This audit finds
those classes in the spines we already have, report-first:

  Offline heuristics (no network):
    scrape_id     — facebook-/tiktok-/twitter-/instagram- identifiers
                    (skipped when the series ITSELF is a scrape cluster)
    transcript    — episode title longer than 200 chars
    review_title  — title says review/reaction/parody/recap/commentary
    cross_show    — archiveID starts with ANOTHER spine's slug
    show_after_se — series name appears only AFTER the SxxEyy marker in the
                    title ("Murphy Brown S08E12 All in the Family")
    se_mismatch   — id-embedded S/E disagrees with the assigned S/E

  Network confirm (--confirm; only flagged episodes are fetched):
    archive.org /metadata — review/vlog collections (vlogs, bliptv),
      review-ish subjects/description ("review", "reaction", "parody",
      "does not own"), mediatype sanity.
    TVmaze episodebynumber — resolves se_mismatch into remap / keep /
      unverified exactly like the 2026-06-10 manual pass.

  --apply removes confirmed wrong_show / review_content / scrape_mirror
  episodes, applies confirmed remaps, and rewrites episode counts. Every
  action lands in tools/audit_series_episodes.csv (gitignored, CI artifact)
  so a wrong call can be reviewed and reverted — spines are in git.

Run:  python tools/audit_series_episodes.py                 # offline report
      python tools/audit_series_episodes.py --confirm       # + network verdicts
      python tools/audit_series_episodes.py --confirm --apply
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import time
import unicodedata
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SERIES_DIR = REPO / "series"
REPORT = REPO / "tools" / "audit_series_episodes.csv"
UA = "ArchiveWatch-SeriesAudit/1.0 (https://github.com/bhwilkoff/Archive-Watch)"

SCRAPE_PREFIXES = ("facebook-", "tiktok-", "twitter-", "instagram-")
REVIEW_WORDS = re.compile(
    r"\b(review|reaction|reacts?|parody|recap|commentary|fan\s*(film|made|edit)|"
    r"gaypisode|riff|mst3k)\b", re.IGNORECASE)
# GoAnimate-style fan videos ("Caillou Gets Grounded") wear the show's name
# but are parodies — distinctive phrases, not single words.
PARODY_WORDS = re.compile(
    r"(gets?[\s_-]*grounded|ungrounded|goanimate|go[\s_-]?animate)",
    re.IGNORECASE)
REVIEW_COLLECTIONS = {"vlogs", "bliptv", "youtube", "fan-films"}
SE = re.compile(r"s\s*0*(\d{1,2})\s*[-_. ]*e\s*0*(\d{1,3})", re.IGNORECASE)


def norm_words(t):
    t = re.sub(r"[^a-z0-9 ]+", " ", (t or "").lower())
    return set(t.split())


def slugify(t):
    return re.sub(r"[^a-z0-9]+", "-", (t or "").lower()).strip("-")


def fetch_json(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def one_or_many(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def load_spines():
    spines = {}
    for p in sorted(SERIES_DIR.glob("*.json")):
        try:
            spines[p] = json.loads(p.read_text(encoding="utf-8"))
        except ValueError:
            print(f"  ! unreadable spine {p.name}", file=sys.stderr)
    return spines


def flag_offline(spines):
    """Yield finding dicts {path, doc, ep, reasons} from pure-local checks."""
    slug_index = {p.stem: slugify(d.get("title") or p.stem)
                  for p, d in spines.items()}
    findings = []
    for p, d in spines.items():
        title_words = norm_words(d.get("title"))
        eps = [e for s in d.get("seasons", []) for e in s.get("episodes", [])]
        n_scrape = sum(1 for e in eps if (e.get("archiveID") or "")
                       .lower().startswith(SCRAPE_PREFIXES))
        scrape_cluster = eps and n_scrape >= len(eps) / 2
        for e in eps:
            aid = e.get("archiveID") or ""
            t = e.get("title") or ""
            reasons = []
            if aid.lower().startswith(SCRAPE_PREFIXES) and not scrape_cluster:
                reasons.append("scrape_id")
            if len(t) > 200:
                reasons.append("transcript")
            if REVIEW_WORDS.search(t):
                reasons.append("review_title")
            if PARODY_WORDS.search(t) or PARODY_WORDS.search(aid):
                reasons.append("fan_parody")
            aslug = aid.lower()
            own = slug_index[p.stem]
            for other, oslug in slug_index.items():
                if other == p.stem or len(oslug) < 8:
                    continue
                if aslug.startswith(oslug + "-") and not own.startswith(oslug):
                    reasons.append(f"cross_show:{other}")
                    break
            m = SE.search(t)
            if m and title_words:
                before = norm_words(t[:m.start()])
                after = norm_words(t[m.end():])
                if not (title_words & before) and (title_words & after):
                    reasons.append("show_after_se")
            m = SE.search(aid.replace("-", " "))
            sn, en = e.get("seasonNumber"), e.get("episodeNumber")
            if m and sn is not None and en is not None:
                ids, ide = int(m.group(1)), int(m.group(2))
                if (ids, ide) != (sn, en):
                    reasons.append(f"se_mismatch:{ids}x{ide}")
            if reasons:
                findings.append({"path": p, "doc": d, "ep": e,
                                 "reasons": reasons})
    return findings


def confirm(f, throttle):
    """Network verdict for one finding. Returns (verdict, evidence)."""
    aid = f["ep"].get("archiveID") or ""
    reasons = f["reasons"]
    evidence = []

    if any(r == "scrape_id" for r in reasons) or \
       any(r == "transcript" for r in reasons):
        return "scrape_mirror", "social-scrape identifier / transcript title"

    # Archive metadata: is this review/commentary/parody content, not the show?
    needs_meta = any(r in ("review_title", "fan_parody")
                     or r.startswith("cross_show") for r in reasons) \
        or any(r == "show_after_se" for r in reasons)
    if needs_meta:
        try:
            meta = fetch_json(f"https://archive.org/metadata/{aid}")
            time.sleep(throttle)
        except Exception as ex:  # noqa: BLE001
            return "unverified", f"metadata fetch failed: {ex}"
        md = meta.get("metadata", {})
        cols = {str(c).lower() for c in one_or_many(md.get("collection"))}
        subj = " ".join(str(s) for s in one_or_many(md.get("subject"))).lower()
        desc = str(md.get("description") or "").lower()
        at = str(md.get("title") or "")
        if "fan_parody" in reasons and (PARODY_WORDS.search(at)
                                        or PARODY_WORDS.search(subj)
                                        or PARODY_WORDS.search(desc)):
            return "fan_parody", f"self-described parody: {at[:120]}"
        if cols & REVIEW_COLLECTIONS and (REVIEW_WORDS.search(subj)
                                          or REVIEW_WORDS.search(desc)
                                          or "does not own" in desc):
            return "review_content", f"collections={sorted(cols)}; review subjects"
        if any(r.startswith("cross_show") or r == "show_after_se"
               for r in reasons):
            # The Archive item's own title is the authority (Decision 026
            # spirit). wrong_show ONLY when a DIFFERENT name leads the title
            # before the SxxEyy marker; a bare "S3E28 The Avengers" upload
            # (nothing before the marker) is the show, oddly named.
            m = SE.search(at)
            show_words = norm_words(f["doc"].get("title"))
            if m and show_words:
                before = norm_words(at[:m.start()])
                if show_words & before:
                    evidence.append("series name leads the archive title")
                elif before:
                    return "wrong_show", f"archive title: {at[:120]}"
                elif show_words & norm_words(at[m.end():]):
                    evidence.append("show named after marker, nothing before")
            if not evidence:
                evidence.append(f"archive title: {at[:120]}")

    # se_mismatch: ask TVmaze whether the id's S/E or the assigned S/E
    # matches the id's embedded episode-title words.
    mm = [r for r in reasons if r.startswith("se_mismatch")]
    if mm:
        tvm = f["doc"].get("tvmazeID")
        ep = f["ep"]
        if not tvm:
            return "unverified", "se_mismatch but no tvmazeID"
        ids, ide = (int(x) for x in mm[0].split(":")[1].split("x"))
        aid_sp = (ep.get("archiveID") or "").replace("-", " ") \
            .replace(".", " ").replace("_", " ")
        m = SE.search(aid_sp)
        tail = norm_words(re.sub(
            r"\b(colorized|colorzied|restored|\d+p|hd|sd|low|vhsrip|sdtv|x|"
            r"264|avi|mkv|serial|chap|\d{4,6})\b", " ", aid_sp[m.end():]))

        def canonical(s, n):
            try:
                d_ = fetch_json("https://api.tvmaze.com/shows/"
                                f"{tvm}/episodebynumber?season={s}&number={n}")
                time.sleep(throttle)
                return d_.get("name")
            except Exception:  # noqa: BLE001
                return None

        def overlap(name):
            w = norm_words(name)
            return len(w & tail) / len(w) if w else 0

        n_id = canonical(ids, ide)
        n_asg = canonical(ep.get("seasonNumber"), ep.get("episodeNumber"))
        if n_id and tail and overlap(n_id) >= 0.5:
            return f"remap:{ids}:{ide}:{n_id}", \
                f"id title matches canonical S{ids}E{ide} '{n_id}'"
        if n_asg and tail and overlap(n_asg) >= 0.5:
            return "keep", f"uploader misnumbered; assigned '{n_asg}' matches"
        return "unverified", \
            f"no title corroboration (id={n_id!r} assigned={n_asg!r})"

    if evidence:
        return "keep", "; ".join(evidence)
    return "unverified", "offline flag only"


def apply_verdicts(rows):
    """Remove / remap confirmed-bad episodes; rewrite counts."""
    by_path = {}
    for r in rows:
        if r["verdict"].startswith(("wrong_show", "review_content",
                                    "scrape_mirror", "fan_parody", "remap:")):
            by_path.setdefault(r["path"], []).append(r)
    changed = 0
    for path, actions in by_path.items():
        d = json.loads(Path(path).read_text(encoding="utf-8"))
        flat = [e for s in d.get("seasons", []) for e in s.get("episodes", [])]
        drop = {r["archiveID"] for r in actions
                if not r["verdict"].startswith("remap:")}
        flat = [e for e in flat if e.get("archiveID") not in drop]
        for r in actions:
            if not r["verdict"].startswith("remap:"):
                continue
            _, s, n, name = r["verdict"].split(":", 3)
            for e in flat:
                if e.get("archiveID") == r["archiveID"]:
                    e["seasonNumber"], e["episodeNumber"] = int(s), int(n)
                    e["title"] = name
                    e["overview"] = e["airDate"] = None
                    e["stillURL"] = ("https://archive.org/services/img/"
                                     + r["archiveID"])
        by_season = {}
        for e in flat:
            by_season.setdefault(e.get("seasonNumber"), []).append(e)
        d["seasons"] = [
            {"seasonNumber": sn,
             "episodes": sorted(by_season[sn],
                                key=lambda e: (e.get("episodeNumber") is None,
                                               e.get("episodeNumber") or 0,
                                               e.get("title") or ""))}
            for sn in sorted(by_season, key=lambda x: (x is None, x or 0))]
        d["episodesCount"] = len(flat)
        years = [e["year"] for e in flat if e.get("year")]
        if years:
            d["yearStart"], d["yearEnd"] = min(years), max(years)
        Path(path).write_text(json.dumps(d, ensure_ascii=False, indent=2),
                              encoding="utf-8")
        changed += 1
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--confirm", action="store_true",
                    help="Fetch archive.org/TVmaze evidence for flagged episodes.")
    ap.add_argument("--apply", action="store_true",
                    help="Remove/remap confirmed-bad episodes (implies --confirm).")
    ap.add_argument("--throttle", type=float, default=0.7)
    args = ap.parse_args()
    if args.apply:
        args.confirm = True

    spines = load_spines()
    findings = flag_offline(spines)
    print(f"{len(findings)} flagged episodes across "
          f"{len({f['path'] for f in findings})} series "
          f"(of {len(spines)} spines)")

    rows = []
    for f in findings:
        verdict, evidence = ("flagged", "; ".join(f["reasons"])) \
            if not args.confirm else confirm(f, args.throttle)
        rows.append({
            "series": f["path"].stem,
            "archiveID": f["ep"].get("archiveID"),
            "title": (f["ep"].get("title") or "")[:160],
            "reasons": ";".join(f["reasons"]),
            "verdict": verdict,
            "evidence": evidence,
            "path": str(f["path"]),
        })
        print(f"  {f['path'].stem} | {f['ep'].get('archiveID')}"
              f" | {';'.join(f['reasons'])} -> {verdict}")

    REPORT.parent.mkdir(exist_ok=True)
    with REPORT.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["series", "archiveID", "title",
                                           "reasons", "verdict", "evidence"],
                           extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"report -> {REPORT}")

    if args.apply:
        n = apply_verdicts(rows)
        print(f"applied: {n} spine files rewritten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
