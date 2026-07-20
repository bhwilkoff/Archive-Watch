#!/usr/bin/env python3
"""audit_titles.py — comprehensive title audit for items REGEX + canonical can't fix.

The owner directive: a title must be ONLY the film title — no video quality, actors,
year, or other metadata. ~48% of items carry a TMDb/IMDb id (fixed authoritatively by
backfill_metadata's canonicalTitle); the other ~51% have NO external source, so a messy
title ("Killer Bait Lizabeth Scott, Dan Duryea - Noir Full Movie", or a one-line
description) can only be cleaned by JUDGMENT. This tool brackets that judgment for an
LLM subagent fleet (run on Haiku — a simple extraction task, not worth Opus):

  export  — pick dirty no-external-id titles, write N batch files of {archiveID, title,
            synopsis, director, year, cast} for subagents to audit.
  apply   — read the subagents' results ({archiveID, auditedTitle}) and write
            `auditedTitle` onto each catalog item. remediate._audited_clean adopts it
            (guarded: audited words must be a subset of the uploader title — the audit
            may only REMOVE metadata, never invent/rename).

Mutates ./catalog.json (catalog_release.py fetch before apply, publish after).
The audit is ADDITIVE (Decision 020): `auditedTitle` is a new key older clients ignore.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

# "Looks dirty": more than the bare film title. Deliberately broad for RECALL — the LLM
# is the precision filter (it returns the title unchanged when it's already clean), and
# the _audited_clean subset-guard blocks any bad correction. Cheap pre-filter only.
_META = re.compile(
    r"\b(full movie|full film|full length|colou?ri[sz]|restored|remaster|widescreen|"
    r"featuring|starring|film noir|\bnoir\b|quality|upgrade|1080p|720p|480p|hd\b|dvd|"
    r"blu-?ray|subtitulad|legendado|vose|dubbed|english sub|version|uncut|remux|"
    r"directed by|\bhdrip\b|\bweb-?dl\b)\b", re.I)


def _norm_words(s):
    return [w for w in re.split(r"[^0-9a-z]+", (s or "").lower()) if w]


def looks_dirty(it) -> bool:
    t = it.get("title") or ""
    if not t:
        return False
    if _META.search(t):
        return True
    if len(t.split()) > 7:                     # long strings are descriptions/credit dumps
        return True
    if re.search(r" - .+ - ", t):              # multi-dash uploader dump
        return True
    # "Real Title Firstname Lastname, Firstname Lastname" (glued actor list)
    if re.search(r"\b[A-Z][a-z]+ [A-Z][a-z]+,\s*[A-Z][a-z]+ [A-Z][a-z]+", t):
        return True
    return False


def _cast_names(it):
    cast = it.get("cast") or []
    out = []
    for c in cast[:6]:
        nm = c.get("name") if isinstance(c, dict) else c
        if nm:
            out.append(nm)
    return out


def cmd_export(args):
    cat = json.loads(CATALOG.read_text())
    items = cat["items"]
    targets = []
    for it in items:
        if it.get("titleAudited") and not args.refresh:
            continue                            # resumable: skip already-audited
        if it.get("tmdbID") or it.get("imdbID"):
            continue                            # authoritative canonical path handles these
        if not looks_dirty(it):
            continue
        syn = it.get("synopsis")
        syn = " ".join(syn) if isinstance(syn, list) else (syn or "")
        targets.append({
            "archiveID": it["archiveID"],
            "title": it.get("title") or "",
            "year": it.get("year"),
            "director": it.get("director") or "",
            "cast": _cast_names(it),
            "synopsis": syn[:240],
        })
    # popularity-first so the most-seen titles are fixed earliest
    pop = {it["archiveID"]: (it.get("popularityScore") or it.get("downloads") or 0) for it in items}
    targets.sort(key=lambda x: pop.get(x["archiveID"], 0), reverse=True)
    if args.limit:
        targets = targets[: args.limit]
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    n = args.batch_size
    batches = [targets[i:i + n] for i in range(0, len(targets), n)]
    for i, b in enumerate(batches):
        (outdir / f"batch_{i:03d}.json").write_text(json.dumps(b, ensure_ascii=False, indent=1))
    print(f"[audit] {len(targets)} dirty no-id titles -> {len(batches)} batches of {n} in {outdir}")
    return 0


def cmd_apply(args):
    cat = json.loads(CATALOG.read_text())
    by_id = {it["archiveID"]: it for it in cat["items"]}
    applied = skipped = bad = 0
    result_files = sorted(Path(args.results).glob("*.json")) if Path(args.results).is_dir() \
        else [Path(args.results)]
    for rf in result_files:
        try:
            results = json.loads(rf.read_text())
        except Exception as e:
            print(f"[audit]  skip unreadable {rf.name}: {e}"); continue
        for r in results:
            it = by_id.get(r.get("archiveID"))
            if not it:
                continue
            it["titleAudited"] = True           # mark audited (resumable) regardless of outcome
            audited = (r.get("auditedTitle") or "").strip()
            if not audited:
                skipped += 1; continue
            # anti-hallucination: audited words must be a subset of the uploader title
            if not set(_norm_words(audited)).issubset(set(_norm_words(it.get("title") or ""))):
                bad += 1; continue
            if audited != (it.get("title") or ""):
                it["auditedTitle"] = audited
                applied += 1
            else:
                skipped += 1
    if not args.dry_run:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False))
    print(f"[audit] apply: auditedTitle set={applied} unchanged/blank={skipped} "
          f"rejected(not-subset)={bad}{' (dry-run)' if args.dry_run else ' -> wrote catalog.json'}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export"); e.add_argument("--outdir", default="tools/title_audit")
    e.add_argument("--batch-size", type=int, default=60); e.add_argument("--limit", type=int, default=0)
    e.add_argument("--refresh", action="store_true"); e.set_defaults(func=cmd_export)
    a = sub.add_parser("apply"); a.add_argument("--results", default="tools/title_audit/results")
    a.add_argument("--dry-run", action="store_true"); a.set_defaults(func=cmd_apply)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
