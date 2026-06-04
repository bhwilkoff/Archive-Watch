#!/usr/bin/env python3
"""
tmdb_fill_metadata.py — fill EMPTY synopsis / cast / director from TMDb for
items that have a trusted tmdbID, and resolve imdbID-only items via /find.

Extends the one-shot tmdb_fill_synopsis pass. Measured sandbox-fillable gaps
(2026-06-04, 31,232-item catalog): 63 empty synopsis w/ tmdbID, 2,717 empty
cast, 916 empty director (all among the 16,607 tmdbID items), plus 208
empty-synopsis items carrying imdbID only (resolvable via TMDb /find).

SAFE by construction:
  - only writes fields that are currently empty (never overwrites)
  - tmdbID path uses the existing trusted id (no re-matching)
  - imdbID path uses TMDb /find?external_source=imdb_id (imdbID is a strong key)
  - skips anything TMDb also lacks (no fabrication)
  - genres deliberately NOT filled (catalog uses a Wikidata-style vocabulary
    "drama film"; TMDb's "Drama" would pollute it — leave to remediate/enrich)
  - per-tmdbID JSON cache → cheap, resumable

Cast shape matches the catalog + tmdb_cast_images: {name, character, order,
profilePath}. Run: TMDB_BEARER_TOKEN env / Secrets.xcconfig. Mutates
./catalog.json in place (fetch via catalog_release.py first; publish after).
"""

from __future__ import annotations

import concurrent.futures as cf
import json
import sys
import threading
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmdb_lib as T  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
CACHE = REPO / "tools" / ".tmdb_meta_cache.json"

_local = threading.local()


def _sess():
    if not hasattr(_local, "s"):
        _local.s = requests.Session()
    return _local.s


def _syn(it) -> str:
    s = it.get("synopsis") or ""
    return (" ".join(s) if isinstance(s, list) else s).strip()


def _blank(v) -> bool:
    return not v or (isinstance(v, list) and len(v) == 0)


def _detail(tid, token):
    """Return {plot, director, cast[]} for a tmdbID, or None."""
    r = _sess().get(f"{T.TMDB_API}/movie/{tid}",
                    params={"append_to_response": "credits"},
                    headers=T._headers(token), timeout=20)
    if not r.ok:
        return None
    d = r.json()
    crew = (d.get("credits") or {}).get("crew") or []
    cast = (d.get("credits") or {}).get("cast") or []
    director = next((c["name"] for c in crew if c.get("job") == "Director"), None)
    cast_out = [{"name": c.get("name"), "character": c.get("character") or None,
                 "order": c.get("order"),
                 "profilePath": c.get("profile_path")}
                for c in cast[:15] if c.get("name")]
    return {"plot": (d.get("overview") or "").strip(),
            "director": director, "cast": cast_out}


def _find_tmdb_id(imdb, token):
    r = _sess().get(f"{T.TMDB_API}/find/{imdb}",
                    params={"external_source": "imdb_id"},
                    headers=T._headers(token), timeout=20)
    if not r.ok:
        return None
    mr = (r.json() or {}).get("movie_results") or []
    return mr[0]["id"] if mr else None


def main() -> int:
    token = T.load_tmdb_token(SECRETS)
    if not token:
        print("[tmdb-meta] no TMDB_BEARER_TOKEN — skipping.")
        return 0

    catalog = json.loads(CATALOG.read_text())
    items = catalog["items"]

    # 1) Resolve imdbID-only empty-synopsis items → tmdbID (so the main pass fills them).
    imdb_only = [it for it in items if not _syn(it) and it.get("imdbID")
                 and not it.get("tmdbID")]
    print(f"[tmdb-meta] resolving {len(imdb_only)} imdbID-only items via /find", flush=True)
    resolved = 0
    with cf.ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(_find_tmdb_id, it["imdbID"], token): it for it in imdb_only}
        for f in cf.as_completed(futs):
            tid = None
            try:
                tid = f.result()
            except Exception:  # noqa: BLE001
                pass
            if tid:
                futs[f]["tmdbID"] = tid
                resolved += 1
    print(f"[tmdb-meta] resolved {resolved} new tmdbIDs from imdbID", flush=True)

    # 2) Main pass: any tmdbID item missing synopsis/cast/director.
    targets = [it for it in items if it.get("tmdbID") and
               (not _syn(it) or _blank(it.get("cast")) or _blank(it.get("director")))]
    print(f"[tmdb-meta] {len(targets)} tmdbID items with a fillable gap", flush=True)

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    clock = threading.Lock()

    def fetch(tid):
        key = str(tid)
        if key in cache:
            return cache[key]
        try:
            rec = _detail(tid, token)
        except Exception:  # noqa: BLE001
            rec = None
        with clock:
            cache[key] = rec
        return rec

    ids = sorted({str(it["tmdbID"]) for it in targets})
    print(f"[tmdb-meta] {len(ids)} unique tmdbIDs to fetch", flush=True)
    with cf.ThreadPoolExecutor(max_workers=8) as ex:
        for i, _ in enumerate(ex.map(fetch, ids), 1):
            if i % 500 == 0:
                print(f"  ... fetched {i}/{len(ids)}", flush=True)
                CACHE.write_text(json.dumps(cache))
    CACHE.write_text(json.dumps(cache))

    s_fill = c_fill = d_fill = 0
    for it in targets:
        rec = cache.get(str(it["tmdbID"]))
        if not rec:
            continue
        if not _syn(it) and rec.get("plot") and len(rec["plot"]) > 20:
            it["synopsis"] = rec["plot"]; s_fill += 1
        if _blank(it.get("cast")) and rec.get("cast"):
            it["cast"] = rec["cast"]; c_fill += 1
        if _blank(it.get("director")) and rec.get("director"):
            it["director"] = rec["director"]; d_fill += 1

    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False))
    print(f"[tmdb-meta] filled synopsis={s_fill} cast={c_fill} director={d_fill} "
          f"| imdb-resolved={resolved} | wrote catalog.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
