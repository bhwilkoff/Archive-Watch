#!/usr/bin/env python3
"""build_subtitle_index.py — the full-corpus subtitle CUE index for Text→Supercut (#9, Decision 042).

Parses every captioned film's WebVTT (the catalog's `captions[].vttURL`) into `subtitle.sqlite`
(a `cues` table — the SAME schema `SubtitleIndex.swift` queries), so the macOS supercut searches
spoken lines across the WHOLE catalog instead of the on-device popular-films sample. Published like
clips.sqlite; the app downloads + inflates it (StockIndex pattern), falling back to the sample.

Word-level isolation (SpeechTranscriber timing validated against the caption text, Rule 6b) is the
separate refinement — this is the line-level corpus index.

  python3 tools/build_subtitle_index.py --limit 4000
"""
from __future__ import annotations
import argparse
import json
import re
import sqlite3
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"


def parse_vtt(text: str) -> list[tuple[float, float, str]]:
    """(start, end, text) cues from WebVTT/SRT."""
    out: list[tuple[float, float, str]] = []
    for block in text.replace("\r\n", "\n").split("\n\n"):
        lines = [l for l in block.split("\n") if l.strip()]
        ti = next((i for i, l in enumerate(lines) if "-->" in l), None)
        if ti is None:
            continue
        a, _, b = lines[ti].partition("-->")
        sa, sb = _sec(a), _sec(b)
        if sa is None or sb is None or sb <= sa:
            continue
        body = re.sub(r"<[^>]+>", "", " ".join(lines[ti + 1:])).strip()
        if body:
            out.append((sa, sb, body))
    return out


def _sec(s: str):
    t = s.strip().split(" ")[0].replace(",", ".")
    p = t.split(":")
    try:
        p = [float(x) for x in p]
    except ValueError:
        return None
    if len(p) == 3:
        return p[0] * 3600 + p[1] * 60 + p[2]
    if len(p) == 2:
        return p[0] * 60 + p[1]
    return None


def fetch(url: str) -> str | None:
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return r.read().decode("utf-8", "ignore")
    except Exception:
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=4000, help="captioned films to add this run")
    ap.add_argument("--out", default=str(REPO / "subtitle.sqlite"))
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text())
    items = [it for it in cat["items"]
             if it.get("downloadURL") and not it.get("excluded")
             and any((c.get("vttURL") for c in (it.get("captions") or [])))]
    items.sort(key=lambda it: it.get("popularityScore") or it.get("downloads") or 0, reverse=True)

    db = sqlite3.connect(args.out)
    db.execute("""CREATE TABLE IF NOT EXISTS cues(
        id TEXT PRIMARY KEY, archiveID TEXT, sourceURL TEXT,
        startSeconds REAL, endSeconds REAL, text TEXT, title TEXT)""")
    seen = {r[0] for r in db.execute("SELECT DISTINCT archiveID FROM cues")}

    done = 0
    for it in items:
        if done >= args.limit:
            break
        aid = it["archiveID"]
        if aid in seen:
            continue
        vtt_url = next((c["vttURL"] for c in it["captions"] if c.get("vttURL")), None)
        vtt = fetch(vtt_url) if vtt_url else None
        if not vtt:
            continue
        cues = parse_vtt(vtt)
        if not cues:
            continue
        url, title = it["downloadURL"], it.get("title", "")
        db.executemany("INSERT OR REPLACE INTO cues VALUES(?,?,?,?,?,?,?)",
                       [(f"{aid}#{i}", aid, url, s, e, t, title) for i, (s, e, t) in enumerate(cues)])
        db.commit()
        done += 1
        if done % 50 == 0:
            print(f"[subindex] {done} films…", flush=True)

    n = db.execute("SELECT count(*) FROM cues").fetchone()[0]
    print(f"[subindex] +{done} films this run; {n} cues total in {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
