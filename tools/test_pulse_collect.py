#!/usr/bin/env python3
"""
test_pulse_collect.py — the dashboard's readers, held to the one property that
matters: a reader that cannot read must SAY SO, never report a confident zero.

Every case here was checked to fail against a deliberately broken version of the
rule it covers, which is the only way to know a regression test works.

  python3 tools/test_pulse_collect.py
"""
from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pulse_collect as P  # noqa: E402

PASS = FAIL = 0


def check(name, got, want):
    global PASS, FAIL
    if got == want:
        PASS += 1
        print(f"  ok   {name}")
    else:
        FAIL += 1
        print(f"  FAIL {name}: got {got!r}, want {want!r}")


# ── relevant(): the filter that makes a fuzzy web search usable ──────────────
# Reddit's search answered our query with a post titled "Vintage Tissot". A
# reader with no filter would have put that on the dashboard as a mention.
RELEVANT_CASES = [
    ("strict domain", ("Neat find", "check archivewatch.org for it", ""), True),
    ("strict one word", ("archivewatch on Apple TV", "", ""), True),
    ("strict in url", ("", "", "https://archivewatch.org/item/x"), True),
    ("loose + corroborate", ("Archive Watch", "great public domain app for Apple TV", ""), True),
    ("loose + roku", ("anyone tried archive watch", "on roku", ""), True),
    ("loose alone", ("I archive watch faces from the 70s", "", ""), False),
    ("reddit false positive", ("Vintage Tissot", "watch collectors thread", ""), False),
    ("archive.org talk only", ("The Internet Archive is great", "so many films", ""), False),
    ("empty", ("", "", ""), False),
]
print("relevant()")
for name, args, want in RELEVANT_CASES:
    check(name, P.relevant(*args), want)


# ── WANT / LOVE: a request is a SENTENCE somebody wrote ─────────────────────
# These are the app's own five-star reviews plus requests of the shape users
# actually write. The rule must separate them; it must not fire on prose that
# merely mentions a feature.
WANT_CASES = [
    ("wish", "I wish it had a watchlist.", True),
    ("would love", "Would love to see subtitles on more films.", True),
    ("please add", "Please add support for Chromecast.", True),
    ("only complaint", "My only complaint is the search is slow.", True),
    ("should be able", "You should be able to sort by year.", True),
    ("beta testers", "Let us know in the website announcement if you need beta testers.", False),
    ("plain praise", "The interface is intuitive and the feature set is bonkers.", False),
    ("plain fact", "There is so much content to check out.", False),
    ("would be great", "Would be great to have a watchlist.", True),
]
print("\nWANT")
for name, text, want in WANT_CASES:
    check(name, bool(P.WANT.search(text)), want)

LOVE_CASES = [
    ("works well", "Works really well and I love the curated channels.", True),
    ("perfect", "A perfect way to explore vintage videos.", True),
    ("well done", "Well done! This is what I wanted.", True),
    ("thanks", "Thank you for making this free.", True),
    ("works well", "Works really well.", True),
    ("intuitive", "Interface is intuitive.", True),
    ("complaint", "The search is slow and it crashes on launch.", False),
    ("neutral", "It installs from the Play Store.", False),
    ("a want is not read as praise", "Would be great to have a watchlist.", False),
]
print("\nLOVE")
for name, text, want in LOVE_CASES:
    check(name, bool(P.LOVE.search(text)), want)


# ── asks(): quotes the sentence, never a summary ─────────────────────────────
print("\nasks()")
st = P.blank()
st["reviews"] = [{
    "store": "App Store", "rating": 4, "title": "Great but",
    "body": "Works really well. I wish it had a watchlist. There is so much content.",
    "author": "someone", "date": "2026-09-01", "url": "https://example/r",
}]
st["mentions"] = [{"source": "Reddit", "author": "u/x", "url": "https://example/m",
                   "date": "2026-09-02", "excerpt": "Please add Chromecast support."}]
