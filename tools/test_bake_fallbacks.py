#!/usr/bin/env python3
"""bake_fallbacks remembers a film that has no lighter copy, for a while.

Cases: a heavy film whose item has no smaller derivative is stamped
fallbackMissAt and is not asked about on the next run; once the stamp is older
than the TTL it is asked again; a film that finds a copy is baked. Control:
archive.org not answering is not a miss (no stamp), so the film is asked again
on the next run. Runs in a temp dir with archive.org stubbed.
"""
import datetime
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bake_fallbacks as F

ok = True


def check(name, cond):
    global ok
    ok &= bool(cond)
    print(f"  {'ok  ' if cond else 'FAIL'} {name}")


GB = 2_000_000_000
asked = []
answers = {}


def http_json(url, timeout=20):
    aid = url.rsplit("/", 1)[-1]
    asked.append(aid)
    a = answers.get(aid)
    if a == "down":
        raise OSError("archive.org did not answer")
    return a


F.http_json = http_json
F.head_size = lambda url, timeout=15: 1


def item(aid, **kw):
    return {"archiveID": aid, "downloadURL": f"https://archive.org/download/{aid}/{aid}.mp4",
            "videoFile": {"sizeBytes": GB}, "popularityScore": 1, **kw}


def run(items):
    asked.clear()
    d = tempfile.mkdtemp()
    os.chdir(d)
    Path("catalog.json").write_text(json.dumps({"items": items}))
    sys.argv = ["bake_fallbacks.py", "--min-bytes", "1000"]
    F.main()
    return {i["archiveID"]: i for i in json.loads(Path("catalog.json").read_text())["items"]}


none = {"files": [{"name": "x.mp4", "source": "original", "size": GB}]}
some = {"files": [{"name": "x.mp4", "source": "original", "size": GB},
                  {"name": "x_512kb.mp4", "source": "derivative", "size": 50_000_000}]}
answers.update({"bare": none, "rich": some, "flaky": "down"})

out = run([item("bare"), item("rich"), item("flaky")])
check("a film with no lighter copy is stamped", out["bare"].get(F.MISS_FIELD))
check("a film with a lighter copy is baked, not stamped",
      out["rich"].get("fallbackVideoURL", "").endswith("x_512kb.mp4") and F.MISS_FIELD not in out["rich"])
check("control: archive.org not answering is not a miss", F.MISS_FIELD not in out["flaky"])

out = run(list(out.values()))
check("a stamped film is not asked again inside the TTL", "bare" not in asked)
check("control: an unanswered film is asked again on the next run", "flaky" in asked)

old = (datetime.date.today() - datetime.timedelta(days=F.MISS_TTL_DAYS + 1)).isoformat()
stale = dict(out["bare"], **{F.MISS_FIELD: old})
out = run([stale])
check("a stamp older than the TTL is asked again", "bare" in asked
      and out["bare"][F.MISS_FIELD] == datetime.date.today().isoformat())

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
