#!/usr/bin/env python3
"""
build_web_details.py — emit the web viewer's per-item DETAIL shards.

The slim catalog-index gives the browser browse/search rows, but Detail and
playback need what the pipeline already produced per item: the build-time
picked downloadURL, the curated synopsis, director, cast, runtime. The full
catalog can't ship to a browser (95 MB) and the archive.org metadata API is
an unreliable re-derivation (it hangs/404s for items we play fine — the
downloadURL is the truth). So we shard the display fields into 256 small
JSON files served by Pages (CORS), fetched one shard (~40-90 KB) per Detail
view:

    details/{00..ff}.json  →  { archiveID: [downloadURL, synopsis, director,
                                            castNames, genres, runtimeSeconds,
                                            backdropURL], ... }

Shard = FNV-1a 32-bit hash of the archiveID, low byte, hex — the JS side
(watch.js `Details.shardOf`) implements the SAME function; keep them in sync.
Adult/excluded filtering matches build_catalog_index.py (the index is the
gatekeeper; an item absent there is never requested here).

Reads ./catalog.json (fetch via catalog_release.py first). Writes ./details/.
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
FEATURED = REPO / "featured.json"
OUT_DIR = REPO / "details"

SYNOPSIS_MAX = 500


def fnv1a32(s: str) -> int:
    h = 0x811C9DC5
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def main():
    if not CATALOG.exists():
        print("[details] no catalog.json — run tools/catalog_release.py fetch first",
              file=sys.stderr)
        return 1
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = catalog.get("items", catalog if isinstance(catalog, list) else [])

    adult = set()
    if FEATURED.exists():
        try:
            adult = {c.lower() for c in json.loads(FEATURED.read_text())
                     .get("adultCollections", [])}
        except Exception:  # noqa: BLE001
            adult = set()

    shards: dict[str, dict] = {f"{i:02x}": {} for i in range(256)}
    kept = 0
    for it in items:
        if it.get("excluded") or it.get("isAdult"):
            continue
        cols = {c.lower() for c in (it.get("collections") or [])}
        if adult & cols:
            continue
        aid = it.get("archiveID")
        if not aid:
            continue
        raw_syn = it.get("synopsis")
        if isinstance(raw_syn, list):      # Archive metadata quirk: list-typed
            raw_syn = next((x for x in raw_syn if isinstance(x, str)), "")
        synopsis = (raw_syn or "").strip()
        if len(synopsis) > SYNOPSIS_MAX:
            synopsis = synopsis[:SYNOPSIS_MAX].rsplit(" ", 1)[0] + "…"
        cast = [c.get("name") for c in (it.get("cast") or []) if c.get("name")][:6]
        record = [
            it.get("downloadURL"),
            synopsis or None,
            it.get("director"),
            cast or None,
            (it.get("genres") or [])[:3] or None,
            it.get("runtimeSeconds"),
            it.get("backdropURL"),
        ]
        # Trim trailing nulls so empty tails cost nothing on the wire.
        while record and record[-1] is None:
            record.pop()
        if not record:
            continue
        shards[f"{fnv1a32(aid) & 0xFF:02x}"][aid] = record
        kept += 1

    OUT_DIR.mkdir(exist_ok=True)
    total = 0
    for name, data in shards.items():
        p = OUT_DIR / f"{name}.json"
        p.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")),
                     encoding="utf-8")
        total += p.stat().st_size
    print(f"[details] wrote {kept:,} items into 256 shards, "
          f"{total/1_000_000:.1f} MB total "
          f"(avg {total/256/1000:.0f} KB/shard)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
