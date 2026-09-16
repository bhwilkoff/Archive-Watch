#!/usr/bin/env python3
"""
judge_year_twins.py — a matched film whose TMDb year contradicts the item's
year by more than five is one of two things: the same film under an
uploader's wrong year (Nosferatu "1929"), or a same-title DIFFERENT film
(Kipps 1921 vs 1941). Offline they look identical. TMDb settles it: search the
title at the ITEM's year — if a different film of that title exists there,
the current match is the wrong twin and is cleared (ids, art, synopsis,
credits); if none does, the item's year is wrong and the film's is adopted.

Report-first; --apply writes catalog.json. 26 items on 2026-09-16.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402
import tmdb_lib as T  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
VERIFY = REPO / "shared/editorial/tmdb_verify_cache.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    cat = json.loads(CATALOG.read_text())
    vc = json.loads(VERIFY.read_text())
    vc = vc.get("entries", vc)
    token = T.load_tmdb_token(SECRETS)
    if not token:
        sys.exit("no TMDB_BEARER_TOKEN")
    sess = requests.Session()

    cleared = redated = kept = 0
    for it in cat["items"]:
        if it.get("excluded") or not it.get("tmdbID"):
            continue
        f = vc.get(str(it["tmdbID"])) or {}
        fy, iy = f.get("year"), it.get("year")
        if not (isinstance(fy, int) and isinstance(iy, int) and abs(fy - iy) > 5):
            continue
        idy = [int(y) for y in re.findall(r"(?<!\d)(1[89]\d\d|20\d\d)(?!\d)", it["archiveID"])]
        if any(abs(fy - y) <= 2 for y in idy):
            continue
        title = it.get("title") or ""
        r = sess.get(f"{T.TMDB_API}/search/movie", params={"query": title, "year": iy, "include_adult": "false"},
                     headers=T._headers(token), timeout=20)
        time.sleep(0.1)
        twins = []
        for m in (r.json().get("results") or []) if r.ok else []:
            ry = (m.get("release_date") or "")[:4]
            if m.get("id") != it["tmdbID"] and ry.isdigit() and abs(int(ry) - iy) <= 1 \
                    and T._norm(m.get("title") or "") == T._norm(title):
                twins.append((m["id"], m.get("title"), ry))
        if twins:
            verdict = f"WRONG TWIN -> clear; a {twins[0][2]} {twins[0][1]!r} exists (tmdb {twins[0][0]})"
            cleared += 1
            if args.apply:
                R._clear_wrong_artwork(it, None)
                it["matchVerdict"] = "cleared_year_twin"
                it["matchVerified"] = True
                it["matchCheckedAt"] = time.strftime("%Y-%m-%d")
        elif T._norm(f.get("title") or "") != T._norm(title) or any(abs(iy - y) <= 1 for y in idy):
            # A differing title is a fuzzy match, not a year slip ("The Big
            # Bang" -> "The Big Boss"); an archive id naming the item's own
            # year is the uploader's deliberate evidence (Decision 114).
            verdict = "UNJUDGED — title differs or the id names the item's year"
            kept += 1
        else:
            verdict = f"same film, year {iy} -> {fy}"
            redated += 1
            if args.apply:
                it["year"] = fy
                it["decade"] = R.decade_of(fy)
                it["isSilentFilm"] = bool(fy < R.SILENT_CUTOFF)
                it["yearSource"] = "tmdb-match"
        print(f"{it['archiveID'][:30]:30} {title[:26]:26} item {iy} tmdb {f.get('title','')[:22]!r} {fy}: {verdict}")
    print(f"cleared {cleared} · re-dated {redated} · unjudged {kept}")
    if args.apply:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False, separators=(",", ":")))
        print("wrote catalog.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
