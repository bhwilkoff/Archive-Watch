#!/usr/bin/env python3
"""The RENEWAL registrations of dramas and works prepared for oral delivery
(Class D, and Class C scripts) printed in the Catalog of Copyright Entries, as
a table the audit can read.

WHY (02-rights §3.1): a radio script registered as an unpublished drama under
the 1909 Act and RENEWED in its 28th year is protected for 95 years from
registration, and a free recording of a protected script is not free (Lone
Ranger Television v. Program Radio, 9th Cir. 1984). The Copyright Office's
online records begin with renewals filed in 1978, so a script registered
1923-1950 (renewed 1951-1978) is found only in print. archive.org hosts every
annual "Dramas and Works Prepared for Oral Delivery" volume of the Third
Series (1947-1977) with OCR text; from 1951 each prints its renewals in a
section of their own. Archive Watch's tools/fetch_cce_renewals.py does the same
for motion pictures; this follows it.

Two printed formats, both read:
    1951-1953 (renewal number first):
        The mayor and the manicure, a play in one act. © 31Dec23, D66801.
        R75707, 1Mar51, James D. Rathbun (E)
    1954 on (claimant first, renewal number last):
        Please stand by, a radioletta. © 7Oct26; D77113, Carolyn Draper
        Gilpatric (A); 6Jan54; R124678.
An entry is kept only if it carries an original © date, a D-prefixed original
registration, a renewal number and a renewal date 26-29 years after the
original: a renewal is filed in a copyright's 28th year, so OCR damage to any
of the four can only cause a miss, never a match.

Output: .cache/cce_drama_renewals.json.gz — a list of rows
    {title, author, claimant, reg, orig_date, orig_year, r, r_date, r_year,
     vol, vol_year, line, text, radio, radio_why, src}
`src` opens the scanned volume at a full-text search for the renewal number.

Run: python3 tools/fetch_cce_drama_renewals.py [--only IDENTIFIER] [--offline]
"""
import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_lib as L

RAW = os.path.join(L.CACHE, "cce_drama")
OUT = os.path.join(L.CACHE, "cce_drama_renewals.json.gz")
# Measured 2026-10-17: the first query finds all 31 Third Series drama volumes
# (1947-1977, plus 14 New Series 1915-1926 "Pamphlets, Dramas, Maps" volumes,
# which predate renewals of radio-era work and are dropped by the year filter);
# the second finds nothing the first does not, and is kept as a check.
QUERIES = [
    'title:("catalog of copyright entries") AND title:(dramas)',
    'title:("catalog of copyright entries") AND title:("oral delivery")',
]

MON = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"
MONTHS = {m: i + 1 for i, m in enumerate(MON.split("|"))}
DATE = rf"(\d{{1,2}})\s?({MON})\s?(\d{{2}})"
# "© 7Oct26; D77113" / "© 31Dec23, D66801." — the © is OCR'd as "@" too.
ORIG = re.compile(rf"[©@]\s*{DATE}\s*[;,.:]?\s*(D[PU]?\s?\d{{1,6}})\b")
RNUM = r"R\s?(\d{5,6})"
# 1951-53: "D66801. R75707, 1Mar51, James D. Rathbun (E)"
FMT_A = re.compile(rf"^[\s.,;:-]*{RNUM}\s*[,;.]\s*{DATE}\s*[,;.]?\s*(.*)$")
# 1954 on: "D77113, Carolyn Draper Gilpatric (A); 6Jan54; R124678."
FMT_B = re.compile(rf"^[\s.,;:-]*(.*?)[;,.]?\s*{DATE}\s*[;,.]\s*{RNUM}\b")
# OCR reads 1 as l / I / |, and 0 as O, inside dates and numbers:
# "© 3lJan2l, D67089", "© 12O0ct26", "©11Ju123" (Jul23).
_OCR_DIGIT = re.compile(r"(?<=\d)[lI|](?=[\dlI|;,.:\s])|(?<=[A-Za-z]{3}\d)[lI|]|(?<=\d)O(?=\d)|(?<=[©@] )[lI](?=\d)")
_OCR_MON = re.compile(r"(?<=\d)(Ju1|Jul1|Ju1l)(?=\d)")
_OCR_MON2 = re.compile(r"(?<=\d)O(?=ct\d)|(?<=\d)0ct(?=\d)")
TITLE_END = re.compile(r"(?:,|;)\s+(?:a|an|the|by|in|from|for|comedy|drama|play|piece|opera|operette|"
                       r"operetta|com[eé]die|scripts?|radio|monolog|lecture)\b|;\s|\.\s+(?:By|Text|Music|A\s)\b|\.\s")
