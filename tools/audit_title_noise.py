#!/usr/bin/env python3
"""Measure what is in a catalog title that is NOT the title.

Report-first, like every remediation in this repo: this tool CHANGES NOTHING.
It classifies every title against the noise patterns we know how to recognise,
prints how big each class is, and shows real examples — so a rule is written
against measured evidence and its blast radius is known before it runs.

    python3 tools/audit_title_noise.py [--index index.json] [--show 8]
    python3 tools/audit_title_noise.py --class cast_after_year --show 40

The classes are deliberately ORDERED by how confident the signal is. A title
is counted under the FIRST class it matches, so the counts sum to the number
of noisy titles rather than double-counting a title that is noisy twice over.
"""
import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

YEAR = r"(?:18[7-9]\d|19\d\d|20[0-2]\d)"

# A person name: two-to-four capitalised words. Deliberately strict — it is
# the loosest signal here and is only ever used behind a stronger anchor.
NAME = r"[A-Z][\w.'’\-]+(?:\s+[A-Z][\w.'’\-]+){1,3}"

CLASSES = [
    # ---- anchored on a year parenthesis: whatever follows is uploader junk.
    ("cast_after_year",
     re.compile(rf"[\(\[]\s*{YEAR}[^)\]]*[\)\]]\s*\S.*{NAME}\s*,\s*{NAME}"),
     "Title (1950) Cast, Cast — the cast list follows a year parenthesis"),
    ("junk_after_year",
     re.compile(rf"[\(\[]\s*{YEAR}[^)\]]*[\)\]]\s+\S"),
     "Title (1950) <anything> — content after a year parenthesis"),

    # ---- format / source / quality tags.
    ("format_tag",
     re.compile(r"\b(?:1080p|720p|480p|2160p|4k|hd|sd|dvdrip|dvd|bluray|blu-ray|"
                r"brrip|webrip|web-dl|x264|x265|h\.?264|h\.?265|xvid|divx|mp4|avi|"
                r"mkv|mpeg-?4|ntsc|pal|remastered|restored|colou?rized|"
                r"full\s+movie|complete\s+movie|free\s+movie|public\s+domain)\b", re.I),
     "resolution / codec / source / 'full movie' tags"),

    # ---- credits announced in words (the existing _CREDIT_TAIL class).
    ("credit_words",
     re.compile(r"\b(?:directed\s+by|a\s+film\s+by|starring|featuring|feat\.|"
                r"with\s+cast|cast:|dir\.?\s*:)\s+\S", re.I),
     "'starring …' / 'directed by …' spelled out"),

    # ---- separators that only ever precede credits.
    ("pipe_credits", re.compile(r"\|"), "pipe-separated credits"),

    # ---- a bare trailing name list with NO anchor. The riskiest class: a
    # compilation reel legitimately lists several FILMS this way.
    ("bare_cast_tail",
     re.compile(rf"\b{NAME}(?:\s*,\s*{NAME}){{2,}}\s*$"),
     "trailing comma-separated names, no anchor (RISKY: compilation reels look identical)"),

    # ---- leftovers.
    ("trailing_punct", re.compile(r"[\-–—,;:|]\s*$"), "ends in a dangling separator"),
    ("bracket_noise", re.compile(r"[\[\(][^)\]]{0,40}[\)\]]\s*$"),
     "ends in a parenthetical (may be legitimate — inspect)"),
]


def classify(title):
    for name, rx, _ in CLASSES:
        if rx.search(title):
            return name
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", default="index.json")
    ap.add_argument("--show", type=int, default=6)
    ap.add_argument("--class", dest="only", help="show every example of ONE class")
    a = ap.parse_args()

    p = Path(a.index)
    if not p.exists():
        sys.exit(f"no index at {p} — fetch archivewatch.org/catalog-index.json first")
    items = json.loads(p.read_text())["items"]

    counts, examples = Counter(), {}
    for it in items:
        aid, title = it[0], (it[1] or "")
        cls = classify(title)
        if not cls:
            continue
        counts[cls] += 1
        examples.setdefault(cls, []).append((aid, title))

    total = sum(counts.values())
    print(f"{len(items)} titles · {total} carry recognisable noise "
          f"({100 * total / max(len(items), 1):.1f}%)\n")

    for name, _, why in CLASSES:
        n = counts.get(name, 0)
        if not n:
            continue
        print(f"  {name:18s} {n:5d}   {why}")
        if a.only and a.only != name:
            continue
        for aid, t in examples[name][: (999 if a.only else a.show)]:
            print(f"      {aid[:36]:38s} {t[:104]}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
