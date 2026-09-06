#!/usr/bin/env python3
"""
test_feed.py — locks the programme feed's contract.

A feed's failure mode is quiet and permanent: a reader that has already seen
an entry never re-reads it, so an unstable id or a bad date is not something
you can fix later for the people it already reached.
Run:  python tools/test_feed.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import build_feed as F  # noqa: E402

NS = {"a": "http://www.w3.org/2005/Atom"}
CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


LEDGER = {"posts": [
    # One film, three platforms, one day — must collapse to ONE entry.
    {"at": "2026-09-07T16:11:02+00:00", "id": "suddenly", "title": "Suddenly",
     "slot": "now-showing", "platform": "facebook", "url": "https://fb/1"},
    {"at": "2026-09-07T16:10:04+00:00", "id": "suddenly", "title": "Suddenly",
     "slot": "now-showing", "platform": "bluesky", "url": "https://bsky/1"},
    {"at": "2026-09-07T16:10:31+00:00", "id": "suddenly", "title": "Suddenly",
     "slot": "now-showing", "platform": "mastodon", "url": "https://m/1"},
    {"at": "2026-09-08T16:10:09+00:00", "id": "series:dark-shadows-1966",
     "title": "Dark Shadows", "slot": "now-showing", "platform": "bluesky",
     "url": "https://bsky/2"},
    # A malformed row must not take the feed down.
    {"at": "not-a-date", "id": "broken", "title": "Broken", "platform": "x",
     "url": "https://x/1"},
    {"at": "2026-09-09T16:00:00+00:00", "platform": "x", "url": "https://x/2"},
]}


def build(out: Path, ledger: dict) -> tuple[str, dict]:
    out.mkdir(parents=True, exist_ok=True)
    lp = out / "ledger.json"
    lp.write_text(json.dumps(ledger), encoding="utf-8")
    r = subprocess.run(
        [sys.executable, str(REPO / "tools" / "build_feed.py"),
         "--out", str(out / "site"), "--ledger", str(lp),
         "--index", str(REPO / "catalog-index.json"),
         "--details", str(REPO / "details")],
        capture_output=True, text=True)
    check("build succeeds", r.returncode, 0)
    return ((out / "site" / "feed.xml").read_text(encoding="utf-8"),
            json.loads((out / "site" / "feed.json").read_text(encoding="utf-8")))


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)

        # An EMPTY ledger is the state the feed ships in, so it must still be
        # a valid document rather than a stub or a crash.
        xml, js = build(td / "empty", {"posts": []})
        ET.fromstring(xml)
        check("empty feed is valid Atom",
              len(ET.fromstring(xml).findall("a:entry", NS)), 0)
        check("empty feed is valid JSON Feed", len(js["items"]), 0)

        xml, js = build(td / "full", LEDGER)
        root = ET.fromstring(xml)          # raises if not well-formed
        entries = root.findall("a:entry", NS)

        # Six rows in, two entries out. One film on three platforms is ONE
        # entry (the thing a reader unsubscribes over if it is wrong), and the
        # two malformed rows are DROPPED rather than dated with "now" — a
        # guessed date takes the newest slot in every reader and stays there.
        check("one entry per film, not per platform", len(entries), 2)
        check("JSON Feed agrees with Atom", len(js["items"]), 2)
        check("a row with an unreadable date is dropped",
              any("Broken" in (e.find("a:title", NS).text or "") for e in entries),
              False)
        check("a row with no film id is dropped",
              all(e.find("a:link", NS).get("href") for e in entries), True)

        titles = [e.find("a:title", NS).text for e in entries]
        check("newest first", titles[0].startswith("Dark Shadows"), True)

        ids = [e.find("a:id", NS).text for e in entries]
        check("ids are unique", len(set(ids)), len(ids))
        # A film may legitimately be featured again years later, so the id
        # carries the DATE — the share URL alone would collapse the two.
        for e in entries:
            eid = e.find("a:id", NS).text
            day = e.find("a:published", NS).text[:10]
            check(f"id carries its own date ({day})", day in eid, True)

        links = [e.find("a:link", NS).get("href") for e in entries]
        # A series lives at a different path. /item/series:slug is a 404.
        check("a series links to /series/, not /item/series:",
              any(l.endswith("/series/dark-shadows-1966") for l in links), True)
        check("no link keeps the series: prefix",
              any("series%3A" in l or "/item/series:" in l for l in links), False)

        sud = [e for e in entries if e.find("a:title", NS).text.startswith("Suddenly")][0]
        # The published date is when the PROGRAMME ran, so the earliest stamp
        # of the day wins — not whenever the slowest platform finished.
        check("published is the earliest stamp of the day",
              sud.find("a:published", NS).text, "2026-09-07T16:10:04Z")
        content = sud.find("a:content", NS).text
        check("content names the other platforms", "bluesky" in content, True)
        check("content links to the film",
              "https://archivewatch.org/item/suddenly" in content, True)

        # A malformed date must not emit an invalid one: readers either reject
        # the document or silently sort the entry to 1970.
        for e in entries:
            stamp = e.find("a:updated", NS).text
            check(f"date {stamp!r} is RFC3339",
                  stamp.endswith("Z") and len(stamp) >= 20, True)
        # Nothing may carry today's date: every surviving row is from 2026-09-07
        # or -08, so a "now" fallback firing anywhere would show up here.
        today = __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc).strftime("%Y-%m-%d")
        check("no entry was stamped with today (no guessed dates)",
              any(e.find("a:published", NS).text.startswith(today) for e in entries),
              False)

    bad = [c for c in CASES if not c[1]]
    for name, ok, got, want in CASES:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}"
              + ("" if ok else f"\n        got {got!r}, want {want!r}"))
    print(f"\n{len(CASES) - len(bad)}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
