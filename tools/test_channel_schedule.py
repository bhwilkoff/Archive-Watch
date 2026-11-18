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

# Held days survive a rebuild with a DIFFERENT pool and a new day.
pools2 = copy.deepcopy(POOLS)
pools2["channels"][0]["programs"].reverse()
pools2["channels"][0]["programs"] += [[f"n{i}", f"New {i}", 3000, f"https://x/n{i}.mp4", "feature-film"]
                                      for i in range(6)]
c = S.build(pools2, a, TODAY + dt.timedelta(days=1))
held = [d for d in next(x for x in a["channels"] if x["id"] == "drama")["days"]
        if d >= (TODAY).isoformat()]
same = all(next(x for x in c["channels"] if x["id"] == "drama")["days"][d] ==
           next(x for x in a["channels"] if x["id"] == "drama")["days"][d] for d in held)
check("published days keep their programs across a rebuild", same)
ctrl = S.build(pools2, {}, TODAY + dt.timedelta(days=1))
changed = any(next(x for x in ctrl["channels"] if x["id"] == "drama")["days"].get(d) !=
              next(x for x in a["channels"] if x["id"] == "drama")["days"][d] for d in held)
check("control: without the previous file, the changed pool changes them", changed)

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

# The rotation: a channel plays every title in its pool once before any twice,
# across days. A pool of ~2.5 days of films, built a day at a time for a week.
ROT = {"channels": [{"id": "rot", "title": "R", "tagline": "", "accent": "#000",
                     "programs": [[f"r{i}", f"R {i}", 3600, f"https://x/r{i}.mp4", "feature-film"]
                                  for i in range(60)]}]}


def aired_in_order(sched_by_day):
    return [pid for key in sorted(sched_by_day) for pid in sched_by_day[key]]


def week(chained):
    prev, days = {}, {}
    for k in range(7):
        prev = S.build(ROT, prev if chained else {}, TODAY + dt.timedelta(days=k))
        for key, blk in prev["channels"][0]["days"].items():
            days.setdefault(key, [s[0] for s in blk["slots"]])
    return aired_in_order(days)


def first_repeat_after_all(seq, n):
    """Every window of n consecutive programs holds n different titles."""
    return all(len(set(seq[i:i + n])) == n for i in range(len(seq) - n + 1))


check("the rotation airs all 60 titles before any repeats, across a week",
      first_repeat_after_all(week(True), 60))
check("control: building each day afresh repeats titles inside 60 programs",
      not first_repeat_after_all(week(False), 60))

# Repair removes only what left the CATALOG: a held film that merely fell out
# of its pool stays where it was published.
gone = timeline(a, "drama")[-3][2]
pools4 = copy.deepcopy(POOLS)
pools4["channels"][0]["programs"] = [p for p in pools4["channels"][0]["programs"] if p[0] != gone]
pools4["eligible"] = [p[0] for c in POOLS["channels"] for p in c["programs"]]
kept = S.build(pools4, a, TODAY)
check("a film out of its pool but still in the catalog keeps its slot",
      any(x[2] == gone for x in timeline(kept, "drama") if x[0] >= S.day_start(TODAY)))
pools4["eligible"].remove(gone)
dropped = S.build(pools4, a, TODAY)
check("control: out of the catalog too, it is replaced",
      all(x[2] != gone for x in timeline(dropped, "drama") if x[0] >= S.day_start(TODAY)))

print(f"\n{fails} failure(s)")
sys.exit(1 if fails else 0)
