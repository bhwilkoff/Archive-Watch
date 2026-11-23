#!/usr/bin/env python3
"""tmdb-enrich never re-fetches the same unfillable gaps blindly.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." Each daily run re-fetched every tmdbID item
with an empty synopsis, cast or director, including the ~3,400 whose TMDb
record is empty too, and re-ran /find for imdbIDs TMDb does not know: the same
misses every day. Runs the real main() with TMDb replaced.
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
    import requests  # noqa: F401
except ImportError:            # nothing here reaches the network
    import types
    sys.modules["requests"] = types.ModuleType("requests")
import tmdb_fill_metadata as M  # noqa: E402

V = getattr(M, "TMDB_FILL_VERSION", 1)
TMP = Path(tempfile.mkdtemp(prefix="tmdb-attempts-"))
fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


DETAIL = {"1": {"plot": "", "cast": [], "director": ""},                        # TMDb empty too
          "2": {"plot": "A full plot summary here.", "cast": [{"name": "X"}], "director": "D"}}


def run(items):
    cat = TMP / "catalog.json"
    cat.write_text(json.dumps({"items": items}))
    M.CATALOG = cat
    M.CACHE = TMP / "cache.json"
    M.CACHE.unlink(missing_ok=True)                 # a fresh runner each day
    asked = []
    M.T.load_tmdb_token = lambda _p: "tok"

    def detail(tid, token):
        asked.append(f"d{tid}")
        return DETAIL.get(str(tid), {"plot": "", "cast": [], "director": ""})

    def find(imdb, token):
        asked.append(f"f{imdb}")
        return None
    M._detail, M._find_tmdb_id = detail, find
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            M.main()
        except Exception as e:
            print(f"CRASH {type(e).__name__}: {e}")
    return sorted(asked), buf.getvalue(), json.loads(cat.read_text())["items"]


def gap(aid, tid=None, imdb=None, **kw):
    it = {"archiveID": aid, "synopsis": "", "cast": [], "director": ""}
    if tid: it["tmdbID"] = tid
    if imdb: it["imdbID"] = imdb
    return {**it, **kw}


asked, out, items = run([gap("empty", tid=1), gap("full", tid=2), gap("lost", imdb="tt9")])
by = {i["archiveID"]: i for i in items}
rec = by["empty"].get("tmdbFillTried") or {}
check("a gap TMDb cannot fill is recorded", rec.get("attempts") == 1 and rec.get("v") == V and rec.get("reason"), rec)
check("an imdbID /find miss is recorded", (by["lost"].get("tmdbFillTried") or {}).get("attempts") == 1, by["lost"])
check("a filled item carries no record", "tmdbFillTried" not in by["full"], by["full"])
asked, out, _ = run([by["empty"], by["lost"], gap("new", tid=3)])
check("the next run asks TMDb only about the new item", asked == ["d3"], asked)
check("its summary counts the others as skipped for backoff", "2 skipped (backoff)" in out, out[-400:])


def ago(d):
    return (datetime.now(timezone.utc) - timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%SZ")


def r(n, d, v=V):
    return {"tmdbFillTried": {"outcome": "no_data", "reason": "x", "attempts": n, "at": ago(d), "v": v}}


asked, out, _ = run([gap("a", tid=11, **r(1, 2)), gap("b", tid=12, **r(2, 2)), gap("c", tid=13, **r(3, 20)),
                     gap("d", tid=14, **r(4, 400)), gap("e", tid=15, **r(4, 1, v=V - 1))])
check("backoff 1/7/30 days; a version bump re-opens a capped item", asked == ["d11", "d15"], asked)
check("a capped item is reported, not retried", "1 capped" in out and "d14" not in asked, out[-400:])

shutil.rmtree(TMP, ignore_errors=True)
print("ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
