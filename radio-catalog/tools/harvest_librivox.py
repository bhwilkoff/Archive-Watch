"""Harvest LibriVox's dramatic works (genres "Plays", "Dramatic Readings",
"Drama"; measured 640 distinct projects 2026-10-17) with their sections.

LibriVox: "all our recordings are public domain" — the clean tier. Audio is on
archive.org (`listen_url`). The API caps `limit` at 500; Python's default
User-Agent gets 403, so ia_lib's UA is sent.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

API = "https://librivox.org/api/feed/audiobooks"
GENRES = ["Plays", "Dramatic Readings", "^Drama"]


def main():
    books = {}
    for g in GENRES:
        off = 0
        while True:
            d = ia.get(API, {"genre": g, "format": "json", "limit": 100, "offset": off, "extended": 1},
                       ua="Mozilla/5.0 (ArchiveWatch-RadioCatalog; catalog build)", pause=2)
            if d is None:
                raise SystemExit(f"LibriVox read failed: genre {g} offset {off}")
            page = d.get("books") or []
            if isinstance(page, dict):
                page = list(page.values())
            for b in page:
                books.setdefault(b["id"], b)
            print(f"{g} offset {off}: {len(page)}", file=sys.stderr)
            if len(page) < 100:
                break
            off += 100
            time.sleep(1)
    if not books:
        raise SystemExit("LibriVox: nothing harvested")
    ia.write_json(os.path.join(ia.CACHE, "librivox.json.gz"), list(books.values()), gz=True)
    print(f"{len(books)} projects", file=sys.stderr)


if __name__ == "__main__":
    main()
