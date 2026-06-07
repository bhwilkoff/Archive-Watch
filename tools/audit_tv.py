#!/usr/bin/env python3
"""
audit_tv.py — coverage report for TV content (posters, summaries, cast, episodes).

Measures the series/*.json spines (the runtime source for SeriesDetailView) and,
if present, the catalog's tv-series cards. Read-only. Wire into CI alongside
audit_metadata.py for an ongoing TV quality signal.

Run: python tools/audit_tv.py
"""

from __future__ import annotations

import glob
import json
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def pct(n, d):
    return f"{100 * n // d}%" if d else "—"


def main() -> int:
    files = sorted(glob.glob(str(REPO / "series" / "*.json")))
    n = len(files)
    poster = summ = cast = backdrop = 0
    ep_total = ep_over = ep_still = ep_air = 0
    for f in files:
        d = json.load(open(f))
        if d.get("posterURL"): poster += 1
        if d.get("backdropURL"): backdrop += 1
        if (d.get("overview") or "").strip(): summ += 1
        if d.get("cast"): cast += 1
        for s in d.get("seasons", []):
            for e in s.get("episodes", []):
                ep_total += 1
                if (e.get("overview") or "").strip(): ep_over += 1
                if e.get("stillURL"): ep_still += 1
                if e.get("airDate"): ep_air += 1

    print("=== TV AUDIT — series spines (series/*.json) ===")
    print(f"series files: {n}")
    print(f"  poster:   {poster:>4}  ({pct(poster, n)})")
    print(f"  backdrop: {backdrop:>4}  ({pct(backdrop, n)})")
    print(f"  summary:  {summ:>4}  ({pct(summ, n)})")
    print(f"  cast:     {cast:>4}  ({pct(cast, n)})")
    print(f"episodes: {ep_total}")
    print(f"  overview:    {ep_over:>5}  ({pct(ep_over, ep_total)})")
    print(f"  still image: {ep_still:>5}  ({pct(ep_still, ep_total)})")
    print(f"  air date:    {ep_air:>5}  ({pct(ep_air, ep_total)})")

    cat = REPO / "catalog.json"
    if cat.exists():
        items = json.load(open(cat))["items"]
        tv = [it for it in items if it.get("contentType") == "tv-series"]
        print("\n=== catalog tv-series cards ===")
        print(f"cards: {len(tv)}")
        print(f"  poster:   {sum(1 for it in tv if it.get('posterURL')):>4}  "
              f"({pct(sum(1 for it in tv if it.get('posterURL')), len(tv))})")
        print(f"  synopsis: {sum(1 for it in tv if it.get('synopsis')):>4}")
        print(f"  cast:     {sum(1 for it in tv if it.get('cast')):>4}")
        print("  artworkSource:", dict(Counter(it.get("artworkSource") for it in tv)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
