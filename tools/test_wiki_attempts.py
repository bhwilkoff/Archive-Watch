#!/usr/bin/env python3
"""wikipedia-synopsis and wikidata-posters never re-query the same misses blindly.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." Both took every candidate every week: ~670
synopsis misses and ~593 items with no P18 image were re-queried each run, and
synopses that remediate rejected came straight back as candidates. Runs each
real main() with the network replaced.
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
import enrich_wikipedia_synopsis as WP  # noqa: E402
import enrich_wikidata_posters as WD  # noqa: E402

TMP = Path(tempfile.mkdtemp(prefix="wiki-attempts-"))
fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


def ago(d):
    return (datetime.now(timezone.utc) - timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%SZ")


def run(mod, items, asked):
    cat = TMP / "catalog.json"
    cat.write_text(json.dumps({"items": items}))
    mod.CATALOG = cat
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            sys.argv = ["x", "--throttle", "0"]
            mod.main()
        except Exception as e:
            print(f"CRASH {type(e).__name__}: {e}")
    return sorted(asked), buf.getvalue(), json.loads(cat.read_text())["items"]


def item(q, **kw):
    return {"archiveID": f"a{q}", "wikidataQID": q, "synopsis": "", **kw}


def suite(label, mod, field, version, wire):
    """wire(asked) installs fakes: Q1 always misses, Q2 hits, the rest miss."""
    asked = []
    wire(asked)
    _, out, items = run(mod, [item("Q1"), item("Q2")], asked)
    rec = {i["wikidataQID"]: i for i in items}["Q1"].get(field) or {}
    check(f"{label}: a miss is recorded with reason, count and version",
          rec.get("attempts") == 1 and rec.get("v") == version and rec.get("reason") and rec.get("at"), rec)
    asked.clear()
    keep = [i for i in items if i["wikidataQID"] == "Q1"] + [item("Q3")]
    got, out, _ = run(mod, keep, asked)
    check(f"{label}: the next run skips it", got == ["Q3"], got)
    check(f"{label}: summary counts it as skipped for backoff", "1 skipped (backoff)" in out, out[-300:])

    def r(n, d, v=version):
        return {field: {"outcome": "no_match", "reason": "x", "attempts": n, "at": ago(d), "v": v}}
    asked.clear()
    got, out, _ = run(mod, [item("Q4", **r(1, 2)), item("Q5", **r(2, 2)), item("Q6", **r(3, 20)),
                            item("Q7", **r(4, 400)), item("Q8", **r(4, 1, v=version - 1))], asked)
    check(f"{label}: backoff 1/7/30 days; a version bump re-opens a capped item", got == ["Q4", "Q8"], got)
    check(f"{label}: a capped item is reported, not retried", "1 capped" in out and "aQ7" in out, out[-300:])


EXTRACT = "A long plot summary. " * 20


def wire_wp(asked):
    def titles(qids):
        asked.extend(qids)
        found = {q: f"T{q}" for q in qids if q == "Q2"}
        return (found, "") if hasattr(WP, "SYNOPSIS_VERSION") else found
    WP.fetch_enwiki_titles = titles
    WP.fetch_extract = lambda t: EXTRACT


def wire_wd(asked):
    def p18(qids):
        asked.extend(qids)
        found = {q: "img.jpg" for q in qids if q == "Q2"}
        return (found, "") if hasattr(WD, "POSTERS_VERSION") else found
    WD.fetch_p18 = p18


suite("wikipedia-synopsis", WP, "wpSynopsisTried", getattr(WP, "SYNOPSIS_VERSION", 1), wire_wp)
suite("wikidata-posters", WD, "wdPosterTried", getattr(WD, "POSTERS_VERSION", 1), wire_wd)

# A synopsis remediate threw away comes back as a candidate: it must back off too.
asked = []
wire_wp(asked)
_, _, items = run(WP, [item("Q2")], asked)
items[0]["synopsis"] = ""                      # what remediate's rejection leaves
asked.clear()
got, _, _ = run(WP, items, asked)
check("wikipedia-synopsis: a fill remediate rejected is not re-fetched next week", got == [], got)

# The ledger is for the next run, not the app: none of it ships in item_json.
import build_sqlite  # noqa: E402
LEDGER = {"colorTried", "codecProbeTried", "coverTried", "wpSynopsisTried", "wdPosterTried", "tmdbFillTried"}
shipped = build_sqlite._slim_for_blob({"archiveID": "x", "title": "t", **{k: {"attempts": 1} for k in LEDGER}})
check("ledger records never ship to the clients", not (LEDGER & set(shipped)) and shipped.get("title") == "t",
      sorted(shipped))

shutil.rmtree(TMP, ignore_errors=True)
print("ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
