#!/usr/bin/env python3
"""
backfill_metadata.py — Phase 1 of docs/METADATA-EXPANSION.md (Decision 046). Pull rich, searchable/
filterable metadata our APIs expose INTO the catalog so the apps need no runtime API call.

ONE TMDb /movie/{id}?append_to_response=keywords,alternative_titles,credits call per matched film
feeds most fields; OMDb adds Awards (+ Writer fallback). Each field is stored as an additive JSON
key; build_sqlite (Phase 2) routes it to the right layer (blob / FTS / join table) — this tool only
fills the catalog. Resumable via a `metaSource` marker + a per-id cache. Authoritative, so it fills
EMPTY fields and adds new ones; it does not clobber a non-empty curated value.

Fields set (when present): keywords[], originalTitle, akaTitles[], writer, composer,
cinematographer, studios[], franchise, tagline, releaseDate, awards, and cast[].tmdbPersonID.

Run: TMDB_BEARER_TOKEN / OMDB_KEY in env or Secrets.xcconfig. Mutates ./catalog.json
(catalog_release.py fetch before, publish after). CI-bounded with --limit.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T
import omdb_lib as O

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
CACHE = REPO / "tools" / ".metadata_cache.json"

_WRITER_JOBS = {"Writer", "Screenplay", "Story", "Author", "Novel"}
_MAX_AKA = 8          # cap alt-titles fed to search so the blob/FTS stay lean


def _norm(s: str) -> str:
    return (s or "").strip().lower()


def tmdb_meta(tmdb_id, token, sess) -> dict | None:
    try:
        r = sess.get(f"{T.TMDB_API}/movie/{tmdb_id}",
                     params={"append_to_response": "keywords,alternative_titles,credits"},
                     headers=T._headers(token), timeout=25)
        if not r.ok:
            return None
        d = r.json()
    except Exception:
        return None

    out: dict = {}
    kws = [k.get("name") for k in (d.get("keywords") or {}).get("keywords", []) if k.get("name")]
    if kws:
        out["keywords"] = kws[:30]

    title = d.get("title") or ""
    orig = d.get("original_title") or ""
    if orig and _norm(orig) != _norm(title):
        out["originalTitle"] = orig
    akas, seen = [], {_norm(title), _norm(orig)}
    for t in (d.get("alternative_titles") or {}).get("titles", []):
        nm = (t.get("title") or "").strip()
        if nm and _norm(nm) not in seen:
            akas.append(nm); seen.add(_norm(nm))
        if len(akas) >= _MAX_AKA:
            break
    if akas:
        out["akaTitles"] = akas

    crew = (d.get("credits") or {}).get("crew") or []
    writer = next((c["name"] for c in crew if c.get("job") in _WRITER_JOBS and c.get("name")), None)
    composer = next((c["name"] for c in crew if c.get("job") == "Original Music Composer" and c.get("name")), None)
    dop = next((c["name"] for c in crew if c.get("job") == "Director of Photography" and c.get("name")), None)
    if writer:   out["writer"] = writer
    if composer: out["composer"] = composer
    if dop:      out["cinematographer"] = dop

    studios = [c.get("name") for c in (d.get("production_companies") or []) if c.get("name")]
    if studios:
        out["studios"] = studios[:6]
    bc = d.get("belongs_to_collection")
    if bc and bc.get("name"):
        out["franchise"] = bc["name"]
    if d.get("tagline"):
        out["tagline"] = d["tagline"].strip()
    if d.get("release_date"):
        out["releaseDate"] = d["release_date"]

    # cast person ids — keyed by normalized name so the catalog's existing cast entries can adopt them.
    cast = (d.get("credits") or {}).get("cast") or []
    out["_personIDsByName"] = {_norm(c["name"]): c["id"] for c in cast if c.get("name") and c.get("id")}
    return out


def omdb_awards(imdb_id, key, sess) -> tuple[str | None, str | None]:
    try:
        r = sess.get("https://www.omdbapi.com/", params={"i": imdb_id, "apikey": key}, timeout=20)
        if not r.ok:
            return None, None
        d = r.json()
        aw = (d.get("Awards") or "").strip()
        wr = (d.get("Writer") or "").split(",")[0].strip()
        return (aw if aw and aw != "N/A" else None), (wr if wr and wr != "N/A" else None)
    except Exception:
        return None, None


def apply(it: dict, meta: dict) -> None:
    person_ids = meta.pop("_personIDsByName", {})
    for k, v in meta.items():
        it[k] = v                                   # additive metadata keys
    if person_ids and isinstance(it.get("cast"), list):
        for c in it["cast"]:
            if isinstance(c, dict) and not c.get("tmdbPersonID"):
                pid = person_ids.get(_norm(c.get("name", "")))
                if pid:
                    c["tmdbPersonID"] = pid


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = T.load_tmdb_token(SECRETS)
    key = O.load_omdb_key(SECRETS)
    if not token:
        print("[meta] no TMDB_BEARER_TOKEN — nothing to do", file=sys.stderr)
        return 0

    cat = json.loads(CATALOG.read_text())
    items = cat["items"]

    def needs(it) -> bool:
        if it.get("metaSource") and not args.refresh:
            return False
        return bool(it.get("tmdbID"))               # TMDb id is the gate (the workhorse source)

    targets = [it for it in items if needs(it)]
    targets.sort(key=lambda it: -(it.get("popularityScore") or it.get("downloads") or 0))
    if args.limit:
        targets = targets[: args.limit]
    print(f"[meta] {len(targets)} items to enrich "
          f"(done={sum(1 for it in items if it.get('metaSource'))})", flush=True)

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    sess = requests.Session()
    filled = empty = 0
    for i, it in enumerate(targets):
        aid = it["archiveID"]
        if aid in cache and not args.refresh:
            meta = cache[aid]
        else:
            meta = tmdb_meta(it["tmdbID"], token, sess) or {}
            time.sleep(0.26)
            if key and it.get("imdbID"):
                aw, wr = omdb_awards(it["imdbID"], key, sess)
                if aw: meta["awards"] = aw
                if wr and not meta.get("writer"): meta["writer"] = wr
                time.sleep(0.12)
            cache[aid] = meta
            if i % 200 == 0:
                CACHE.write_text(json.dumps(cache))
        # strip the helper key from what we count as "real" metadata
        real = {k: v for k, v in meta.items() if k != "_personIDsByName"}
        if real or meta.get("_personIDsByName"):
            if not args.dry_run:
                apply(it, dict(meta))
                it["metaSource"] = "tmdb"
            filled += 1 if real else 0
        else:
            if not args.dry_run:
                it["metaSource"] = "none"
            empty += 1
        if i and i % 500 == 0:
            print(f"[meta]  {i}/{len(targets)} filled={filled} empty={empty}", flush=True)
            if not args.dry_run:
                CATALOG.write_text(json.dumps(cat, ensure_ascii=False))

    CACHE.write_text(json.dumps(cache))
    if not args.dry_run:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False))
    print(f"[meta] DONE filled={filled} empty={empty}"
          f"{' (dry-run)' if args.dry_run else ' -> wrote catalog.json'}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
