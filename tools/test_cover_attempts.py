#!/usr/bin/env python3
"""cover-generation never retries the same frame-grab failures blindly.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." The only failure record was a manifest on the
runner's disk, never restored, so 259 of 300 items failed `no_frame` in each of
three runs, the same head every time. Failures now live on the catalog
(`coverTried`), which the workflow's catalog_delta already carries. Runs the
real main() with the frame grab replaced.
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
try:
    import cv2  # noqa: F401
except ImportError:            # the frame grab is replaced below; it needs no OpenCV here
    import types
    sys.modules["frame_cover"] = types.ModuleType("frame_cover")
import batch_covers as BC  # noqa: E402

VERSION = getattr(BC, "COVER_VERSION", 1)
TMP = Path(tempfile.mkdtemp(prefix="cover-attempts-"))
fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


def item(aid, pop, **kw):
    return {"archiveID": aid, "popularityScore": pop, "title": aid,
            "downloadURL": f"https://archive.org/download/{aid}/{aid}.mp4", **kw}


def run(items, *extra):
    """A fresh runner each time: new out dir (no manifest), catalog carried over."""
    cat = TMP / "catalog.json"
    cat.write_text(json.dumps({"items": items}))
    out = TMP / "out"
    shutil.rmtree(out, ignore_errors=True)
    tried = []

    def fake(it, posters, *a, **k):
        tried.append(it["archiveID"])
        ok = it["archiveID"].startswith("ok")
        return {"archiveID": it["archiveID"], "status": "ok" if ok else "no_frame",
                "reason": "" if ok else "grab_failed"}
    BC.process = fake
    BC.needs_cover = lambda it: not it.get("hasRealArtwork")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            sys.argv = ["batch_covers.py", "--catalog", str(cat), "--out", str(out), "--workers", "1", *extra]
            BC.main()
        except Exception as e:
            print(f"CRASH {type(e).__name__}: {e}")
    return sorted(tried), buf.getvalue(), json.loads(cat.read_text())["items"]


def ago(d):
    return (datetime.now(timezone.utc) - timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%SZ")


def rec(n, d, v=VERSION):
    return {"outcome": "no_frame", "reason": "grab_failed", "attempts": n, "at": ago(d), "v": v}


tried, out, items = run([item("bad1", 9), item("ok1", 8)])
r = {i["archiveID"]: i for i in items}["bad1"].get("coverTried") or {}
check("a no_frame failure is recorded on the catalog",
      r.get("outcome") == "no_frame" and r.get("attempts") == 1 and r.get("v") == VERSION, r)
tried, out, items = run([i for i in items if i["archiveID"] == "bad1"] + [item("ok2", 1)])
check("the next run (fresh runner, no manifest) skips it", tried == ["ok2"], tried)
check("its summary counts it as skipped for backoff", "1 skipped (backoff)" in out, out[-300:])

tried, out, _ = run([item("a", 9, coverTried=rec(1, 2)), item("b", 8, coverTried=rec(2, 2)),
                     item("c", 7, coverTried=rec(3, 20)), item("d", 6, coverTried=rec(4, 400))])
check("backoff grows: 1 day, then 7, then 30", tried == ["a"], tried)
check("a capped item is reported, not retried", "1 capped" in out and "d" not in tried, out[-300:])

tried, out, items = run([item("ok3", 9, coverTried=rec(4, 1, v=VERSION - 1))])
check("a version bump re-opens a capped failure", tried == ["ok3"], tried)
check("a success clears the failure record", "coverTried" not in items[0], items[0])

shutil.rmtree(TMP, ignore_errors=True)
print("ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
