#!/usr/bin/env python3
"""
test_sqlite_atomic.py — a build that dies part-way leaves the last DB in place.

build_sqlite unlinked catalog.sqlite and rebuilt it where it stood, so a run
that failed part-way (or was cancelled) left a truncated DB for the next step
to compress and publish. It now builds beside it and renames into place.

Control: the same failure with the rename removed deletes the old DB.

Run: python3 tools/test_sqlite_atomic.py
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_sqlite as B  # noqa: E402

fails = 0


def check(name, cond):
    global fails
    fails += not cond
    print(("  PASS  " if cond else "  FAIL  ") + name)


def boom(*a, **k):
    raise RuntimeError("simulated failure mid-build")


with tempfile.TemporaryDirectory() as d:
    out = Path(d) / "catalog.sqlite"
    out.write_bytes(b"OLD-GOOD-DB")
    real = B.populate_series
    B.populate_series = boom
    try:
        B.build_db_obj({"items": [], "generatedAt": "x"}, out, materialize_episodes=False)
        check("the build raised", False)
    except RuntimeError:
        pass
    finally:
        B.populate_series = real
    check("the previous DB is untouched after a failed build", out.read_bytes() == b"OLD-GOOD-DB")
    m = Path(d) / "m.json"
    B._atomic_write_text(m, '{"a": 1}')
    check("an atomic text write lands whole and leaves no temp file",
          m.read_text() == '{"a": 1}' and not (Path(d) / "m.json.tmp").exists())

print("PASS" if not fails else f"FAIL ({fails})")
sys.exit(1 if fails else 0)
