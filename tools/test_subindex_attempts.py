#!/usr/bin/env python3
"""subtitle-index never re-fetches the same failed caption files blindly.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." A VTT that would not download, or held no
confident cue, returned None with nothing recorded, so every run fetched it
again before reaching new films. Runs the real main() with the fetch replaced.
"""
import contextlib
import io
import json
import shutil
import sqlite3
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_subtitle_index as S  # noqa: E402

V = getattr(S, "SUBTITLE_INDEX_VERSION", 1)
TMP = Path(tempfile.mkdtemp(prefix="subindex-attempts-"))
fails = 0
GOOD = "WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nHello there friend\n"


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


def film(aid, pop):
    return {"archiveID": aid, "popularityScore": pop, "downloadURL": f"https://x/{aid}.mp4",
            "captions": [{"vttURL": f"https://v/{aid}.vtt", "source": "opensubtitles"}]}


def run(films, db):
    cat = TMP / "catalog.json"
    cat.write_text(json.dumps({"items": films}))
    S.CATALOG = cat
    asked = []

    def fake(url):
        aid = url.rsplit("/", 1)[-1][:-4]
        asked.append(aid)
        return GOOD if aid.startswith("ok") else (None if aid.startswith("dead") else "WEBVTT\n\n")
    S.fetch = fake
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            sys.argv = ["x", "--out", str(db), "--concurrency", "1"]
            S.main()
        except Exception as e:
            print(f"CRASH {type(e).__name__}: {e}")
    return sorted(asked), buf.getvalue()


def records(db):
    con = sqlite3.connect(db)
    try:
        return {r[0]: r[1:] for r in con.execute("SELECT archiveID, outcome, reason, attempts, at, v FROM index_failures")}
    except sqlite3.OperationalError:
        return {}
    finally:
        con.close()


db = TMP / "subtitle.sqlite"
run([film("dead1", 9), film("empty1", 8), film("ok1", 7)], db)
rec = records(db)
check("an unfetchable VTT is recorded", rec.get("dead1", ("",))[0] == "unreadable" and rec["dead1"][2] == 1, rec)
check("a VTT with no confident cue is recorded", rec.get("empty1", ("",))[0] == "no_cues", rec)
asked, out = run([film("dead1", 9), film("empty1", 8), film("ok1", 7), film("ok2", 1)], db)
check("the next run skips them and reaches the new film", asked == ["ok2"], asked)
check("its summary counts them as skipped for backoff", "2 skipped (backoff)" in out, out[-300:])


def ago(d):
    return (datetime.now(timezone.utc) - timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%SZ")


db2 = TMP / "seeded.sqlite"
con = sqlite3.connect(db2)
con.execute("CREATE TABLE index_failures(archiveID TEXT PRIMARY KEY, outcome TEXT, reason TEXT, attempts INTEGER, at TEXT, v INTEGER)")
con.executemany("INSERT INTO index_failures VALUES(?,?,?,?,?,?)", [
    ("dead_a", "unreadable", "x", 1, ago(2), V), ("dead_b", "unreadable", "x", 2, ago(2), V),
    ("dead_c", "unreadable", "x", 3, ago(20), V), ("dead_d", "unreadable", "x", 4, ago(400), V),
    ("ok_e", "unreadable", "x", 4, ago(1), V - 1)])
con.commit(); con.close()
asked, out = run([film(a, 9 - i) for i, a in enumerate(["dead_a", "dead_b", "dead_c", "dead_d", "ok_e"])], db2)
check("backoff 1/7/30 days; a version bump re-opens a capped film", asked == ["dead_a", "ok_e"], asked)
check("a capped film is reported, not retried", "1 capped" in out and "dead_d" in out, out[-300:])
check("a success overwrites its failure in place (no shrink)", records(db2).get("ok_e", ("",))[0] == "ok", records(db2))

shutil.rmtree(TMP, ignore_errors=True)
print("ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
