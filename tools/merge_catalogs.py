#!/usr/bin/env python3
"""
merge_catalogs.py — union two catalog.json files by archiveID.

Exists because rebuild-catalog runs build-catalog.mjs, which writes a FRESH,
small catalog (Wikidata seed + per-shelf query results) and OVERWRITES
catalog.json. On 2026-06-03 that silently clobbered the full ~30k catalog down
to ~1.1k (the catalog lives on a Release, not git — Decision 018 — so there was
no diff to catch it). This makes the rebuild ADDITIVE: the freshly-built items
update/extend the existing catalog instead of replacing it.

Union semantics, ENRICHMENT-PRESERVING: every archiveID from BASE is kept with
its full (accumulated) record; OVERLAY only (a) ADDS items BASE doesn't have
(e.g. new Wikidata seeds) and (b) refreshes the `shelves` assignment on items it
rebuilt. It deliberately does NOT overwrite a base item's other fields — a fresh
build-catalog.mjs run is TMDb-only and would otherwise strip the OMDb cast,
Commons posters, Wikipedia synopses, and remediate fixes the daily/weekly crons
had accumulated. (Earlier draft let overlay win wholesale, which downgrades.)

Shrink guard: if the merged result has fewer items than BASE, something went
wrong upstream (e.g. a failed/empty build) — exit non-zero WITHOUT writing, so
the workflow aborts before publishing a truncated catalog.

Usage:
  python tools/merge_catalogs.py BASE.json OVERLAY.json OUT.json
"""

import json
import sys


def main(argv):
    if len(argv) != 4:
        print("usage: merge_catalogs.py BASE.json OVERLAY.json OUT.json", file=sys.stderr)
        return 2
    base_path, overlay_path, out_path = argv[1:4]
    base = json.loads(open(base_path, encoding="utf-8").read())
    overlay = json.loads(open(overlay_path, encoding="utf-8").read())

    merged = {}
    for it in base.get("items", []):
        aid = it.get("archiveID")
        if aid:
            merged[aid] = it
    shelves_refreshed = added = 0
    for it in overlay.get("items", []):
        aid = it.get("archiveID")
        if not aid:
            continue
        if aid in merged:
            # Keep the base (accumulated) record; only adopt the freshly-resolved
            # shelf assignment so home shelves stay current without downgrading
            # the item's enrichment.
            new_shelves = it.get("shelves")
            if new_shelves and new_shelves != merged[aid].get("shelves"):
                merged[aid]["shelves"] = new_shelves
                shelves_refreshed += 1
        else:
            merged[aid] = it
            added += 1

    n_base = len(base.get("items", []))
    n_out = len(merged)
    print(f"[merge] base={n_base} overlay={len(overlay.get('items', []))} "
          f"-> merged={n_out} (added={added}, shelves_refreshed={shelves_refreshed})")

    # Shrink guard: never let a merge produce fewer items than the base.
    if n_out < n_base:
        print(f"[merge] ABORT: merged ({n_out}) < base ({n_base}); refusing to "
              f"write a truncated catalog.", file=sys.stderr)
        return 1

    out = dict(overlay)            # keep overlay's version/generator/stats shape
    out["items"] = list(merged.values())
    if isinstance(out.get("stats"), dict):
        out["stats"]["totalItems"] = n_out
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"[merge] wrote {out_path} ({n_out} items)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
