"""Harvest the Generic Radio Workshop script library (genericradio.com):
206 series, 1,374 scripts (its own count, 2026-10-17), each a broadcast script
with series, title and air date, plus a downloadable text file.

GRW states the scripts "remain, as they should, the copyright of their
respective owners" and advises "Assume Copyright". So the text is cached for
SEARCH and matching only; a client links to the GRW page (which GRW hosts and
funds with ads) and never re-publishes the script. robots.txt blocks only
/eklipse/ and /common/; a 3-second delay is used anyway.
"""
import html
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

BASE = "https://www.genericradio.com"
UA = "Mozilla/5.0 (Macintosh) ArchiveWatch-RadioCatalog (catalog build; links back to every script)"
DELAY = 3
SERIES = re.compile(r"<a href=series/([A-Za-z0-9_-]+)>([^<]+)")
ROW = re.compile(r"<tr><td>([^<]*)</td><td><a href='/show/([0-9A-Za-z]+)'>([^<]*)</a>")
MONTHS = {m: i for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}


def fetch(path):
    body = ia.get(BASE + path, ua=UA, raw=True, timeout=90)
    time.sleep(DELAY)
    return None if body is None else body.decode("utf-8", "replace")


def iso(d):
    m = re.match(r"([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{4})", d.strip())
    if m and m.group(1) in MONTHS:
        return f"{m.group(3)}-{MONTHS[m.group(1)]:02d}-{int(m.group(2)):02d}"
    return None


def main():
    out = os.path.join(ia.CACHE, "grw")
    os.makedirs(os.path.join(out, "text"), exist_ok=True)
    lib = fetch("/library.php")
    if not lib:
        raise SystemExit("GRW library unreadable")
    series = [(slug, html.unescape(name).strip()) for slug, name in SERIES.findall(lib)]
    if len(series) < 150:
        raise SystemExit(f"GRW library parsed only {len(series)} series")
    scripts, failed = {}, []
    for slug, name in series:
        page = fetch(f"/series/{slug}")
        if page is None:
            failed.append("series:" + slug)
            continue
        for date, sid, title in ROW.findall(page):
            scripts.setdefault(sid, {"id": sid, "series": name, "series_slug": slug, "title": html.unescape(title).strip(),
                                     "date_text": date.strip(), "date": iso(date), "url": f"{BASE}/show/{sid}"})
    for sid, s in scripts.items():
        path = os.path.join(out, "text", sid + ".txt")
        if os.path.exists(path):
            continue
        body = ia.get(f"{BASE}/files/generic_radio_workshop_radio_script_{sid}.txt", ua=UA, raw=True, timeout=90)
        time.sleep(DELAY)
        if body is None:
            # Some scripts have no text download (404 on ~20%, 2026-10-17); the
            # show page carries the same script in its scriptbody block.
            page = fetch(f"/show/{sid}")
            m = re.search(r"class=.scriptbody[^>]*>(.*?)(?:<div class=.aboutblock|</body>)", page or "", re.S)
            if not m:
                failed.append("text:" + sid)
                continue
            body = m.group(1).encode("utf-8")
        with open(path, "wb") as f:
            f.write(body)
    ia.write_json(os.path.join(out, "scripts.json"), {"series": len(series), "scripts": list(scripts.values()),
                                                       "failed": failed})
    print(f"{len(series)} series, {len(scripts)} scripts, {len(failed)} failed", file=sys.stderr)
    if not scripts:
        sys.exit(1)


if __name__ == "__main__":
    main()
