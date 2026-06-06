#!/usr/bin/env python3
"""
covers_status.py — one dashboard for the whole cover pipeline (#86).

Reports every stage: GENERATE (batch_covers), PUBLISH (upload/drain), and what's
left to WIRE — plus background-process health, throughput, and ETA. Read-only;
safe to run anytime, including while the pipeline is going.

Usage:
    python tools/covers_status.py            # one snapshot
    python tools/covers_status.py --watch 15 # refresh every 15s
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TOOLS = Path(__file__).resolve().parent
OUT = TOOLS / "covers_out"
CATALOG = REPO / "catalog.json"
TARGET_CACHE = OUT / "target.json"

C = {"g": "\033[32m", "r": "\033[31m", "y": "\033[33m", "c": "\033[36m",
     "b": "\033[1m", "d": "\033[2m", "x": "\033[0m"}

# Disable ANSI when piped to a file/log, when NO_COLOR is set, or --plain is passed.
if ("--plain" in sys.argv) or ("NO_COLOR" in __import__("os").environ) or (not sys.stdout.isatty()):
    C = {k: "" for k in C}


def col(s, k):
    return f"{C[k]}{s}{C['x']}"


def alive(pat: str) -> str:
    r = subprocess.run(["pgrep", "-f", pat], capture_output=True, text=True)
    pids = r.stdout.split()
    return col(f"running (pid {pids[0]})", "g") if pids else col("stopped", "r")


def needs_cover(it: dict) -> bool:
    if it.get("hasRealArtwork") is True:
        return False
    src = it.get("artworkSource")
    if it.get("posterURL") and src not in (None, "", "archive", "none", "generated"):
        return False
    return True


def load_target() -> dict:
    """Total missing-art items (+ per-type), cached so --watch doesn't reload 89 MB."""
    if TARGET_CACHE.exists():
        try:
            return json.loads(TARGET_CACHE.read_text())
        except json.JSONDecodeError:
            pass
    if not CATALOG.exists():
        return {"total": 0, "byType": {}}
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    miss = [it for it in items if needs_cover(it)]
    bt: dict = {}
    for it in miss:
        bt[it.get("contentType") or "?"] = bt.get(it.get("contentType") or "?", 0) + 1
    data = {"total": len(miss), "byType": bt, "catalog": len(items)}
    OUT.mkdir(parents=True, exist_ok=True)
    TARGET_CACHE.write_text(json.dumps(data))
    return data


def read_manifest() -> list:
    p = OUT / "manifest.jsonl"
    if not p.exists():
        return []
    rows = []
    for line in open(p):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def read_uploaded() -> list:
    p = OUT / "uploaded.jsonl"
    if not p.exists():
        return []
    rows = []
    for line in open(p):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def parse_ts(s):
    try:
        return datetime.fromisoformat(s).timestamp()
    except (ValueError, TypeError):
        return None


def rate_eta(times: list, remaining: int):
    """items/min over the recent window + ETA, from a list of unix timestamps."""
    ts = sorted(t for t in times if t)
    if len(ts) < 2:
        return None, None
    window = ts[-200:]
    span = window[-1] - window[0]
    if span <= 0:
        return None, None
    rpm = (len(window) - 1) / span * 60.0
    eta = remaining / rpm if rpm > 0 else None
    return rpm, eta


def fmt_eta(mins):
    if mins is None:
        return "?"
    if mins < 90:
        return f"{mins:.0f}m"
    return f"{mins/60:.1f}h"


def bar(done, total, width=32):
    if total <= 0:
        return "-" * width
    f = max(0.0, min(1.0, done / total))
    n = int(f * width)
    return "[" + "#" * n + "-" * (width - n) + f"] {f*100:5.1f}%"


