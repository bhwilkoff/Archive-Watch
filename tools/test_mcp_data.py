#!/usr/bin/env python3
"""build_mcp_data.load_cast reads detail shards whose records drop trailing
empty fields. A 2-field record took deploy-pages down on 2026-09-28."""
import json, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import build_mcp_data as M

d = Path(tempfile.mkdtemp())
(d / "00.json").write_text(json.dumps({
    "short": ["https://x/a.mp4", "A synopsis"],             # stops before cast
    "four": [None, None, None, [["Jeff Donnell"], ["Peggy King"]]],
    "odd": ["u", None, None, [[], None, "Plain Name"]],
}))
cast = M.load_cast(d)
fails = 0
def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name); fails += not cond
check("a record that stops before its cast is skipped", "short" not in cast)
check("a four-field record yields its cast", cast.get("four") == "Jeff Donnell Peggy King")
check("empty and bare entries are tolerated", cast.get("odd") == "Plain Name")
# Control: the unguarded read this replaced must fail on the same shard.
try:
    for aid, rec in json.loads((d / "00.json").read_text()).items():
        [c[0] if isinstance(c, list) else c for c in (rec[3] or [])[:3]]
    check("control: the old read crashes on a short record", False)
except IndexError:
    check("control: the old read crashes on a short record", True)
sys.exit(1 if fails else 0)
