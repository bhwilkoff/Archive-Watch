#!/usr/bin/env python3
"""
enrich_subtitles.py — attach subtitle/caption tracks to catalog items.

PHASE 1 source: archive.org's OWN caption files. Many Archive video items ship
auto-generated ASR captions (`<name>.asr.srt`) or uploader-provided subtitle
files (`.srt`/`.vtt`, sometimes language-tagged like `Film.es.srt`). These are
FREE, already hosted on the same item we stream, and carry no redistribution/ToS
issue — so they're the robust-coverage backbone (~33%+ of films in a sample).
This tool scans each playable item's file list and records the tracks in a new
additive `captions` field that every client side-loads onto the progressive MP4.

Layered sources (later phases, NOT here): OpenSubtitles by imdb/tmdb id
(human-made, multi-language; non-commercial + backlink per their ToS) for titles
Archive doesn't caption, and Whisper-generated VTT (we own the output — the films
are public domain) to fill the remaining gaps.

Per item it writes:
  captions: [{ "lang": "en", "label": "English (auto)", "format": "srt",
               "url": "https://archive.org/download/<id>/<file>",
               "source": "archive-asr" }]
and marks `captionsChecked` so re-runs are cheap (resumable). Bounded per run
(Archive metadata is fetched per item); popularity-first. `--refresh` re-checks.

Run: python tools/enrich_subtitles.py [--limit N] [--workers 12] [--dry-run]
Catalog I/O via local catalog.json (catalog_release.py fetch first in CI).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import threading
import urllib.parse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

# archive.org tags caption files with these `format` values in the search index
# (.srt → "SubRip", .vtt → "Web Video Text Tracks"). The advancedsearch API
# returns an item's full format list AND accepts many identifiers per query, so
# a batched search pre-filter tells us which items even HAVE a caption file —
# letting us skip the per-item /metadata fetch for the ~84% that don't (verified
# reliable: format:SubRip ⇔ a real .srt exists). Items absent from the search
# index fall through to a /metadata fetch so nothing is missed.
SEARCH_URL = "https://archive.org/advancedsearch.php"
CAPTION_FORMATS = {"SubRip", "Web Video Text Tracks"}
SEARCH_BATCH = 60          # ids per advancedsearch query (URL-length safe)


def search_caption_filter(targets, workers, session):
    """Return {archiveID: 'cc'|'none'} for targets resolvable via the search
    index. Ids NOT in the returned dict were absent from search (dark/just-
    ingested) and must fall through to a /metadata fetch."""
    verdict = {}
    lock = threading.Lock()
    batches = [targets[i:i + SEARCH_BATCH] for i in range(0, len(targets), SEARCH_BATCH)]

    def do(batch):
        ids = [it["archiveID"] for it in batch]
        q = "identifier:(" + " OR ".join(ids) + ")"
        url = (SEARCH_URL + "?" +
               urllib.parse.urlencode({"q": q, "rows": len(ids), "output": "json"}) +
               "&fl[]=identifier&fl[]=format")
        try:
            r = session.get(url, headers={"User-Agent": A.UA}, timeout=30)
            docs = r.json()["response"]["docs"]
        except Exception:
            return {}                       # whole batch falls back to /metadata
        out = {}
        for d in docs:
            fmts = d.get("format") or []
            if isinstance(fmts, str):
                fmts = [fmts]
            out[d["identifier"]] = "cc" if any(f in CAPTION_FORMATS for f in fmts) else "none"
        return out

    with ThreadPoolExecutor(max_workers=workers) as ex:
        for res in ex.map(do, batches):
            with lock:
                verdict.update(res)
    return verdict

CAPTION_EXTS = (".srt", ".vtt")            # formats every client can use (Android
                                           # natively; web/Apple convert SRT→VTT).
# Common language tokens that may appear in a caption filename, → BCP-47 code.
_LANG = {
    "en": "en", "eng": "en", "english": "en",
    "es": "es", "spa": "es", "spanish": "es", "espanol": "es",
    "fr": "fr", "fre": "fr", "fra": "fr", "french": "fr",
    "de": "de", "ger": "de", "deu": "de", "german": "de",
    "it": "it", "ita": "it", "italian": "it",
    "pt": "pt", "por": "pt", "portuguese": "pt",
    "ru": "ru", "rus": "ru", "russian": "ru",
    "ja": "ja", "jpn": "ja", "japanese": "ja",
    "zh": "zh", "chi": "zh", "zho": "zh", "chinese": "zh",
    "nl": "nl", "dut": "nl", "dutch": "nl",
    "ar": "ar", "ara": "ar", "arabic": "ar",
    "ko": "ko", "kor": "ko", "korean": "ko",
}
_LANG_NAMES = {
    "en": "English", "es": "Spanish", "fr": "French", "de": "German", "it": "Italian",
    "pt": "Portuguese", "ru": "Russian", "ja": "Japanese", "zh": "Chinese",
    "nl": "Dutch", "ar": "Arabic", "ko": "Korean",
}


def classify_caption(filename):
    """Return (lang, label, format, source) for a caption file, or None if it
    isn't one. ASR files default to English-auto; a `.xx.srt` segment overrides
    the language."""
    low = filename.lower()
    ext = next((e for e in CAPTION_EXTS if low.endswith(e)), None)
    if not ext:
        return None
    fmt = ext.lstrip(".")
    stem = low[: -len(ext)]
    # SKIP archive.org auto-ASR captions entirely (Decision 039b): on the catalog's
    # old-film audio they hallucinate into word-salad ("all the world all right",
    # "why why why" x19) that matches nothing on screen — a wrong subtitle is worse
    # than none. Only human/uploader caption files are ingested.
    if ".asr" in stem or stem.endswith("asr"):
        return None
    # Language from a dotted/underscored token anywhere in the stem.
    lang = None
    for tok in re.split(r"[._-]", stem):
        if tok in _LANG and tok != "asr":
            lang = _LANG[tok]
            break
    if lang is None:
        lang = "en"                         # untagged uploader sub defaults to English
    name = _LANG_NAMES.get(lang, lang.upper())
    return lang, name, fmt, "archive"


def captions_for(iaid, files):
    """Build the captions list for an item from its Archive file list.
    Dedupes by language, preferring a non-ASR (human) track and then .vtt."""
    found = {}
    for f in files:
        name = f.get("name") or ""
        c = classify_caption(name)
        if not c:
            continue
        lang, label, fmt, source = c
        url = A.download_url(iaid, name)
        cand = {"lang": lang, "label": label, "format": fmt, "url": url, "source": source}
        cur = found.get(lang)
        if cur is None:
            found[lang] = cand
            continue
        # Prefer human over ASR, then vtt over srt.
        better = (cur["source"] == "archive-asr" and source != "archive-asr") or \
                 (cur["source"] == source and cur["format"] == "srt" and fmt == "vtt")
        if better:
            found[lang] = cand
    # English first, then alphabetical.
    return sorted(found.values(), key=lambda c: (c["lang"] != "en", c["lang"]))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--refresh", action="store_true", help="re-check already-checked items")
    ap.add_argument("--dry-run", action="store_true", help="report only; write nothing")
    ap.add_argument("--no-prefilter", action="store_true",
                    help="skip the search pre-filter; /metadata-fetch every item (old behavior)")
    args = ap.parse_args()

    if not CATALOG.exists():
        print("[subs] no catalog.json (run catalog_release.py fetch first)")
        return 2

    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat

    def candidate(it):
        if not it.get("downloadURL") or it.get("excluded"):
            return False
        if it.get("contentType") in ("tv-series",):     # series cards aren't items
            return False
        return args.refresh or not it.get("captionsChecked")

    targets = [it for it in items if candidate(it)]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[subs] {len(targets)} items to scan for captions "
          f"(workers {args.workers}{' DRY-RUN' if args.dry_run else ''})", flush=True)

    tally = Counter()
    lock = threading.Lock()
    session = requests.Session()

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    # Phase A — batched search pre-filter. Items the index says have NO caption
    # file are marked checked WITHOUT a /metadata fetch (the big win); only
    # caption-bearing + not-indexed items proceed to Phase B.
    verdict = {}
    if targets and not args.no_prefilter:
        verdict = search_caption_filter(targets, args.workers, session)
        skipped = [it for it in targets if verdict.get(it["archiveID"]) == "none"]
        for it in skipped:
            if not args.dry_run:
                it["captionsChecked"] = True
                it.pop("captions", None)
            tally["none"] += 1
        if not args.dry_run and skipped:
            flush()
        targets = [it for it in targets if verdict.get(it["archiveID"]) != "none"]
        print(f"[subs] prefilter: skipped {len(skipped)} no-caption items; "
              f"{len(targets)} need /metadata", flush=True)

    def work(it):
        try:
            meta = A.archive_meta(it["archiveID"], session)
        except Exception:
            return "unreachable"            # leave unmarked; retry next run
        caps = captions_for(it["archiveID"], meta.get("files") or [])
        if args.dry_run:
            return f"found_{len(caps)}" if caps else "none"
        it["captionsChecked"] = True
        if caps:
            it["captions"] = caps
            return "captioned"
        # Clear any stale captions if a refresh found none.
        it.pop("captions", None)
        return "none"

    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(work, it) for it in targets]
        for fut in as_completed(futs):
            v = fut.result()
            with lock:
                tally[v] += 1
                done += 1
            if (done % 200 == 0 or done == len(targets)) and not args.dry_run:
                flush()
            if done % 500 == 0 or done == len(targets):
                print(f"[{done}/{len(targets)}] {dict(tally)}", flush=True)
    if not args.dry_run:
        flush()
    print(f"[subs] done: {dict(tally)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
