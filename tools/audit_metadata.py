#!/usr/bin/env python3
"""
audit_metadata.py — the measurement layer of the metadata-quality program
(docs/architecture/metadata-audit.md). Scans EVERY app-displayed field on every
catalog item, classifies problems, scores each item 0-100, and emits a report so
we can track quality over time and target work where users actually see it.

It does NOT modify the catalog — auditing and fixing are separate jobs
(remediate_catalog.py = deterministic Tier-1 fixes; enrichment workflows =
Tier-2; an LLM pass = Tier-3). This is read-only: it tells us WHAT and HOW MUCH.

Issue classes (by where they hurt):
  BLOCKER  — junk the user actually reads: URLs, HTML, social/donate calls,
             email, uploader/codec noise, mojibake, junk titles. These make the
             app look broken; highest priority.
  GAP      — a displayed field is missing (no poster/year/synopsis/cast/...).
  MINOR    — present but weak (very short synopsis, ALL-CAPS title, ...).

Strategy baked in: every count is also reported POPULARITY-WEIGHTED (issues among
the top-N most-popular items matter most — those are what fills Home, the seed,
and search), so the long tail never drowns out the titles people see.

Usage:
  python tools/audit_metadata.py                 # console summary
  python tools/audit_metadata.py --json out.json # full machine report
  python tools/audit_metadata.py --samples 5     # show example offenders
  python tools/audit_metadata.py --top 2000      # popularity cohort size
"""

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

# ---------------------------------------------------------------------------
# Detectors. Kept declarative so remediate_catalog.py (Tier 1) can share the
# same regexes — what we DETECT here is exactly what we CLEAN there.
# ---------------------------------------------------------------------------
HTML     = re.compile(r"<[^>]+>|&[a-z]+;|&#\d+;", re.I)
URL      = re.compile(r"https?://|www\.\w|\b\w+\.(?:com|org|net|tv|io|ly)\b", re.I)
SOCIAL   = re.compile(r"\b(instagram|facebook|twitter|tiktok|youtube|patreon|"
                      r"subscribe|follow us|follow me|like and|donate|paypal|"
                      r"venmo|onlyfans|discord|telegram|kickstarter|gofundme)\b", re.I)
EMAIL    = re.compile(r"[\w.+-]+@[\w-]+\.\w+")
MOJIBAKE = re.compile(r"Ã.|â€|Â.|�")
UPLOADER = re.compile(r"\b(uploaded by|ripped by|encoded by|courtesy of|"
                      r"my channel|click here|watch more|full movie|please rate|"
                      r"thanks for watching)\b", re.I)
# Encoding/transcode boilerplate uploaders paste in: "Container: mkv Video:
# h.264 @ 1500kbps", "~~~~", "Audio: AC3", "29.97 fps". Label:value or codec
# tokens — not plot.
TECH = re.compile(r"\bx264\b|\bxvid\b|\bh\.?264\b|\d+\s?kbps|\d+(?:\.\d+)?\s?fps|"
                  r"\bbitrate\b|\b(?:container|codec|video|audio|soundtrack|"
                  r"resolution|framerate)\s*:|~~~|====", re.I)
T_RES    = re.compile(r"\b(720p|1080p|2160p|480p|x264|h\.?264|xvid|hdtv|webrip|"
                      r"dvdrip|bluray|\.mp4|\.mkv|\.avi|\.ogv)\b", re.I)
T_BRACKET = re.compile(r"\[[^\]]*\]")
T_DISC   = re.compile(r"\b(disc|disk|reel|tape)\s*\d", re.I)
T_NUMERIC = re.compile(r"^[\d\W]{1,6}$")


def _text(v):
    return (" ".join(v) if isinstance(v, list) else (v or "")).strip()


