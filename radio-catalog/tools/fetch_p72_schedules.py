"""Download the Copyright Office's pre-1972 sound-recording schedules in full
(§1401(f)(5): an owner who filed one may claim statutory damages; one who did
not may not). 299,447 entries measured 2026-10-17. Matching happens locally in
the rights audit; this tool only mirrors the index.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

PROXY = "https://www.copyright.gov/music-modernization/pre1972-soundrecordings/proxy.php"
KEEP = ("title", "alt_title", "artist", "alt_artist", "rights_owner", "album", "label", "pub_date", "index_date", "isrc")
ROWS = 5000


def page(start):
    body = urllib.parse.urlencode({"query": f"q=*:*&rows={ROWS}&start={start}&wt=json&sort=id asc"}).encode()
    for attempt in range(6):
        try:
            req = urllib.request.Request(PROXY, data=body, headers={"User-Agent": "Mozilla/5.0 " + ia.UA})
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read().decode("utf-8", "replace"))
        except Exception as e:
            print(f"retry {attempt} start={start}: {e}", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    return None


def flat(v):
    if isinstance(v, list):
        v = " | ".join(x for x in v if x and x.strip())
    return (v or "").strip() or None


def main():
    rows, start, total = [], 0, None
    while total is None or start < total:
        d = page(start)
        if d is None:
            raise SystemExit(f"schedules read failed at {start}")
        total = d["response"]["numFound"]
        for doc in d["response"]["docs"]:
            rows.append({k: flat(doc.get(k)) for k in KEEP})
        start += ROWS
        print(f"{len(rows)}/{total}", file=sys.stderr, flush=True)
        time.sleep(2)
    if len(rows) < total * 0.99:
        raise SystemExit(f"schedules incomplete: {len(rows)} of {total}")
    ia.write_json(os.path.join(ia.CACHE, "p72_schedules.json.gz"), {"numFound": total, "rows": rows}, gz=True)


if __name__ == "__main__":
    main()
