#!/usr/bin/env python3
"""stock-index never re-scans the same failures blindly, and finds real cuts in old film.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." The same ~2,354 films came back "no shots"
four times a day because nothing recorded the result, and the result itself was
wrong: scdet's threshold of 10 sat above every real cut in low-contrast
archival film (Maniac 1934's cuts score 4-9).

Cases:
  * a failed film is recorded (outcome, reason, attempts, time, version)
  * the next run skips it, and its summary counts it as skipped-for-backoff
  * backoff grows 1 -> 7 -> 30 days and caps, after which it is reported
  * a version bump re-opens a capped failure once
  * scene_cuts finds a low-contrast cut (needs ffmpeg; skipped without it)
"""
import contextlib
import io
import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_stock_index as B  # noqa: E402

VERSION = getattr(B, "STOCK_INDEX_VERSION", 1)
TMP = Path(tempfile.mkdtemp(prefix="stock-attempts-"))
fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


def film(aid, pop):
    return {"archiveID": aid, "title": aid, "downloadURL": f"https://archive.org/download/{aid}/{aid}.mp4",
            "popularityScore": pop, "runtimeSeconds": 600, "rightsStatus": "public_domain",
            "contentType": "feature-film"}


FILMS = [film("good", 9), film("blank", 8), film("dead", 7)]
RESULTS = {"good": ([3.0, 9.0, 15.0], ""),
           "blank": ([], ""),
           "dead": ([], "ffmpeg exit 183: Error opening input: Server returned 403 Forbidden")}


def run(out, seen_from=None, films=FILMS):
    """One run of the real main() with ffmpeg replaced; returns (scanned ids, stdout)."""
    cat = TMP / "catalog.json"
    cat.write_text(json.dumps({"items": films}))
    B.CATALOG = cat
    scanned = []

    def fake(url, max_seconds, fps):
        aid = url.rsplit("/", 1)[-1][:-4]
        scanned.append(aid)
        return RESULTS.get(aid, ([], ""))
    B.scene_cuts = fake
    argv = ["build_stock_index.py", "--limit", "10", "--out", str(out)]
    if seen_from:
        argv += ["--seen-from", str(seen_from)]
    sys.argv = argv
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            B.main()
        except Exception as e:                       # old code may not even run
            print(f"CRASH {type(e).__name__}: {e}")
    return sorted(scanned), buf.getvalue()


def attempts(db):
    con = sqlite3.connect(db)
    try:
        return {r[0]: r[1:] for r in con.execute(
            "SELECT archiveID, outcome, reason, attempts, at, v FROM attempts")}
    except sqlite3.OperationalError:
        return {}
    finally:
        con.close()


def seed(db, rows):
    """A published index whose attempts table holds these records."""
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE IF NOT EXISTS shots(id TEXT PRIMARY KEY, archiveID TEXT, sourceURL TEXT,"
                " startSeconds REAL, endSeconds REAL, tags TEXT, title TEXT)")
    con.execute("CREATE TABLE IF NOT EXISTS attempts(archiveID TEXT PRIMARY KEY, outcome TEXT,"
                " reason TEXT, attempts INTEGER, at TEXT, v INTEGER)")
    con.executemany("INSERT OR REPLACE INTO attempts VALUES(?,?,?,?,?,?)", rows)
    con.commit(); con.close()


def ago(days):
    return (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")


# 1. a run records every outcome
run1 = TMP / "run1.sqlite"
scanned, out = run(run1)
rec = attempts(run1)
check("first run scans all three", scanned == ["blank", "dead", "good"], scanned)
check("a no-shots film is recorded with its reason and count",
      rec.get("blank", (None,))[0] == "no_shots" and rec["blank"][2] == 1 and rec["blank"][4] == VERSION,
      rec.get("blank"))
check("a 403 film is recorded as unreadable, keeping the reason",
      rec.get("dead", (None,))[0] == "unreadable" and "403" in (rec["dead"][1] or ""), rec.get("dead"))
check("an indexed film is recorded too", rec.get("good", (None,))[0] == "indexed", rec.get("good"))

# 2. the next run (the published index restored as --seen-from) skips them
scanned, out = run(TMP / "run2.sqlite", seen_from=run1)
check("the next run re-scans NONE of last run's failures", scanned == [], scanned)
check("its summary counts them as skipped for backoff", "2 skipped (backoff)" in out, out.strip()[-400:])

# 3. backoff grows, then caps
idx = TMP / "seed3.sqlite"
FAILS = [film(f"f{i}", 5 - i * 0.1) for i in range(5)]
seed(idx, [
    ("f0", "no_shots", "", 1, ago(2), VERSION),    # 1 failure, 2 days ago: 1-day wait over -> scan
    ("f1", "no_shots", "", 2, ago(2), VERSION),    # 2 failures, 2 days ago: 7-day wait -> skip
    ("f2", "no_shots", "", 2, ago(8), VERSION),    # 2 failures, 8 days ago: wait over -> scan
    ("f3", "no_shots", "", 3, ago(20), VERSION),   # 3 failures, 20 days ago: 30-day wait -> skip
    ("f4", "no_shots", "", 4, ago(400), VERSION),  # 4 failures: capped, reported, never retried
])
scanned, out = run(TMP / "run3.sqlite", seen_from=idx, films=FAILS)
check("backoff grows: 1 day, then 7, then 30", scanned == ["f0", "f2"], scanned)
check("a capped film is reported in the summary, not retried",
      "1 capped" in out and "f4" in out and "f4" not in scanned, out.strip()[-400:])
check("summary counts backoff separately from capped", "2 skipped (backoff)" in out, out.strip()[-400:])
rec = attempts(TMP / "run3.sqlite")
check("a retried failure counts up", rec.get("f2", (0, 0, 0))[2] == 3, rec.get("f2"))

# 4. a version bump re-opens every recorded failure once
idx = TMP / "seed4.sqlite"
seed(idx, [("f4", "no_shots", "", 4, ago(1), VERSION - 1)])
scanned, out = run(TMP / "run4.sqlite", seen_from=idx, films=[FAILS[4]])
check("a version bump re-opens a capped failure", scanned == ["f4"], scanned)
rec = attempts(TMP / "run4.sqlite")
check("the count restarts under the new version", rec.get("f4", (0, 0, 0))[2] == 1, rec.get("f4"))

# 5. the detector itself: a faint cut in dim footage, like Maniac (1934)'s
import importlib  # noqa: E402
importlib.reload(B)
if shutil.which("ffmpeg"):
    clip = TMP / "faint_cut.mp4"
    # two dim grey shots, 16 levels apart (~6% of full scale) — scdet scores the
    # cut ~6, under the old threshold of 10, like every real cut Maniac had.
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", "color=c=0x303030:s=320x240:d=4:r=24",
                    "-f", "lavfi", "-i", "color=c=0x404040:s=320x240:d=4:r=24",
                    "-filter_complex", "[0][1]concat=n=2:v=1[v]", "-map", "[v]",
                    "-pix_fmt", "yuv420p", str(clip)], check=True)
    cuts, problem = B.scene_cuts(str(clip), 60, 4.0)
    check("a faint cut in dim footage is found", any(3.5 <= c <= 4.5 for c in cuts) and not problem,
          f"cuts={cuts} problem={problem!r}")
else:
    print("SKIP faint-cut detection (no ffmpeg on this machine)")

shutil.rmtree(TMP, ignore_errors=True)
print(f"{'ok' if not fails else f'{fails} failed'}")
sys.exit(1 if fails else 0)
