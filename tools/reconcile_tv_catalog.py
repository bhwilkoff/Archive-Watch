#!/usr/bin/env python3
"""
reconcile_tv_catalog.py — make the catalog's TV cards match the canonical
series/*.json produced by build_canonical_tv.py.

After the canonical rebuild, the catalog still carries the OLD tv-series
cards (403 old-slug series + 1,064 single items). This step reconciles them:

  1. Delete superseded old series files: any old slug whose content was folded
     into a canonical series (from the rebuild report's consumedRefs) and that
     isn't itself a canonical output.
  2. Rebuild tv-series cards FROM series/*.json — exactly one card per
     surviving series file (canonical or an unmatched-but-kept old one).
  3. Drop standalone cards for single items that became episodes (their
     archiveID now appears inside a series file).
  4. Reclassify the remaining single "tv-series" items (whole-show files +
     TVmaze no-matches) to contentType "tv-special" so they route to the
     normal DetailView, play directly, and show up in Browse — instead of
     masquerading as empty series.

Operates on both catalogs (full + bundled seed). Idempotent-ish; safe to
re-run after a fresh rebuild.

Usage:
  python tools/reconcile_tv_catalog.py --dry-run
  python tools/reconcile_tv_catalog.py
"""

import argparse
import json
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SERIES_DIR = REPO / "series"
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"
REPORT = REPO / "shared" / "editorial" / "tv_rebuild_report.json"


def load(p):
    return json.loads(p.read_text(encoding="utf-8"))

def dump(p, d):
    p.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")


def series_card(s):
    """Build a catalog tv-series card from a canonical series dict, including
    every field Catalog.Item requires to decode."""
    slug = s["seriesID"]
    ys = s.get("yearStart")
    nets = s.get("networks") or []
    has_poster = bool(s.get("posterURL"))
    return {
        "archiveID": f"series:{slug}",
        "title": s.get("title"),
        "year": ys,
        "decade": (ys // 10 * 10) if ys else None,
        "runtimeSeconds": None,
        "synopsis": s.get("overview"),
        "collections": [],
        "subjects": s.get("genres") or [],
        "mediatype": "movies",
        "language": "English",
        "imdbID": None, "tmdbID": None, "wikidataQID": None, "tvmazeID": s.get("tvmazeID"),
        "videoFile": None,
        "downloadURL": None,
        "posterURL": s.get("posterURL"),
        "backdropURL": s.get("backdropURL"),
        "hasRealArtwork": has_poster,
        "artworkSource": "tvmaze" if has_poster else "archive",
        "contentType": "tv-series",
        "genres": s.get("genres") or [],
        "countries": [],
        "cast": [],
        "director": None, "producer": None,
        "seriesName": s.get("title"), "network": (nets[0] if nets else None),
        "enrichmentTier": "fullyEnriched",
        "shelves": [],
        "rightsStatus": None, "qualityScore": None, "popularityScore": None,
        "bestSourceType": "tvmaze", "isSilentFilm": False,
        "seriesID": slug,
        "yearEnd": s.get("yearEnd"),
        "seasonsCount": len(s.get("seasons") or []),
        "episodesCount": s.get("episodesCount"),
        "networks": nets,
        "creator": s.get("creator"),
        "imdbRating": None, "imdbVotes": None, "contentRating": None,
        "synopsisSource": "tvmaze" if s.get("overview") else None,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    report = load(REPORT)
    written_slugs = {r["slug"] for r in report["shows"] if r.get("availableEps", 0) > 0}

    # 1) Delete superseded old series files.
    consumed_old = set()
    for r in report["shows"]:
        if r.get("availableEps", 0) <= 0:
            continue
        for ref in r.get("consumedRefs", []):
            if ref["kind"] == "series":
                consumed_old.add(ref["ref"])
    to_delete = [old for old in consumed_old if old not in written_slugs]
    print(f"[reconcile] superseded old series files to delete: {len(to_delete)}")
    if not args.dry_run:
        for old in to_delete:
            f = SERIES_DIR / f"{old}.json"
            if f.exists():
                f.unlink()

    # 2) Load the surviving series files -> canonical cards + episode index.
    cards = []
    episode_ids = set()
    for f in sorted(SERIES_DIR.glob("*.json")):
        s = load(f)
        # only the version-2 canonical files carry tvmazeID; old kept files
        # still produce a valid card from their existing fields.
        cards.append(series_card({
            "seriesID": s.get("seriesID", f.stem),
            "title": s.get("title"), "yearStart": s.get("yearStart"),
            "yearEnd": s.get("yearEnd"), "overview": s.get("overview"),
            "posterURL": s.get("posterURL"), "backdropURL": s.get("backdropURL"),
            "genres": s.get("genres"), "networks": s.get("networks"),
            "creator": s.get("creator"), "tvmazeID": s.get("tvmazeID"),
            "seasons": s.get("seasons"), "episodesCount": s.get("episodesCount"),
        }))
        for season in s.get("seasons", []):
            for ep in season.get("episodes", []):
                if ep.get("archiveID"):
                    episode_ids.add(ep["archiveID"])
    print(f"[reconcile] canonical/kept series cards: {len(cards)}; "
          f"episode archiveIDs indexed: {len(episode_ids)}")

    reclassify_ids = set(report.get("reclassifyArchiveIDs", []))
    reclassify_ids |= {u["ref"] for u in report.get("unmatched", [])
                       if u.get("kind") == "single" and u.get("ref")}

    def transform(catalog, label):
        items = catalog["items"]
        kept, dropped_old_series, dropped_to_episode, reclassed = [], 0, 0, 0
        for it in items:
            ct = it.get("contentType")
            if ct == "tv-series":
                if it.get("seriesID"):
                    dropped_old_series += 1      # rebuilt from series/*.json
                    continue
                aid = it.get("archiveID")
                if aid in episode_ids:
                    dropped_to_episode += 1       # now an episode in a series
                    continue
                if aid in reclassify_ids:
                    it = dict(it); it["contentType"] = "tv-special"; reclassed += 1
                # else: leave as-is (rare; a tv-series single we didn't touch)
            kept.append(it)
        # Add canonical cards present in THIS catalog's id space. Seed gets all
        # canonical series cards too (small, enables first-launch TV browsing).
        kept.extend([dict(c) for c in cards])
        catalog["items"] = kept
        # refresh stats.totalItems if present
        if isinstance(catalog.get("stats"), dict):
            catalog["stats"]["totalItems"] = len(kept)
        print(f"  [{label}] dropped old-series cards={dropped_old_series} "
              f"singles->episode={dropped_to_episode} reclassified->tv-special={reclassed} "
              f"added canonical cards={len(cards)} | total now {len(kept)}")
        return catalog

    for path, label in [(FULL_CATALOG, "full"), (SEED_CATALOG, "seed")]:
        cat = load(path)
        cat = transform(cat, label)
        if not args.dry_run:
            dump(path, cat)

    print(f"[reconcile] done{' (dry-run)' if args.dry_run else ''}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