HEADING = re.compile(r"^((?:[A-Z][A-Z'’&.\-]*,?\s+){0,6}[A-Z][A-Z'’&.\-]*)\.\s+(?=[A-Z][a-z])")
RADIO = re.compile(
    r"\bradio|\bbroadcast|\btranscri(?:ption|bed)\b|\bon the air\b|\bWOR\b|\bWXYZ\b|\bNBC\b|\bCBS\b|"
    r"National Broadcasting|Columbia Broadcasting|Mutual Broadcasting|"
    r"Lone Ranger|Green Hornet|Fibber McGee|Inner Sanctum|Lights Out|Amos .n. Andy|Jack Benny|"
    r"Johnny Dollar|Gunsmoke|Dragnet|Cavalcade of America|Gang Busters|One Man'?s Family|"
    r"Ma Perkins|Myrt and Marge|Vic and Sade|Easy Aces|Lum and Abner|Death Valley Days", re.I)


def volumes():
    found = {}
    for q in QUERIES:
        d = L.get(L.ADV, {"q": q, "fl[]": ["identifier", "year", "title"], "rows": 500, "output": "json"})
        if d is None:
            raise RuntimeError(f"advancedsearch failed: {q}")
        for x in d["response"]["docs"]:
            t = x.get("title") or ""
            try:
                y = int(str(x.get("year"))[:4])
            except ValueError:
                continue
            if "oral delivery" in t.lower() and 1947 <= y <= 1977:
                found[x["identifier"]] = (y, t)
    return sorted(((i, y, t) for i, (y, t) in found.items()), key=lambda v: v[1])


def fetch(ident, offline=False):
    path = os.path.join(RAW, ident + "_djvu.txt")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    if offline:
        return None
    meta = L.get(L.META + ident + "/files")
    names = [f["name"] for f in (meta or {}).get("result", []) if f["name"].endswith("_djvu.txt")]
    if not names:
        return None
    raw = L.get("https://archive.org/download/" + ident + "/" + names[0], raw=True, timeout=300)
    if not raw:
        return None
    os.makedirs(RAW, exist_ok=True)
    with open(path + ".tmp", "wb") as f:
        f.write(raw)
    os.replace(path + ".tmp", path)
    time.sleep(3)
    return path


def clean(s):
    s = " ".join(s.split())
    s = re.sub(r"(\w)- (\w)", r"\1\2", s)               # line-break hyphens
    s = _OCR_MON.sub("Jul", s)
    s = _OCR_MON2.sub(lambda m: "O" if m.group() == "O" else "Oct", s)
    s = _OCR_DIGIT.sub(lambda m: "0" if m.group() == "O" else "1", s)
    return s


def _date(d, m, y):
    d, y = int(d), 1900 + int(y)
    if not 1 <= d <= 31:
        return None, None
    return f"{y}-{MONTHS[m]:02d}-{d:02d}", y


def blocks(text):
    """Blank-line blocks with their starting line number. An entry split by a
    blank line (the © in one block, the renewal number in the next) is joined."""
    out, cur, start = [], [], 1
    for n, line in enumerate(text.split("\n"), 1):
        if line.strip():
            if not cur:
                start = n
            cur.append(line)
        elif cur:
            out.append((start, "\n".join(cur)))
            cur = []
    if cur:
        out.append((start, "\n".join(cur)))
    joined, i = [], 0
    while i < len(out):
        s, b = out[i]
        cb = clean(b)
        if ORIG.search(cb) and not re.search(RNUM, cb[ORIG.search(cb).end():]) and i + 1 < len(out):
            nb = clean(out[i + 1][1])
            if re.search(RNUM, nb) and not ORIG.search(nb):
                joined.append((s, b + "\n" + out[i + 1][1]))
                i += 2
                continue
        joined.append((s, b))
        i += 1
    return joined


CAPS_LEAD = re.compile(r"^((?:THE |A |AN |LA |LE |EL |DER |DIE |DAS )?[A-Z0-9][A-Z0-9'’&!?.:\-]*(?:\s+[A-Z0-9'’&!?.:\-]+)*?)\s*([,;.])\s")
BARE_HEADING = re.compile(r"^[A-Z][A-Z'’&.\- ]*,\s+[A-Z][A-Z'’&.\- ]*\.?$")


def title_first(bl):
    """The 1950s volumes enter a renewal under its AUTHOR ("ABBOTT, GEORGE."
    then "Broadway, a play..."); from about 1958 under its TITLE in capitals
    ("FACE THE MUSIC, a musical play ... by Irving Berlin"). Decided per volume
    by which shape most entries take."""
    caps = mixed = 0
    for _, block in bl:
        b = clean(block)
        if not ORIG.search(b):
            continue
        if re.match(r"^(?:THE |A |AN )?[A-Z][A-Z'’\-]{2,}(?:\s+[A-Z'’\-]+)*,\s+(?:a|an)\s", b):
            caps += 1
        elif re.match(r"^[A-Z][a-z]", b):
            mixed += 1
    return caps > mixed


