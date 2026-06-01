#!/usr/bin/env python3
"""
rights_evidence.py — stamp catalog items with sound public-domain evidence.

A deliberately conservative pass that records WHY an item is public domain,
not just that it is. It only asserts what's legally solid:

  • Published before the rolling US PD cutoff (pre-1930 as of 2026) →
    PD by age. This is the cleanest test (no renewal needed; copyright
    expired). Stamps rightsStatus=public_domain + rightsEvidence="pre_1930".
  • Already flagged by an upstream source (Wikidata P6216, or a curated PD
    Archive/LoC collection) → rightsEvidence="source_flagged" if not
    otherwise evidenced.

What it deliberately does NOT do: it does not try to prove non-renewal for
1929–1963 films. The NYPL `cce-renewals` dataset (the obvious candidate) is
Class-A *book* registrations — it contains essentially no motion pictures,
so a film's absence from it is not evidence of anything. Asserting PD from
book data would be misleading, which is worse than leaving it un-evidenced.
Films in that window keep whatever rightsStatus the source feed assigned,
with rightsEvidence="source_unverified" so it's honest about the gap.

Idempotent. Operates on the committed catalogs only.

Usage:
    python tools/rights_evidence.py            # stamp both catalogs
    python tools/rights_evidence.py --dry-run  # report only
"""

import argparse
import json
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FULL_CATALOG = REPO / "catalog.json"
SEED_CATALOG = REPO / "ArchiveWatch" / "ArchiveWatch" / "catalog.json"

# US public-domain publication cutoff. Works published before this year are
# PD by age alone. Rolls forward every Jan 1 (<1929 in 2025, <1930 in 2026).
PD_YEAR_CUTOFF = 1930

# Sources whose own classification we treat as a (soft) PD flag.
FLAGGED_SOURCES = {"wikidata", "archive_collection", "loc"}


def evidence_for(item):
    """Return (rightsStatus, rightsEvidence) for an item, or (None, None)
    to leave it unchanged."""
    year = item.get("year")
    if year and year < PD_YEAR_CUTOFF:
        return "public_domain", "pre_%d" % PD_YEAR_CUTOFF

    src = item.get("discoverySource")
    status = item.get("rightsStatus")

    if status == "public_domain":
        # Already PD from a feed; mark how solidly we know it.
        if item.get("pdFlagged") or src == "wikidata":
            return "public_domain", "source_flagged"
        return "public_domain", "source_unverified"

    if status == "creative_commons":
        return "creative_commons", "source_licensed"

    # In the 1929–1963 non-renewal window with no age/flag certainty: keep
    # the status but be explicit that we haven't independently verified.
    if year and PD_YEAR_CUTOFF <= year <= 1963 and status:
        return status, "source_unverified"

    return None, None


def stamp(catalog, dry_run):
    changed = 0
    ev = Counter()
    for item in catalog.get("items", []):
        new_status, new_ev = evidence_for(item)
        if new_ev is None:
            continue
        ev[new_ev] += 1
        if (item.get("rightsStatus") != new_status
                or item.get("rightsEvidence") != new_ev):
            if not dry_run:
                item["rightsStatus"] = new_status
                item["rightsEvidence"] = new_ev
            changed += 1
    return changed, ev


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    total_changed = Counter()
    for path in (FULL_CATALOG, SEED_CATALOG):
        if not path.exists():
            continue
        cat = json.loads(path.read_text(encoding="utf-8"))
        changed, ev = stamp(cat, args.dry_run)
        total_changed[path.name] = changed
        print(f"[rights] {path.name}: {changed} items (re)stamped; "
              f"evidence {dict(ev)}", flush=True)
        if changed and not args.dry_run:
            path.write_text(json.dumps(cat, ensure_ascii=False, indent=2),
                            encoding="utf-8")

    print(f"[rights] done{' (dry-run)' if args.dry_run else ''}: "
          f"{sum(total_changed.values())} total", flush=True)
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
