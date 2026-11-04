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

A serial or short series prints its title once and its chapters beneath:

    FLASH GORDON, a series of photoplays by Universal Productions. 2 reels each.
    © Universal Pictures Co., Inc. (PWH)
    The planet of peril. © 20Apr36; LP6300. 8Mar64; R337803.

Output: shared/editorial/cce_renewals.json — a list of
{"t": TITLE, "y": original year, "reg": "LP1323", "r": "R211372",
 "c": claimant, "vol": archive.org identifier}, with "s" (the series), "ch" (the
chapter) where the entry is a part of one, "sr": 1 where that series is a serial
(one work in chapters, unlike a newsreel's numbered issues), "rl" (its reels), and
"yr": 1 where OCR left the year unreadable and the renewal date fixed it. corroborate_copyright.py matches it on
title AND original year, exactly as it matches the online records.

Run: python tools/fetch_cce_renewals.py [--only IDENTIFIER] [--from TEXT_FOLDER]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "shared/editorial/cce_renewals.json"
UA = {"User-Agent": "ArchiveWatch/1.0 (https://archivewatch.org; rights corroboration)"}
SEARCH = ("https://archive.org/advancedsearch.php?q=title%3A%28%22catalog+of+copyright+entries%22%29"
          "+AND+title%3A%28%22third+series%22%29+AND+title%3A%28motion+pictures%29"
          "&fl%5B%5D=identifier&fl%5B%5D=year&rows=100&output=json")

# Every spelling OCR gave the months in these 28 volumes. "0ct" alone lost every
# October; "3u1", "J3an" and "dan" are the typewriter's J.
_MONTH = (r"(?P<mon>[J3d5]?[3J]?an|[FP]e[bd]|[MHN]ar|A[po]r|[MHN]ay|[J3Id]u[nm]|[J35]u[l1I]|J?[3J]?7?5u[l1I]|"
          r"A[un]g|Sept?|[O0Q]c[tl]|[NH]ov|[Dd]e[co]|[A-Z][a-z]{2})")
# The typewriter's 4 reads as anything: "4Junt0", "4Apr}2", "20ctH2", "6Augh3",
# "13Aug$3", "15deck5", "14Novi2". An O or l is its 0 or 1: "2Oct4O", "2Feb3l".
_DIGIT = {**dict.fromkeys("tThH}#$kKiA¥%", "4"), "O": "0", "o": "0", "l": "1", "I": "1",
          "|": "1", "S": "5", "Z": "2", "B": "3", "J": "3"}
_DATE = (r"(?P<day>[0-9lIOSoh]{1,3})\s?" + _MONTH +
         r"\s?(?P<yr>[0-9A-Za-z}#$¥%|]{1,3}?)(?=[\s;,:.\-~]|$)")
DATE = re.compile(_DATE)
_REG = r"(?P<reg>[LMJ][PU]?\s?[0-9lIO]{1,7}|[1Il][0-9lIO]{3,6}|[0-9]{3,6})"
# "© 17May30; LP1323." The © is often OCR'd as "@", "6" or "6G" in the 1970s
# volumes ("6 17Dec47; 11354"), "S1Apr44" is a damaged day, and some print a
# comma after the date. Where the mark is lost entirely the registration number
# after the date still says it is the original date, not the renewal's.
ORIG = re.compile(r"(?:[©@€]|\(c\)|\b6G?\b)\s*(?:[SlIOB](?=[\dO]?[A-Z0-9]))?" + _DATE.replace("[0-9lIOSoh]", "[0-9lIOSohB]") +
                  r"(?:\s*[;,:.]?\s*" + _REG + r")?")
ORIG_BARE = re.compile(r"(?<![A-Za-z])" + _DATE + r"\s*[;,:]\s*" + _REG)
# "R353717", and what OCR made of it: "R3Z1016", "RB41915", "R¥91144", or an 8 after
# the date. Words are refused by the digit test.
RENEW = re.compile(r"(?<![A-Za-z0-9])R\s?(?=[0-9A-Za-z¥#]*\d[0-9A-Za-z¥#]*\d)[0-9A-Za-z¥#]{5,13}"
                   r"(?![A-Za-z0-9])|(?<=[;,] )8\d{6}\b")
# Where a title stops when the entry says what it is.
KIND = re.compile(r"[,.]?\s+(?:a|an|4|@|a&,?)\s+(?:(?:\w+[- ]){0,3}?)(?:p?photoplays?|motion\s*pictures?|series|serial|"
                  r"film|cartoon|newsreel)\b", re.I)
SERIES = re.compile(r"[,.]\s+(?:a|an|4|@)\s+(?:\w+\s+)?(?:series|serial)\b", re.I)
# Where it stops otherwise: ". By Columbia", ". No.1151", or a period.
TITLE_END = re.compile(r",\s+(?:a|an)\s|\.\s+(?:By|No\.|A\s+motion|A\s+photoplay)\b|(?<![A-Z])(?<!Mr)(?<!Mrs)(?<!Dr)(?<!St)"
                       r"(?<!Mt)(?<!Jr)\.\s|,\s+(?:by|in)\s")
# "Adventures of Sir Galahad, episode no. 5", "THE MASKED MARVEL, CHAP.1-12".
PART = re.compile(r"[,.\s]+(?:chap(?:ter)?s?|episodes?|ep|issue|vol|nos?)\.?\s*(?:nos?\.?\s*|number\s*)?(\d{1,3}(?:\s?-\s?\d{1,3})?)\b.*$", re.I)
# 1974-77: "Cody saves a life. By Columbia (Cody of the pony express, episode no. 5)".
IN_SERIES = re.compile(r"^(?P<t>.{3,100}?)[.,]?\s+(?:By\b[^(]*)?\((?P<s>[^()]{3,80}?)[,.]?\s+(?:chap\w*|e[a-z]{5,7}|ser\w*|no)"
                       r"\.?\s*(?:no[.,]?\s*)?(?P<n>\d{1,3})", re.I)
# The capitals of a title, after whatever OCR left in front of them.
CAPS = re.compile(r"(?:^|\s)((?:THE |A |AN )?[A-Z0-9'\"!?&.,:;()-]{2,}(?:\s+[A-Z0-9'\"!?&.,:;()-]+)*)$")
# "FIERY DANGER. See LOST CITY OF THE JUNGLE. 5." or "... THE SHADOW. Chap. no.9."
SEE = re.compile(r"^(?P<x>.{2,110}?)[.,]?\s+(?:See|SEE)\b\s*(?P<y>.*)$")
SEE_PART = re.compile(r"^(?P<s>.{3,100}?)[.,]\s*(?:(?:chap|episode|no)[a-z]*\.?\s*(?:no\.?\s*)?)?(?P<n>\d{1,3})\.?\s*$", re.I)
FURNITURE = re.compile(r"^(?:[\W_\d]*|[A-Za-z]{1,2}|\d{4}|(?:MOTION PICTURES|CURRENT REGISTRATIONS|RENEWAL REGISTRATIONS|"
                       r"RENEWALS|These entries alone|work\. Contact)\b.*)$")
# "a photoplay in nine reels", "in 8 reels", "9 reels.", "2 reels each".
REELS = re.compile(r"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|\d{1,2})"
                   r"\s+reels?\b", re.I)
_WORDS = ("one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
          "thirteen", "fourteen", "fifteen")
# A running head or the scanner's notice, wherever OCR left it: often on the title's line.
RUNNING = re.compile(r"(?:\b\d{1,3}\s+)?(?:MOTION PICTURES AND FILMSTRIPS|CATALOG OF COPYRIGHT ENTRIES|RENEWAL REGISTRATIONS)"
                     r"(?:\s+\d{1,3}\b)?|(?:These entries alone may not reflect[^.]*\.\s*)?"
                     r"(?:work\.\s+)?Contact the U\.?S\.? Copyright Office[^.]*\.|\bJan\S{0,2}\s?June\b[.:\s]*|\bJuly\S{0,2}\s?Dec\w*\b[.:\s]*")
CLAIM_END = re.compile(r"\((?:PWH|PCB|PPW|A|E|W|C|NK|PPT)\)?", re.I)


FLOOR = 15000


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


def flatten(text):
    """One line per paragraph, with words broken at a line end joined again."""
    out = []
    for block in re.split(r"\n\s*\n", text):
        b = " ".join(re.sub(r"(\w)-\s*\n\s*(\w)", r"\1\2", block).split())
        b = RUNNING.sub(" ", b).strip()
        if b:
            out.append(b)
    return "\n".join(out)


def _ymd(m):
    """(year, month, day) of a DATE match, each None where OCR left no digit."""
    y = "".join(_DIGIT.get(c, c) for c in m.group("yr"))[:2]
    d = "".join(_DIGIT.get(c, c) for c in m.group("day"))[-2:]
    mon = m.group("mon").lower()
    n = next((i + 1 for i, k in enumerate(("an", "e[bd]", "[as]r", "a[po]", "ay", "u[nm]", "u[l1i]", "a[un][ge]", "se",
                                           "c[tl]", "ov", "de")) if re.search(k, mon)), None)
    return (1900 + int(y) if y.isdigit() and len(y) == 2 else None, n,
            int(d) if d.isdigit() and 1 <= int(d) <= 31 else None)


def original_year(m, renewed):
    """(year, read_from_renewal). A renewal could be filed only in a work's 28th
    year, so the renewal date fixes the year of the original date: one read
    cleanly must agree with it, and one OCR damaged is read from it."""
    y, mon, day = _ymd(m)
    if not renewed or not renewed[0] or not mon or not renewed[1]:
        return y, False
    if y and 27 <= renewed[0] - y <= 28:
        return y, False
    # On or before the renewal's day of the year: 27 years on; after it: 28.
    later = (mon, day or 15) > (renewed[1], renewed[2] or 15)
    return renewed[0] - (28 if later else 27), True


def _entry(seg):
    """The text of the entry that ends a stretch of paragraphs: page furniture and
    cross-references out, and a paragraph that continues the one before it (a
    lower-case start, or a previous line with no full stop) kept with it."""
    paras = [p.strip() for p in seg.split("\n")]
    label = next((p for p in reversed(paras) if p.strip(" .,;:~'-")), "")
    if re.fullmatch(r"\d{1,3}(?:\s?-\s?\d{1,3})?[.,]?", label):
        return label                     # "1-6. © 4Apr42": a chapter printed as a number alone
    paras = [p for p in paras if p and not FURNITURE.match(p) and not _see(p)]
    if not paras:
        return ""
    i = len(paras) - 1
    while i > 0 and not KIND.search(paras[i][:140]) and (paras[i][0].islower() or paras[i].startswith("By ") or
                                                         not re.search(r"[.)]$", paras[i - 1])):
        i -= 1
    e = " ".join(paras[i:])
    e = re.sub(r"^.*(?:\(PWH\)|PWH\))[;,.]?\s+(?=[A-Z0-9'\"])", "", e) if not SERIES.search(e) else e
    return re.sub(r"^([A-Z]) (?=\1)", "", e.lstrip(" .,;:~-"))


def _see(p):
    """A cross-reference, with no entry of its own after it."""
    m = SEE.match(p)
    if p in ("See", "SEE"):
        return True
    return bool(m) and not KIND.search(p) and not ORIG.search(p)


def _clean_title(t):
    t = re.split(r"\s+By\s+", t)[0]
    return re.sub(r"^[\W_]+|[\W_]+$", "", t.replace("  ", " "))


def _reels(e):
    m = REELS.search(e)
    if not m:
        return None
    w = m.group(1).lower()
    return int(w) if w.isdigit() else _WORDS.index(w) + 1


def _part(t):
    """(title without an episode tail, the part it names)."""
    m = PART.search(t)
    if m and m.start() >= 3:
        return t[:m.start()].rstrip(" ,.;"), m.group(1).replace(" ", "")
    return t, None


def volume_text(ident):
    meta = _get(f"https://archive.org/metadata/{ident}/files")
    names = [f["name"] for f in json.loads(meta or b'{"result":[]}').get("result", [])
             if f["name"].endswith("_djvu.txt")]
    return _get(f"https://archive.org/download/{ident}/{names[0]}") if names else None


def parse(text, vol):
    """Every renewal in one volume. A renewal number ends an entry (the 1964+ form
    prints it last, 1950-63 prints the claimant after it, 1976-77 also prints it
    above the entry as a sort key), so the text between two numbers holds exactly
    one entry, whatever blank lines OCR put inside it. The earlier block reader
    needed an entry in one paragraph and lost about half.

    A "series of photoplays" prints its title once and its chapters beneath, each
    with its own date and renewal. A row carries `s` (the series) and `ch` (the
    chapter) as well as `t` (the chapter's title, the series' when it has none).
    The earlier reader saw each chapter as a film, and any two in one paragraph as
    nothing: 123 such headers in print, 2 in the table."""
    s = flatten(text)
    marks = list(RENEW.finditer(s))
    # The renewal year of a typical entry in this volume: a date claiming another is OCR.
    years = Counter()
    for m in marks:
        d = None
        for d in DATE.finditer(s[max(0, m.start() - 24):m.start()]):
            pass
        y = _ymd(d)[0] if d else None
        if y:
            years[y] += 1
    usual = {y for y, n in years.most_common(3) if n >= 20} or set(years)
    out, seen_cross, prev, series = [], [], 0, None
    for i, m in enumerate(marks):
        chunk = s[prev:m.start()]
        prev = m.end()
        o = None
        for o in ORIG.finditer(chunk):
            pass
        for b in ORIG_BARE.finditer(chunk):
            if not o or b.start() > o.end():
                o = b
        for line in chunk.split("\n"):
            c = SEE.match(line)
            if c and c.group("y"):
                seen_cross.append((c.group("x"), c.group("y")))
        # Its renewal date: printed before the number, or after it in 1950-63.
        tail = chunk[o.end():] if o else chunk
        after = s[m.end():m.end() + 24]
        d = None
        for d in DATE.finditer(tail):
            pass
        if not d:
            d = DATE.search(after[:16])
        renewed = _ymd(d) if d else None
        if renewed and renewed[0] not in usual:
            renewed = None
        year, inferred = original_year(o, renewed) if o else (None, True)
        reg = re.sub(r"^[1lI](?=\d{4,6}$)|^Ll(?=\d)", "L", ((o and o.group("reg")) or "").replace(" ", ""))
        # A chapter whose date OCR lost ("1. Enemy passport. 24Aug70; R490023") still
        # belongs to its series, and may be the one that carries the series' header.
        head = chunk[:o.start()] if o else (chunk[:d.start()] if d and d.string == tail else chunk)
        e = _entry(head)
        if not e:
            continue
        reels = _reels(e)
        inner = IN_SERIES.match(e)
        hp = next((p for p in reversed(head.split("\n")) if SERIES.search(p) and not _see(p)), None)
        if inner:
            series = None
        elif hp:
            hdr = SERIES.search(hp)
            name, _ = _part(_clean_title(hp[:hdr.start()]))
            cl = re.search(r"[©@]\s*([^©@]{3,90}?\(PWH\)?)", head.replace("\n", " "))
            serial = bool(re.search(r"photoplays?|serial|episodes", hp[hdr.start():hdr.end() + 40], re.I))
            series = {"t": name, "c": cl.group(1) if cl else "", "serial": serial}
            if SERIES.search(e):        # the header and its first chapter in one paragraph
                hdr = SERIES.search(e)
                rest = CLAIM_END.split(e[hdr.end():])
                e = rest[-1] if len(rest) > 1 else ""
                e = re.sub(r"^.*?\b(?:each|reels?)\b[^.]*\.", "", e) if len(rest) == 1 else e
        elif KIND.search(e) or ". By " in e or re.match(r"[A-Z0-9'\"]{2,}(?:[ ,.]|$)", e) and e.upper() == e:
            series = None
        if not o and not series:
            continue
        if series:
            year = year or series.get("y") or (renewed and renewed[0] - 28)
            series["y"] = year
        if inner:
            title, sname, part, claim = _clean_title(inner.group("t")), _clean_title(inner.group("s")), inner.group("n"), ""
            serial = bool(re.search(r"chap|e[a-z]{5,7}\b", inner.group(0)[len(inner.group("t")):], re.I))
        elif series:
            e = re.sub(r"^.*(?:Chap(?:ter)?|Episode)\.?\s*nos?\.?", "", e, flags=re.I)
            n = re.match(r"\W*(\d{1,3}(?:\s?-\s?\d{1,3})?)[\W_]*(.*)$", e)
            part, name = (n.group(1).replace(" ", ""), n.group(2)) if n else (None, e)
            name = re.split(r"\.\s", name)[0]
            title, sname = _clean_title(name), series["t"]
            claim, serial = series["c"], series["serial"]
        else:
            k = KIND.search(e)
            t = re.sub(r"^\d{1,3}[.,]\s+", "", e[:k.start()] if k else e)     # "1. Amazing Mazie." in a series
            base, part = _part(t)
            serial = bool(part) and bool(re.search(r"chap|episode", t[len(base):], re.I))
            caps = CAPS.search(base) if k else None
            if caps and re.search(r"[A-Za-z]{2}", caps.group(1)):
                base = caps.group(1)
                base = re.split(r"(?<![A-Z])(?<!MR)(?<!MRS)(?<!DR)(?<!ST)(?<!MT)(?<!JR)\.\s|’,\s", base)[-1]
            if not k:
                end = TITLE_END.search(base + " ")
                base = base[:end.start()] if end else base
            title, sname = _clean_title(base), None
            if part and title:
                title, sname = "", title
            claim = ""
        name = title or sname or ""
        if not (3 <= len(name) <= 120) or not re.search(r"[A-Za-z]{3}", name):
            continue
        if name.upper().startswith("SEE ") or name.lower() in ("reel", "reels", "chap", "episode no"):
            continue
        # A renewal's ORIGINAL registration: 1909 Act works, renewed 28 years on.
        if not (year and 1909 <= year <= 1950) or reg.startswith("R"):
            continue
        if not claim:
            claim = tail[:d.start()] if d and d.string == tail else tail
            if not d or d.string != tail:
                claim = s[m.end():m.end() + 130].split("\n")[0]
                claim = re.sub(r"^[\s,.;]*" + _DATE + r"[\s,.;]*", "", claim)
            claim = claim.strip(" .;,\n")
            claim = re.sub(r"[;,]?\s*[%\d]{1,2}\s*[A-Za-z]{3,4}\s*\d{2}\s*$", "", claim).strip(" .;,")
            claim = re.sub(r"(\w)- (\w)", r"\1\2", claim.replace("\n", " "))
        r = re.sub(r"\s", "", m.group())
        r = "R" + "".join(_DIGIT.get(c, c) for c in r[1:])
        r = r[:7] if len(r) > 11 else r        # "R326860326861": two numbers printed as a range
        row = {"t": title or sname, "y": year, "reg": reg, "r": r, "c": claim[:120], "vol": vol}
        if sname:
            row["s"] = sname
        if part:
            row["ch"] = part
        if serial:
            row["sr"] = 1
        if reels and not sname:
            row["rl"] = reels
        if inferred:
            row["yr"] = 1
        out.append(row)
    return out + _cross_named(out, seen_cross)


def _cross_named(rows, crosses):
    """"FIERY DANGER. See LOST CITY OF THE JUNGLE. 5." names a chapter the series
    prints as a number, or a range ("1-6. © 4Apr42"). The chapter gets a row of its
    own, on the renewal that covers it."""
    by = {}
    for r in rows:
        if r.get("s") and r.get("ch"):
            by.setdefault(re.sub(r"[^a-z0-9]", "", r["s"].lower()), []).append(r)
    extra = []
    for x, y in crosses:
        p = SEE_PART.match(y)
        if not p:
            continue
        for r in by.get(re.sub(r"[^a-z0-9]", "", re.sub(r"(?i)^(the|a|an)\s+", "", p.group("s")).lower()), []) or \
                by.get(re.sub(r"[^a-z0-9]", "", p.group("s").lower()), []):
            lo, _, hi = r["ch"].partition("-")
            if int(lo) <= int(p.group("n")) <= int(hi or lo):
                t = _clean_title(x)
                if 3 <= len(t) <= 120:
                    extra.append({**r, "t": t, "ch": p.group("n")})
                break
    return extra


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--from", dest="folder", help="read <identifier>.txt from here instead of archive.org")
    a = ap.parse_args()
    if a.folder:
        vols = [(p.stem, 0) for p in sorted(Path(a.folder).glob("*.txt"))]
    else:
        vols = [(a.only, 0)] if a.only else volumes()
    print(f"[cce] {len(vols)} volumes")
    rows, seen = [], set()
    for ident, y in vols:
        raw = (Path(a.folder) / f"{ident}.txt").read_bytes() if a.folder else volume_text(ident)
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
    # A reader that could not read must not replace a table that could.
    if len(rows) < FLOOR:
        print(f"::error::[cce] only {len(rows)} renewals read (floor {FLOOR}): table left alone")
        return 1
    OUT.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
    print(f"[cce] wrote {len(rows)} renewals -> {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
