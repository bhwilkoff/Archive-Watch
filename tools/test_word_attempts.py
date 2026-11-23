#!/usr/bin/env python3
"""word-index never re-downloads the same failing films blindly.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." A failed audio download was `continue`d with
nothing recorded, so edge-of-darkness-1943, the-proud-rebel-1958_202401 and
the-revolt-of-mamie-stover-1956 failed in every run, and double.-door.-1934
spent its 420-second cap every run of a budget that aligns 12-16 films.

Selection and recording are tested directly (the alignment itself needs torch).
"""
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_word_index as W  # noqa: E402

fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


if not hasattr(W, "select_films"):
    check("build_word_index has a ledger-aware select_films()", False, "missing")
    sys.exit(1)

V = W.WORD_INDEX_VERSION
NOW = datetime.now(timezone.utc)


def db_with(films, failures=()):
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE cues(archiveID TEXT, sourceURL TEXT, startSeconds REAL, endSeconds REAL, text TEXT)")
    for aid, n in films:
        db.executemany("INSERT INTO cues VALUES(?,?,?,?,?)", [(aid, f"u/{aid}", i, i + 1, "hi") for i in range(n)])
    W.ensure_tables(db)
    for aid, n, days, v in failures:
        rec = {"outcome": "unreadable", "reason": "Invalid argument", "attempts": n,
               "at": (NOW - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ"), "v": v}
        W.save_attempt(db, aid, rec)
    return db


# a failure recorded now is skipped next run, and the limit reaches the next film
db = db_with([("bad", 30), ("good", 20), ("next", 10)])
W.record_attempt(db, "bad", "unreadable", "Error opening output files: Invalid argument", NOW)
films, line = W.select_films(db, max_cues=1000, limit=2, now=NOW)
check("a recently failed film is skipped and the limit reaches the next", [a for a, _ in films] == ["good", "next"], films)
check("the summary counts it as skipped for backoff", "1 skipped (backoff)" in line, line)
rec = W.load_attempts(db)["bad"]
check("the failure keeps its reason, count, time and version",
      rec["attempts"] == 1 and "Invalid argument" in rec["reason"] and rec["v"] == V and rec["at"], rec)

# backoff grows, caps, and a version bump re-opens
db = db_with([("a", 50), ("b", 40), ("c", 30), ("d", 20), ("e", 10)],
             [("a", 1, 2, V), ("b", 2, 2, V), ("c", 3, 20, V), ("d", 4, 400, V), ("e", 4, 1, V - 1)])
films, line = W.select_films(db, max_cues=1000, limit=10, now=NOW)
check("backoff 1/7/30 days, and a version bump re-opens a capped film", [a for a, _ in films] == ["a", "e"], films)
check("a capped film is reported, not retried", "1 capped" in line and "d" in line, line)

# a success is recorded without shrinking the table (the publish guard refuses shrinkage)
W.record_attempt(db, "a", "ok", "aligned", NOW)
check("a success overwrites the failure in place", W.load_attempts(db)["a"]["outcome"] == "ok",
      W.load_attempts(db)["a"])

print("ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
