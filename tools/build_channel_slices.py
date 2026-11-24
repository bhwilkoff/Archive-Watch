#!/usr/bin/env python3
"""One small schedule per channel, for the Worker (worker/src/live.js).

/live/<channel> parsed the whole channel-schedule.json (275 KB) on every
request: 8 to 9 ms of the free plan's 10 ms CPU (measured 2026-11-24). Each
slice has the whole file's shape with one channel and only the programs it
airs, so live.js reads either the same way. Built into the deploy artifact,
never committed.

  python3 tools/build_channel_slices.py --out _site
"""
import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def slices(sched: dict) -> dict:
    out = {}
    for ch in sched["channels"]:
        if not re.fullmatch(r"[a-z0-9-]+", ch["id"]):
            raise SystemExit(f"channel id {ch['id']!r} cannot be a file name")
        ids = {slot[0] for day in ch["days"].values() for slot in day["slots"]}
        out[ch["id"]] = {**sched, "channels": [ch],
                         "programs": {i: p for i, p in sched["programs"].items() if i in ids}}
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--schedule", default=str(REPO / "channel-schedule.json"))
    a = ap.parse_args()
    made = slices(json.loads(Path(a.schedule).read_text(encoding="utf-8")))
    if not made:
        print("no channels in the schedule", file=sys.stderr)
        return 1
    d = Path(a.out) / "channel-schedule"
    d.mkdir(parents=True, exist_ok=True)
    for cid, doc in made.items():
        (d / f"{cid}.json").write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"channel slices: {len(made)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