def snapshot():
    tgt = load_target()
    total = tgt["total"]
    man = read_manifest()
    up = read_uploaded()

    ok = [r for r in man if r.get("status") == "ok"]
    nf = [r for r in man if r.get("status") in ("no_frame", "no_score")]
    err = [r for r in man if r.get("status") == "error"]
    attempts = len(man)

    out = []
    out.append(col("ARCHIVE WATCH — COVER PIPELINE", "b") +
               col(f"   {datetime.now().strftime('%H:%M:%S')}", "d"))
    out.append(col(f"catalog {tgt.get('catalog','?')} items  |  missing real art {total:,}", "d"))
    out.append("")

    # processes
    out.append(col("processes", "b"))
    out.append(f"  generator  : {alive('batch_covers.py')}")
    out.append(f"  drain/upload: {alive('drain_covers.sh')}")
    out.append(f"  caffeinate : {alive('caffeinate -i')}")
    out.append("")

    # generate
    g_times = [parse_ts(r.get("generatedAt")) for r in ok]
    rpm, eta = rate_eta(g_times, total - len(ok))
    out.append(col("1. GENERATE", "b") + col("  (grab + on-device Vision pick)", "d"))
    out.append("  " + bar(len(ok), total))
    out.append(f"  ok {col(len(ok),'g')}  no_frame {col(len(nf),'y')}  error {col(len(err),'r')}"
               f"  of {attempts} attempts  ({len(ok)}/{total:,})")
    if rpm:
        out.append(f"  rate {rpm:.1f}/min   eta {fmt_eta(eta)}")
    # scorer + aesthetics
    scorers: dict = {}
    aesth = []
    for r in ok:
        scorers[r.get("scorer") or "?"] = scorers.get(r.get("scorer") or "?", 0) + 1
        if isinstance(r.get("aesthetics"), (int, float)):
            aesth.append(r["aesthetics"])
    sline = " ".join(f"{k}={v}" for k, v in scorers.items())
    amean = f"{sum(aesth)/len(aesth):+.2f}" if aesth else "n/a"
    nf_rate = f"{100*len(nf)/attempts:.0f}%" if attempts else "0%"
    out.append(col(f"  scorer: {sline}   mean aesthetics {amean}   no_frame rate {nf_rate}", "d"))
    out.append("")

    # publish
    u_times = [r.get("at") for r in up]
    urpm, ueta = rate_eta([t for t in u_times if t], len(ok) - len(up))
    out.append(col("2. PUBLISH", "b") + col("  (upload to archive.org item 'archivewatch-covers')", "d"))
    out.append("  " + bar(len(up), len(ok) if ok else 1))
    out.append(f"  uploaded {col(len(up),'g')} / {len(ok)} generated"
               + (f"   rate {urpm:.0f}/min   eta {fmt_eta(ueta)}" if urpm else ""))
    out.append("")

    # wire
    out.append(col("3. WIRE", "b") + col("  (apply_covers -> catalog posterURL)", "d"))
    out.append(f"  {col(len(up),'c')} covers hosted + ready to wire into the catalog")
    out.append(col("  run after generation/upload settle:", "d"))
    out.append(col("    catalog_release.py fetch -> apply_covers.py -> "
                   "catalog_release.py publish -> publish-db", "d"))
    out.append("")

    # per-type generated vs target
    gt: dict = {}
    for r in ok:
        gt[r.get("contentType") or "?"] = gt.get(r.get("contentType") or "?", 0) + 1
    out.append(col("by content type (generated / missing)", "b"))
    for t, n in sorted(tgt["byType"].items(), key=lambda kv: -kv[1]):
        out.append(f"  {t:14} {gt.get(t,0):>6,} / {n:>6,}  {bar(gt.get(t,0), n, 20)}")

    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--watch", type=int, default=0, help="refresh every N seconds")
    ap.add_argument("--plain", action="store_true", help="no ANSI color (for logs)")
    args = ap.parse_args()
    if not args.watch:
        print(snapshot())
        return 0
    try:
        while True:
            sys.stdout.write("\033[2J\033[H")
            print(snapshot())
            print(col(f"\n  refreshing every {args.watch}s — Ctrl-C to stop", "d"))
            time.sleep(args.watch)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
