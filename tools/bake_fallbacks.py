#!/usr/bin/env python3
"""Bake `fallbackVideoURL` onto catalog items whose primary file is heavy.

Owner decision 2026-08-15: when a film's best copy cannot stream (degraded
archive.org node, bitrate above what the source can serve), the app falls
back to a vetted lower-quality copy — "fallback is only appropriate when the
full version isn't feasible." A film must start within ~30 seconds.

The identity vetting happens HERE, never at runtime (Decision 026): a
fallback is either

  1. a SMALLER video file on another catalog item carrying the SAME imdbID
     (the duplicate copies Decision 040's merge collapses at DB-build time —
     they remain separate items in catalog.json, so their URLs are on hand), or
  2. a smaller archive-generated derivative on the SAME item (fetched from
     /metadata; `source: "derivative"` files are h.264 by construction —
     an uploader original labeled "MPEG4" can hide AV1, which no Apple TV
     decodes).

Only items whose primary file exceeds --min-bytes (default 1.5 GB) get a
fallback: lighter films play through degraded weather on their own, and the
metadata fetches are the expensive part. Additive + idempotent (Decision
020): items already carrying fallbackVideoURL are skipped unless --refresh.

Usage (inside the usual fetch/publish wrap):
  python tools/catalog_release.py fetch
  python tools/bake_fallbacks.py [--min-bytes N] [--limit N] [--dry-run]
  python tools/catalog_release.py publish
"""
import argparse, json, time, urllib.parse, urllib.request

CATALOG = "catalog.json"
UA = {"User-Agent": "ArchiveWatch-pipeline (fallbacks; contact ben@learningischange.com)"}


def http_json(url, timeout=20):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def head_size(url, timeout=15):
    req = urllib.request.Request(url, headers={**UA, "Range": "bytes=0-0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            cr = r.headers.get("Content-Range", "")
            if "/" in cr:
                return int(cr.rsplit("/", 1)[1])
    except Exception:
        pass
    return None


def same_item_derivative(item_id, current_name, current_size):
    try:
        meta = http_json(f"https://archive.org/metadata/{item_id}")
    except Exception:
        return None
    best = None
    for f in meta.get("files", []):
        name = f.get("name", "")
        if (not name.lower().endswith(".mp4") or name == current_name
                or f.get("source") != "derivative"):
            continue
        try:
            size = int(f.get("size", 0))
        except (TypeError, ValueError):
            continue
        if size < 5_000_000 or size >= current_size // 2:
            continue
        if best is None or size > best[1]:
            best = (name, size)
    if not best:
        return None
    return (f"https://archive.org/download/{item_id}/"
            + urllib.parse.quote(best[0]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-bytes", type=int, default=1_500_000_000)
    ap.add_argument("--limit", type=int, default=0, help="0 = all")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--refresh", action="store_true")
    args = ap.parse_args()

    with open(CATALOG) as f:
        catalog = json.load(f)
    items = catalog["items"]

    # imdb -> [(size, item)] over every VISIBLE playable copy, so a heavy
    # copy can find its lighter same-film sibling even when the sibling is
    # merged away at DB-build time.
    by_imdb = {}
    for it in items:
        imdb = it.get("imdbID")
        url = it.get("downloadURL")
        if not imdb or not url or it.get("excluded"):
            continue
        size = (it.get("videoFile") or {}).get("sizeBytes")
        try:
            size = int(size)
        except (TypeError, ValueError):
            size = None
        by_imdb.setdefault(imdb, []).append((size, it))

    heavy = []
    for it in items:
        if it.get("excluded") or not it.get("downloadURL"):
            continue
        if it.get("fallbackVideoURL") and not args.refresh:
            continue
        size = (it.get("videoFile") or {}).get("sizeBytes")
        try:
            size = int(size)
        except (TypeError, ValueError):
            continue
        if size >= args.min_bytes:
            heavy.append((size, it))
    heavy.sort(key=lambda t: -(t[1].get("popularityScore") or 0))
    if args.limit:
        heavy = heavy[: args.limit]
    print(f"heavy items needing a fallback: {len(heavy)}")

    baked = sibling = derivative = 0
    for n, (size, it) in enumerate(heavy):
        fb = None
        # Tier 1: same-imdb sibling copies, meaningfully lighter, biggest
        # first (best quality that still undercuts the heavy copy by half).
        # Probe EACH until one answers — a merged sibling can die like any
        # other item (Decision 056), and one dead candidate must not cost
        # the film its fallback.
        for sib_size, sib in sorted(
                by_imdb.get(it.get("imdbID") or "", []),
                key=lambda t: -(t[0] or 0)):
            if sib is it or not sib_size or sib_size >= size // 2:
                continue
            cand = sib["downloadURL"]
            if head_size(cand) is not None:
                fb = cand
                sibling += 1
                break
            print(f"  dead sibling for {it['archiveID']}: {cand}")
        # Tier 2: same-item smaller derivative.
        if not fb:
            name = urllib.parse.unquote(
                it["downloadURL"].rsplit("/", 1)[-1])
            cand = same_item_derivative(it["archiveID"], name, size)
            time.sleep(0.3)
            if cand and head_size(cand) is not None:
                fb = cand
                derivative += 1
        if not fb:
            continue
        print(f"  {it['archiveID']}: {size//1_000_000}MB -> {fb}")
        if not args.dry_run:
            it["fallbackVideoURL"] = fb
        baked += 1
        if n % 100 == 99:
            print(f"  ... {n+1}/{len(heavy)} scanned, {baked} baked")

    print(f"baked {baked} fallbacks ({sibling} imdb-siblings, {derivative} same-item derivatives)")
    if not args.dry_run and baked:
        with open(CATALOG, "w") as f:
            json.dump(catalog, f, separators=(",", ":"))
        print("catalog written")


if __name__ == "__main__":
    main()
