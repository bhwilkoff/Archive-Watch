#!/usr/bin/env python3
"""
build_channel_schedule.py — Channels on ONE clock (ORPHANED-FILMS #2).

Owner, 2026-09-27: "Move forward with a single clock. If you need a time zone
to organize around, you can choose UTC, but all times should show as their
local times when they look at channels. This should only be to sync all titles
to the same time."

Every platform used to compute its own schedule from a 6 AM LOCAL broadcast
day, with three different shuffles and two pool sources, so no two viewers saw
the same program. This builds ONE timeline per channel, in UTC, and publishes
it as channel-schedule.json; every client plays and draws from it and shows its
times in the viewer's own zone.

Shape (schema 1):
  {"schema":1, "gap":120, "updatedAt":"...",
   "programs": {id: [title, runtimeSeconds|null, downloadURL, contentType]},
   "channels": [{"id","title","tagline","accent",
                 "days": {"YYYY-MM-DD": {"start": epochSeconds,
                                         "slots": [[id, seconds], ...]}}}]}
A slot starts where the previous one ended plus `gap`. Days are UTC calendar
days and run back to back: a day's first program starts where the previous
day's last one ended, so a film that crosses midnight UTC is never cut.

Stability: days already published keep their programs across rebuilds (the
tonight.json rule), so a publish at noon never changes what is on. A held
program that is no longer eligible (a rights hide, a takedown) is replaced in
place by the channel's film of the nearest length, keeping every start time.

Input: channel-pools.json (built just before, from the same catalog).
"""

import datetime as dt
import hashlib
import json
import random
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
POOLS = REPO / "channel-pools.json"
OUT = REPO / "channel-schedule.json"

GAP = 120
DAYS_BACK = 1
DAYS_AHEAD = 3


# A known length is the film's length. The apps' old rule trusted only lengths
# over two minutes and gave anything shorter its type's default, so a 104-second
# silent film got a 90-minute slot of dead air (the owner's Documentary channel,
# 2026-09-27). Under MIN_KNOWN seconds a runtime is treated as unknown.
MIN_KNOWN = 30


def slot_seconds(runtime, ctype) -> int:
    if runtime and runtime >= MIN_KNOWN:
        return int(min(runtime, 3 * 3600))
    if ctype in ("feature-film", "silent-film"):
        return 90 * 60
    if ctype in ("tv-special", "documentary"):
        return 50 * 60
    if ctype in ("short-film", "animation", "newsreel", "ephemeral"):
        return 12 * 60
    return 60 * 60


def day_start(day: dt.date) -> int:
    return int(dt.datetime(day.year, day.month, day.day, tzinfo=dt.timezone.utc).timestamp())


def block_end(block: dict) -> int:
    t = block["start"]
    for _, secs in block["slots"]:
        t += secs + GAP
    return t


def fill_day(channel_id: str, day: dt.date, start: int, pool: list, avoid: str | None) -> dict:
    """Programs from `start` until the next UTC midnight, in an order seeded by
    the channel and the date, cycling the pool so nothing repeats within a day
    while the pool lasts."""
    seed = int(hashlib.sha1(f"{channel_id}:{day.isoformat()}".encode()).hexdigest(), 16)
    order = list(pool)
    random.Random(seed).shuffle(order)
    if avoid and len(order) > 1 and order[0][0] == avoid:
        order.append(order.pop(0))
    end = day_start(day + dt.timedelta(days=1))
    slots, t, i = [], start, 0
    while t < end and len(slots) < 2000:
        p = order[i % len(order)]
        secs = slot_seconds(p[2], p[4])
        slots.append([p[0], secs])
        t += secs + GAP
        i += 1
    return {"start": start, "slots": slots}


def repair(block: dict, eligible: dict, pool: list) -> int:
    """Swap programs that left the catalog for the pool film of nearest length,
    in place, so every start time stays where it was published."""
    swapped = 0
    for s in block["slots"]:
        if s[0] in eligible:
            continue
        best = min(pool, key=lambda p: abs(slot_seconds(p[2], p[4]) - s[1]))
        s[0] = best[0]
        swapped += 1
    return swapped


def build(pools: dict, previous: dict, today: dt.date) -> dict:
    prev_channels = {c["id"]: c.get("days") or {} for c in previous.get("channels") or []}
    prev_programs = previous.get("programs") or {}
    days = [today + dt.timedelta(days=k) for k in range(-DAYS_BACK, DAYS_AHEAD + 1)]
    programs, channels = {}, []
    for ch in pools["channels"]:
        pool = [p for p in ch["programs"] if p[3]]
        if not pool:
            continue
        eligible = {p[0]: p for p in pool}
        held = prev_channels.get(ch["id"], {})
        out, cursor, last = {}, None, None
        for day in days:
            key = day.isoformat()
            block = held.get(key)
            if block and day > today and any(
                    s[0] in eligible and s[1] != slot_seconds(eligible[s[0]][2], eligible[s[0]][4])
                    for s in block["slots"]):
                # A future day laid out under the old length rule is rebuilt
                # (from here on, since each day starts where the last ended);
                # today and earlier keep their published times.
                print(f"  {ch['id']} {key}: slot lengths from the old rule, rebuilt")
                held = {k: v for k, v in held.items() if k < key}
                block = None
            if block and block.get("slots"):
                block = {"start": block["start"], "slots": [list(s) for s in block["slots"]]}
                if day >= today:
                    n = repair(block, eligible, pool)
                    if n:
                        print(f"  {ch['id']} {key}: {n} program(s) no longer eligible, replaced in place")
            else:
                start = cursor if cursor is not None else day_start(day)
                block = fill_day(ch["id"], day, start, pool, last)
            out[key] = block
            cursor = block_end(block)
            last = block["slots"][-1][0]
        for block in out.values():
            for pid, _ in block["slots"]:
                if pid not in programs:
                    p = eligible.get(pid) or next(
                        (q for c in pools["channels"] for q in c["programs"] if q[0] == pid), None)
                    if p:
                        programs[pid] = [p[1], p[2], p[3], p[4]]
                    elif pid in prev_programs:
                        # Over, and gone from every pool: its title still
                        # labels the hours it aired.
                        programs[pid] = prev_programs[pid]
        channels.append({"id": ch["id"], "title": ch["title"], "tagline": ch["tagline"],
                         "accent": ch["accent"], "days": out})
    return {"schema": 1, "gap": GAP,
            "updatedAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "programs": programs, "channels": channels}


def main() -> int:
    if not POOLS.exists():
        raise SystemExit(f"{POOLS.name} is missing — build_channel_pools.py runs first")
    pools = json.loads(POOLS.read_text())
    try:
        previous = json.loads(OUT.read_text())
    except Exception:  # noqa: BLE001 — first run, or an unreadable file: start fresh
        previous = {}
    today = dt.datetime.now(dt.timezone.utc).date()
    out = build(pools, previous, today)
    if not out["channels"]:
        raise SystemExit("no channel could be scheduled — refusing to publish an empty guide")
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    n = sum(len(b["slots"]) for c in out["channels"] for b in c["days"].values())
    print(f"wrote {OUT.name}: {len(out['channels'])} channels, {n} programs over "
          f"{DAYS_BACK + DAYS_AHEAD + 1} UTC days, {OUT.stat().st_size / 1e3:.0f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
