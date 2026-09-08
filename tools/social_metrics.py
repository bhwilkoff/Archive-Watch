#!/usr/bin/env python3
"""
social_metrics.py — read the numbers back off each platform.

The programme has been posting blind. This is the instrument: for every row in
`social/posted.json` it asks the platform that holds the post how it did, and
appends the reading to `social/metrics.json`.

Three decisions worth knowing:

* **Sample twice, at 24h and 7d.** An early number and a settled one answer
  different questions — the first says whether the post caught its hour, the
  second whether it kept travelling. One sample cannot say both.

* **Never fatal, ever.** A platform that will not answer costs one printed
  line. Measurement exists to inform the programme, not to stop it, and a
  metrics failure must never fail the run that posts.

* **The conclusions wait.** `--report` refuses to rank a bucket holding fewer
  than MIN_N posts. With a handful of posts and single-digit likes, any
  ranking is noise wearing a table's clothes, and reading trends out of that
  is how a programme talks itself into nonsense.

It also REPAIRS a ledger permalink while it is there: the Meta adapters used
to construct instagram.com/p/<media-id>, which is not a permalink, and the
`permalink` field is fetched here anyway.

Run:
  python3 tools/social_metrics.py                 # sample, print, write nothing
  python3 tools/social_metrics.py --apply         # sample and write
  python3 tools/social_metrics.py --report        # what the numbers say so far
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import statistics
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LEDGER = REPO / "social" / "posted.json"
METRICS = REPO / "social" / "metrics.json"
UA = "ArchiveWatch/1.0 (+https://archivewatch.org)"

# A row is sampled once at each window. 20h/6d rather than 24h/7d so a daily
# cron reaches every window instead of missing it by minutes.
WINDOWS = [("24h", 20.0), ("7d", 144.0)]
MIN_N = 10          # below this, a ranking is noise


def http(url: str, timeout: int = 30) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


# --------------------------------------------------------------------------
# Per-platform readers. Each returns a dict of counts, or None if it cannot
# answer. None is a normal outcome — a deleted post, a token that expired, a
# platform having a bad afternoon.
# --------------------------------------------------------------------------

def read_bluesky(url: str) -> dict | None:
    """bsky.app/profile/<handle>/post/<rkey> -> the post's own counts.

    Public: no token. The handle must be resolved to a DID first because an
    at:// URI addresses the repository, not the name pointing at it — and a
    handle can change while the DID cannot.
    """
    parts = urllib.parse.urlparse(url).path.strip("/").split("/")
    if len(parts) < 4 or parts[0] != "profile":
        return None
    handle, rkey = parts[1], parts[3]
    api = "https://public.api.bsky.app/xrpc"
    did = http(f"{api}/com.atproto.identity.resolveHandle"
               f"?handle={urllib.parse.quote(handle)}").get("did")
    if not did:
        return None
    uri = f"at://{did}/app.bsky.feed.post/{rkey}"
    posts = http(f"{api}/app.bsky.feed.getPosts"
                 f"?uris={urllib.parse.quote(uri, safe='')}").get("posts") or []
    if not posts:
        return None
    p = posts[0]
    return {"likes": p.get("likeCount"), "reposts": p.get("repostCount"),
            "replies": p.get("replyCount"), "quotes": p.get("quoteCount")}


def read_mastodon(url: str) -> dict | None:
    """instance/@user/<id> -> the status. Public statuses need no token."""
    u = urllib.parse.urlparse(url)
    sid = u.path.rstrip("/").rsplit("/", 1)[-1]
    if not sid.isdigit():
        return None
    d = http(f"{u.scheme}://{u.netloc}/api/v1/statuses/{sid}")
    return {"likes": d.get("favourites_count"), "reposts": d.get("reblogs_count"),
            "replies": d.get("replies_count")}


def _meta_id(url: str) -> str | None:
    tail = urllib.parse.urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    return tail if tail.isdigit() else None


def read_threads(url: str) -> tuple[dict | None, str | None]:
    token = os.environ.get("THREADS_ACCESS_TOKEN")
    mid = _meta_id(url)
    if not (token and mid):
        return None, None
    api = "https://graph.threads.net/v1.0"
    q = urllib.parse.quote(token)
    perma = http(f"{api}/{mid}?fields=permalink&access_token={q}").get("permalink")
    ins = http(f"{api}/{mid}/insights"
               f"?metric=views,likes,replies,reposts,quotes&access_token={q}")
    got = {}
    for row in ins.get("data") or []:
        vals = row.get("values") or [{}]
        got[row.get("name")] = vals[0].get("value")
    return (got or None), perma


def read_instagram(url: str) -> tuple[dict | None, str | None]:
    token = os.environ.get("IG_ACCESS_TOKEN")
    mid = _meta_id(url)
    if not (token and mid):
        return None, None
    api = "https://graph.instagram.com/v21.0"
    q = urllib.parse.quote(token)
    d = http(f"{api}/{mid}?fields=like_count,comments_count,permalink"
             f"&media_type&access_token={q}")
    got = {"likes": d.get("like_count"), "replies": d.get("comments_count")}
    try:
        ins = http(f"{api}/{mid}/insights?metric=views,reach&access_token={q}")
        for row in ins.get("data") or []:
            got[row.get("name")] = (row.get("values") or [{}])[0].get("value")
    except (urllib.error.HTTPError, urllib.error.URLError, OSError):
        pass                     # insights are not offered on every media type
    return got, d.get("permalink")


def read_youtube(url: str) -> dict | None:
    """statistics need OAuth here: this channel has no public API key, and the
    refresh token the poster uses is already in the environment."""
    vid = urllib.parse.parse_qs(urllib.parse.urlparse(url).query).get("v", [None])[0]
    cid = os.environ.get("YOUTUBE_CLIENT_ID")
    sec = os.environ.get("YOUTUBE_CLIENT_SECRET")
    ref = os.environ.get("YOUTUBE_REFRESH_TOKEN")
    if not (vid and cid and sec and ref):
        return None
    body = urllib.parse.urlencode({"client_id": cid, "client_secret": sec,
                                   "refresh_token": ref,
                                   "grant_type": "refresh_token"}).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body,
                                 headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        tok = json.loads(r.read().decode())["access_token"]
    req = urllib.request.Request(
        f"https://www.googleapis.com/youtube/v3/videos?part=statistics&id={vid}",
        headers={"Authorization": f"Bearer {tok}", "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        items = json.loads(r.read().decode()).get("items") or []
    if not items:
        return None
    st = items[0].get("statistics") or {}
    return {"views": int(st.get("viewCount", 0)),
            "likes": int(st.get("likeCount", 0)),
            "replies": int(st.get("commentCount", 0))}


def sample(row: dict) -> tuple[dict | None, str | None]:
    plat, url = row.get("platform"), row.get("url") or ""
    try:
        if plat == "bluesky":
            return read_bluesky(url), None
        if plat == "mastodon":
            return read_mastodon(url), None
        if plat == "threads":
            return read_threads(url)
        if plat == "instagram":
            return read_instagram(url)
        if plat == "youtube":
            return read_youtube(url), None
    except Exception as e:  # noqa: BLE001
        print(f"  {plat}: could not read ({e})")
    return None, None


def hours_since(iso: str) -> float:
    try:
        at = dt.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return -1.0
    if at.tzinfo is None:
        at = at.replace(tzinfo=dt.timezone.utc)
    return (dt.datetime.now(dt.timezone.utc) - at).total_seconds() / 3600.0


def due(row: dict, seen: set) -> str | None:
    age = hours_since(row.get("at", ""))
    if age < 0:
        return None
    for name, after in WINDOWS:
        if age >= after and (row.get("url"), name) not in seen:
            return name
    return None


# --------------------------------------------------------------------------

def report(samples: list) -> None:
    """What the numbers say — and, far more often at this stage, that they do
    not yet say anything."""
    latest = {}
    for s in samples:                       # last reading per post wins
        latest[s["url"]] = s
    rows = list(latest.values())
    print(f"\n{len(rows)} posts measured\n")

    def engagement(s):
        m = s.get("metrics") or {}
        return sum(v for k, v in m.items()
                   if k in ("likes", "replies", "reposts", "quotes")
                   and isinstance(v, int))

    for field, label in (("platform", "platform"), ("slot", "slot"),
                         ("format", "format")):
        buckets = defaultdict(list)
        for s in rows:
            buckets[s.get(field) or "?"].append(engagement(s))
        print(f"by {label}:")
        for key, vals in sorted(buckets.items(), key=lambda kv: -statistics.mean(kv[1] or [0])):
            note = "" if len(vals) >= MIN_N else f"   (n={len(vals)} — too few to rank)"
            print(f"  {key:<14} mean {statistics.mean(vals or [0]):6.1f}"
                  f"  n={len(vals)}{note}")
        print()
    if len(rows) < MIN_N:
        print(f"Fewer than {MIN_N} posts measured. Nothing here is a finding "
              f"yet — the instrument is running, the conclusions wait.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ledger", default=str(LEDGER))
    ap.add_argument("--out", default=str(METRICS))
    ap.add_argument("--apply", action="store_true", help="write the readings")
    ap.add_argument("--report", action="store_true", help="print the ranking")
    ap.add_argument("--all", action="store_true",
                    help="sample every row, not only the ones that are due")
    args = ap.parse_args()

    ledger = json.loads(Path(args.ledger).read_text(encoding="utf-8"))
    posts = ledger.get("posts") or []
    store = ({"_": "Readings taken by tools/social_metrics.py. One row per "
                   "post per window; the ledger is the source of what was "
                   "posted, this is only what happened next.", "samples": []}
             if not Path(args.out).exists()
             else json.loads(Path(args.out).read_text(encoding="utf-8")))
    samples = store.setdefault("samples", [])
    seen = {(s.get("url"), s.get("window")) for s in samples}

    now = dt.datetime.now(dt.timezone.utc).isoformat()
    taken = repaired = 0
    for row in posts:
        window = "adhoc" if args.all else due(row, seen)
        if not window:
            continue
        got, perma = sample(row)
        if perma and perma != row.get("url"):
            # The ledger drives the public feed, so a URL that goes nowhere is
            # a broken link for every reader. Correct it while we are here.
            print(f"  {row['platform']}: permalink corrected -> {perma}")
            row["url"] = perma
            repaired += 1
        if got is None:
            continue
        taken += 1
        print(f"  {row['platform']:<10} {window:<5} {got}")
        samples.append({"url": row.get("url"), "platform": row.get("platform"),
                        "id": row.get("id"), "slot": row.get("slot"),
                        "format": row.get("format"), "window": window,
                        "posted": row.get("at"), "sampled": now,
                        "metrics": got})

    print(f"\n{taken} reading(s), {repaired} permalink(s) corrected")
    if args.apply:
        Path(args.out).write_text(json.dumps(store, indent=1) + "\n",
                                  encoding="utf-8")
        if repaired:
            Path(args.ledger).write_text(json.dumps(ledger, indent=1) + "\n",
                                         encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        print("(nothing written — pass --apply)")
    if args.report:
        report(samples)
    return 0


if __name__ == "__main__":
    sys.exit(main())
