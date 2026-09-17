#!/usr/bin/env python3
"""
A cast-anchored film gets its commercial footprint back for the rights audit.

Decision 125 keeps the credits of a no-id film when three or more cast names
reverse-match a TMDb film carrying the item's own title. That anchor proves
the IDENTITY — and the identity is what the rights audit needs: 184 visible
1970s features (Eraserhead, Suspiria, A Bridge Too Far, The Panic in Needle
Park, In the Realm of the Senses) sat in the catalog with `rightsAudit: None`
because they carry no imdbID and so no `imdbVotes`, and Decision 114's
renewal-zone gate (5,000 IMDb votes in 1964-77 = a renewed studio film) never
saw them.

This tool, run LOCALLY (archive.org is not involved, but the keys are local):
  1. re-derives each visible no-id item's anchor tid exactly as remediate does,
  2. fetches the anchor film's imdb_id from TMDb and its vote count from OMDb
     (cache first), and
  3. writes shared/editorial/anchor_footprint.json {archiveID: {...}}.

remediate_catalog then carries `imdbVotes` (and `footprintSource:
"cast-anchored"`) onto the item every build, so audit_rights.py --apply judges
it with the rules it already has. No new hide class is introduced here.

Run: python tools/anchor_rights_footprint.py [--dry-run] [--limit N]
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import sys
import time
from collections import Counter
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402
import tmdb_lib as T  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
CAST_CACHE = REPO / "shared/editorial/tmdb_cast_cache.json"
VERIFY_CACHE = REPO / "shared/editorial/tmdb_verify_cache.json"
OMDB_CACHE = REPO / "shared/editorial/omdb_cache.json"
OUT = REPO / "shared/editorial/anchor_footprint.json"


def _omdb_key():
    v = os.environ.get("OMDB_KEY")
    if v:
        return v
    if SECRETS.exists():
        for line in SECRETS.read_text().splitlines():
            if line.strip().startswith("OMDB_KEY"):
                return line.split("=", 1)[1].strip()
    return None


def anchors(items):
    """{archiveID: tid} for every visible no-id item remediate would anchor."""
    cc = json.loads(CAST_CACHE.read_text()); cc = cc.get("entries", cc)
    by_name = {}
    for tid, cast in cc.items():
        for name in (cast or {}):
            by_name.setdefault(name, set()).add(tid)
    probe = copy.deepcopy(items)
    anchored = R.cast_residue_fixes(probe, Counter())
    out = {}
    for it in probe:
        if it["archiveID"] not in anchored or it.get("excluded"):
            continue
        name_votes = Counter()
        for c in it.get("cast") or []:
            for tid in by_name.get((c.get("name") or "").lower(), ()):
                name_votes[tid] += 1
        if name_votes:
            out[it["archiveID"]] = name_votes.most_common(1)[0][0]
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text())
    have = json.loads(OUT.read_text()) if OUT.exists() else {}
    omdb = json.loads(OMDB_CACHE.read_text()) if OMDB_CACHE.exists() else {}
    omdb = omdb.get("entries", omdb)
    token = T.load_tmdb_token(SECRETS)
    okey = _omdb_key()
    if not token or not okey:
        print("[footprint] need TMDB_BEARER_TOKEN and OMDB_KEY (env or Secrets.xcconfig)", file=sys.stderr)
        return 1

    todo = {aid: tid for aid, tid in anchors(cat["items"]).items() if aid not in have}
    if args.limit:
        todo = dict(list(todo.items())[: args.limit])
    print(f"[footprint] {len(have)} known, {len(todo)} to fetch")
    s = requests.Session()
    n_new = 0
    for aid, tid in todo.items():
        try:
            r = s.get(f"{T.TMDB_API}/movie/{tid}", headers=T._headers(token), timeout=20)
            if not r.ok:
                have[aid] = {"tmdbID": int(tid), "error": f"tmdb {r.status_code}"}
                continue
            d = r.json()
            imdb = d.get("imdb_id") or None
            rec = {"tmdbID": int(tid), "imdbID": imdb, "title": d.get("title"),
                   "year": int(d["release_date"][:4]) if (d.get("release_date") or "")[:4].isdigit() else None,
                   "tmdbVotes": d.get("vote_count")}
            if imdb:
                o = omdb.get(imdb)
                if not o:
                    time.sleep(0.05)
                    orr = s.get("https://www.omdbapi.com/", params={"i": imdb, "apikey": okey}, timeout=20)
                    if orr.ok and orr.json().get("Response") == "True":
                        j = orr.json()
                        v = (j.get("imdbVotes") or "").replace(",", "")
                        o = {"imdb_votes": int(v) if v.isdigit() else None}
                rec["imdbVotes"] = (o or {}).get("imdb_votes")
            have[aid] = rec
            n_new += 1
            time.sleep(0.05)
        except Exception as e:  # noqa: BLE001
            have[aid] = {"tmdbID": int(tid), "error": str(e)[:80]}
    if not args.dry_run:
        OUT.write_text(json.dumps(have, indent=1, ensure_ascii=False, sort_keys=True) + "\n")
    big = sum(1 for v in have.values() if isinstance(v.get("imdbVotes"), int) and v["imdbVotes"] >= 5000)
    print(f"[footprint] fetched {n_new}; {len(have)} anchored films known, {big} with >= 5,000 IMDb votes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
