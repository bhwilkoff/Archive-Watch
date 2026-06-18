#!/usr/bin/env python3
"""
dedupe_orphan_episodes.py — hide orphaned TV-episode DUPLICATES that masquerade
as standalone films.

Why: a TV episode often exists on archive.org as several uploads. The canonical
TV pipeline (Decision 016) maps ONE upload per episode onto a series spine
(series/{slug}.json); the OTHER uploads are left as standalone items typed
`tv-special`/`feature-film` with seriesID=null. They then surface as a "film"
card AND keep an unverified title-matched poster (e.g. "The Devil's Laughter" —
really One Step Beyond S1E11, already in the spine as S1E11THEDEVILSLAUGHTER —
showed as a film with a foreign-movie poster). This hides the confirmed
duplicates (reversible `excluded`, Decision 027) so only the real series episode
remains.

SAFETY (this is the hard part — descriptions cross-reference other shows, and
generic "Pilot"/"Episode 1" titles collide across series, so neither signal
alone is safe). An item is hidden ONLY when BOTH hold:
  1. SERIES IDENTITY from the item's OWN naming — the series name (multi-word)
     appears as the title prefix, the synopsis prefix (before the first colon,
     near the start), or the archiveID slug prefix. NOT a mid-synopsis mention.
  2. EPISODE IDENTITY in that SAME spine — a parsed (season,episode) that is a
     FILLED slot (mapped to a different archiveID), or an episode-title match.
The matched spine must be unambiguous (exactly one). Confirmed via the slot
already holding a different archiveID, so no content is ever lost.

Run: python tools/dedupe_orphan_episodes.py [--apply]   (default: dry-run report)
Catalog I/O via local catalog.json (catalog_release.py fetch first in CI).
"""

from __future__ import annotations

import argparse
import glob
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SERIES_DIR = REPO / "series"

_STOP = re.compile(r"\b(the|a|an|of|part|pt)\b")
_SXE = re.compile(r"s(\d{1,2})e(\d{1,2})|season\s*(\d+)\s*episode\s*(\d+)"
                  r"|series\s*(\d+)\s*episode\s*(\d+)", re.I)
# markers at which a title/slug stops being the series name
_CUT = re.compile(r"\s*(?:[|:]|s\d{1,2}e\d{1,2}|season\s*\d+|series\s*\d+"
                  r"|episode\s*\d+|\bep\.?\s*\d+)", re.I)
ORPHAN_TYPES = {"tv-special", "feature-film"}
# Not a single episode — a promos reel, trailer, or multi-episode/whole-season
# bundle can spuriously parse an (S,E) and mis-map onto one episode slot.
_NOT_SINGLE = re.compile(r"promo|bumper|trailer|compilation|complete series"
                         r"|all\s+\d+\s+episodes|episodes?\s+\d+\s*[-,&]\s*\d+", re.I)


def norm(s):
    s = _STOP.sub(" ", re.sub(r"[^a-z0-9 ]", " ", (s or "").lower()))
    return re.sub(r"\s+", " ", s).strip()


def synopsis(it):
    s = it.get("synopsis")
    return s if isinstance(s, str) else ""


def parse_se(text):
    m = _SXE.search(text or "")
    if not m:
        return None
    g = [x for x in m.groups() if x]
    return (int(g[0]), int(g[1]))


def extract_series_names(it):
    """Series-name candidates from the item's OWN naming (never a buried
    synopsis mention). Each is normalized + must be >=2 tokens."""
    out = []
    title = it.get("title") or ""
    out.append(_CUT.split(title)[0])
    s = synopsis(it)
    if ":" in s[:60]:                         # "One Step Beyond: <episode> ..."
        pre = s.split(":", 1)[0]
        if len(pre.split()) <= 6:
            out.append(pre)
    slug = re.sub(r"[_-]", " ", it.get("archiveID") or "")
    out.append(_CUT.split(slug)[0])
    seen, names = set(), []
    for c in out:
        n = norm(c)
        if len(n.split()) >= 2 and n not in seen:
            seen.add(n)
            names.append(n)
    return names