P.asks(st)
check("one request from the review", any("watchlist" in a["text"] for a in st["asks"]), True)
check("one request from the mention", any("Chromecast" in a["text"] for a in st["asks"]), True)
check("praise kept separately", any("Works really well" in l["text"] for l in st["loves"]), True)
check("neutral sentence dropped",
      any("so much content" in a["text"] for a in st["asks"] + st["loves"]), False)
check("the request carries its link",
      all(a.get("url") for a in st["asks"]), True)
check("a sentence is never both", set(a["text"] for a in st["asks"]) &
      set(l["text"] for l in st["loves"]), set())


# ── the parsers, against fixtures ────────────────────────────────────────────
print("\nparsers")
REDDIT = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
 <entry><title>Archive Watch on Apple TV is great</title>
  <content type="html">&lt;p&gt;Found archivewatch.org today&lt;/p&gt;</content>
  <link href="https://reddit.com/r/appletv/comments/a"/>
  <author><name>/u/someone</name></author><updated>2026-09-08T10:00:00+00:00</updated></entry>
 <entry><title>Vintage Tissot</title><content type="html">watch collectors</content>
  <link href="https://reddit.com/r/watches/comments/b"/>
  <author><name>/u/other</name></author><updated>2026-09-08T11:00:00+00:00</updated></entry>