# Each check: (field, issue_id, severity, predicate(item)->bool).
def _checks():
    syn = lambda it: _text(it.get("synopsis"))
    title = lambda it: (it.get("title") or "").strip()
    designed = lambda it: bool(it.get("hasRealArtwork")) or it.get("artworkSource") not in (None, "archive")
    return [
        # BLOCKERS — visible junk
        ("synopsis", "html",      "blocker", lambda it: bool(HTML.search(syn(it)))),
        ("synopsis", "url",       "blocker", lambda it: bool(URL.search(syn(it)))),
        ("synopsis", "social",    "blocker", lambda it: bool(SOCIAL.search(syn(it)))),
        ("synopsis", "email",     "blocker", lambda it: bool(EMAIL.search(syn(it)))),
        ("synopsis", "mojibake",  "blocker", lambda it: bool(MOJIBAKE.search(syn(it)))),
        ("synopsis", "uploader",  "blocker", lambda it: bool(UPLOADER.search(syn(it)))),
        ("synopsis", "tech",      "blocker", lambda it: bool(TECH.search(syn(it)))),
        ("title",    "codec",     "blocker", lambda it: bool(T_RES.search(title(it)))),
        ("title",    "bracket",   "blocker", lambda it: bool(T_BRACKET.search(title(it)))),
        ("title",    "disc",      "blocker", lambda it: bool(T_DISC.search(title(it)))),
        ("title",    "numeric",   "blocker", lambda it: bool(T_NUMERIC.match(title(it)))),
        ("title",    "mojibake",  "blocker", lambda it: bool(MOJIBAKE.search(title(it)))),
        # GAPS — missing displayed fields
        ("poster",   "missing",   "gap", lambda it: not designed(it)),
        ("synopsis", "missing",   "gap", lambda it: not syn(it)),
        ("year",     "missing",   "gap", lambda it: not it.get("year")),
        ("genres",   "missing",   "gap", lambda it: not it.get("genres")),
        ("cast",     "missing",   "gap", lambda it: not it.get("cast")),
        ("director", "missing",   "gap", lambda it: not it.get("director")),
        # MINOR — present but weak
        ("synopsis", "tooshort",  "minor", lambda it: 0 < len(syn(it)) < 60),
        ("title",    "allcaps",   "minor", lambda it: title(it).isupper() and len(title(it).split()) > 1),
        ("runtime",  "suspect",   "minor", lambda it: bool(it.get("runtimeSeconds")) and it["runtimeSeconds"] < 180),
    ]


SEVERITY_WEIGHT = {"blocker": 25, "gap": 8, "minor": 3}
CHECKS = _checks()


def audit_item(it):
    """Return (score 0-100, [issue_ids]). A blocker is heavily penalised; the
    score is for ranking/ gating, not a precise metric."""
    issues = [f"{field}.{iid}" for field, iid, sev, pred in CHECKS if pred(it)]
    penalty = sum(SEVERITY_WEIGHT[sev] for field, iid, sev, pred in CHECKS if pred(it))
    return max(0, 100 - penalty), issues


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", help="write full report JSON here")
    ap.add_argument("--samples", type=int, default=0, help="print N example offenders per issue")
    ap.add_argument("--top", type=int, default=2000, help="popularity-cohort size")
    args = ap.parse_args()

    items = [it for it in json.loads(CATALOG.read_text(encoding="utf-8"))["items"]
             if it.get("contentType") != "tv-series"]
    n = len(items)
    # popularity cohort = the items users actually see (Home/seed/search lead).
    top = set(id(it) for it in sorted(items, key=lambda it: it.get("popularityScore") or 0,
                                      reverse=True)[:args.top])

    counts, top_counts, samples = Counter(), Counter(), defaultdict(list)
    scores = []
    blocker_items = 0
    for it in items:
        score, issues = audit_item(it)
        scores.append(score)
        has_blocker = False
        for field, iid, sev, pred in CHECKS:
            if pred(it):
                key = f"{field}.{iid}"
                counts[key] += 1
                if id(it) in top:
                    top_counts[key] += 1
                if sev == "blocker":
                    has_blocker = True
                if len(samples[key]) < args.samples:
                    samples[key].append({"archiveID": it.get("archiveID"),
                                         "title": it.get("title"),
                                         "snippet": _text(it.get("synopsis"))[:80]})
        if has_blocker:
            blocker_items += 1

    clean = sum(1 for s in scores if s >= 90)
    print(f"=== METADATA AUDIT — {n} non-series items, top cohort = {args.top} ===")
    print(f"avg score {sum(scores)//max(n,1)}/100 | clean(>=90) {clean} ({100*clean//max(n,1)}%) "
          f"| items with a BLOCKER {blocker_items} ({100*blocker_items//max(n,1)}%)\n")
    print(f"{'issue':22} {'total':>7} {'top'+str(args.top):>8}  severity")
    sev_of = {f"{f}.{i}": s for f, i, s, _ in CHECKS}
    for key, total in counts.most_common():
        print(f"  {key:20} {total:7} {top_counts[key]:8}  {sev_of[key]}")
        for ex in samples.get(key, []):
            print(f"        e.g. {ex['archiveID']}: {ex.get('snippet') or ex.get('title')!r}")

    if args.json:
        Path(args.json).write_text(json.dumps({
            "items": n, "avgScore": sum(scores)//max(n,1), "cleanPct": 100*clean//max(n,1),
            "itemsWithBlocker": blocker_items,
            "counts": dict(counts), "topCohortCounts": dict(top_counts),
        }, indent=2))
        print(f"\nwrote {args.json}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
