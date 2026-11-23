#!/usr/bin/env python3
"""color-classify never retries the same unreadable items blindly.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." Each run took the top 1,200 unclassified items,
~1,195 came back unreadable, nothing recorded it, and the next run took the same
1,200 again.

Cases run the real compute -> deltas -> apply path, with ffmpeg replaced:
  * an unreadable item is recorded on the catalog (outcome, reason, attempts, time, version)
  * the next run skips it and counts it as skipped-for-backoff, so --limit reaches NEW items
  * backoff grows 1 -> 7 -> 30 days, then caps and is reported
  * a version bump re-opens a capped failure once
  * a success clears the failure record
"""
import contextlib
import io
import json
import shutil
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import classify_color as C  # noqa: E402

VERSION = getattr(C, "COLOR_CLASSIFY_VERSION", 1)
OLD = not hasattr(C, "COLOR_CLASSIFY_VERSION")   # the pre-ledger classify() returned a pair
TMP = Path(tempfile.mkdtemp(prefix="color-attempts-"))
fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


def item(aid, pop, **kw):
    return {"archiveID": aid, "popularityScore": pop,
            "downloadURL": f"https://archive.org/download/{aid}/{aid}.mp4", **kw}


READABLE = {"alive": ("bw", 0.4), "fixed": ("color", 18.0)}


def run(items, *extra):
    """compute (deltas) then apply, as the workflow does; returns (probed ids, stdout, catalog)."""
    cat = TMP / "catalog.json"
    cat.write_text(json.dumps({"items": items}))
    C.CATALOG = cat
    probed = []

    def fake(it, threshold, frame_timeout=90):
        probed.append(it["archiveID"])
        got = READABLE.get(it["archiveID"])
        if got:
            return got if OLD else (*got, "")
        return (None, None) if OLD else (None, None, "HTTP error 403 Forbidden")
    C.classify = fake
    deltas = TMP / "deltas.jsonl"
    deltas.unlink(missing_ok=True)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            sys.argv = ["classify_color.py", "--limit", "2", "--deltas-out", str(deltas), *extra]
            C.main()
            sys.argv = ["classify_color.py", "--apply-deltas", str(deltas)]
            C.main()
        except Exception as e:
            print(f"CRASH {type(e).__name__}: {e}")
    return sorted(probed), buf.getvalue(), json.loads(cat.read_text())["items"]


def ago(days):
    return (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")


def tried(n, days, v=VERSION):
    return {"outcome": "unreadable", "reason": "403", "attempts": n, "at": ago(days), "v": v}


# 1. an unreadable item is recorded; the next run moves past it
items = [item("dead1", 9), item("dead2", 8), item("alive", 7)]
probed, out, items = run(items)
by = {i["archiveID"]: i for i in items}
rec = by["dead1"].get("colorTried") or {}
check("an unreadable item is recorded on the catalog",
      rec.get("outcome") == "unreadable" and rec.get("attempts") == 1 and rec.get("v") == VERSION
      and rec.get("at") and "403" in rec.get("reason", ""), rec)
probed, out, items = run(items)
check("the next run skips last run's failures and reaches a new item", probed == ["alive"], probed)
check("its summary counts them as skipped for backoff", "2 skipped (backoff)" in out, out.strip()[-300:])
check("a classified item carries no failure record",
      "colorTried" not in {i["archiveID"]: i for i in items}["alive"], items)

# 2. backoff grows, then caps
items = [item("a", 9, colorTried=tried(1, 2)),    # 1-day wait over -> probe
         item("b", 8, colorTried=tried(2, 2)),    # 7-day wait -> skip
         item("c", 7, colorTried=tried(3, 20)),   # 30-day wait -> skip
         item("d", 6, colorTried=tried(4, 400))]  # capped -> reported
probed, out, items = run(items, "--limit", "10")
check("backoff grows: 1 day, then 7, then 30", probed == ["a"], probed)
check("a capped item is reported, not retried", "1 capped" in out and "d" not in probed, out.strip()[-300:])
check("a retried failure counts up",
      ({i["archiveID"]: i for i in items}["a"].get("colorTried") or {}).get("attempts") == 2, items[0])

# 3. a version bump re-opens a capped failure once; a success clears it
items = [item("fixed", 9, colorTried=tried(4, 1, v=VERSION - 1))]
probed, out, items = run(items)
check("a version bump re-opens a capped failure", probed == ["fixed"], probed)
check("its success replaces the failure with the reading",
      items[0].get("colorMode") == "color" and "colorTried" not in items[0], items[0])

shutil.rmtree(TMP, ignore_errors=True)
print(f"{'ok' if not fails else f'{fails} failed'}")
sys.exit(1 if fails else 0)
