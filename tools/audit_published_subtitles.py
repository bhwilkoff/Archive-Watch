#!/usr/bin/env python3
"""Audit the subtitle tracks the app is ACTUALLY SERVING right now.

The builders were hardened on 2026-08-09 (404.html served as VTT with HTTP 200,
UTF-16/RAR payloads written as .vtt, no output validation at all), but hardening
a builder does not repair what is already published. This measures the live set
so the repair is aimed at real numbers instead of an estimate.

It samples detail shards from archivewatch.org, takes every item that advertises
a caption track, fetches the VTT the app would fetch, and classifies it:

    ok          real cues, spanning a plausible share of the runtime
    html        our SPA 404 fallback served with HTTP 200 — renders nothing
    binary      RAR/ZIP/UTF-16 mojibake published under a .vtt name
    empty       fetched fine, but no cues
    short       cues stop early enough that the track is effectively broken
    missing     a real HTTP error

Usage:
    python3 tools/audit_published_subtitles.py [--shards 16] [--out report.csv]
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import csv
import json
import re
import sys
import urllib.request
from collections import Counter

SITE = "https://archivewatch.org"
# WebVTT allows BOTH `HH:MM:SS.mmm` and `MM:SS.mmm`. Requiring hours made this
# audit report a fifth of the live set as empty when the files were fine — the
# measurement was broken, not the tracks. Hours are optional here.
TIMESTAMP = re.compile(r"(?:(\d{1,3}):)?(\d{2}):(\d{2})[.,](\d{3})\s*-->")
CUE_TEXT = re.compile(r"-->.*\n((?:.+\n?)*)")


def get(url: str, timeout: int = 30) -> tuple[int, bytes]:
    req = urllib.request.Request(url, headers={"User-Agent": "ArchiveWatch-audit/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception:
        return 0, b""


def classify(raw: bytes, runtime: int | None) -> tuple[str, str]:
    """Return (verdict, detail). The order matters: the cheap, certain
    disqualifiers run before anything that needs the text decoded."""
    if not raw:
        return "missing", "no body"
    head = raw[:8]
    if head.startswith(b"Rar!") or head.startswith(b"PK\x03\x04") or head.startswith(b"\x1f\x8b"):
        return "binary", f"archive magic {head[:4]!r}"
    if head.startswith(b"\xff\xfe") or head.startswith(b"\xfe\xff") or raw[:200].count(b"\x00") > 20:
        return "binary", "UTF-16 / NUL-heavy"
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return "binary", "not UTF-8"
    low = text[:400].lower()
    if "<!doctype html" in low or "<html" in low:
        return "html", "SPA fallback served as VTT"
    stamps = TIMESTAMP.findall(text)
    if not stamps:
        return "empty", "no cue timestamps"
    last = max(int(h or 0) * 3600 + int(m) * 60 + int(s) for h, m, s, _ in stamps)
    if len(stamps) < 5:
        return "short", f"{len(stamps)} cues"

    # Degeneracy — a track that repeats one line is present, parses, and tells
    # the viewer nothing (the "ALRIGHT ALRIGHT ALRIGHT" class, Decision 043).
    lines = [ln.strip().lower() for ln in text.splitlines()
             if ln.strip() and "-->" not in ln and not ln.strip().isdigit()
             and not ln.startswith("WEBVTT") and not ln.startswith("X-TIMESTAMP")]
    if len(lines) >= 10:
        dup = sum(1 for a, b in zip(lines, lines[1:]) if a == b)
        uniq = len(set(lines)) / len(lines)
        if dup / len(lines) > 0.25 or uniq < 0.25:
            return "repetitive", f"{uniq:.0%} unique lines"

    if runtime and runtime > 0:
        cover = last / runtime
        if cover < 0.5:
            return "short", f"{len(stamps)} cues, stops {cover:.0%} in"
    return "ok", f"{len(stamps)} cues"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--shards", type=int, default=16,
                    help="how many of the 256 detail shards to sample")
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--out", default="tools/published_subtitles_audit.csv")
    args = ap.parse_args()

    targets: list[tuple[str, str, int | None]] = []   # (id, vtt url, runtime)
    for i in range(args.shards):
        name = f"{i:02x}"
        status, body = get(f"{SITE}/details/{name}.json")
        if status != 200 or not body:
            print(f"  shard {name}: HTTP {status}", file=sys.stderr)
            continue
        try:
            shard = json.loads(body)
        except json.JSONDecodeError:
            continue
        for aid, rec in shard.items():
            # rec[5] = runtime seconds, rec[7] = captions [[lang, label, url], ...]
            if not isinstance(rec, list) or len(rec) < 8:
                continue
            caps = rec[7]
            runtime = rec[5] if isinstance(rec[5], int) else None
            if isinstance(caps, list) and caps:
                for c in caps:
                    if isinstance(c, list) and len(c) >= 3 and isinstance(c[2], str):
                        targets.append((aid, c[2], runtime))
                        break

    if not targets:
        print("no captioned items found in the sampled shards", file=sys.stderr)
        return 1

    print(f"sampled {args.shards} shards -> {len(targets)} captioned items")

    rows, tally = [], Counter()

    def probe(t):
        aid, url, runtime = t
        status, raw = get(url)
        if status != 200:
            return aid, url, "missing", f"HTTP {status}"
        verdict, detail = classify(raw, runtime)
        return aid, url, verdict, detail

    with cf.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for aid, url, verdict, detail in pool.map(probe, targets):
            tally[verdict] += 1
            rows.append({"archiveID": aid, "url": url, "verdict": verdict, "detail": detail})

    with open(args.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["archiveID", "url", "verdict", "detail"])
        w.writeheader()
        w.writerows(rows)

    total = sum(tally.values())
    print(f"\n{'verdict':<10} {'count':>6}  share")
    for v, n in tally.most_common():
        print(f"{v:<10} {n:>6}  {n / total:.1%}")
    good = tally["ok"]
    print(f"\nworking: {good}/{total} = {good / total:.1%}")
    print(f"report: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
