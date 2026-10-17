#!/usr/bin/env python3
"""The RENEWAL registrations of dramas and works prepared for oral delivery
(Class D dramas, and Class C scripts) printed in the Catalog of Copyright
Entries, 1951-1977, as a table the audit can read.

WHY (docs/research/radio/02-rights.md §3.1): a radio script registered as an
unpublished drama under the 1909 Act and RENEWED in its 28th year is protected
for 95 years from registration, and a free recording of a protected script is
not free (Lone Ranger Television v. Program Radio, 9th Cir. 1984). The
Copyright Office's online records begin with renewals filed in 1978, so a
script registered 1923-1950 (renewed 1951-1978) is found only in print.
archive.org hosts all 31 annual "Dramas and Works Prepared for Oral Delivery"
volumes of the Third Series (1947-1977) with OCR text; from 1951 each prints
the renewals filed that year (1947-1950's are in Part 14A, not here). This
follows Archive Watch's tools/fetch_cce_renewals.py (motion pictures).

The printed formats, all read:
    1951-1953, under the author, renewal number first:
        The mayor and the manicure, a play in one act. © 31Dec23, D66801.
        R75707, 1Mar51, James D. Rathbun (E)
    1954-1957, under the author, claimant first, renewal number last:
        Please stand by, a radioletta. © 7Oct26; D77113, Carolyn Draper
        Gilpatric (A); 6Jan54; R124678.
    1958-1970, under the TITLE in capitals; a series lists each registration:
        THE LONE RANGER; radio program by Francis Striker. © No.A-9--A-10,
        15Aug34, D30663-30664 ; No.A-11, 17Aug34, D30707. The Lone Ranger,
        Inc. (PWH); 13Aug62; R300173-300175.
    1971-1977, in renewal-number order, the series in parentheses:
        R577542.
        How six traveled through the world. By Nila Mack. (Let's pretend)
        © 3May47; D9330. CBS, Inc. (PWH); 20May74; R577542.
A row needs an original © date with a D- or C-prefixed registration, a renewal
number and a renewal date 26-29 years after the original (a renewal is filed
in a copyright's 28th year), so OCR damage to any of them causes a miss, never
a match.

Output: .cache/cce_drama_renewals.json.gz — one row per original registration:
    {title, episode, series, author, claimant, reg, reg_class, orig_date,
     orig_year, r (None when the OCR'd number is implausible; r_printed
     keeps it), r_range, r_date, r_year, vol, vol_year, line, text, radio,
     radio_why, src}
`src` opens the scanned volume at a full-text search for the renewal number.

Run: python3 tools/fetch_cce_drama_renewals.py [--offline] [--only IDENTIFIER]
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
# Measured 2026-10-17. The first query returns 45 items: the 31 Third Series
# drama volumes 1947-1977 (one per year, none missing) and 14 New Series
# 1915-1926 "Pamphlets, Dramas, Maps" volumes, which hold no renewals of
# radio-era work and are dropped by the title/year filter. The second returns
# nothing the first does not; it is kept as a check.
QUERIES = [
    'title:("catalog of copyright entries") AND title:(dramas)',
    'title:("catalog of copyright entries") AND title:("oral delivery")',
]

MON = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"
MONTHS = {m: i + 1 for i, m in enumerate(MON.split("|"))}
DATE = rf"(\d{{1,2}})\s?({MON})\s?(\d{{2}})"
COPY = r"(?:[©@€]G?@?)"
REG = r"((?:D[PUF]?|C)\s?\d{1,6}(?:\s?-\s?\d{1,6})?)"
# One registration inside a © statement, with its optional issue number:
# "No.A-11, 17Aug34, D30707" / "3-10, 6Aug31, D11597" / "7Oct26; D77113".
PAIR = re.compile(rf"(?:(?:Nos?\.?\s*)?([\w.\-]+(?:\s?-+\s?[\w.\-]+)?)\s*[,;:]\s*)?{DATE}\s*[;,.:]?\s*{REG}(?![\w])")
FIRST = re.compile(rf"{COPY}\s*(?:(?:Nos?\.?\s*)?[\w.\-]+(?:\s?-+\s?[\w.\-]+)?\s*[,;:]\s*)?{DATE}\s*[;,.:]?\s*{REG}(?![\w])")
RNUM = r"R\s?(\d{5,6})(?:\s?-\s?R?\s?(\d{5,6}))?(?!\)?\d)"
# 1951-53: "D66801. R75707, 1Mar51, James D. Rathbun (E)"
FMT_A = re.compile(rf"^[\s.,;:-]*{RNUM}\s*[,;.]\s*{DATE}\s*[,;.]?\s*(.*)$")
# 1954 on: "... Carolyn Draper Gilpatric (A); 6Jan54; R124678." The ";" before
# the R is OCR'd as a trailing 3 or 5 ("4Jun645 R338916"), so one is allowed.
FMT_B = re.compile(rf"(.*?)[;,.]?\s*{DATE}[35s]?\s*[;,.]?\s*{RNUM}(?![\d])")
# OCR reads 1 as l / I / |, and 0 as O, inside dates and numbers:
# "© 3lJan2l, D67089", "© 12O0ct26", "©11Ju123" (Jul23), "lMay42".
_OCR_ONE = re.compile(r"(?<=\d)[lI|](?=[\dlI|;,.:\s]|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\d)|(?<=[A-Z][a-z]{2}\d)[lI|]|(?<=[\s©@])[lI](?=\d|[A-Z][a-z]{2}\d)")
_OCR_ZERO = re.compile(r"(?<=\d)O(?=\d)")
# h for 4 ("R7590h", "31Dec5h", "20Augh2"), and a registration's D read as p
# straight after a © date ("© 16Feb28; p82825").
_OCR_FOUR = re.compile(r"(?<=\d)h(?=[\d\s.,;)]|$)|(?<=[A-Z][a-z]{2})h(?=\d)")
_OCR_D = re.compile(r"(?<=\d\d[;,.] )p(?=[PU]?\d{3,6}\b)|(?<=\d\d[;,.])p(?=[PU]?\d{3,6}\b)")
_OCR_JUL = re.compile(r"(?<=\d)Ju[1l](?=\d)")
_OCR_OCT = re.compile(r"(?<=\d)[O0]?0ct(?=\d)|(?<=\d)O0ct(?=\d)")
TITLE_END = re.compile(r"(?:,|;)\s+(?:a|an|the|by|in|from|for|comedy|drama|play|piece|opera|operette|"
                       r"operetta|com[eé]die|scripts?|radio|monologu?e?|lecture|program|no\.?)\b|;\s|"
                       r"\.\s+(?:By|by|Text|Music|A|An|Radio|NM:|No\.)\s|\.\s+\(|\.\s*$")
HEADING = re.compile(r"^((?:[A-Z][A-Z'’&.\-]*,?\s+){0,6}[A-Z][A-Z'’&.\-]*)\.\s+(?=[A-Z][a-z])")
BARE_HEADING = re.compile(r"^[A-Z][A-Z'’&.\- ]*,\s+[A-Z][A-Z'’&.\- ]*\.?$")
CAPS_TITLE = re.compile(r"^((?:[A-Z0-9][A-Z0-9'’&!?.:\-]*\s+)*?[A-Z0-9][A-Z0-9'’&!?\-]*[A-Z0-9!?'])\s*[,;.]\s")
BY = re.compile(r"\b[Bb]y\s+((?:[A-Z][\w'’.\-]*\.?\s?){1,6}?(?:(?:\s*&\s*|,\s+|\s+and\s+)(?:[A-Z][\w'’.\-]*\.?\s?){1,5}?)*)(?=[.,;(]|\s+(?:and|from|with)\b|$)")
SERIES = re.compile(r"\(([^()]{3,90})\)\s*$")
RADIO = re.compile(
    r"\bradio|\bbroadcast|\btranscri(?:ption|bed)\b|\bon the air\b|\brecording script|\bWOR\b|\bWXYZ\b|\bNBC\b|"
    r"\bC ?BS\b|National Broadcasting|Columbia Broadcasting|Mutual Broadcasting|"
    r"Lone Ranger|Green Hornet|Fibber McGee|Inner Sanctum|Lights Out|Amos .n. Andy|Jack Benny|"
    r"Johnny Dollar|Gunsmoke|Dragnet|Cavalcade of America|Gang Busters|One Man'?s Family|Let'?s pretend|"
    r"Ma Perkins|Myrt and Marge|Vic and Sade|Easy Aces|Lum and Abner|Death Valley Days|Witch'?s Tale", re.I)
# Radio series named only in an entry's series parenthesis, "(The Shadow)",
# where the bare word would match plays too.
RADIO_SERIES = re.compile(r"^(?:The )?(?:Shadow|(?:Return of )?[NW]ick Carter|Greatest story ever told|"
                          r"Favorite stor(?:y|ies)|Thirteen by Corwin|More by Corwin)\b", re.I)


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
    s = _OCR_JUL.sub("Jul", s)
    s = _OCR_OCT.sub("Oct", s)
    s = _OCR_ZERO.sub("0", s)
    s = _OCR_FOUR.sub("4", s)
    s = _OCR_D.sub("D", s)
    return _OCR_ONE.sub("1", s)


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
    # An entry whose title was split from its © by a blank line: "The Case of
    # the unlucky corpses. By" / "Norman A. Daniels. (Nick Carter...) © 23Dec49".
    back = []
    for s, b in out:
        cb, pb = clean(b), clean(back[-1][1]) if back else ""
        f = FIRST.search(cb)
        if f and back and len(pb) < 300 and not FIRST.search(pb) and not re.search(RNUM, pb) \
                and not re.search(r"\b(?:SEE|See)\s+[A-Z]", pb) and \
                (re.search(r"(?:\b[Bb]y|,|\bof|\bthe|\band|&|\(|-)$", pb) or re.match(r"^(?:[a-z]|no\.)", cb)):
            back[-1] = (back[-1][0], back[-1][1] + "\n" + b)
        else:
            back.append((s, b))
    out = back
    joined, i = [], 0
    while i < len(out):
        s, b = out[i]
        cb = clean(b)
        f = FIRST.search(cb)
        if f and not re.search(RNUM, cb[f.end():]) and i + 1 < len(out):
            nb = clean(out[i + 1][1])
            if re.search(RNUM, nb) and not FIRST.search(nb):
                joined.append((s, b + "\n" + out[i + 1][1]))
                i += 2
                continue
        joined.append((s, b))
        i += 1
    return joined


def title_first(bl):
    """1951-57 enter a renewal under its AUTHOR ("ABBOTT, GEORGE." then
    "Broadway, a play..."); 1958-70 under its TITLE in capitals ("FACE THE
    MUSIC, a musical play ... by Irving Berlin"); 1971-77 under a mixed-case
    title. Decided per volume by which shape most entries take."""
    caps = mixed = 0
    for _, block in bl:
        b = clean(block)
        if not FIRST.search(b):
            continue
        if re.match(r"^(?:THE |A |AN )?[A-Z][A-Z'’\-]{2,}(?:\s+[A-Z'’\-]+)*[,;]\s", b):
            caps += 1
        elif re.match(r"^[A-Z][a-z]", b):
            mixed += 1
    return caps > mixed


def _expand(reg):
    """'D30663-30664' -> ['D30663', 'D30664']; a range wider than 60 is not
    expanded (an OCR'd digit would invent registrations)."""
    m = re.match(r"([A-Z]+)(\d+)(?:-(\d+))?$", reg)
    if not m:
        return [reg]
    p, a, b = m.group(1), int(m.group(2)), m.group(3)
    if b is None:
        return [reg]
    b = int(b)
    if b < a and len(m.group(3)) < len(m.group(2)):        # "D11105-9": short form
        b = int(m.group(2)[:-len(m.group(3))] + m.group(3))
    if not 0 <= b - a <= 60:
        return [f"{p}{a}"]
    return [f"{p}{n}" for n in range(a, b + 1)]


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
        f = FIRST.search(b)
        if not f:
            continue
        stmt = b[f.start():]
        a = None
        pairs, pos = [], 1
        for p in PAIR.finditer(stmt, 1):
            if stmt[pos:p.start()].strip(" ;,.:-&") and pairs:
                break                                    # the claimant begins
            pairs.append(p)
            pos = p.end()
        rest = stmt[pos:]
        a = FMT_A.match(rest)
        bm = None if a else FMT_B.match(rest)
        if a:
            r1, r2, rd, claim = a.group(1), a.group(2), a.groups()[2:5], a.group(6)
            claim = re.split(r"\s+(?:SEE\b|[A-Z][A-Z ,.'-]{6,}\.\s)", claim)[0]
        elif bm:
            claim, rd, r1, r2 = bm.group(1), bm.groups()[1:4], bm.group(5), bm.group(6)
        else:
            continue
        rdate, ryear = _date(*rd)
        if not rdate or not (1947 <= ryear <= 1978):
            continue
        rnums = [r1]
        if r2:
            lo, hi = int(r1), int(r2)
            rnums = [str(n) for n in range(lo, hi + 1)] if 0 <= hi - lo <= 200 else [r1]
        head = b[:f.start()]
        if h and h.end() <= f.start():
            head = head[h.end():]
        head = re.sub(r"^R\s?\d{5,6}\s?[.,\-«]*\s*", "", head)  # 1971-77: the entry's own R number
        head = re.sub(r"^\d{1,3}\.\s+", "", head).strip()
        s = SERIES.search(head)
        series = s.group(1).split(",")[0].strip() if s else ""
        if tfirst:
            c = CAPS_TITLE.match(head + " ")
            title = c.group(1) if c and re.search(r"[A-Z]{2}", c.group(1)) else ""
        else:
            title = ""
        if not title:
            end = TITLE_END.search(head)
            title = head[:end.start()] if end else head
        title = title.strip(" ,.;:")
        if not (2 <= len(title) <= 160) or not re.search(r"[A-Za-z]{2}", title):
            continue
        by = BY.search(head)
        entry_author = by.group(1).strip(" ,.") if by else ("" if tfirst else author)
        claim = re.sub(r"\s*\([A-Za-z&]{1,4}[^)]{0,40}\)?\s*$", "", claim.strip(" .;,"))
        m = RADIO.search(b) or (RADIO.search(author) if author and not tfirst else None) or \
            (RADIO_SERIES.search(re.sub(r"^In\s+", "", series)) if series else None)
        regs = []
        for p in pairs:
            od, oy = _date(*p.groups()[1:4])
            if not od or not (1909 <= oy <= 1950) or not (26 <= ryear - oy <= 29):
                continue
            for reg in _expand(p.group(5).replace(" ", "")):
                regs.append((p.group(1), od, oy, reg))
        for k, (ep, od, oy, reg) in enumerate(regs):
            r = "R" + (rnums[k] if len(rnums) == len(regs) else rnums[0])
            rows.append({
                "title": title, "episode": (ep or "").strip(" .,") or None, "series": series or None,
                "author": entry_author, "claimant": claim.strip(" .;,")[:160],
                "reg": reg, "reg_class": "C" if reg.startswith("C") else "D",
                "orig_date": od, "orig_year": oy,
                "r": r, "r_printed": None, "r_range": f"R{rnums[0]}-R{rnums[-1]}" if len(rnums) > 1 else None,
                "r_date": rdate, "r_year": ryear,
                "vol": vol, "vol_year": vol_year, "line": line, "text": b[:500],
                "radio": bool(m), "radio_why": m.group(0) if m else None,
                "src": f"https://archive.org/details/{vol}?q={r}",
            })
    # Renewal numbers rise through a year, so one far from the volume's median
    # lost or changed a digit in the OCR ("R14627" in 1955, where they run
    # R14xxxx-R16xxxx). The entry is still a renewal, so the row is kept with
    # its number unread rather than guessed, and `src` searches the scan for
    # the original registration instead.
    nums = sorted(int(x["r"][1:]) for x in rows)
    if nums:
        med = nums[len(nums) // 2]
        for x in rows:
            if not 0.75 * med <= int(x["r"][1:]) <= 1.35 * med:
                x["r_printed"], x["r"], x["r_range"] = x["r"], None, None
                x["src"] = f"https://archive.org/details/{x['vol']}?q={x['reg']}"
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--offline", action="store_true", help="parse the cached OCR only")
    a = ap.parse_args()
    if a.only:
        vols = [(a.only, 0, "")]
    else:
        vols = volumes()
        for ident, y, t in vols:
            print(f"  {y} {ident} | {t}")
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
        new = [g for g in got if (g["r"] or g["r_printed"], g["reg"]) not in seen]
        seen |= {(g["r"] or g["r_printed"], g["reg"]) for g in new}
        rows += new
        per.append((y, ident, len(new)))
        print(f"[cce-drama] {y} {ident}: {len(new)} renewals, {sum(g['radio'] for g in new)} radio", flush=True)
    if a.only:
        for g in rows[:25]:
            print("  ", {k: g[k] for k in ("title", "episode", "series", "author", "reg", "orig_date", "r", "r_date", "radio")})
        return 0
    if not rows:
        print("[cce-drama] parsed nothing", file=sys.stderr)
        return 1
    L.write_json(OUT, rows, gz=True)
    print(f"[cce-drama] wrote {len(rows)} renewals ({sum(g['radio'] for g in rows)} radio, "
          f"{sum(g['r'] is None for g in rows)} with the renewal number unread, "
          f"{sum(g['reg_class'] == 'C' for g in rows)} Class C) from {sum(1 for v in per if v[2])} of "
          f"{len(per)} volumes -> {os.path.relpath(OUT, L.ROOT)}; unread: {failed or 'none'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