def parse(text, vol, vol_year=0):
    rows, author = [], ""
    bl = blocks(text)
    tfirst = title_first(bl)
    for line, block in bl:
        b = clean(block)
        h = None if tfirst else HEADING.match(b)
        if h and "SEE" not in h.group(1).split():
            author = h.group(1).strip(" ,.")
        elif not tfirst and BARE_HEADING.match(b) and len(b) < 60:
            author = b.strip(" ,.")                  # a bare heading block: "ADE, GEORGE."
        o = ORIG.search(b)
        if not o:
            continue
        rest = b[o.end():]
        a, bm = FMT_A.match(rest), FMT_B.match(rest)
        if a:
            r, rd, claim = a.group(1), a.groups()[1:4], a.group(5)
            claim = re.split(r"\s+(?:SEE|[A-Z][A-Z ,.'-]{6,}\.\s)", claim)[0]
        elif bm:
            claim, rd, r = bm.group(1), bm.groups()[1:4], bm.group(5)
        else:
            continue
        odate, oyear = _date(*o.groups()[:3])
        rdate, ryear = _date(*rd)
        if not (odate and rdate) or not (1909 <= oyear <= 1950) or not (26 <= ryear - oyear <= 29):
            continue
        head = b[:o.start()]
        if h:
            head = head[h.end():] if h.end() <= o.start() else head
        head = re.sub(r"^\d{1,3}\.\s+", "", head).strip()
        end = TITLE_END.search(head)
        title = (head[:end.start()] if end else head).strip(" ,.;:")
        if not (2 <= len(title) <= 160) or not re.search(r"[A-Za-z]{2}", title):
            continue
        by = re.search(r"\bby\s+([A-Z][\w.'’ -]+?)(?:[,.;]|\s+and\b|$)", head)
        if tfirst:
            c = CAPS_LEAD.match(head + " ")
            if c and re.search(r"[A-Z]{2}", c.group(1)):
                title = c.group(1).strip(" ,.;:")
            entry_author = by.group(1).strip() if by else ""
        else:
            entry_author = author or (by.group(1).strip() if by else "")
        m = RADIO.search(b) or RADIO.search(author if author else "")
        claim = re.sub(r"\s*\([A-Za-z&]{1,4}[^)]{0,30}\)?\s*$", "", claim.strip(" .;,"))
        rows.append({
            "title": title, "author": entry_author, "claimant": claim.strip(" .;,")[:160],
            "reg": o.group(4).replace(" ", ""), "orig_date": odate, "orig_year": oyear,
            "r": "R" + r, "r_date": rdate, "r_year": ryear,
            "vol": vol, "vol_year": vol_year, "line": line, "text": b[:400],
            "radio": bool(m), "radio_why": m.group(0) if m else None,
            "src": f"https://archive.org/details/{vol}?q=R{r}",
        })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--offline", action="store_true", help="parse the cached OCR only")
    a = ap.parse_args()
    if a.only:
        vols = [(a.only, 0, "")]
    elif a.offline:
        vols = [(f[:-9], 0, "") for f in sorted(os.listdir(RAW)) if f.endswith("_djvu.txt")]
    else:
        vols = volumes()
    print(f"[cce-drama] {len(vols)} volumes")
    rows, seen, failed, per = [], set(), [], []
    for ident, y, _t in vols:
        p = fetch(ident, a.offline)
        if not p:
            failed.append(ident)
            print(f"[cce-drama] {ident} ({y}): could not read the text layer")
            continue
        with open(p, encoding="utf-8", errors="replace") as f:
            got = parse(f.read(), ident, y)
        new = [g for g in got if (g["r"], g["reg"]) not in seen]
        seen |= {(g["r"], g["reg"]) for g in new}
        rows += new
        per.append((y, ident, len(new), sum(g["radio"] for g in new)))
        print(f"[cce-drama] {y} {ident}: {len(new)} renewals, {sum(g['radio'] for g in new)} radio", flush=True)
    if a.only:
        for g in rows[:20]:
            print("  ", {k: g[k] for k in ("title", "author", "reg", "orig_date", "r", "r_date", "radio")})
        return 0
    if not rows:
        print("[cce-drama] parsed nothing", file=sys.stderr)
        return 1
    L.write_json(OUT, rows, gz=True)
    with_r = sum(1 for v in per if v[2])
    print(f"[cce-drama] wrote {len(rows)} renewals ({sum(g['radio'] for g in rows)} radio) from "
          f"{with_r} of {len(per)} volumes -> {os.path.relpath(OUT, L.ROOT)}; unread: {failed or 'none'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
