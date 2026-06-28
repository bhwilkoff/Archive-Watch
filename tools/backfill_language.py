#!/usr/bin/env python3
"""
backfill_language.py — set each film's AUDIO language from an authoritative source so the
supercut's non-English filter (SubtitleIndex.isNonEnglishAudio) can drop foreign films whose
English subtitle is just a TRANSLATION (foreign audio doesn't belong in an English supercut).

The catalog's existing `language` came from archive.org UPLOADER metadata: only ~45% coverage and
mixed quality (eng/English/ger/...). This backfills the gaps AND upgrades to a consistent ISO 639-1
code from TMDb `original_language` (primary — no daily cap, Decision 007) with OMDb `Language` as a
fallback for items that have an IMDb id but no tmdbID. original_language IS the film's audio
language — exactly what the supercut needs.

Writes `language` (ISO 639-1: en/de/fr/ja/...) + `languageSource` (tmdb|omdb|none). Resumable:
skips items already stamped (cache + languageSource) unless --refresh. Authoritative sources
OVERWRITE the uploader value (so a Japanese film wrongly tagged "English" gets fixed to "ja").
Items with neither tmdbID nor imdbID keep their uploader value (no match to look up).

Run: TMDB_BEARER_TOKEN / OMDB_KEY in env or Secrets.xcconfig. Mutates ./catalog.json in place
(catalog_release.py fetch before, publish after). CI-bounded with --limit; local full run is fine.
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
CACHE = REPO / "tools" / ".language_cache.json"

# OMDb returns language NAMES; map the common ones to ISO 639-1 so the stored value is consistent
# with TMDb's codes (and with the app's English test). An unmapped name is treated as "not found".
_NAME_TO_ISO = {
    "english": "en", "german": "de", "spanish": "es", "french": "fr", "italian": "it",
    "japanese": "ja", "russian": "ru", "portuguese": "pt", "swedish": "sv", "hindi": "hi",
    "mandarin": "zh", "chinese": "zh", "cantonese": "zh", "korean": "ko", "dutch": "nl",
    "polish": "pl", "danish": "da", "norwegian": "no", "finnish": "fi", "czech": "cs",
    "hungarian": "hu", "greek": "el", "turkish": "tr", "arabic": "ar", "hebrew": "he",
    "thai": "th", "tagalog": "tl", "filipino": "tl", "vietnamese": "vi", "romanian": "ro",
    "ukrainian": "uk", "bengali": "bn", "tamil": "ta", "telugu": "te", "urdu": "ur",
    "persian": "fa", "farsi": "fa", "latin": "la", "catalan": "ca", "esperanto": "eo",
    "yiddish": "yi", "icelandic": "is", "serbian": "sr", "croatian": "hr", "bulgarian": "bg",
    "slovak": "sk", "indonesian": "id", "malay": "ms", "afrikaans": "af", "none": "zxx",
}


def tmdb_language(tmdb_id, token, sess) -> str | None:
    """The film's original (audio) language as an ISO 639-1 code, or None."""
    try:
        r = sess.get(f"{T.TMDB_API}/movie/{tmdb_id}", headers=T._headers(token), timeout=20)
        if not r.ok:
            return None
        lang = (r.json().get("original_language") or "").strip().lower()
        return lang or None
    except Exception:
        return None


def omdb_language(imdb_id, key, sess) -> str | None:
    """First listed language from OMDb, mapped to an ISO code, or None."""
    try:
        r = sess.get("https://www.omdbapi.com/", params={"i": imdb_id, "apikey": key}, timeout=20)
        if not r.ok:
            return None
        name = (r.json().get("Language") or "").split(",")[0].strip().lower()
        return _NAME_TO_ISO.get(name)
    except Exception:
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="cap items this run (0 = all)")
    ap.add_argument("--source", choices=["tmdb", "omdb", "both"], default="both")
    ap.add_argument("--refresh", action="store_true", help="re-stamp items already done")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = T.load_tmdb_token(SECRETS)
    key = O.load_omdb_key(SECRETS)
    if not token and args.source in ("tmdb", "both"):
        print("[language] no TMDB_BEARER_TOKEN — TMDb disabled", file=sys.stderr)
    if not key and args.source in ("omdb", "both"):
        print("[language] no OMDB_KEY — OMDb disabled", file=sys.stderr)

    cat = json.loads(CATALOG.read_text())
    items = cat["items"]

    def needs(it) -> bool:
        if it.get("languageSource") and not args.refresh:
            return False
        return bool(it.get("tmdbID") or it.get("imdbID"))

    targets = [it for it in items if needs(it)]
    targets.sort(key=lambda it: -(it.get("popularityScore") or it.get("downloads") or 0))
    if args.limit:
        targets = targets[: args.limit]
    print(f"[language] {len(targets)} items to backfill (source={args.source}, "
          f"already-stamped={sum(1 for it in items if it.get('languageSource'))})", flush=True)

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    sess = requests.Session()
    from_tmdb = from_omdb = none = 0

    for i, it in enumerate(targets):
        aid = it["archiveID"]
        if aid in cache and not args.refresh:
            lang, src = cache[aid].get("lang"), cache[aid].get("src")
        else:
            lang = src = None
            if args.source in ("tmdb", "both") and token and it.get("tmdbID"):
                lang = tmdb_language(it["tmdbID"], token, sess)
                if lang:
                    src = "tmdb"
                time.sleep(0.26)                                  # TMDb ~40 req/10s
            if not lang and args.source in ("omdb", "both") and key and it.get("imdbID"):
                lang = omdb_language(it["imdbID"], key, sess)
                if lang:
                    src = "omdb"
                time.sleep(0.12)
            cache[aid] = {"lang": lang, "src": src}
            if i % 200 == 0:
                CACHE.write_text(json.dumps(cache))

        if lang and src:
            if not args.dry_run:
                it["language"] = lang
                it["languageSource"] = src
            from_tmdb += (src == "tmdb")
            from_omdb += (src == "omdb")
        else:
            if not args.dry_run:
                it["languageSource"] = "none"        # tried, nothing authoritative — keep uploader value
            none += 1

        if i and i % 500 == 0:
            print(f"[language]  {i}/{len(targets)} tmdb={from_tmdb} omdb={from_omdb} none={none}", flush=True)
            if not args.dry_run:
                CATALOG.write_text(json.dumps(cat, ensure_ascii=False))   # periodic checkpoint

    CACHE.write_text(json.dumps(cache))
    if not args.dry_run:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False))
    print(f"[language] DONE tmdb={from_tmdb} omdb={from_omdb} none={none}"
          f"{' (dry-run, nothing written)' if args.dry_run else ' -> wrote catalog.json'}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
