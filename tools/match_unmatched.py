#!/usr/bin/env python3
"""
match_unmatched.py — recover the CANONICAL match for currently-UNMATCHED films so they get an
authoritative title (Decision 046 title-resolution) + poster + metadata.

WHY they were unmatched: the matcher searched with the cruddy uploader title ("The Dark Corner 1946
(CC) Crime, Film-Noir Lucille Ball…") and got nothing. This pass searches with (a) the CLEANED title
(remediate.sanitize_title) and (b) the archiveID SLUG (often the cleanest source — "convict13" ->
"convict 13"), against TMDb then OMDb, and ACCEPTS only a YEAR-CORROBORATED hit (Decision 026: the
result's year must be within ±2 of the item's own year; tmdb_lib already enforces a 0.6 title-
similarity floor). Validated 8/30 of a sample, 0 false matches. On accept it fills identity + artwork
via the shared apply_* and sets canonicalTitle, so the title resolves and enrichment completes.

Resumable via a `matchAttempted` marker. Mutates ./catalog.json (catalog_release.py fetch before,
publish after). CI-bounded with --limit. Genuinely-not-in-any-DB films (compilations, obscure
amateur/silent, spam) stay unmatched — they have no canonical title anywhere; year-truncation
cleaning is the best we can do for them.

Run: TMDB_BEARER_TOKEN / OMDB_KEY in env or Secrets.xcconfig.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T
import omdb_lib as O
import remediate_catalog as R

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
CACHE = REPO / "tools" / ".match_cache.json"

# Titles that are not a single film — never try to match these to one (false-match magnets).
_NOT_A_FILM = re.compile(
    r"(?i)\b(compilation|collection|complete series|filmography|all films|"
    r"double feature|triple feature|marathon|playlist|various|trailers?|"
    r"full episodes|tribute|best of)\b")
_YEAR = re.compile(r"\b(18|19|20)\d\d\b")


def _slug_title(archive_id: str) -> str:
    s = re.sub(r"_\d+$", "", archive_id or "").replace("-", " ").replace("_", " ")
    return _YEAR.sub("", s).strip()


def _candidates(it: dict) -> list[str]:
    cc = copy.deepcopy(it)
    R.sanitize_title(cc)
    cands, seen = [], set()
    for c in [(cc.get("title") or ""), _slug_title(it.get("archiveID") or "")]:
        c = c.strip()
        k = re.sub(r"[^a-z0-9]+", "", c.lower())
        if len(c) >= 2 and k and k not in seen:
            cands.append(c); seen.add(k)
    return cands


def _omdb_match(cand: str, year: int, key: str, sess) -> dict | None:
    try:
        r = sess.get("https://www.omdbapi.com/",
                     params={"t": cand, "y": str(year), "type": "movie", "apikey": key}, timeout=20)
        d = r.json() if r.ok else {}
    except Exception:
        return None
    if d.get("Response") != "True" or not d.get("imdbID"):
        return None
    ry = re.search(r"(\d{4})", d.get("Year") or "")
    if not ry or abs(int(ry.group(1)) - year) > 2:
        return None
    return {"imdb_id": d["imdbID"], "title": (d.get("Title") or "").strip() or None}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = T.load_tmdb_token(SECRETS)
    key = O.load_omdb_key(SECRETS)
    if not token:
        print("[match] no TMDB_BEARER_TOKEN — nothing to do", file=sys.stderr); return 0

    cat = json.loads(CATALOG.read_text())
    items = cat["items"]

    def needs(it) -> bool:
        if it.get("matchAttempted") and not args.refresh:
            return False
        if it.get("tmdbID") or it.get("imdbID") or it.get("excluded"):
            return False
        if it.get("contentType") in ("tv-series", "tv-episode"):
            return False
        if not it.get("year") or R.is_junk(it):
            return False
        return not _NOT_A_FILM.search(it.get("title") or "")

    targets = [it for it in items if needs(it)]
    targets.sort(key=lambda it: -(it.get("popularityScore") or it.get("downloads") or 0))
    if args.limit:
        targets = targets[: args.limit]
    print(f"[match] {len(targets)} unmatched films to try", flush=True)

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    sess = requests.Session()
    tmdb_n = omdb_n = miss = 0

    for i, it in enumerate(targets):
        aid, year = it["archiveID"], it["year"]
        if aid in cache and not args.refresh:
            rec, src = cache[aid].get("rec"), cache[aid].get("src")
        else:
            rec = src = None
            for cand in _candidates(it):
                try:
                    mid = T.search_movie(cand, year, token, sess)
                except Exception:
                    mid = None
                time.sleep(0.26)
                if mid:
                    d = T.movie_detail(mid, token, sess); time.sleep(0.26)
                    if d and d.get("year") and abs(d["year"] - year) <= 2:
                        rec, src = d, "tmdb"; break
            if not rec and key:
                for cand in _candidates(it):
                    m = _omdb_match(cand, year, key, sess); time.sleep(0.12)
                    if m:
                        rec, src = m, "omdb"; break
            cache[aid] = {"rec": rec, "src": src}
            if i % 100 == 0:
                CACHE.write_text(json.dumps(cache))

        if rec and src and not args.dry_run:
            O.apply_identity(it, rec)            # imdbID/director/genres/year/cast (empty-only)
            if src == "tmdb":
                O.apply_rich(it, rec)            # poster/plot/runtime
                it["tmdbID"] = rec.get("tmdb_id")
            if rec.get("title"):
                it["canonicalTitle"] = rec["title"]
            it["matchAttempted"] = src
            it["matchVerified"] = True
        elif not args.dry_run:
            it["matchAttempted"] = "none"

        if rec and src == "tmdb": tmdb_n += 1
        elif rec and src == "omdb": omdb_n += 1
        else: miss += 1
        if i and i % 300 == 0:
            print(f"[match]  {i}/{len(targets)} tmdb={tmdb_n} omdb={omdb_n} miss={miss}", flush=True)
            if not args.dry_run:
                CATALOG.write_text(json.dumps(cat, ensure_ascii=False))

    CACHE.write_text(json.dumps(cache))
    if not args.dry_run:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False))
    print(f"[match] DONE tmdb={tmdb_n} omdb={omdb_n} miss={miss}"
          f"{' (dry-run)' if args.dry_run else ' -> wrote catalog.json'}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
