#!/usr/bin/env python3
"""subtitle-sync never re-listens to the same failures blindly, and keeps its ledger.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." Two holes: the workflow downloaded
`subtitle_audio_verdicts.jsonl` but uploaded `verdicts.jsonl`, so every run
started "0 already decided"; and SKIP / AUDIO-FAIL / SYNC-FAIL wrote nothing, so
abraham_lincoln, daisies_202103 and tokyo-drifter failed in every run.
Runs the real main() with the audio extraction replaced.
"""
import contextlib
import csv
import io
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
try:
    import requests  # noqa: F401
except ImportError:            # pulled in by build_subtitle_assets; nothing here fetches
    import types
    sys.modules["requests"] = types.ModuleType("requests")
import sync_subtitles_audio as S  # noqa: E402

VERSION = getattr(S, "SYNC_VERSION", 1)
TMP = Path(tempfile.mkdtemp(prefix="subsync-attempts-"))
fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n  {detail}"))


# The workflow restores the ledger under the same name it publishes it.
wf = (HERE.parent / ".github/workflows/subtitle-sync.yml").read_text()
ups = set(re.findall(r"gh release upload subtitle-assets (\S+)", wf))
downs = set(re.findall(r"gh release download subtitle-assets -p (\S+)", wf)) - {"subs.tar.gz"}
check("the ledger is downloaded under the name it is uploaded", downs and downs <= ups, f"down={downs} up={ups}")

subs = TMP / "subs"
findings = TMP / "findings.csv"
db = TMP / "catalog.sqlite"
verdicts = TMP / "verdicts.jsonl"
FILMS = ["dead1", "dead2", "nourl", "new1"]
for aid in FILMS:
    (subs / aid).mkdir(parents=True)
    (subs / aid / "en.vtt").write_text("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nhi\n")
with open(findings, "w", newline="") as f:
    w = csv.DictWriter(f, ["archiveID", "verdict", "pop", "runtime", "lastCue"])
    w.writeheader()
    for i, aid in enumerate(FILMS):
        w.writerow({"archiveID": aid, "verdict": "overruns", "pop": 10 - i, "runtime": 600, "lastCue": 700})
con = sqlite3.connect(db)
con.execute("CREATE TABLE item_json(archiveID TEXT, json TEXT)")
for aid in FILMS:
    if aid != "nourl":
        con.execute("INSERT INTO item_json VALUES(?,?)", (aid, json.dumps({"downloadURL": f"https://x/{aid}.mp4"})))
con.commit(); con.close()


def run(limit=3):
    tried = []

    def fake(url, wav, timeout):
        tried.append(url.rsplit("/", 1)[-1][:-4])
        raise subprocess.CalledProcessError(1, "ffmpeg", stderr=b"Invalid argument")
    S.extract_audio = fake
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            sys.argv = ["x", "--subs", str(subs), "--findings", str(findings), "--db", str(db),
                        "--verdicts", str(verdicts), "--limit", str(limit)]
            S.main()
        except Exception as e:
            print(f"CRASH {type(e).__name__}: {e}")
    return sorted(tried), buf.getvalue()


tried, out = run()
lines = [json.loads(l) for l in verdicts.read_text().splitlines()] if verdicts.exists() else []
rec = {v["id"]: v for v in lines}
check("an audio failure is written to the ledger with its reason",
      rec.get("dead1", {}).get("result") == "failed" and "Invalid argument" in rec["dead1"].get("reason", "")
      and rec["dead1"].get("attempts") == 1, rec.get("dead1"))
check("a missing URL is written too", rec.get("nourl", {}).get("result") == "failed", rec.get("nourl"))
tried, out = run()
check("the next run skips them and reaches a new film", tried == ["new1"], tried)
check("its summary counts them as skipped for backoff", "3 skipped (backoff)" in out, out[-300:])


def ago(d):
    return (datetime.now(timezone.utc) - timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%SZ")


verdicts.write_text("".join(json.dumps(v) + "\n" for v in [
    {"id": "dead1", "result": "failed", "reason": "x", "attempts": 1, "at": ago(2), "v": VERSION},
    {"id": "dead2", "result": "failed", "reason": "x", "attempts": 2, "at": ago(2), "v": VERSION},
    {"id": "nourl", "result": "failed", "reason": "x", "attempts": 4, "at": ago(400), "v": VERSION},
    {"id": "new1", "result": "failed", "reason": "x", "attempts": 4, "at": ago(1), "v": VERSION - 1},
]))
tried, out = run(limit=10)
check("backoff grows and a version bump re-opens a capped failure", tried == ["dead1", "new1"], tried)
check("a capped film is reported, not retried", "1 capped" in out and "nourl" in out, out[-300:])
last = {}
for l in verdicts.read_text().splitlines():
    v = json.loads(l); last[v["id"]] = v
check("a retried failure counts up", last["dead1"].get("attempts") == 2, last["dead1"])

shutil.rmtree(TMP, ignore_errors=True)
print("ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
