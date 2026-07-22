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
import difflib
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
import verify_external_match as V   # archive_meta: Decision-026 authoritative signals

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
SECRETS = REPO / "Secrets.xcconfig"
CACHE = REPO / "tools" / ".match_cache.json"

# Titles that are not a single film — never try to match these to one (false-match magnets).
# Applied to BOTH the cleaned title AND the archiveID slug (markers routinely live only in the id).
_NOT_A_FILM = re.compile(
    r"(?i)\b(compilation|collection|complete[\s-]series|complete[\s-]season|"
    r"filmography|all films|serial|"
    r"double feature|triple feature|marathon|playlist|various|"
    r"movie[\s-]?trailers?|trailers?|"
    r"full episodes|tribute|best of)\b")
_YEAR = re.compile(r"\b(18|19|20)\d\d\b")

# Similarity floors — abstain-over-wrong for generic/short and pre-1950 titles.
_STOP = {"the", "a", "an", "of", "and", "or", "to", "in", "on", "for", "with"}
_OLD_CUTOFF = 1950


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def _sim(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, _norm(a), _norm(b)).ratio()


def _n_sig(title: str) -> int:
    return len([w for w in _norm(title).split() if w not in _STOP])


def _slug_words(archive_id: str) -> str:
    """archiveID -> space-separated words, splitting camelCase + digit/letter runs so the
    not-a-film markers fire on separator-less ids (…1954MovieTrailer -> … Movie Trailer)."""
    s = (archive_id or "").replace("_", " ").replace("-", " ")
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", s)
    s = re.sub(r"(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])", " ", s)
    return s


def _slug_title(archive_id: str) -> str:
    s = re.sub(r"_\d+$", "", archive_id or "").replace("-", " ").replace("_", " ")
    return _YEAR.sub("", s).strip()


def _fuzzy_accept(it: dict, rec: dict, gate_year: int | None) -> bool:
    """Gate a FUZZY (title-based) match before adopting it. Bias hard against a
    wrong identity: pre-1950 needs a near-exact title; a 1-2 significant-word
    (generic) title needs an EXACT title AND an EXACT year — otherwise abstain."""
    mt = rec.get("title") or ""
    cands = _candidates(it)
    sim = max((_sim(c, mt) for c in cands), default=0.0)
    exact = any(_norm(c) == _norm(mt) for c in cands)
    ry = rec.get("year")
    # Pre-1950: a common modern title can outrank an obscure old one — demand a tight title.
    if gate_year and gate_year < _OLD_CUTOFF and not exact and sim < 0.85:
        return False
    # Generic 1-2-word title: exact title + exact year, else abstain (no Archive id to anchor).
    if _n_sig(mt) <= 2:
        if not exact or not (ry and gate_year and ry == gate_year):
            return False
    return True


def _resolve_imdb(imdb: str, token: str, key: str | None, sess) -> tuple[dict | None, str]:
    """Resolve an AUTHORITATIVE Archive-declared imdb id to a full record.
    Prefer TMDb /find (poster + tmdb_id), fall back to OMDb by id. Returns
    (rec, src) where src is 'archive-id' on success, else (None, '')."""
    try:
        mid = T.find_by_imdb(imdb, token, sess)
        if mid:
            d = T.movie_detail(mid, token, sess)
            if d:
                d["imdb_id"] = d.get("imdb_id") or imdb
                return d, "archive-id"
    except Exception:
        pass
    if key:
        try:
            m = O.fetch_omdb_full(key, sess, imdb_id=imdb)
            if m:
                return m, "archive-id"
        except Exception:
            pass
    return None, ""


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


_WD_API = "https://www.wikidata.org/w/api.php"
_WD_UA = "ArchiveWatch/1.0 (https://archivewatch.org; catalog enrichment)"
# film + the common film subclasses (P31). The YEAR gate is the real safety; this just blocks
# matching a same-named book/album/person.
_FILM_QIDS = {"Q11424", "Q24862", "Q202866", "Q93204", "Q506240", "Q24869",
              "Q229390", "Q18011172", "Q130232", "Q500694"}


