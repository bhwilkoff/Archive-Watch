#!/usr/bin/env python3
"""The budget must bound NETWORK work without ever costing an EPISODE.

build_canonical_tv cannot be run here — it hammers archive.org, which
rate-limits the household IP and stalls the owner's Apple TV — so the network
call is stubbed and the two properties that matter are asserted directly:

  1. past the deadline, ensure_playable is not called again (the overrun that
     blew the 180-minute step timeout on 2026-08-16), and
  2. every episode is STILL emitted, because a partial spine would silently
     delete TV content from every client (Decisions 016/036).
"""
import sys, time, types
sys.path.insert(0, "tools")
import build_canonical_tv as B

calls = {"n": 0}
def fake_ensure_playable(aid, dl, vf):
    calls["n"] += 1
    return dl, vf, False, True
B.ensure_playable = fake_ensure_playable

EPS = 40
show = {"name": "Budget Test", "premiered": "1955-01-01", "id": 1}
# Shape taken from canonical_episodes() itself, not guessed.
B.canonical_episodes = lambda sh: [
    {"season": 1, "number": i + 1, "title": f"Ep {i+1}", "overview": "",
     "airDate": "1955-01-02", "stillURL": None, "runtimeSeconds": 1500}
    for i in range(EPS)]
items = [{"archiveID": f"aid-{i+1}", "downloadURL": f"https://x/{i+1}.mp4",
          "videoFile": f"{i+1}.mp4", "title": f"Budget Test S01E{i+1:02d}",
          "runtimeSeconds": 1500} for i in range(EPS)]
B.map_items_to_canonical = lambda our, canon: (
    {(1, i + 1): (canon[i], items[i]) for i in range(min(len(items), len(canon)))}, [])

def run(deadline):
    calls["n"] = 0
    series, row = B.rebuild_show(show, items, repick=True, deadline=deadline)
    n_eps = sum(len(s.get("episodes", [])) for s in (series or {}).get("seasons", [])) \
        if series else 0
    return calls["n"], n_eps, row

ok = True
def check(name, cond, detail=""):
    global ok
    ok &= bool(cond)
    print(f"  {'PASS' if cond else 'FAIL'} {name}{(' — ' + detail) if detail else ''}")

n, eps, row = run(None)                       # no budget: unchanged behaviour
check("no deadline => every episode re-picked", n == EPS, f"ensure_playable x{n}")
check("no deadline => every episode emitted", eps == EPS, f"{eps}/{EPS}")
base_eps = eps

n, eps, row = run(time.monotonic() - 1)       # budget already blown
check("past deadline => ZERO network calls", n == 0, f"ensure_playable x{n}")
check("past deadline => episodes STILL emitted", eps == base_eps,
      f"{eps}/{base_eps} — a partial spine would delete TV content")
check("past deadline => degradation is counted", row.get("repickSkipped", 0) == EPS,
      f"repickSkipped={row.get('repickSkipped')}")

n, eps, row = run(time.monotonic() + 3600)    # budget with room
check("future deadline => re-picks normally", n == EPS, f"ensure_playable x{n}")

print(f"\n{'ALL PASS' if ok else 'FAILURES'}")
sys.exit(0 if ok else 1)
