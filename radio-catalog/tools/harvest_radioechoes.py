"""Crawl RadioEchoes' series list and each series page: the episode spine
(owner, 2026-10-17: "Can we use radioechoes as the spine and archive.org as
the content source?" — yes; docs/research/radio/03 addendum).

robots.txt: Disallow nothing public, Crawl-delay 10 — honored. Resumable: a
series page already cached is not fetched again. Facts only (Feist); RadioEchoes
audio (its own S3) is never played.
"""
import html
import os
import re
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

BASE = "https://www.radioechoes.com/"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 ArchiveWatch-RadioCatalog"
DELAY = 10
SERIES_LINK = re.compile(r'href="\?page=series&genre=([^&"]+)&series=([^"]+)"')
EP = re.compile(r'mode=play&dl_mp3folder=([^&]*)&dl_file=([^&"]+)&dl_series=([^&"]*)&dl_title=([^&"]*)&dl_date=([^&"]*)&dl_size=([^&"]*)"')
LEN = re.compile(r"Length:\s*([0-9:]+)")


def fetch(params):
    body = ia.get(BASE, params, ua=UA, raw=True, timeout=120)
    time.sleep(DELAY)
    return None if body is None else body.decode("utf-8", "replace")


def parse_series_page(page):
    eps = []
    chunks = page.split("mode=play&")
    for c in chunks[1:]:
        m = EP.search("mode=play&" + c)
        if not m:
            continue
        folder, f, ser, title, date, size = (html.unescape(urllib.parse.unquote(x)) for x in m.groups())
        lm = LEN.search(c)
        eps.append({"file": f, "series": ser, "title": title, "date": date, "size": size,
                    "length": lm.group(1) if lm else None})
    return eps


def main():
    out = os.path.join(ia.CACHE, "radioechoes")
    os.makedirs(os.path.join(out, "series"), exist_ok=True)
    idx = os.path.join(out, "series_all.json")
    if os.path.exists(idx):
        series = ia.read_json(idx)
    else:
        page = fetch({"page": "series_all"})
        if not page:
            raise SystemExit("series_all unreadable")
        series = [{"genre": html.unescape(g), "series": html.unescape(s)} for g, s in SERIES_LINK.findall(page)]
        if len(series) < 4000:
            raise SystemExit(f"series_all parsed only {len(series)} series")
        ia.write_json(idx, series)
    failed = []
    for i, s in enumerate(series):
        key = re.sub(r"[^A-Za-z0-9]+", "_", s["series"]).strip("_")[:120] + "__" + str(i)
        path = os.path.join(out, "series", key + ".json")
        if os.path.exists(path):
            continue
        page = fetch({"page": "series", "genre": s["genre"], "series": s["series"]})
        if page is None:
            failed.append(s["series"])
            continue
        ia.write_json(path, dict(s, episodes=parse_series_page(page)))
        if i % 100 == 0:
            print(f"{i}/{len(series)}", file=sys.stderr, flush=True)
    ia.write_json(os.path.join(out, "failed.json"), failed)
    print(f"done; failed {len(failed)}", file=sys.stderr)


if __name__ == "__main__":
    main()