def _wikidata_match(cand: str, year: int, sess) -> dict | None:
    """Search Wikidata for a FILM whose label matches `cand` and whose publication year is within ±2,
    returning its English label (canonical) + IMDb id (P345). Catches obscure/foreign films TMDb +
    OMDb miss; the imdb id then lets the normal OMDb enrichment complete the record."""
    try:
        r = sess.get(_WD_API, headers={"User-Agent": _WD_UA}, timeout=20, params={
            "action": "wbsearchentities", "search": cand, "language": "en",
            "type": "item", "limit": 6, "format": "json"})
        cands = [c["id"] for c in (r.json().get("search") or [])]
    except Exception:
        return None
    for qid in cands[:5]:
        try:
            r = sess.get(f"https://www.wikidata.org/wiki/Special:EntityData/{qid}.json",
                         headers={"User-Agent": _WD_UA}, timeout=20)
            ent = r.json()["entities"][qid]
        except Exception:
            continue
        claims = ent.get("claims", {})
        p31 = [(c.get("mainsnak", {}).get("datavalue", {}) or {}).get("value", {}).get("id")
               for c in claims.get("P31", [])]
        if not any(q in _FILM_QIDS for q in p31):
            continue
        yrs = []
        for c in claims.get("P577", []):
            tm = (c.get("mainsnak", {}).get("datavalue", {}) or {}).get("value", {}).get("time", "")
            m = re.search(r"(\d{4})", tm or "")
            if m:
                yrs.append(int(m.group(1)))
        match_yr = next((yy for yy in yrs if abs(yy - year) <= 2), None)
        if match_yr is None:
            continue
        label = ((ent.get("labels", {}) or {}).get("en", {}) or {}).get("value")
        imdb = None
        for c in claims.get("P345", []):
            v = (c.get("mainsnak", {}).get("datavalue", {}) or {}).get("value")
            if v:
                imdb = v
                break
        if label or imdb:
            return {"imdb_id": imdb, "title": label, "year": match_yr}
    return None


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
    mt = (d.get("Title") or "").strip()
    # Title-similarity floor (OMDb `t=` is fuzzy — Assassination 0.59 / Heavenly Bodies
    # slipped through with year-only). Short/generic (<=2 sig words) needs a tighter 0.8.
    sim = _sim(cand, mt)
    floor = 0.8 if _n_sig(mt) <= 2 else 0.6
    if sim < floor:
        return None
    return {"imdb_id": d["imdbID"], "title": mt or None,
            "year": int(ry.group(1))}


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
        # tv-special is not a film (Decision 036) — exclude alongside series/episodes.
        if it.get("contentType") in ("tv-series", "tv-episode", "tv-special"):
            return False
        if not it.get("year") or R.is_junk(it):
            return False
        # Require a color signal so the B&W x year guard (Decision 025) always has one.
        if not it.get("colorMode"):
            return False
        # Not-a-film markers in EITHER the title or the archiveID slug.
        if _NOT_A_FILM.search(it.get("title") or "") or _NOT_A_FILM.search(_slug_words(it.get("archiveID"))):
            return False
        return True

    targets = [it for it in items if needs(it)]
    targets.sort(key=lambda it: -(it.get("popularityScore") or it.get("downloads") or 0))
    if args.limit:
        targets = targets[: args.limit]
    print(f"[match] {len(targets)} unmatched films to try", flush=True)

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    sess = requests.Session()
    tmdb_n = omdb_n = wd_n = aid_n = miss = 0

    for i, it in enumerate(targets):
        aid, year = it["archiveID"], it["year"]
        if aid in cache and not args.refresh:
            rec, src = cache[aid].get("rec"), cache[aid].get("src")
        else:
            rec = src = None
            # Decision 026: consult the Archive item's OWN signals BEFORE any fuzzy
            # title search. Best-effort (network) — on failure fall through to the
            # guarded fuzzy path, never block.
            a_imdb, a_year = V.archive_meta(aid)
            gate_year = a_year or year   # prefer the trustworthy Archive date year
            if a_imdb:
                # Authoritative id declared by the upload — adopt directly, no fuzzy search.
                rec, src = _resolve_imdb(a_imdb, token, key, sess); time.sleep(0.26)
                if not rec:  # id we couldn't resolve — record the id, skip fuzzy (don't guess).
                    rec, src = {"imdb_id": a_imdb, "title": None}, "archive-id"
            if not rec:
                for cand in _candidates(it):
                    try:
                        mid = T.search_movie(cand, gate_year, token, sess)
                    except Exception:
                        mid = None
                    time.sleep(0.26)
                    if mid:
                        d = T.movie_detail(mid, token, sess); time.sleep(0.26)
                        if d and d.get("year") and abs(d["year"] - gate_year) <= 2:
                            rec, src = d, "tmdb"; break
            if not rec and key:
                for cand in _candidates(it):
                    m = _omdb_match(cand, gate_year, key, sess); time.sleep(0.12)
                    if m:
                        rec, src = m, "omdb"; break
            if not rec:                          # 3rd source: Wikidata (obscure/foreign long tail)
                for cand in _candidates(it):
                    m = _wikidata_match(cand, gate_year, sess); time.sleep(0.2)
                    if m:
                        rec, src = m, "wikidata"; break
            # Fuzzy (title-based) accept gate — abstain-over-wrong for old/generic titles.
            if rec and src != "archive-id" and not _fuzzy_accept(it, rec, gate_year):
                rec = src = None
            cache[aid] = {"rec": rec, "src": src}
            if i % 100 == 0:
                CACHE.write_text(json.dumps(cache))

        if rec and src and not args.dry_run:
            O.apply_identity(it, rec)            # imdbID/director/genres/year/cast (empty-only)
            if src in ("tmdb", "archive-id"):
                O.apply_rich(it, rec)            # poster/plot/runtime
                if rec.get("tmdb_id"):
                    it["tmdbID"] = rec["tmdb_id"]
            if rec.get("title"):
                it["canonicalTitle"] = rec["title"]
            it["matchAttempted"] = src
            # ONLY the Archive-id-adopted case is self-certified. Fuzzy matches stay
            # UNVERIFIED so verify_external_match.py re-checks them (Decision 026).
            if src == "archive-id":
                it["matchVerified"] = True
        elif not args.dry_run:
            it["matchAttempted"] = "none"

        if rec and src == "archive-id": aid_n += 1
        elif rec and src == "tmdb": tmdb_n += 1
        elif rec and src == "omdb": omdb_n += 1
        elif rec and src == "wikidata": wd_n += 1
        else: miss += 1
        if i and i % 300 == 0:
            print(f"[match]  {i}/{len(targets)} archive-id={aid_n} tmdb={tmdb_n} omdb={omdb_n} wikidata={wd_n} miss={miss}", flush=True)
            if not args.dry_run:
                CATALOG.write_text(json.dumps(cat, ensure_ascii=False))

    CACHE.write_text(json.dumps(cache))
    if not args.dry_run:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False))
    print(f"[match] DONE archive-id={aid_n} tmdb={tmdb_n} omdb={omdb_n} wikidata={wd_n} miss={miss}"
          f"{' (dry-run)' if args.dry_run else ' -> wrote catalog.json'}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