def series_matches(cands, spine_name):
    """True if a candidate and the spine name are the same series. Requires a
    CONTIGUOUS-phrase match (equality, or one name contained in the other as a
    whole phrase) — NOT a loose token-subset, which conflated films with
    similarly-named shows ("The Lone Star Ranger" film vs "The Lone Ranger",
    "Man with a Movie Camera" vs "Man with a Camera", "C-Man" vs "The Man from
    U.N.C.L.E"). The shorter side must be >=2 tokens to stay distinctive."""
    if len(spine_name.split()) < 2:
        return False
    sp = f" {spine_name} "
    for c in cands:
        if len(c.split()) < 2:
            continue
        cc = f" {c} "
        if c == spine_name or cc in sp or sp in cc:
            return True
    return False


def load_spines():
    spines = []
    for f in glob.glob(str(SERIES_DIR / "*.json")):
        try:
            d = json.load(open(f))
        except (json.JSONDecodeError, OSError):
            continue
        name = norm(d.get("title") or "")
        if len(name.split()) < 2:
            continue                          # 1-word series names are too collision-prone
        slots, titles = {}, {}
        for s in d.get("seasons", []):
            for e in s.get("episodes", []):
                aid = e.get("archiveID")
                if not (aid or e.get("downloadURL")):
                    continue
                if e.get("seasonNumber") and e.get("episodeNumber"):
                    slots[(int(e["seasonNumber"]), int(e["episodeNumber"]))] = aid
                if e.get("title"):
                    titles[norm(e["title"])] = aid
        if slots or titles:
            spines.append({"name": name, "slots": slots, "titles": titles,
                           "raw": d.get("title")})
    return spines


def find_duplicate(it, spines):
    """Return (spine, canonical_archiveID, reason) if `it` is a confirmed
    duplicate of a mapped spine episode, else None. Requires an UNAMBIGUOUS
    series match."""
    cands = extract_series_names(it)
    if not cands:
        return None
    matched = [sp for sp in spines if series_matches(cands, sp["name"])]
    if len(matched) != 1:                     # 0 = no series; >1 = ambiguous
        return None
    sp = matched[0]
    aid = it.get("archiveID")
    # Episode identity must be a parsed (season,episode) that is a FILLED slot in
    # this same spine (held by a DIFFERENT archiveID = a true duplicate). The
    # title-only fallback was dropped: generic "Pilot"/"Episode 1" titles collide
    # across shows, and same-named films/shows aren't the same work.
    se = parse_se((it.get("archiveID") or "") + " " + synopsis(it) + " " + (it.get("title") or ""))
    if se and se in sp["slots"] and sp["slots"][se] != aid:
        return (sp, sp["slots"][se], f"S{se[0]}E{se[1]}")
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write excluded=true (default: report only)")
    args = ap.parse_args()
    if not CATALOG.exists():
        print("[dedupe-eps] no catalog.json (run catalog_release.py fetch first)")
        return 2

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    spines = load_spines()
    print(f"[dedupe-eps] {len(spines)} usable spines")

    hits = []
    for it in items:
        if it.get("excluded") or it.get("seriesID"):
            continue
        if it.get("contentType") not in ORPHAN_TYPES or not it.get("downloadURL"):
            continue
        if _NOT_SINGLE.search((it.get("title") or "") + " " + (it.get("archiveID") or "")
                              + " " + synopsis(it)):
            continue
        m = find_duplicate(it, spines)
        if m:
            hits.append((it, m))

    print(f"[dedupe-eps] {len(hits)} confirmed orphan-episode duplicates "
          f"{'(APPLYING)' if args.apply else '(dry-run)'}")
    for it, (sp, canon, why) in hits:
        print(f"  [{why:6}] {(it.get('archiveID') or '')[:42].ljust(42)} "
              f"'{(it.get('title') or '')[:30]}' -> {sp['raw']} ({canon})")
        if args.apply:
            it["excluded"] = True
            it["episodeDuplicate"] = True
            it["duplicateOf"] = canon

    if args.apply and hits:
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)
        print(f"[dedupe-eps] wrote {len(hits)} exclusions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
