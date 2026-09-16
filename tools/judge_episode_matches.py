#!/usr/bin/env python3
"""
judge_episode_matches.py — a TV EPISODE matched to a FILM.

An item whose archive id or title carries an episode marker (S01E02, 5x09,
"Episode 4", "Season 1") and whose external match is a film is judged
against that film's title: when none of the item's titles agrees (sequence
ratio >= 0.55, or one contains the other), the match is cleared. Genuine
serials keep theirs — "Les Vampires - Episode 3" agrees with the serial's
"Les Vampires" aka. Found 2026-09-16: "Newhart Season 1" wearing Twelve Plus
One (1969), Captain Video wearing The Maltese Falcon, a Jackie Gleason hour
wearing 4D Man, The Walking Dead Episode 4 wearing a 1916 film, a K-pop dance
clip wearing a 1920 one.

Report-first; --apply writes catalog.json.
"""
from __future__ import annotations

import argparse
import difflib
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
SE = re.compile(r"(?<![a-z0-9])(s\d{1,2}[ _-]?e\d{1,3}|\d{1,2}x\d{2}|season[ _-]?\d|ep(isode)?[ _-]?\d{1,3})(?![a-z0-9])", re.I)


def n(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def agrees(item_title, film_titles):
    """A serial chapter: the item's OWN title begins with the film's title
    ("Robinson Crusoe of Clipper Island - Chapter 3", "Les Vampires - Episode
    3" against the serial's aka). Never the item's canonicalTitle or akas —
    those came from the match and would agree with anything."""
    a = n(item_title)
    for b in film_titles:
        b2 = n(b)
        if len(b2.split()) >= 2 and a.startswith(b2):
            return True
    return False


def film_titles(it, token, sess):
    out = []
    try:
        if it.get("tmdbID"):
            r = sess.get(f"{T.TMDB_API}/movie/{it['tmdbID']}", headers=T._headers(token), timeout=20)
            if r.ok:
                d = r.json(); out += [d.get("title"), d.get("original_title")]
        elif it.get("imdbID"):
            r = sess.get(f"{T.TMDB_API}/find/{it['imdbID']}", params={"external_source": "imdb_id"},
                         headers=T._headers(token), timeout=20)
            if r.ok:
                d = r.json()
                for m in (d.get("movie_results") or []) + (d.get("tv_results") or []):
                    out += [m.get("title") or m.get("name"), m.get("original_title") or m.get("original_name")]
        time.sleep(0.1)
    except Exception as e:  # noqa: BLE001
        print(f"  ! {it['archiveID']}: {e}")
    return [t for t in out if t]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--also", default="", help="comma-separated archive ids to clear on a hand judgement "
                    "(an exact two-word title can pass the serial test: '8-26-09 Episode 2 - Straight Through')")
    args = ap.parse_args()
    also = {x.strip() for x in args.also.split(",") if x.strip()}
    cat = json.loads(CATALOG.read_text())
    token = T.load_tmdb_token(SECRETS)
    if not token:
        sys.exit("no TMDB_BEARER_TOKEN")
    sess = requests.Session()
    cleared = kept = unknown = 0
    for it in cat["items"]:
        if it.get("excluded") or not (it.get("tmdbID") or it.get("imdbID")):
            continue
        if it.get("contentType") in ("tv-series", "tv-episode"):
            continue
        if not (SE.search(it["archiveID"]) or SE.search(it.get("title") or "")):
            continue
        ft = film_titles(it, token, sess)
        # The film's akas (from TMDb itself) let "Les Vampires" match the
        # serial's English title; the ITEM's akas are never consulted.
        try:
            if it.get("tmdbID"):
                r = sess.get(f"{T.TMDB_API}/movie/{it['tmdbID']}/alternative_titles", headers=T._headers(token), timeout=20)
                if r.ok:
                    ft += [x.get("title") for x in (r.json().get("titles") or []) if x.get("title")]
        except Exception:  # noqa: BLE001
            pass
        if not ft:
            unknown += 1
            print(f"{it['archiveID'][:34]:34} {str(it.get('title'))[:28]:28} UNKNOWN — film title not resolvable")
            continue
        if agrees(it.get("title") or "", ft) and it["archiveID"] not in also:
            kept += 1
            print(f"{it['archiveID'][:34]:34} {str(it.get('title'))[:28]:28} keep — {ft[0]!r}")
            continue
        cleared += 1
        print(f"{it['archiveID'][:34]:34} {str(it.get('title'))[:28]:28} CLEAR — matched film {ft[0]!r}")
        if args.apply:
            R._clear_wrong_artwork(it, None)
            it["matchVerdict"] = "cleared_episode_as_film"
            it["matchVerified"] = True
            it["matchCheckedAt"] = time.strftime("%Y-%m-%d")
    print(f"cleared {cleared} · kept {kept} · unknown {unknown}")
    if args.apply:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False, separators=(",", ":")))
        print("wrote catalog.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
