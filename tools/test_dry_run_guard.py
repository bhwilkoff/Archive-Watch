#!/usr/bin/env python3
"""
test_dry_run_guard.py — a dry run must never reach the ledger.

This exists because it happened. When Instagram and Threads began returning
"DRY-RUN (reel)" / "DRY-RUN (video)" to say which format they had chosen, the
dispatcher's EXACT `url == "DRY-RUN"` check stopped matching, both fell through
to the posted branch, and a DRY RUN wrote two fabricated entries which the
workflow then pushed (run 34241396212).

That is not a cosmetic bug. The ledger is what stops a film being posted twice
(SOCIAL-PROGRAM §7) and what drives the public feed, so a false entry silently
retires a film and publishes a link that goes nowhere.

The guard is read out of the SHIPPED tool.
"""
import pathlib, re, sys

src = pathlib.Path(__file__).with_name("social_post.py").read_text()
m = re.search(r'if (str\(url\)\.startswith\("DRY-RUN"\)|url == "DRY-RUN")', src)
if not m:
    print("FAIL: dry-run guard not found in social_post.py"); sys.exit(1)
guard_is_prefix = "startswith" in m.group(0)

# Every shape an adapter returns for a dry run today, plus real permalinks.
DRY = ["DRY-RUN", "DRY-RUN (reel)", "DRY-RUN (image)", "DRY-RUN (video)"]
REAL = ["https://www.instagram.com/p/abc", "https://www.threads.net/@me/post/1",
        "https://bsky.app/profile/x/post/y", "https://youtube.com/watch?v=z"]

def skipped(url):  # what the shipped guard decides
    return str(url).startswith("DRY-RUN") if guard_is_prefix else url == "DRY-RUN"

fails = 0
for u in DRY:
    ok = skipped(u)
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  dry run never ledgered: {u}")
for u in REAL:
    ok = not skipped(u)
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  real post IS ledgered: {u[:40]}")

# And the ledger itself must be free of fabricated entries.
led = pathlib.Path(__file__).resolve().parent.parent / "social" / "posted.json"
if led.exists():
    import json
    bad = [e for e in json.loads(led.read_text()).get("posts", [])
           if str(e.get("url", "")).startswith("DRY-RUN")]
    ok = not bad
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  ledger carries no DRY-RUN entries ({len(bad)} found)")

total = len(DRY) + len(REAL) + 1
print(f"\n{total - fails}/{total} passed")
sys.exit(0 if fails == 0 else 1)
