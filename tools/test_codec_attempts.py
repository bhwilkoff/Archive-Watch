#!/usr/bin/env python3
"""codec-audit never re-probes the same unprobeable items blindly.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." A failed ffprobe was `continue`d with nothing
written, so the same handful came back every day. Runs the real compute ->
deltas -> apply path with ffprobe replaced.
"""
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_codecs as A  # noqa: E402

NEW = hasattr(A, "CODEC_AUDIT_VERSION")
VERSION = getattr(A, "CODEC_AUDIT_VERSION", 1)
TMP = Path(tempfile.mkdtemp(prefix="codec-attempts-"))
fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


def item(aid, pop, **kw):
    return {"archiveID": aid, "popularityScore": pop, "videoFile": {"format": "MPEG4"},
            "downloadURL": f"https://archive.org/download/{aid}/{aid}.mp4", **kw}


def run(items, *extra):
    os.chdir(TMP)
    Path(A.CATALOG).write_text(json.dumps({"items": items}))
    probed = []

    def fake(url):
        aid = url.rsplit("/", 1)[-1][:-4]
        probed.append(aid)
        codec = "h264" if aid.startswith("ok") else None
        if NEW:
            return codec, ("" if codec else "HTTP error 403 Forbidden")
        return codec
    A.probe = fake
    deltas = TMP / "d.jsonl"
    deltas.unlink(missing_ok=True)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            sys.argv = ["audit_codecs.py", "--deltas-out", str(deltas), *extra]
            A.main()
            if deltas.exists():
                sys.argv = ["audit_codecs.py", "--apply-deltas", str(deltas)]
                A.main()
        except Exception as e:
            print(f"CRASH {type(e).__name__}: {e}")
    return sorted(probed), buf.getvalue(), json.loads(Path(A.CATALOG).read_text())["items"]


def ago(d):
    return (datetime.now(timezone.utc) - timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%SZ")


def tried(n, d, v=VERSION):
    return {"outcome": "unreadable", "reason": "403", "attempts": n, "at": ago(d), "v": v}


probed, out, items = run([item("bad1", 9), item("ok1", 8)])
rec = {i["archiveID"]: i for i in items}["bad1"].get("codecProbeTried") or {}
check("a failed probe is recorded on the catalog",
      rec.get("outcome") == "unreadable" and rec.get("attempts") == 1 and "403" in rec.get("reason", ""), rec)
probed, out, items = run(items + [item("ok2", 1)])
check("the next run skips it", probed == ["ok2"], probed)
check("its summary counts it as skipped for backoff", "1 skipped (backoff)" in out, out[-300:])

probed, out, _ = run([item("a", 9, codecProbeTried=tried(1, 2)), item("b", 8, codecProbeTried=tried(2, 2)),
                      item("c", 7, codecProbeTried=tried(3, 20)), item("d", 6, codecProbeTried=tried(4, 400))])
check("backoff grows: 1 day, then 7, then 30", probed == ["a"], probed)
check("a capped item is reported, not retried", "1 capped" in out and "d" not in probed, out[-300:])

probed, out, items = run([item("ok3", 9, codecProbeTried=tried(4, 1, v=VERSION - 1))])
check("a version bump re-opens a capped failure", probed == ["ok3"], probed)
check("a success clears the failure record",
      items[0].get("videoCodec") == "h264" and "codecProbeTried" not in items[0], items[0])

os.chdir("/")
shutil.rmtree(TMP, ignore_errors=True)
print("ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
