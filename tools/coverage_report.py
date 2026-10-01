#!/usr/bin/env python3
"""
coverage_report.py — for every title the apps SERVE, which checks it is still
owed. A report, never a writer: exit 0 always.

WHY: the checks live in separate workers and each picks its own targets, so a
title can reach the screen having slipped between two of them. On 2026-09-30
the renewal check skipped every hidden title while the rights audit un-hid
titles the moment they gained a year, so eleven renewed films were one publish
from the screen unchecked. Nothing counted that. This counts it, per check,
over what is actually served, so a gap is a number in the publish-db summary
the day it opens rather than a film someone notices.

Served = not excluded and not merged into another card, after the rights gate
has been applied (run it after `audit_rights --apply`).

Run: python tools/coverage_report.py [--catalog PATH] [--list CHECK] [--json OUT]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_rights as AR          # noqa: E402
import corroborate_copyright as CC  # noqa: E402
import metadata_review as MR       # noqa: E402

REPO = Path(__file__).resolve().parent.parent
TV = {"tv-episode", "tv-series", "tv-special"}
PLAYBACK_TTL_DAYS = 90


def served(it):
    return not (it.get("excluded") or it.get("duplicateMergedInto") or it.get("duplicateOf"))


def _age_days(stamp, today):
    try:
        return (today - dt.date.fromisoformat(str(stamp)[:10])).days
    except ValueError:
        return None


def owed(it, today):
    """The checks this served title still needs, as short names."""
    out = []
    ct = it.get("contentType")
    y = it.get("year")
    if not isinstance(y, int) and ct not in TV:
        out.append("year")
    # Owed exactly when the renewal check itself would pick it: asking the
    # checker, not restating its rules, keeps the report from drifting.
    if CC.targets([it], today):
        out.append("renewal")
    # A series spine is a container of episodes with no file of its own, so it
    # is never probed: 256 of the first 266 "playback" owed were spines.
    if ct == "tv-series":
        pass
    elif not it.get("playbackVerified"):
        out.append("playback")
    else:
        age = _age_days(it.get("playbackCheckedAt"), today)
        if age is None or age > PLAYBACK_TTL_DAYS:
            out.append("playback-stale")
    if (it.get("synopsisSource") or "archive") == "archive" and MR._syn(it) and not MR._reviewed(it):
        out.append("summary")
    if not it.get("hasRealArtwork"):
        out.append("artwork")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=str(REPO / "catalog.json"))
    ap.add_argument("--list", help="print the served titles owing this check")
    ap.add_argument("--json", help="write the counts here")
    ap.add_argument("--limit", type=int, default=50)
    a = ap.parse_args()
    today = dt.date.today()
    items = [it for it in json.loads(Path(a.catalog).read_text(encoding="utf-8"))["items"] if served(it)]
    counts, lists = {}, {}
    for it in items:
        for c in owed(it, today):
            counts[c] = counts.get(c, 0) + 1
            lists.setdefault(c, []).append(it)
    order = ["renewal", "year", "playback", "playback-stale", "summary", "artwork"]
    lines = [f"Served titles: {len(items):,}", "",
             "| check owed | titles | share |", "|---|---:|---:|"]
    for c in order:
        n = counts.get(c, 0)
        lines.append(f"| {c} | {n:,} | {100 * n / max(len(items), 1):.1f}% |")
    report = "\n".join(lines)
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write("## Coverage: checks owed by served titles\n\n" + report + "\n")
    if a.json:
        Path(a.json).write_text(json.dumps({"date": today.isoformat(), "served": len(items),
                                            "owed": counts}, indent=2))
    if a.list:
        for it in sorted(lists.get(a.list, []), key=lambda i: -(i.get("popularityScore") or 0))[:a.limit]:
            print(f"  {it.get('year')}\t{it['archiveID']}\t{it.get('title')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
