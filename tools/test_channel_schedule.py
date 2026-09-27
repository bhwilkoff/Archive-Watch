#!/usr/bin/env python3
"""Channels on one clock (build_channel_schedule.py): the rules, each with a
control that must produce the opposite verdict."""
import copy
import datetime as dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_channel_schedule as S  # noqa: E402

POOLS = {"channels": [
    {"id": "drama", "title": "Drama", "tagline": "", "accent": "#000",
     "programs": [[f"f{i}", f"Film {i}", 3600 + 300 * i, f"https://x/{i}.mp4", "feature-film"]
                  for i in range(12)]},
    {"id": "cartoon", "title": "Cartoons", "tagline": "", "accent": "#000",
     "programs": [[f"c{i}", f"Cartoon {i}", None, f"https://x/c{i}.mp4", "animation"]
                  for i in range(30)]},
]}
TODAY = dt.date(2026, 9, 27)
fails = 0


def check(name, ok):
    global fails
    print(("PASS " if ok else "FAIL ") + name)
    fails += 0 if ok else 1


def timeline(sched, cid):
    ch = next(c for c in sched["channels"] if c["id"] == cid)
    out = []
    for key in sorted(ch["days"]):
        b = ch["days"][key]
        t = b["start"]
        for pid, secs in b["slots"]:
            out.append((t, t + secs, pid))
            t += secs + sched["gap"]
    return out


a = S.build(POOLS, {}, TODAY)
b = S.build(POOLS, {}, TODAY)
check("the same inputs give the same schedule", a["channels"] == b["channels"])

for cid in ("drama", "cartoon"):
    tl = timeline(a, cid)
    gaps = {tl[i + 1][0] - tl[i][1] for i in range(len(tl) - 1)}
    check(f"{cid}: one continuous timeline across UTC days (gaps {sorted(gaps)})", gaps == {S.GAP})
    first = S.day_start(TODAY - dt.timedelta(days=S.DAYS_BACK))
    check(f"{cid}: the first program starts at UTC midnight", tl[0][0] == first)
    ch = next(c for c in a["channels"] if c["id"] == cid)
    covered_to = S.block_end(ch["days"][max(ch["days"])])
    check(f"{cid}: covers through the last UTC day", covered_to >= S.day_start(TODAY + dt.timedelta(days=S.DAYS_AHEAD + 1)))

# Held days survive a rebuild with a DIFFERENT pool order and a new day.
pools2 = copy.deepcopy(POOLS)
pools2["channels"][0]["programs"].reverse()
c = S.build(pools2, a, TODAY + dt.timedelta(days=1))
held = [d for d in next(x for x in a["channels"] if x["id"] == "drama")["days"]
        if d >= (TODAY).isoformat()]
same = all(next(x for x in c["channels"] if x["id"] == "drama")["days"][d] ==
           next(x for x in a["channels"] if x["id"] == "drama")["days"][d] for d in held)
check("published days keep their programs across a rebuild", same)
ctrl = S.build(pools2, {}, TODAY + dt.timedelta(days=1))
changed = any(next(x for x in ctrl["channels"] if x["id"] == "drama")["days"].get(d) !=
              next(x for x in a["channels"] if x["id"] == "drama")["days"][d] for d in held)
check("control: without the previous file, the reordered pool changes them", changed)

# A program that leaves the catalog is replaced in place; start times hold.
pools3 = copy.deepcopy(POOLS)
gone = timeline(a, "drama")[-3][2]
pools3["channels"][0]["programs"] = [p for p in pools3["channels"][0]["programs"] if p[0] != gone]
d = S.build(pools3, a, TODAY)
after = timeline(d, "drama")
future = [x for x in after if x[0] >= S.day_start(TODAY)]
check("a hidden film never airs today or later", all(x[2] != gone for x in future))
starts_before = [x[0] for x in timeline(a, "drama")]
check("replacing it moves no start time", [x[0] for x in after] == starts_before)

# Nothing in the schedule depends on the machine's zone: the anchor is UTC.
import os, time
os.environ["TZ"] = "Pacific/Kiritimati"; time.tzset()
e = S.build(POOLS, {}, TODAY)
check("the schedule is the same in any time zone", e["channels"] == a["channels"])

# A short film's slot is its own length, not its type's 90-minute default.
check("a 104-second silent film gets a 104-second slot", S.slot_seconds(104, "silent-film") == 104)
check("control: an unknown length still takes the type default", S.slot_seconds(None, "silent-film") == 90 * 60)
check("a runtime under 30 s is treated as unknown", S.slot_seconds(5, "feature-film") == 90 * 60)

print(f"\n{fails} failure(s)")
sys.exit(1 if fails else 0)