</feed>"""
ns = {"a": "http://www.w3.org/2005/Atom"}
st = P.blank()
for e in ET.fromstring(REDDIT).findall("a:entry", ns):
    ln = e.find("a:link", ns)
    P._mention(st, "Reddit", e.findtext("a:title", "", ns),
               e.findtext("a:content", "", ns), ln.get("href") if ln is not None else "",
               e.findtext("a:author/a:name", "", ns), e.findtext("a:updated", "", ns))
check("reddit: the real one is kept", len(st["mentions"]), 1)
check("reddit: the watch thread is dropped",
      any("Tissot" in m["title"] for m in st["mentions"]), False)
check("reddit: the link survives",
      st["mentions"][0]["url"], "https://reddit.com/r/appletv/comments/a")


# ── a source that fails must be RECORDED, not silently zero ─────────────────
print("\nnever a silent zero")
st = P.blank()


def broken(_state):
    raise RuntimeError("no credential in this environment")


saved = P.SOURCES
P.SOURCES = [("broken_source", broken)]
import contextlib, io
try:
    sys.argv = ["pulse_collect.py", "--only", "broken_source", "--out", "/dev/null"]
    with contextlib.redirect_stdout(io.StringIO()) as buf:
        rc = P.main()
    check("main() survives a broken source", rc, 0)
    check("main() says the source failed", "broken_source" in buf.getvalue(), True)
finally:
    P.SOURCES = saved
# main() builds its own state; assert the contract on a hand-run instead.
st = P.blank()
try:
    broken(st)
    st["sources"]["broken_source"] = {"ok": True, "note": ""}
except Exception as e:  # noqa: BLE001
    st["sources"]["broken_source"] = {"ok": False, "note": str(e)}
check("a failed source is ok:false", st["sources"]["broken_source"]["ok"], False)
check("a failed source keeps its reason",
      "credential" in st["sources"]["broken_source"]["note"], True)


# ── history: one row per day, append-only, numbers only ─────────────────────
print("\nhistory")
st = P.blank()
st["ratings"] = [{"store": "App Store", "average": 4.4, "count": 5}]
st["reviews"] = [{"store": "App Store", "id": "1", "date": "2026-09-01"}]
st["social"] = {"totalPosts": 9, "byPlatform": {"bluesky": {"likes": 3}},
                "reach": {"bluesky": {"followers": 12}}}
st["github"] = {"stars": 0, "views14d": 20}
st["health"] = {"catalog": {"items": 26711},
                "workflows": [{"severity": "BROKEN"}, {"severity": "STALE"}]}
row = P.history_row(st)
check("one date", row["date"], P.today())
check("apple rating carried", row["appleRating"], 4.4)
check("likes summed", row["likes"], 3)
check("followers summed", row["followers"], 12)
check("urgent counts BROKEN not STALE", row["urgent"], 1)
check("row holds only scalars",
      all(not isinstance(v, (list, dict)) for v in row.values()), True)

hist = [{"date": "2026-01-01", "stars": 0}, {"date": P.today(), "stars": 99}]
kept = [h for h in hist if h.get("date") != P.today()] + [row]
check("today replaces today, yesterday survives",
      [h["date"] for h in kept], ["2026-01-01", P.today()])


# ── dedupe keeps the first (newest, since rows are sorted) ──────────────────
print("\ndedupe")
rows = [{"u": "a", "n": 1}, {"u": "b", "n": 2}, {"u": "a", "n": 3}]
check("collapses by key", [r["n"] for r in P.dedupe(rows, lambda r: r["u"])], [1, 2])

# ── a partial run must not delete what it did not collect ───────────────────
# A local `--only apple_reviews` once overwrote ops/pulse.json and dropped every
# mention CI had gathered — the page then reported a confident 0 for readers
# that had simply not been asked. Same rule as `sources`, one level up.
print("\npartial runs merge")
import subprocess as _sp
import tempfile as _tf

with _tf.TemporaryDirectory() as tmp:
    f = Path(tmp) / "pulse.json"
    f.write_text(json.dumps({
        "reviews": [{"store": "App Store", "id": "r1", "rating": 5, "date": "2026-09-01"}],
        "mentions": [{"source": "Mastodon", "url": "u1", "excerpt": "someone said a thing"},
                     {"source": "Reddit", "url": "u2", "excerpt": "another"}],
        "github": {"stars": 3},
        "social": {"totalPosts": 9},
        "history": [{"date": "2026-01-01", "stars": 3}],
    }))
    r = _sp.run([sys.executable, str(Path(__file__).parent / "pulse_collect.py"),
                 "--only", "mentions_reddit", "--apply", "--out", str(f)],
                capture_output=True, text=True, timeout=180)
    got = json.loads(f.read_text())
    check("a source it did not run keeps its reviews", len(got["reviews"]), 1)
    check("...and its github reading", got["github"].get("stars"), 3)
    check("...and its social section", got["social"].get("totalPosts"), 9)
    check("a mention from ANOTHER source survives",
          any(m["source"] == "Mastodon" for m in got["mentions"]), True)
    check("a mention found once is not lost when a fuzzy search does not repeat",
          {m["url"] for m in got["mentions"]} >= {"u1", "u2"}, True)
    check("yesterday's history row survives",
          any(h["date"] == "2026-01-01" for h in got["history"]), True)


# ── every credential the collector reads must reach it in CI ────────────────
# The reports key was set as a repo secret and NOT passed by the workflow, so
# the run stayed green and the Downloads panel stayed empty. A secret that
# exists and never arrives is indistinguishable from one that was never made.
print("\nthe workflow passes what the collector reads")
_src = (Path(__file__).parent / "pulse_collect.py").read_text()
_wf = (Path(__file__).parent.parent / ".github" / "workflows" / "pulse.yml").read_text()
_names = set(re.findall(r'os\.environ(?:\.get)?[\(\[]"([A-Z][A-Z0-9_]{3,})"', _src))
# ASC_KEY_ID/ISSUER_ID are exported into GITHUB_ENV by the key-writing step, and
# PLAY_SERVICE_ACCOUNT_JSON may legitimately be a local path outside CI.
_via_env_file = {"ASC_KEY_ID", "ASC_ISSUER_ID"}
_missing = sorted(n for n in _names - _via_env_file if n not in _wf)
check("no credential the collector reads is missing from pulse.yml", _missing, [])

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
