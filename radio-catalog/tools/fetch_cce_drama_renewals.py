#!/usr/bin/env python3
"""PLACEHOLDER: fetch stage only (rewritten below once the formats are read)."""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_lib as L

RAW = os.path.join(L.CACHE, "cce_drama")
QUERIES = [
    'title:("catalog of copyright entries") AND title:(dramas)',
    'title:("catalog of copyright entries") AND title:("oral delivery")',
]


def volumes():
    found = {}
    for q in QUERIES:
        d = L.get(L.ADV, {"q": q, "fl[]": ["identifier", "year", "title"], "rows": 500, "output": "json"})
        if d is None:
            raise RuntimeError(f"advancedsearch failed: {q}")
        for x in d["response"]["docs"]:
            t = x.get("title") or ""
            if "oral delivery" not in t.lower():
                continue
            try:
                y = int(str(x.get("year"))[:4])
            except ValueError:
                continue
            found[x["identifier"]] = (y, t)
    return sorted(((i, y, t) for i, (y, t) in found.items()), key=lambda v: v[1])


def fetch(ident):
    path = os.path.join(RAW, ident + "_djvu.txt")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path, False
    meta = L.get(L.META + ident + "/files")
    names = [f["name"] for f in (meta or {}).get("result", []) if f["name"].endswith("_djvu.txt")]
    if not names:
        return None, True
    raw = L.get("https://archive.org/download/" + ident + "/" + names[0], raw=True, timeout=300)
    if not raw:
        return None, True
    os.makedirs(RAW, exist_ok=True)
    with open(path + ".tmp", "wb") as f:
        f.write(raw)
    os.replace(path + ".tmp", path)
    time.sleep(3)
    return path, True


if __name__ == "__main__":
    for ident, y, t in volumes():
        p, fetched = fetch(ident)
        print(y, ident, "FAILED" if not p else ("fetched" if fetched else "cached"), flush=True)
