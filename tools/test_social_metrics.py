#!/usr/bin/env python3
"""
test_social_metrics.py — the reader's parsing and its refusal to conclude.

Nothing here touches a network. What is asserted is the part that would fail
silently: pulling the right id out of five different URL shapes, sampling each
window exactly once, and refusing to rank a bucket too small to mean anything.
Checked to FAIL against a reader that samples every run.

Run: python3 tools/test_social_metrics.py
"""
import datetime as dt
import io
import sys
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import social_metrics as M

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


def ago(hours):
    return (dt.datetime.now(dt.timezone.utc)
            - dt.timedelta(hours=hours)).isoformat()


print("id parsing")
check("a Meta media id comes off the permalink",
      M._meta_id("https://www.instagram.com/p/17991528983844452") == "17991528983844452")
check("a shortcode is NOT read as an id",
      M._meta_id("https://www.instagram.com/p/DAbc123xyz/") is None)
check("a trailing slash does not change the id",
      M._meta_id("https://www.threads.net/@me/post/18089279720272016/")
      == "18089279720272016")

print("\nsampling windows")
seen = set()
row = {"platform": "mastodon", "url": "u1", "at": ago(2)}
check("a fresh post is not sampled", M.due(row, seen) is None)
row["at"] = ago(21)
check("a day-old post is due at 24h", M.due(row, seen) == "24h")
seen.add(("u1", "24h"))
check("it is not sampled twice in the same window", M.due(row, seen) is None)
row["at"] = ago(150)
check("a week-old post is due again at 7d", M.due(row, seen) == "7d")
seen.add(("u1", "7d"))
check("and then never again", M.due(row, seen) is None)
check("an unreadable date is skipped, not stamped now",
      M.due({"url": "u2", "at": "not a date"}, set()) is None)
# The threshold must sit BELOW the window it names, or a daily cron running at
# the same clock time each day arrives a few minutes early and misses it — the
# post then waits a further 24 hours and the "24h" reading is a 48h reading.
NOMINAL = {"24h": 24.0, "7d": 168.0}
check("each threshold clears its window with a daily run in hand",
      all(NOMINAL[name] - after >= 4.0 for name, after in M.WINDOWS),
      str(M.WINDOWS))

print("\nthe report refuses to conclude on nothing")
few = [{"url": f"u{i}", "platform": "bluesky", "slot": "now-showing",
        "format": "video", "metrics": {"likes": i}} for i in range(3)]
buf = io.StringIO()
with redirect_stdout(buf):
    M.report(few)
out = buf.getvalue()
check("it says the sample is too small", "too few to rank" in out, out[:120])
check("it says so once at the end too", "the conclusions wait" in out)
check("it still shows the numbers", "3 posts measured" in out)

many = [{"url": f"v{i}", "platform": "bluesky" if i % 2 else "mastodon",
         "slot": "now-showing", "format": "video",
         "metrics": {"likes": i}} for i in range(24)]
buf = io.StringIO()
with redirect_stdout(buf):
    M.report(many)
out = buf.getvalue()
check("with enough posts it ranks without the warning",
      "too few to rank" not in out and "the conclusions wait" not in out)
check("the last reading of a post wins, not the first",
      "24 posts measured" in out)

dupes = [{"url": "same", "platform": "bluesky", "metrics": {"likes": 1}},
         {"url": "same", "platform": "bluesky", "metrics": {"likes": 9}}]
buf = io.StringIO()
with redirect_stdout(buf):
    M.report(dupes)
check("two windows of one post count once", "1 posts measured" in buf.getvalue())

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
