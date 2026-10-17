"""Shared HTTP for the radio catalog pipeline: one polite client, one cache.

A fetch that fails returns None and is recorded by the caller as a failure;
"could not read" is never written as "nothing there" (ENGINEERING-PROCESS §1).
"""
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "ArchiveWatch-RadioCatalog/0.1 (https://archivewatch.org; catalog build, read-only)"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache")
OUT = os.path.join(ROOT, "out")
EDITORIAL = os.path.join(ROOT, "editorial")

ADV = "https://archive.org/advancedsearch.php"
SCRAPE = "https://archive.org/services/search/v1/scrape"
META = "https://archive.org/metadata/"


def get(url, params=None, *, ua=UA, tries=6, pause=0.0, raw=False, timeout=90):
    if params:
        url = url + ("&" if "?" in url else "?") + urllib.parse.urlencode(params, doseq=True)
    delay = 2.0
    for attempt in range(tries):
        req = urllib.request.Request(url, headers={"User-Agent": ua})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read()
            if pause:
                time.sleep(pause)
            return body if raw else json.loads(body)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504):
                time.sleep(delay)
                delay *= 2
                continue
            print(f"HTTP {e.code} {url}", file=sys.stderr)
            return None
        except (urllib.error.URLError, TimeoutError, ConnectionError, json.JSONDecodeError) as e:
            print(f"retry {attempt}: {e} {url}", file=sys.stderr)
            time.sleep(delay)
            delay *= 2
    return None


def num_found(q):
    d = get(ADV, {"q": q, "rows": 0, "output": "json"})
    return None if d is None else d["response"]["numFound"]


def scrape(q, fields, count=5000):
    """Yield every hit; raise if a page could not be read (a partial list is not a list)."""
    cursor = None
    while True:
        p = {"q": q, "fields": fields, "count": count}
        if cursor:
            p["cursor"] = cursor
        d = get(SCRAPE, p)
        if d is None:
            raise RuntimeError(f"scrape failed mid-query: {q}")
        yield from d.get("items", [])
        cursor = d.get("cursor")
        if not cursor:
            return


def write_json(path, obj, gz=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    op = gzip.open if gz else open
    with op(tmp, "wt", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def read_json(path):
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt", encoding="utf-8") as f:
        return json.load(f)
