#!/usr/bin/env python3
"""
fetch_cce_renewals.py — the motion-picture RENEWAL registrations printed in the
Catalog of Copyright Entries, 1950-1977, as a table the build can read.

WHY: Decision 151 hides a title on a copyright claim a reader can open, and
the Copyright Office's online records begin with renewals filed in 1978 — so a
film registered 1923-1949 (renewed 28 years later, 1951-1977) could only be
caught through Wikidata. Frankenstein (1931), renewed by Universal in 1958-59,
stayed "presumed public domain". The Catalog of Copyright Entries printed every
renewal in its annual Motion Pictures volume; archive.org hosts the scans with
OCR text. Each entry reads:

    ALL QUIET ON THE WESTERN FRONT, a photoplay in fourteen reels by
    Universal Pictures Corp. © 17May30; LP1323. Universal Pictures Co.,
    Inc. (PWH); 26Mar58; R211372.

Output: shared/editorial/cce_renewals.json — a list of
{"t": TITLE, "y": original year, "reg": "LP1323", "r": "R211372",
 "c": claimant, "vol": archive.org identifier}. corroborate_copyright.py
matches it on title AND original year, exactly as it matches the online
records.

Run: python tools/fetch_cce_renewals.py [--only IDENTIFIER]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "shared/editorial/cce_renewals.json"
UA = {"User-Agent": "ArchiveWatch/1.0 (https://archivewatch.org; rights corroboration)"}
SEARCH = ("https://archive.org/advancedsearch.php?q=title%3A%28%22catalog+of+copyright+entries%22%29"
          "+AND+title%3A%28%22third+series%22%29+AND+title%3A%28motion+pictures%29"
          "&fl%5B%5D=identifier&fl%5B%5D=year&rows=100&output=json")

# "© 17May30; LP1323." — the © is often OCR'd as "@", "6" or "6G" in the
# 1970s volumes ("6 17Dec47; 11354"), and some print a comma after the date.
ORIG = re.compile(r"(?:[©@]|\b6G?)\s*(\d{1,2})\s*([A-Z][a-z]{2})\s*(\d{2})\d?\s*[;,:]\s*([A-Z]{0,3}\s?\d{2,7})")
# OCR reads a 1 as l or I, and an 0 as O, inside the date and number of an
# entry: Dracula (1931) is printed "© 2Feb3l1; LP1947" and went unmatched, so
# Universal's 1958 renewal R227698 never reached the audit (2026-09-29).
_OCR_DIGIT = re.compile(r"(?<=\d)[lI|](?=[\dlI|;,:])|(?<=[A-Za-z]{3}\d)[lI|]|(?<=\d)O(?=\d)")
RENEW = re.compile(r"\b(R\s?\d{5,6})\b")
# Where a title stops: ", a photoplay", ". By Columbia", ". No.1151", or a period.
TITLE_END = re.compile(r",\s+(?:a|an)\s|\.\s+(?:By|No\.|A\s+motion|A\s+photoplay)\b|\.\s|,\s+(?:by|in)\s")


def _get(url, tries=3):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.read()
        except Exception:
            time.sleep(2 + 3 * i)
    return None


def volumes():
    d = json.loads(_get(SEARCH))["response"]["docs"]
    out = []
    for x in d:
        y = x.get("year")
        try:
            y = int(str(y)[:4])
        except (TypeError, ValueError):
            continue
        if 1950 <= y <= 1977:
            out.append((x["identifier"], y))
    return sorted(out, key=lambda v: v[1])


def parse(text, vol):
    """Renewal entries anywhere in one volume: a block carrying BOTH an original
    registration and a renewal number (new registrations carry no R number).
    Earlier volumes print renewals in their own section, the 1974-77 volumes
    interleave them with new registrations, so the whole text is read."""
    out = []
    for block in re.split(r"\n\s*\n", text):
        b = " ".join(block.split())
        b = _OCR_DIGIT.sub(lambda m: "0" if m.group() == "O" else "1", b)
        r = RENEW.search(b)
        o = ORIG.search(b)
        if not (r and o) or o.start() > r.start():
            continue
        head = re.sub(r"^\d{1,3}\.\s+", "", b[:o.start()])     # "1. Amazing Mazie." in a series
        end = TITLE_END.search(head)
        title = (head[:end.start()] if end else head)
        title = re.split(r"\s+By\s+", title)[0].strip(" ,.;")
        if not (3 <= len(title) <= 120) or title.upper().startswith("SEE ") or not re.search(r"[A-Za-z]{3}", title):
            continue
        year = 1900 + int(o.group(3))
        reg = o.group(4).replace(" ", "")
        # A renewal's ORIGINAL registration: 1909 Act works, renewed 28 years on.
        if not (1909 <= year <= 1950) or reg.startswith("R") or title.lower() in ("reel", "reels"):
            continue
        claim = b[o.end():r.start()].strip(" .;,")
        claim = re.sub(r"[;,]?\s*[%\d]{1,2}\s*[A-Za-z]{3,4}\s*\d{2}\s*$", "", claim).strip(" .;,")
        claim = re.sub(r"(\w)- (\w)", r"\1\2", claim)        # line-break hyphens
        out.append({"t": title, "y": year, "reg": reg,
                    "r": r.group(1).replace(" ", ""), "c": claim[:120], "vol": vol})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    a = ap.parse_args()
    vols = [(a.only, 0)] if a.only else volumes()
    print(f"[cce] {len(vols)} volumes")
    rows, seen = [], set()
    for ident, y in vols:
        meta = _get(f"https://archive.org/metadata/{ident}/files")
        names = [f["name"] for f in json.loads(meta or b'{"result":[]}').get("result", [])
                 if f["name"].endswith("_djvu.txt")]
        if not names:
            print(f"[cce] {ident} ({y}): no text layer")
            continue
        raw = _get(f"https://archive.org/download/{ident}/{names[0]}")
        if not raw:
            print(f"[cce] {ident} ({y}): download failed")
            continue
        got = parse(raw.decode("utf-8", "replace"), ident)
        new = [g for g in got if (g["r"], g["t"]) not in seen]
        seen |= {(g["r"], g["t"]) for g in new}
        rows += new
        print(f"[cce] {ident} ({y}): {len(new)} renewals", flush=True)
        time.sleep(1)
    if a.only:
        for g in rows[:15]:
            print("  ", g)
        return 0
    OUT.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
    print(f"[cce] wrote {len(rows)} renewals -> {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
