#!/usr/bin/env python3
"""
pulse_collect.py — one place that knows how Archive Watch is doing.

Reads every channel the project actually has a route to — the three Apple
platforms, Play, the social programme, the open web — and writes ONE file,
`ops/pulse.json`, that the /pulse page renders. Run daily from CI.

Three rules the whole tool is built on:

* **A source that will not answer costs one line, never the run.** Every
  collector is wrapped; a failure is recorded as a note IN the output, so the
  page can say "Play: no credential in CI" instead of showing a confident zero.
  A dashboard that silently reports 0 for a broken reader is worse than no
  dashboard, because it reads as good news.

* **Numbers are kept; text is capped.** `history` holds one compact row per
  day forever (that is the whole point — progress over time). Reviews and
  mentions are capped, newest first, because they are a window and not an
  archive.

* **A request is QUOTED, never summarized.** `asks` extracts the sentence a
  person actually wrote and links to it. There is no model in this loop and
  no sentiment score: the owner reads what a user said, in their words.

Run:
  python3 tools/pulse_collect.py                 # collect, print, write nothing
  python3 tools/pulse_collect.py --apply         # write ops/pulse.json
  python3 tools/pulse_collect.py --only apple_reviews,mentions_hn
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "ops" / "pulse.json"

APPLE_APP_ID = "6776697407"
PLAY_PACKAGE = "com.archivewatch.app"
GH_REPO = "bhwilkoff/Archive-Watch"

UA = "ArchiveWatchPulse/1.0 (+https://archivewatch.org)"

# What we are looking for when we search the open web. Deliberately narrow:
# "archive watch" as two words matches a great deal of unrelated talk about
# the Internet Archive, so a hit must carry one of the STRICT terms, or the
# loose term AND a corroborating word.
STRICT = ("archivewatch.org", "archivewatch", "archive watch app")
LOOSE = "archive watch"
CORROBORATE = ("apple tv", "tvos", "roku", "fire tv", "android tv", "public domain",
               "internet archive", "app store", "google play", "sideload", "streaming app")

MAX_REVIEWS = 200
MAX_MENTIONS = 150
MAX_HISTORY = 800          # ~2 years of daily rows


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def today() -> str:
    return dt.datetime.now(dt.timezone.utc).date().isoformat()


def get(url, headers=None, timeout=25):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def get_json(url, headers=None, timeout=25):
    return json.loads(get(url, headers, timeout).decode("utf-8", "replace"))


def clamp(s, n):
    s = re.sub(r"\s+", " ", (s or "")).strip()
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def relevant(*fields) -> bool:
    """Does this text plausibly talk about US, and not about the Archive at large?"""
    blob = " ".join(f for f in fields if f).lower()
    if any(t in blob for t in STRICT):
        return True
    if LOOSE in blob and any(c in blob for c in CORROBORATE):
        return True
    return False


# ─────────────────────────────────────────────────────────────── Apple

def _asc():
    sys.path.insert(0, str(REPO / "tools"))
    import asc_release  # noqa: E402  (needs the env vars loaded first)
    return asc_release


def apple_stores(state):
    """Where each of the three Apple platforms stands right now."""
    A = _asc()
    aid = A.app_id()
    mv, bn = A.repo_version()
    rows = []
    for platform, label in (("TV_OS", "Apple TV"), ("IOS", "iPhone & iPad"), ("MAC_OS", "Mac")):
        vs = A.versions(aid, platform)
        if not vs:
            continue
        # The live one is READY_FOR_SALE; anything else is the one in flight.
        live = next((v for v in vs if v["attributes"]["appStoreState"] == "READY_FOR_SALE"), None)
        flight = next((v for v in vs if v["attributes"]["appStoreState"] != "READY_FOR_SALE"), None)
        cur = flight or live
        rows.append({
            "store": "App Store",
            "platform": label,
            "state": cur["attributes"]["appStoreState"] if cur else "NONE",
            "version": cur["attributes"]["versionString"] if cur else None,
            "live": live["attributes"]["versionString"] if live else None,
            "repoVersion": mv,
            "repoBuild": bn,
            "url": f"https://appstoreconnect.apple.com/apps/{aid}/distribution",
        })
    state["stores"] += rows
    return f"{len(rows)} Apple platform(s)"


def apple_reviews(state):
    """Every customer review, all territories, newest first."""
    A = _asc()
    aid = A.app_id()
    out, cursor, pages = [], None, 0
    while pages < 6:
        ep = (f"v1/apps/{aid}/customerReviews?limit=200&sort=-createdDate"
              "&include=response")
        if cursor:
            ep += f"&cursor={urllib.parse.quote(cursor)}"
        d = A.call(ep)
        replies = {i["id"]: i for i in d.get("included", []) if i["type"] == "customerReviewResponses"}
        for r in d.get("data", []):
            a = r["attributes"]
            rid = ((r.get("relationships") or {}).get("response") or {}).get("data") or {}
            out.append({
                "store": "App Store",
                "id": r["id"],
                "rating": a.get("rating"),
                "title": clamp(a.get("title"), 120),
                "body": clamp(a.get("body"), 1200),
                "author": a.get("reviewerNickname"),
                "territory": a.get("territory"),
                "date": a.get("createdDate"),
                "responded": bool(replies.get(rid.get("id"))),
                "url": f"https://appstoreconnect.apple.com/apps/{aid}/distribution/reviews",
            })
        cursor = ((d.get("links") or {}).get("next") or "")
        cursor = urllib.parse.parse_qs(urllib.parse.urlparse(cursor).query).get("cursor", [None])[0]
        pages += 1
        if not cursor:
            break
    state["reviews"] += out
    return f"{len(out)} review(s)"


def apple_rating(state):
    """The public ratings summary — no auth, so it works anywhere."""
    d = get_json(f"https://itunes.apple.com/lookup?id={APPLE_APP_ID}&country=us")
    if not d.get("resultCount"):
        raise RuntimeError("iTunes lookup returned no result")
    r = d["results"][0]
    state["ratings"].append({
        "store": "App Store",
        "average": r.get("averageUserRating"),
        "count": r.get("userRatingCount"),
        "version": r.get("version"),
        "releasedAt": r.get("currentVersionReleaseDate"),
        "url": r.get("trackViewUrl"),
    })
    return f"{r.get('averageUserRating')} from {r.get('userRatingCount')}"


# ─────────────────────────────────────────────────────────────── Google Play

def _play():
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    key = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON",
                         os.path.expanduser("~/.config/play/archivewatch-play.json"))
    if key.strip().startswith("{"):          # the secret may arrive as JSON itself
        info = json.loads(key)
        creds = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    else:
        if not os.path.exists(key):
            raise RuntimeError("no Play service-account key (set PLAY_SERVICE_ACCOUNT_JSON)")
        creds = service_account.Credentials.from_service_account_file(
            key, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def play_stores(state):
    svc = _play()
    ed = svc.edits().insert(packageName=PLAY_PACKAGE, body={}).execute()
    try:
        tracks = svc.edits().tracks().list(packageName=PLAY_PACKAGE, editId=ed["id"]).execute()
    finally:
        try:
            svc.edits().delete(packageName=PLAY_PACKAGE, editId=ed["id"]).execute()
        except Exception:
            pass
    rows = []
    for t in tracks.get("tracks", []):
        rel = (t.get("releases") or [{}])[0]
        if not rel.get("status"):
            continue
        rows.append({
            "store": "Google Play",
            "platform": t["track"].title(),
            "state": (rel.get("status") or "").upper(),
            "version": rel.get("name"),
            "live": rel.get("name") if rel.get("status") == "completed" else None,
            "build": ", ".join(rel.get("versionCodes") or []),
            "url": f"https://play.google.com/console/developers/app/{PLAY_PACKAGE}",
        })
    state["stores"] += rows
    return f"{len(rows)} track(s)"


def play_reviews(state):
    """Play only serves reviews from roughly the last week — an empty answer is
    normal, and is NOT the same as 'no reviews exist'."""
    svc = _play()
    r = svc.reviews().list(packageName=PLAY_PACKAGE, maxResults=100).execute()
    out = []
    for v in r.get("reviews", []):
        c = (v.get("comments") or [{}])[0].get("userComment", {}) or {}
        dev = any("developerComment" in c2 for c2 in v.get("comments", []))
        ts = c.get("lastModified", {}).get("seconds")
        out.append({
            "store": "Google Play",
            "id": v.get("reviewId"),
            "rating": c.get("starRating"),
            "title": "",
            "body": clamp(c.get("text"), 1200),
            "author": v.get("authorName"),
            "territory": (c.get("reviewerLanguage") or "").upper(),
            "date": dt.datetime.fromtimestamp(int(ts), dt.timezone.utc).isoformat() if ts else None,
            "responded": dev,
            "device": c.get("device"),
            "appVersion": c.get("appVersionName"),
            "url": f"https://play.google.com/console/developers/app/{PLAY_PACKAGE}/user-feedback",
        })
    state["reviews"] += out
    return f"{len(out)} review(s) in Play's 7-day window"


def _reporting():
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    key = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON",
                         os.path.expanduser("~/.config/play/archivewatch-play.json"))
    scopes = ["https://www.googleapis.com/auth/playdeveloperreporting"]
    if key.strip().startswith("{"):
        creds = service_account.Credentials.from_service_account_info(json.loads(key), scopes=scopes)
    else:
        if not os.path.exists(key):
            raise RuntimeError("no Play service-account key")
        creds = service_account.Credentials.from_service_account_file(key, scopes=scopes)
    return build("playdeveloperreporting", "v1beta1", credentials=creds, cache_discovery=False)


def _window(days=28):
    end = dt.date.today()
    start = end - dt.timedelta(days=days)
    return start, end


def play_vitals(state):
    """Crash and ANR rate — the signal that says something needs fixing before a
    user bothers to write it down.

    The metric set ADVERTISES the window it actually holds, and querying past it
    is a 400 that reads like a malformed request. Ask, then query to that date;
    never guess at 'today'."""
    svc = _reporting()
    got, errs, notes = {}, [], []
    for res, metric, mset in (("crashrate", "crashRate", "crashRateMetricSet"),
                              ("anrrate", "anrRate", "anrRateMetricSet")):
        api = getattr(svc.vitals(), res)()
        try:
            fresh = api.get(name=f"apps/{PLAY_PACKAGE}/{mset}").execute()
            daily = next((f for f in (fresh.get("freshnessInfo") or {}).get("freshnesses", [])
                          if f.get("aggregationPeriod") == "DAILY"), None)
            if not daily:
                notes.append(f"{metric}: Play reports no daily window yet")
                continue
            le = daily["latestEndTime"]
            end = dt.date(le["year"], le["month"], le["day"])
        except Exception as e:                       # noqa: BLE001
            errs.append(f"{metric}: {str(e)[:90]}")
            continue
        begin = end - dt.timedelta(days=27)
        body = {"timelineSpec": {"aggregationPeriod": "DAILY",
                                 "startTime": {"year": begin.year, "month": begin.month,
                                               "day": begin.day},
                                 "endTime": {"year": end.year, "month": end.month,
                                             "day": end.day}},
                "metrics": [metric]}
        try:
            d = api.query(name=f"apps/{PLAY_PACKAGE}/{mset}", body=body).execute()
            vals = [float(m["decimalValue"]["value"])
                    for r in d.get("rows", []) for m in r.get("metrics", [])
                    if m.get("metric") == metric and m.get("decimalValue")]
            if vals:
                got[metric] = round(sum(vals) / len(vals), 5)
                got[metric + "Days"] = len(vals)
            else:
                # Play withholds a rate below a minimum audience. That is a real
                # answer about the app's size, not a broken reader.
                notes.append(f"{metric}: too few users for Play to publish a rate")
        except Exception as e:                       # noqa: BLE001
            errs.append(f"{metric}: {str(e)[:90]}")
    state["health"]["playVitals"] = got
    if notes:
        state["health"]["playVitalsNote"] = "; ".join(notes)
    if errs and not got:
        raise RuntimeError("; ".join(errs))
    return (", ".join(f"{k}={v}" for k, v in got.items() if not k.endswith("Days"))
            or "; ".join(notes) or "no data yet")


def play_crashes(state):
    """The actual crash clusters, worst first — a named stack beats a rate.

    And the axis that decides whether one MATTERS: the last build it was seen
    on, against the build in production. Two clusters here account for 15 of the
    24 affected users and were last seen on build 34 against a live build of 54
    — reporting those as urgent is how a dashboard trains its reader to ignore
    it. Each cluster carries `stale`, and the page acts on it."""
    svc = _reporting()
    start, end = _window()
    iv = {"interval_startTime_year": start.year, "interval_startTime_month": start.month,
          "interval_startTime_day": start.day,
          "interval_endTime_year": end.year, "interval_endTime_month": end.month,
          "interval_endTime_day": end.day}
    d = svc.vitals().errors().issues().search(
        parent=f"apps/{PLAY_PACKAGE}", pageSize=20, orderBy="distinctUsers desc",
        sampleErrorReportLimit=1, **iv).execute()

    live_vc = None                                   # the build actually in production
    for row in state.get("stores", []):
        if row.get("store") == "Google Play" and (row.get("platform") or "").lower() == "production":
            try:
                live_vc = int((row.get("build") or "").split(",")[0])
            except (TypeError, ValueError):
                pass
    rows = []
    for i in d.get("errorIssues", []):
        last_vc = i.get("lastAppVersion", {}).get("versionCode")
        try:
            last_vc = int(last_vc)
        except (TypeError, ValueError):
            last_vc = None
        stale = bool(live_vc and last_vc and last_vc < live_vc)
        rows.append({
            "type": i.get("type"), "cause": clamp(i.get("cause"), 160),
            "location": clamp(i.get("location"), 160),
            "users": int(i.get("distinctUsers") or 0),
            "reports": int(i.get("errorReportCount") or 0),
            "lastSeen": i.get("lastErrorReportTime"),
            "firstBuild": i.get("firstAppVersion", {}).get("versionCode"),
            "lastBuild": str(last_vc) if last_vc is not None else None,
            "api": f"{i.get('firstOsVersion', {}).get('apiLevel')}"
                   f"-{i.get('lastOsVersion', {}).get('apiLevel')}",
            "stale": stale,
            "url": i.get("issueUri"),
            "fixedIn": _fixed_in(i.get("issueUri")),
            "ours": _our_frame(svc, i, iv),
        })
    state["health"]["playCrashes"] = rows
    state["health"]["playLiveBuild"] = live_vc
    fresh = [r for r in rows if not r["stale"]]
    return (f"{len(rows)} cluster(s), {len(fresh)} still on build {live_vc}"
            if live_vc else f"{len(rows)} cluster(s)")


_FIXED: dict | None = None


def _fixed_in(issue_uri):
    """Has this cluster's CAUSE already been fixed in the repo?

    A crash with a fix in hand is a different thing from one nobody has looked
    at — the action is no longer "fix it", it is "ship it" — and a dashboard
    that cannot tell those apart asks for the same work twice. `ops/fixed-in.json`
    records the build that carries the fix; the page compares it to what is
    actually in production."""
    global _FIXED
    if _FIXED is None:
        try:
            _FIXED = json.loads((REPO / "ops" / "fixed-in.json").read_text()).get("clusters", {})
        except (OSError, ValueError):
            _FIXED = {}
    cid = (issue_uri or "").rstrip("/").split("/")[-2] if "/details" in (issue_uri or "") \
        else (issue_uri or "").rstrip("/").split("/")[-1]
    return _FIXED.get(cid)


def _our_frame(svc, issue, iv):
    """The first line of the stack that is OUR code, which is the whole
    difference between 'Compose threw' and 'this list has a duplicate key'."""
    try:
        rep = svc.vitals().errors().reports().search(
            parent=f"apps/{PLAY_PACKAGE}", pageSize=1,
            filter=f'errorIssueId = "{issue["name"].split("/")[-1]}"', **iv).execute()
    except Exception:                                # noqa: BLE001
        return None
    for r in rep.get("errorReports", [])[:1]:
        text = r.get("reportText") or ""
        head = next((ln.strip() for ln in text.splitlines()
                     if ln.strip().startswith("Exception ")), None)
        mine = next((ln.strip() for ln in text.splitlines()
                     if "app.archivewatch" in ln), None)
        return clamp(" · ".join(x for x in (head, mine) if x), 300) or None
    return None


# Play's dimensions, in the order they are worth reading. Every one of these is
# ACCEPTED by the API today and returns nothing, because Play withholds a
# per-dimension figure below a minimum audience — the readers are proven, the
# audience is not there yet, and those are very different sentences.
PLAY_DIMENSIONS = ("countryCode", "deviceModel", "deviceBrand", "versionCode",
                   "apiLevel", "deviceType", "deviceRamBucket")


def play_users(state):
    """Distinct users per day, and the same split every way Play allows.

    This is the usage number Android has been missing. It comes off the same
    metric set as the crash rate — `distinctUsers` is a metric there, not a
    separate API — so it costs one more query and no new credential."""
    svc = _reporting()
    api = svc.vitals().crashrate()
    fresh = api.get(name=f"apps/{PLAY_PACKAGE}/crashRateMetricSet").execute()
    daily = next((f for f in (fresh.get("freshnessInfo") or {}).get("freshnesses", [])
                  if f.get("aggregationPeriod") == "DAILY"), None)
    if not daily:
        raise RuntimeError("Play reports no daily window yet")
    le = daily["latestEndTime"]
    end = dt.date(le["year"], le["month"], le["day"])
    begin = end - dt.timedelta(days=27)

    def q(dims=None):
        body = {"timelineSpec": {"aggregationPeriod": "DAILY",
                                 "startTime": {"year": begin.year, "month": begin.month,
                                               "day": begin.day},
                                 "endTime": {"year": end.year, "month": end.month,
                                             "day": end.day}},
                "metrics": ["distinctUsers"]}
        if dims:
            body["dimensions"] = list(dims)
        return api.query(name=f"apps/{PLAY_PACKAGE}/crashRateMetricSet", body=body).execute()

    def val(row):
        m = (row.get("metrics") or [{}])[0]
        try:
            return float(m.get("decimalValue", {}).get("value") or 0)
        except (TypeError, ValueError):
            return 0.0

    series = []
    for r in q().get("rows", []):
        t = r.get("startTime", {})
        series.append({"date": f"{t.get('year')}-{t.get('month'):02d}-{t.get('day'):02d}",
                       "users": round(val(r), 1)})
    breakdown = {}
    for dim in PLAY_DIMENSIONS:
        try:
            agg = {}
            for r in q([dim]).get("rows", []):
                d0 = (r.get("dimensions") or [{}])[0]
                k = d0.get("stringValue") or d0.get("int64Value") or d0.get("valueLabel")
                if k is None:
                    continue
                agg[str(k)] = round(agg.get(str(k), 0) + val(r), 1)
            if agg:
                breakdown[dim] = dict(sorted(agg.items(), key=lambda kv: -kv[1])[:12])
        except Exception:                            # noqa: BLE001 — one dimension, never the run
            continue
    state["health"]["playUsers"] = {"daily": series, "byDimension": breakdown,
                                    "window": f"{begin.isoformat()}..{end.isoformat()}"}
    if not series and not breakdown:
        return ("every dimension query was accepted and returned nothing — "
                "Play withholds per-user figures below a minimum audience")
    return f"{len(series)} day(s) of users, {len(breakdown)} dimension(s)"


PLAY_REPORT_FILES = ("overview", "country", "device", "os_version",
                     "app_version", "language", "carrier")


def _gcs_bytes(bucket, obj):
    """Read one object as the service account, falling back to the owner's
    gcloud. Play grants bucket access through the CONSOLE, and that grant takes
    hours to reach the bucket's ACLs — so a freshly-permitted service account
    reads 403 while `gcloud` (already the account owner) reads fine. The
    fallback is local-only by nature and simply does not fire in CI."""
    from google.oauth2 import service_account
    from googleapiclient.discovery import build as _build
    key = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON",
                         os.path.expanduser("~/.config/play/archivewatch-play.json"))
    scopes = ["https://www.googleapis.com/auth/devstorage.read_only"]
    try:
        if key.strip().startswith("{"):
            creds = service_account.Credentials.from_service_account_info(json.loads(key), scopes=scopes)
        else:
            creds = service_account.Credentials.from_service_account_file(key, scopes=scopes)
        gcs = _build("storage", "v1", credentials=creds, cache_discovery=False)
        return gcs.objects().get_media(bucket=bucket, object=obj).execute(), "service account"
    except Exception:                                # noqa: BLE001
        pass
    try:
        out = subprocess.run(["gcloud", "storage", "cat", f"gs://{bucket}/{obj}"],
                             capture_output=True, timeout=120)
        if out.returncode == 0 and out.stdout:
            return out.stdout, "gcloud"
    except Exception:                                # noqa: BLE001
        pass
    return None, None


def _play_csv(raw):
    """Play writes these as UTF-16 with a BOM, which reads as mojibake if you
    assume UTF-8 and produces a header nothing matches."""
    import csv
    import gzip
    import io
    # The objects are stored gzip-encoded. `gcloud storage cp` decompresses on
    # download and `cat` does NOT, so the same file arrives either way depending
    # on how it was fetched — and gzipped bytes parse as a one-column CSV of
    # mojibake rather than failing, which is why this cost a debugging round.
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        text = raw.decode("utf-16", "ignore")
    else:
        text = raw.decode("utf-8-sig", "replace")
    # Normalise the line endings BEFORE the reader sees them: these files are
    # UTF-16 with CRLF, and a stray CR inside a decoded field makes csv report
    # "new-line character seen in unquoted field" for the whole file.
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return list(csv.DictReader(io.StringIO(text)))


def play_reports(state):
    """Installs, uninstalls, active devices and their splits, from the Play
    Console's Cloud Storage reports bucket.

    This is the robust half of Play's data and it is in NO API: the Console
    writes monthly CSVs to `gs://pubsite_prod_rev_<id>/stats/`, and unlike the
    Reporting API they carry no minimum-audience threshold — which is why
    installs are readable here while `distinctUsers` is withheld.

    The bucket id is NOT the developer id in the Console URL and cannot be
    derived from it; the Console names it under Download reports -> Statistics
    ("Copy Cloud Storage URI"). The bucket also holds OTHER apps' reports, so
    every object name is package-scoped."""
    bucket = os.environ.get("PLAY_REPORTS_BUCKET", "").strip().replace("gs://", "").strip("/").split("/")[0]
    if not bucket:
        raise RuntimeError("set PLAY_REPORTS_BUCKET (Play Console -> Download reports "
                           "-> Statistics -> Copy Cloud Storage URI)")
    today_ = dt.date.today()
    months, m = [], today_.replace(day=1)
    for _ in range(4):
        months.append(m.strftime("%Y%m"))
        m = (m - dt.timedelta(days=1)).replace(day=1)

    got, how = {}, set()
    for kind in PLAY_REPORT_FILES:
        rows = []
        for ym in months:
            raw, via = _gcs_bytes(bucket, f"stats/installs/installs_{PLAY_PACKAGE}_{ym}_{kind}.csv")
            if not raw:
                continue
            how.add(via)
            try:
                rows.extend(_play_csv(raw))
            except Exception:                        # noqa: BLE001 — one file, never the set
                continue
        if rows:
            got[kind] = rows
    if not got:
        raise RuntimeError(f"no reports readable in gs://{bucket} — a Console grant "
                           f"can take hours to reach the bucket's ACLs")

    def num(v):
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return 0

    daily = [{"date": r.get("Date"),
              "installs": num(r.get("Daily Device Installs")),
              "uninstalls": num(r.get("Daily Device Uninstalls")),
              "upgrades": num(r.get("Daily Device Upgrades")),
              "activeDevices": num(r.get("Active Device Installs")),
              "userInstalls": num(r.get("Daily User Installs"))}
             for r in got.get("overview", []) if r.get("Date")]
    daily.sort(key=lambda r: r["date"])

    def split(kind, col):
        agg = {}
        for r in got.get(kind, []):
            k = (r.get(col) or "").strip()
            if not k:
                continue
            agg[k] = agg.get(k, 0) + num(r.get("Daily Device Installs"))
        return dict(sorted(agg.items(), key=lambda kv: -kv[1])[:12])

    recent = daily[-28:]
    state["health"]["playInstalls"] = {
        "daily": recent,
        "installs28d": sum(r["installs"] for r in recent),
        "uninstalls28d": sum(r["uninstalls"] for r in recent),
        "activeDevices": (recent[-1]["activeDevices"] if recent else None),
        "byCountry": split("country", "Country"),
        "byDevice": split("device", "Device"),
        "byOs": split("os_version", "Android OS Version"),
        "byVersion": split("app_version", "App Version Code"),
        "byLanguage": split("language", "Language"),
        "readVia": ", ".join(sorted(how)),
    }
    return (f"{sum(r['installs'] for r in recent)} install(s) over {len(recent)} day(s), "
            f"{len(got)} report(s), via {', '.join(sorted(how))}")


def play_rating(state):
    """Public Play listing rating, scraped from the store page's own JSON-LD-ish
    payload. Best effort: Play has no public ratings API."""
    html = get(f"https://play.google.com/store/apps/details?id={PLAY_PACKAGE}&hl=en&gl=US").decode("utf-8", "replace")
    m = re.search(r'\[\[\["([0-9]\.[0-9])"\]\],\[\[', html)
    avg = float(m.group(1)) if m else None
    c = re.search(r'(\d[\d,]*)\s*(?:reviews|ratings)', html)
    cnt = int(c.group(1).replace(",", "")) if c else None
    if avg is None and cnt is None:
        raise RuntimeError("Play listing carries no rating yet")
    state["ratings"].append({
        "store": "Google Play", "average": avg, "count": cnt,
        "url": f"https://play.google.com/store/apps/details?id={PLAY_PACKAGE}",
    })
    return f"{avg} from {cnt}"

# ─────────────────────────────────────────────────── Who is talking about us

def _mention(state, source, title, body, url, author=None, date=None, extra=None):
    if not relevant(title, body, url):
        return False
    state["mentions"].append({
        "source": source, "title": clamp(title, 160), "excerpt": clamp(body, 400),
        "url": url, "author": author, "date": date, **(extra or {}),
    })
    return True


def mentions_reddit(state):
    """Reddit's JSON search refuses an unauthenticated caller (403); the RSS of
    the SAME search answers 200. It is rate-limited hard, so one query, and the
    results are fuzzy — `relevant()` is what makes them usable."""
    import xml.etree.ElementTree as ET
    ns = {"a": "http://www.w3.org/2005/Atom"}
    q = urllib.parse.quote('archivewatch OR "archive watch" apple tv')
    xml = get(f"https://www.reddit.com/search.rss?q={q}&sort=new&limit=50")
    kept = 0
    for e in ET.fromstring(xml).findall("a:entry", ns):
        title = e.findtext("a:title", "", ns)
        body = re.sub(r"<[^>]+>", " ", e.findtext("a:content", "", ns) or "")
        ln = e.find("a:link", ns)
        link = ln.get("href") if ln is not None else ""
        auth = e.findtext("a:author/a:name", "", ns)
        kept += _mention(state, "Reddit", title, body, link, auth, e.findtext("a:updated", "", ns))
    return f"{kept} kept"


def mentions_hn(state):
    d = get_json("https://hn.algolia.com/api/v1/search?query=" +
                 urllib.parse.quote("archivewatch OR \"archive watch\"") + "&hitsPerPage=40")
    kept = 0
    for h in d.get("hits", []):
        title = h.get("title") or h.get("story_title") or ""
        url = h.get("url") or f"https://news.ycombinator.com/item?id={h.get('objectID')}"
        kept += _mention(state, "Hacker News", title, h.get("comment_text") or h.get("story_text") or "",
                         url, h.get("author"), h.get("created_at"),
                         {"points": h.get("points"), "comments": h.get("num_comments")})
    return f"{kept} kept of {d.get('nbHits', 0)}"


def mentions_lemmy(state):
    kept = 0
    for host in ("lemmy.world", "lemmy.ml"):
        try:
            d = get_json(f"https://{host}/api/v3/search?q=archivewatch&type_=All&limit=20")
        except Exception:
            continue
        for p in d.get("posts", []):
            po = p.get("post", {})
            kept += _mention(state, "Lemmy", po.get("name", ""), po.get("body", ""),
                             po.get("ap_id") or f"https://{host}/post/{po.get('id')}",
                             (p.get("creator") or {}).get("name"), po.get("published"))
        for c in d.get("comments", []):
            co = c.get("comment", {})
            kept += _mention(state, "Lemmy", (c.get("post") or {}).get("name", ""), co.get("content", ""),
                             co.get("ap_id", ""), (c.get("creator") or {}).get("name"), co.get("published"))
    return f"{kept} kept"


def mentions_news(state):
    """Google News RSS — the only free route to press coverage."""
    import xml.etree.ElementTree as ET
    q = urllib.parse.quote('"Archive Watch" (app OR "Apple TV" OR Roku OR "public domain")')
    xml = get(f"https://news.google.com/rss/search?q={q}&hl=en-US&gl=US&ceid=US:en")
    kept = 0
    for it in ET.fromstring(xml).iter("item"):
        kept += _mention(state, "News", it.findtext("title", ""), it.findtext("description", ""),
                         it.findtext("link", ""), it.findtext("source", ""), it.findtext("pubDate", ""))
    return f"{kept} kept"


def mentions_bluesky(state):
    """Our own credential, used to search the whole network — not just our posts."""
    handle, pw = os.environ.get("BLUESKY_HANDLE"), os.environ.get("BLUESKY_APP_PASSWORD")
    if not (handle and pw):
        raise RuntimeError("no Bluesky credential in this environment")
    sess = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://bsky.social/xrpc/com.atproto.server.createSession",
        data=json.dumps({"identifier": handle, "password": pw}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": UA}), timeout=25).read())
    hdr = {"Authorization": "Bearer " + sess["accessJwt"]}
    kept = 0
    for q in ("archivewatch.org", "archive watch app", "archivewatch"):
        try:
            d = get_json("https://bsky.social/xrpc/app.bsky.feed.searchPosts?limit=25&q=" +
                         urllib.parse.quote(q), hdr)
        except Exception:
            continue
        for p in d.get("posts", []):
            a = p.get("author", {})
            if a.get("handle") == handle:            # our own programme, counted elsewhere
                continue
            uri = p.get("uri", "").split("/")[-1]
            kept += _mention(state, "Bluesky", "", (p.get("record") or {}).get("text", ""),
                             f"https://bsky.app/profile/{a.get('handle')}/post/{uri}",
                             a.get("handle"), (p.get("record") or {}).get("createdAt"),
                             {"likes": p.get("likeCount"), "reposts": p.get("repostCount")})
    return f"{kept} kept"


def mentions_mastodon(state):
    inst = (os.environ.get("MASTODON_INSTANCE") or os.environ.get("MASTODON_BASE_URL") or "").rstrip("/")
    tok = os.environ.get("MASTODON_ACCESS_TOKEN")
    if not (inst and tok):
        raise RuntimeError("no Mastodon credential in this environment")
    try:                                             # who are WE on this instance
        me = get_json(f"{inst}/api/v1/accounts/verify_credentials",
                      {"Authorization": "Bearer " + tok}).get("acct", "")
    except Exception:                                # noqa: BLE001
        me = ""
    kept = 0
    for q in ("archivewatch.org", "archivewatch"):
        d = get_json(f"{inst}/api/v2/search?type=statuses&limit=20&q=" + urllib.parse.quote(q),
                     {"Authorization": "Bearer " + tok})
        for s in d.get("statuses", []):
            acct = (s.get("account") or {}).get("acct", "")
            if me and acct == me:                    # our own programme, not a mention
                continue
            kept += _mention(state, "Mastodon", "", re.sub(r"<[^>]+>", " ", s.get("content", "")),
                             s.get("url", ""), acct, s.get("created_at"),
                             {"likes": s.get("favourites_count"), "reposts": s.get("reblogs_count")})
    return f"{kept} kept"


# ─────────────────────────────────────────────────────── The social programme

def social_programme(state):
    """What we posted, and what it did — joined from the two files the
    programme already keeps. `social_metrics.py` is the reader; this only
    presents what it has already measured."""
    led = json.loads((REPO / "social" / "posted.json").read_text()).get("posts", [])
    met = json.loads((REPO / "social" / "metrics.json").read_text()).get("samples", [])
    best = {}
    for s in met:                                    # the LATEST window per post wins
        k = s.get("url")
        if k and (k not in best or (s.get("sampled") or "") > (best[k].get("sampled") or "")):
            best[k] = s
    posts, per = [], {}
    for row in sorted(led, key=lambda r: r.get("at") or "", reverse=True):
        m = (best.get(row.get("url")) or {}).get("metrics") or {}
        posts.append({
            "at": row.get("at"), "platform": row.get("platform"), "title": row.get("title"),
            "id": row.get("id"), "slot": row.get("slot"), "format": row.get("format"),
            "url": row.get("url"),
            "likes": m.get("likes"), "reposts": m.get("reposts"),
            "replies": m.get("replies"), "views": m.get("views"),
            "window": (best.get(row.get("url")) or {}).get("window"),
        })
        p = per.setdefault(row.get("platform"), {"posts": 0, "likes": 0, "replies": 0,
                                                 "reposts": 0, "views": 0, "measured": 0})
        p["posts"] += 1
        if m:
            p["measured"] += 1
            for k in ("likes", "replies", "reposts", "views"):
                p[k] += int(m.get(k) or 0)
    state["social"] = {"posts": posts[:120], "byPlatform": per,
                       "totalPosts": len(led), "measured": len(best)}
    return f"{len(led)} post(s) across {len(per)} platform(s), {len(best)} measured"


def social_reach(state):
    """Follower counts — the one number that says whether the programme is
    building anything, as opposed to shouting into a new room every day."""
    got = {}
    handle, pw = os.environ.get("BLUESKY_HANDLE"), os.environ.get("BLUESKY_APP_PASSWORD")
    if handle:
        try:
            d = get_json("https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=" +
                         urllib.parse.quote(handle))
            got["bluesky"] = {"followers": d.get("followersCount"), "posts": d.get("postsCount")}
        except Exception as e:                       # noqa: BLE001
            got["bluesky"] = {"error": str(e)[:80]}
    inst = (os.environ.get("MASTODON_INSTANCE") or os.environ.get("MASTODON_BASE_URL") or "").rstrip("/")
    tok = os.environ.get("MASTODON_ACCESS_TOKEN")
    if inst and tok:
        try:
            d = get_json(f"{inst}/api/v1/accounts/verify_credentials",
                         {"Authorization": "Bearer " + tok})
            got["mastodon"] = {"followers": d.get("followers_count"), "posts": d.get("statuses_count")}
        except Exception as e:                       # noqa: BLE001
            got["mastodon"] = {"error": str(e)[:80]}
    uid, itok = os.environ.get("IG_USER_ID"), os.environ.get("IG_ACCESS_TOKEN")
    if uid and itok:
        try:
            d = get_json(f"https://graph.instagram.com/v21.0/{uid}"
                         f"?fields=followers_count,media_count&access_token={itok}")
            got["instagram"] = {"followers": d.get("followers_count"), "posts": d.get("media_count")}
        except Exception as e:                       # noqa: BLE001
            got["instagram"] = {"error": str(e)[:80]}
    if not got:
        raise RuntimeError("no social credential in this environment")
    state["social"]["reach"] = got
    return ", ".join(f"{k}={v.get('followers')}" for k, v in got.items())


def social_replies(state):
    """A reply to one of our posts is the cheapest user research there is —
    surfaced as a mention so it lands in the same reading list."""
    handle, pw = os.environ.get("BLUESKY_HANDLE"), os.environ.get("BLUESKY_APP_PASSWORD")
    if not (handle and pw):
        raise RuntimeError("no Bluesky credential in this environment")
    sess = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://bsky.social/xrpc/com.atproto.server.createSession",
        data=json.dumps({"identifier": handle, "password": pw}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": UA}), timeout=25).read())
    hdr = {"Authorization": "Bearer " + sess["accessJwt"]}
    d = get_json("https://bsky.social/xrpc/app.bsky.notification.listNotifications?limit=60", hdr)
    kept = 0
    for n in d.get("notifications", []):
        if n.get("reason") not in ("reply", "mention", "quote"):
            continue
        a = n.get("author", {})
        if a.get("handle") == handle:
            continue
        uri = n.get("uri", "").split("/")[-1]
        state["mentions"].append({
            "source": "Bluesky reply", "title": n.get("reason", "").title(),
            "excerpt": clamp((n.get("record") or {}).get("text", ""), 400),
            "url": f"https://bsky.app/profile/{a.get('handle')}/post/{uri}",
            "author": a.get("handle"), "date": n.get("indexedAt"),
        })
        kept += 1
    return f"{kept} reply/mention notification(s)"


def social_liveness(state):
    """Ask each platform whether the post is STILL THERE.

    The ledger records what we published, not what survived: the owner deleted
    several early videos by hand, and the dashboard went on counting them. A
    post that no longer exists is not reach, and reporting it as reach is the
    same confident-absence this tool exists to avoid — pointed at ourselves.

    Every check is a positive test: a post is `live` only when a platform
    CONFIRMS it. A reader that cannot answer leaves `live: null`, which the page
    renders as unknown rather than as gone — deleting a row on a network blip
    would be its own kind of lie."""
    posts = state.get("social", {}).get("posts") or []
    if not posts:
        raise RuntimeError("no posts in the ledger yet")

    bsky_hdr = None
    handle, pw = os.environ.get("BLUESKY_HANDLE"), os.environ.get("BLUESKY_APP_PASSWORD")
    if handle and pw:
        try:
            sess = json.loads(urllib.request.urlopen(urllib.request.Request(
                "https://bsky.social/xrpc/com.atproto.server.createSession",
                data=json.dumps({"identifier": handle, "password": pw}).encode(),
                headers={"Content-Type": "application/json", "User-Agent": UA}), timeout=25).read())
            bsky_hdr = {"Authorization": "Bearer " + sess["accessJwt"]}
        except Exception:                            # noqa: BLE001
            bsky_hdr = None

    yt_hdr = None
    cid, csec = os.environ.get("YOUTUBE_CLIENT_ID"), os.environ.get("YOUTUBE_CLIENT_SECRET")
    rtok = os.environ.get("YOUTUBE_REFRESH_TOKEN")
    if cid and csec and rtok:
        try:
            body = urllib.parse.urlencode({"client_id": cid, "client_secret": csec,
                                           "refresh_token": rtok,
                                           "grant_type": "refresh_token"}).encode()
            tok = json.loads(urllib.request.urlopen(urllib.request.Request(
                "https://oauth2.googleapis.com/token", data=body,
                headers={"Content-Type": "application/x-www-form-urlencoded"}),
                timeout=25).read())["access_token"]
            yt_hdr = {"Authorization": "Bearer " + tok}
        except Exception:                            # noqa: BLE001
            yt_hdr = None

    # The author feed is PUBLIC, so this must not be gated on holding a
    # credential — the handle is in the post URLs the ledger already has.
    who = handle or next((r["url"].split("/profile/")[1].split("/")[0]
                          for r in posts
                          if r.get("platform") == "bluesky" and "/profile/" in (r.get("url") or "")),
                         None)
    bsky_live = None
    if who:
        try:
            live, cursor = set(), None
            for _ in range(4):
                u = ("https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed"
                     f"?actor={urllib.parse.quote(who)}&limit=100")
                if cursor:
                    u += f"&cursor={urllib.parse.quote(cursor)}"
                d = get_json(u)
                for it in d.get("feed", []):
                    live.add((it.get("post", {}).get("uri") or "").rstrip("/").split("/")[-1])
                cursor = d.get("cursor")
                if not cursor:
                    break
            bsky_live = live
        except Exception:                            # noqa: BLE001
            bsky_live = None

    inst = (os.environ.get("MASTODON_INSTANCE") or os.environ.get("MASTODON_BASE_URL") or "").rstrip("/")
    mtok = os.environ.get("MASTODON_ACCESS_TOKEN")
    igtok = os.environ.get("IG_ACCESS_TOKEN")
    thtok = os.environ.get("THREADS_ACCESS_TOKEN")

    def check(row):
        plat, url = row.get("platform"), row.get("url") or ""
        try:
            if plat == "bluesky":
                # The author feed is ONE public call for every post, needs no
                # auth, and compares the record keys the ledger already holds.
                # The first version built at://<handle>/... — an AT-URI takes a
                # DID, not a handle, so getPosts answered nothing for every
                # post and all five came back "unknown" while three were live.
                if bsky_live is None:
                    return None
                return url.rstrip("/").split("/")[-1] in bsky_live
            if plat == "mastodon":
                sid = url.rstrip("/").split("/")[-1]
                if not (inst and mtok and sid.isdigit()):
                    return None
                try:
                    get_json(f"{inst}/api/v1/statuses/{sid}", {"Authorization": "Bearer " + mtok})
                    return True
                except urllib.error.HTTPError as e:
                    return False if e.code in (404, 410) else None
            if plat == "youtube":
                m = re.search(r"(?:shorts/|watch\?v=|youtu\.be/)([\w-]{6,})", url)
                if not (yt_hdr and m):
                    return None
                d = get_json("https://www.googleapis.com/youtube/v3/videos?part=id&id="
                             + m.group(1), yt_hdr)
                return bool(d.get("items"))
            if plat in ("instagram", "threads"):
                mid = row.get("mediaId") or re.search(r"/(\d{10,})/?$", url)
                mid = mid.group(1) if hasattr(mid, "group") else mid
                tok = igtok if plat == "instagram" else thtok
                if not (mid and tok):
                    return None
                host = "graph.instagram.com" if plat == "instagram" else "graph.threads.net"
                try:
                    get_json(f"https://{host}/v21.0/{mid}?fields=id&access_token={tok}")
                    return True
                except urllib.error.HTTPError as e:
                    return False if e.code in (400, 404) else None
        except Exception:                            # noqa: BLE001
            return None
        return None

    live = gone = unknown = 0
    for row in posts:
        v = check(row)
        row["live"] = v
        if v is True:
            live += 1
        elif v is False:
            gone += 1
        else:
            unknown += 1

    # Counts follow what SURVIVED. A deleted post is kept in the list, marked,
    # because "we posted this and it is gone" is itself worth seeing.
    per = {}
    for row in posts:
        if row.get("live") is False:
            continue
        p2 = per.setdefault(row.get("platform"), {"posts": 0, "likes": 0, "replies": 0,
                                                  "reposts": 0, "views": 0, "measured": 0})
        p2["posts"] += 1
        if row.get("likes") is not None:
            p2["measured"] += 1
            for k in ("likes", "replies", "reposts", "views"):
                p2[k] += int(row.get(k) or 0)
    state["social"]["byPlatform"] = per
    state["social"]["totalPosts"] = live + unknown
    state["social"]["deleted"] = gone
    state["social"]["unverified"] = unknown
    return f"{live} live, {gone} deleted, {unknown} could not be checked"


def youtube_channel(state):
    """Views and comments on the teasers — the only platform here that reports
    how many people actually WATCHED."""
    cid, csec = os.environ.get("YOUTUBE_CLIENT_ID"), os.environ.get("YOUTUBE_CLIENT_SECRET")
    rtok = os.environ.get("YOUTUBE_REFRESH_TOKEN")
    if not (cid and csec and rtok):
        raise RuntimeError("no YouTube credential in this environment")
    body = urllib.parse.urlencode({"client_id": cid, "client_secret": csec,
                                   "refresh_token": rtok, "grant_type": "refresh_token"}).encode()
    tok = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://oauth2.googleapis.com/token", data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"}), timeout=25).read())["access_token"]
    hdr = {"Authorization": "Bearer " + tok}
    # The programme's token holds `youtube.upload` ONLY, and deliberately so —
    # tools/youtube_refresh_token.py says "ask for no more than that", and a
    # token that can post but cannot read the account is the right trade for a
    # secret sitting in CI. Reading stats and comments needs `youtube.readonly`.
    # So a 403 here is a CHOICE, not a fault, and it is reported as one.
    note = []
    try:
        ch = get_json("https://www.googleapis.com/youtube/v3/channels"
                      "?part=statistics&mine=true", hdr)
        items = ch.get("items", [])
        if items:
            st = items[0].get("statistics", {})
            state["social"].setdefault("reach", {})["youtube"] = {
                "followers": int(st.get("subscriberCount") or 0),
                "posts": int(st.get("videoCount") or 0),
                "views": int(st.get("viewCount") or 0),
            }
            note.append("channel read")
    except urllib.error.HTTPError as e:
        if e.code != 403:
            raise
        state["social"].setdefault("reach", {})["youtube"] = {
            "error": "the poster's token is youtube.upload only, by design — "
                     "stats need youtube.readonly",
        }
        note.append("stats need youtube.readonly (the token is upload-only, by design)")
    kept = 0
    for row in state.get("social", {}).get("posts", []):
        if row.get("platform") != "youtube" or not row.get("url"):
            continue
        vid = re.search(r"(?:shorts/|watch\?v=|youtu\.be/)([\w-]{6,})", row["url"])
        if not vid:
            continue
        try:
            d = get_json("https://www.googleapis.com/youtube/v3/commentThreads?part=snippet&maxResults=20"
                         f"&videoId={vid.group(1)}", hdr)
        except Exception:
            continue
        for c in d.get("items", []):
            sn = (((c.get("snippet") or {}).get("topLevelComment") or {}).get("snippet") or {})
            state["mentions"].append({
                "source": "YouTube comment", "title": row.get("title") or "",
                "excerpt": clamp(sn.get("textOriginal"), 400),
                "url": row["url"], "author": sn.get("authorDisplayName"),
                "date": sn.get("publishedAt"), "likes": sn.get("likeCount"),
            })
            kept += 1
    note.append(f"{kept} comment(s)")
    return ", ".join(note)


# ──────────────────────────────────────────── Things that need fixing / GitHub

def gh(args, default=None):
    try:
        return json.loads(subprocess.run(["gh", *args], capture_output=True, text=True,
                                         timeout=90, check=True).stdout or "null")
    except Exception:                                # noqa: BLE001
        return default


def github(state):
    r = gh(["api", f"repos/{GH_REPO}"], {})
    traffic = gh(["api", f"repos/{GH_REPO}/traffic/views"], {}) or {}
    clones = gh(["api", f"repos/{GH_REPO}/traffic/clones"], {}) or {}
    state["github"] = {
        "stars": r.get("stargazers_count"), "forks": r.get("forks_count"),
        "watchers": r.get("subscribers_count"), "openIssues": r.get("open_issues_count"),
        "views14d": traffic.get("count"), "uniques14d": traffic.get("uniques"),
        "clones14d": clones.get("count"),
        "url": f"https://github.com/{GH_REPO}",
    }
    issues = gh(["api", f"repos/{GH_REPO}/issues?state=open&per_page=20&sort=updated"], []) or []
    state["health"]["issues"] = [{
        "number": i.get("number"), "title": clamp(i.get("title"), 140),
        "author": (i.get("user") or {}).get("login"), "url": i.get("html_url"),
        "updated": i.get("updated_at"), "labels": [l["name"] for l in i.get("labels", [])],
        "external": (i.get("user") or {}).get("login") not in ("bhwilkoff", "github-actions[bot]"),
    } for i in issues if "pull_request" not in i]
    ext = sum(1 for i in state["health"]["issues"] if i["external"])
    return f"{r.get('stargazers_count')} star(s), {len(state['health']['issues'])} open issue(s), {ext} from outside"


def workflows(state):
    """The fleet's own verdict, from the auditor that already exists. Its
    printed lines ARE the interface — the same regex `report_workflow_health.py`
    reads, so the two can never disagree about what a finding is."""
    p = subprocess.run([sys.executable, str(REPO / "tools" / "audit_workflow_health.py")],
                       capture_output=True, text=True, timeout=900, cwd=str(REPO))
    findings = []
    for line in (p.stdout or "").splitlines():
        m = re.match(r"\s*(BROKEN|KILLED|FAILED|DROPPED|STALE|SILENT|DRAINED)\s+(.+)", line)
        if m:
            findings.append({"severity": m.group(1), "workflow": clamp(m.group(2), 160)})
    state["health"]["workflows"] = findings[:40]
    urgent = [f for f in findings if f["severity"] in ("BROKEN", "KILLED")]
    return f"{len(findings)} finding(s), {len(urgent)} urgent"


def catalog(state):
    """How big and how healthy the thing we are actually shipping is."""
    try:
        d = get_json("https://archivewatch.org/catalog-index.json", timeout=90)
    except Exception as e:                           # noqa: BLE001
        raise RuntimeError(f"catalog-index unreachable: {str(e)[:100]}")
    rows = d.get("items") or d.get("rows") or []
    fields = d.get("fields") or []
    idx = {n: i for i, n in enumerate(fields)}

    def col(name):
        return idx.get(name)

    def count(name, want=1):
        c = col(name)
        return sum(1 for r in rows if c is not None and len(r) > c and r[c] == want)

    state["health"]["catalog"] = {
        "schema": d.get("schema"), "items": len(rows),
        "playable": count("playable"), "professionalArt": count("pro"),
        "withBif": count("bif"), "builtAt": d.get("updatedAt") or None,
    }
    return f"{len(rows)} items, schema {d.get('schema')}"


# ──────────────────────────────────────────────────── What people are ASKING

WANT = re.compile(
    r"\b(wish|would love|would like|please add|hope (?:you|they)|any chance|"
    r"feature request|it needs|needs? to|should (?:be able|have|add|support)|"
    r"can you (?:add|make|support)|missing|would be (?:great|nice|amazing)|"
    r"my only (?:complaint|gripe|wish)|the one thing)\b", re.I)
LOVE = re.compile(
    r"\b(love|loving|amazing|excellent|perfect|fantastic|brilliant|"
    r"beautiful|so good|well done|thank you|thanks for|best app|"
    r"exactly what|intuitive|works (?:really |very )?well|works great|"
    r"easy to use|great app|impressive|delightful|a joy)\b", re.I)


def sentences(text):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+|\n+", text or "") if len(s.strip()) > 12]


def distribution(state):
    """How the written reviews divide across the five stars, per store."""
    by = {}
    for r in state["reviews"]:
        if not r.get("rating"):
            continue
        by.setdefault(r["store"], {i: 0 for i in range(1, 6)})[int(r["rating"])] += 1
    state["distribution"] = by
    return ", ".join(f"{k}: {sum(v.values())} rated" for k, v in by.items()) or "none yet"


def _reports_token():
    """A SEPARATE key for reports, when one exists.

    App Store Connect states it plainly on the key page: a key "can't be
    modified to access more services once created". The release key is App
    Manager and can never gain Sales and Reports, and widening the key that
    ships builds so a dashboard can read a download count is the wrong trade.
    So: `ASC_REPORTS_KEY_ID` + `ASC_REPORTS_KEY_P8` (base64, same issuer) if
    they are set, and the ordinary key otherwise — which fails honestly with
    "the API key in use does not allow this request"."""
    kid = os.environ.get("ASC_REPORTS_KEY_ID", "").strip()
    p8 = os.environ.get("ASC_REPORTS_KEY_P8", "").strip()
    if not (kid and p8):
        return _asc().token()
    import base64
    import time
    import jwt                                       # already a dependency of asc_release
    key = base64.b64decode(p8).decode()
    iss = os.environ["ASC_ISSUER_ID"]
    return jwt.encode({"iss": iss, "iat": int(time.time()),
                       "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


def _asc_raw(ep, accept, reports=False):
    """ASC endpoints that do not speak JSON. `asc_release.call` sets
    Accept: application/json and gets a 406 from both of these, which reads
    exactly like a permission problem and is not one."""
    tok = _reports_token() if reports else _asc().token()
    req = urllib.request.Request("https://api.appstoreconnect.apple.com/" + ep,
                                 headers={"Authorization": "Bearer " + tok,
                                          "Accept": accept})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read()


def apple_performance(state):
    """Launch time, hang rate, memory, disk — Apple's own aggregated field
    metrics, and the one Apple-side signal that says something needs fixing
    before a user writes a review about it."""
    body = _asc_raw(f"v1/apps/{_asc().app_id()}/perfPowerMetrics",
                    "application/vnd.apple.xcode-metrics+json")
    d = json.loads(body)
    prods = d.get("productData") or []
    ins = d.get("insights") or {}
    rows = []
    for p in prods:
        for m in p.get("metricCategories", []):
            for metric in m.get("metrics", []):
                pts = metric.get("datasets", [{}])[0].get("points", [])
                if not pts:
                    continue
                rows.append({"platform": p.get("platform"),
                             "category": m.get("identifier"),
                             "metric": metric.get("identifier"),
                             "value": pts[-1].get("value"),
                             "unit": metric.get("unit")})
    state["health"]["applePerf"] = {
        "metrics": rows[:20],
        "regressions": [clamp(i.get("summaryString") or i.get("metric"), 160)
                        for i in (ins.get("regressions") or [])][:8],
        "improving": [clamp(i.get("summaryString") or i.get("metric"), 160)
                      for i in (ins.get("trendingUp") or [])][:8],
    }
    if not rows and not ins.get("regressions"):
        return "Apple has not aggregated enough device data yet"
    return f"{len(rows)} metric(s), {len(ins.get('regressions') or [])} regression(s)"


def apple_downloads(state):
    """Daily units — the headline performance number, and the only one here
    that says how many people actually installed the thing. Needs the account's
    VENDOR NUMBER (App Store Connect -> Payments and Financial Reports); it is
    an identifier, not a secret, and without it this reader abstains."""
    vendor = os.environ.get("ASC_VENDOR_NUMBER", "").strip()
    if not vendor:
        raise RuntimeError("set ASC_VENDOR_NUMBER (App Store Connect -> "
                           "Payments and Financial Reports) to read downloads")
    import gzip
    import io
    days, series = [], {}
    for back in range(1, 15):                        # Apple posts ~a day behind
        day = (dt.date.today() - dt.timedelta(days=back)).isoformat()
        ep = ("v1/salesReports?filter[frequency]=DAILY&filter[reportType]=SALES"
              f"&filter[reportSubType]=SUMMARY&filter[vendorNumber]={vendor}"
              f"&filter[reportDate]={day}")
        try:
            raw = gzip.decompress(_asc_raw(ep, "application/a-gzip", reports=True))
        except urllib.error.HTTPError as e:
            if e.code == 404:                        # no report for that day yet
                continue
            if e.code == 403:
                raise RuntimeError(
                    "the API key in use has no Sales and Reports access, and a key "
                    "cannot be widened after it is created — generate one with the "
                    "Sales and Reports role and set ASC_REPORTS_KEY_ID / "
                    "ASC_REPORTS_KEY_P8 (see docs/PULSE.md)") from None
            raise
        except OSError:
            continue
        lines = raw.decode("utf-8", "replace").splitlines()
        if len(lines) < 2:
            continue
        head = lines[0].split("\t")
        try:
            i_units, i_type = head.index("Units"), head.index("Product Type Identifier")
        except ValueError:
            continue
        total = 0
        for ln in lines[1:]:
            f = ln.split("\t")
            if len(f) <= max(i_units, i_type):
                continue
            # 1/1F/1T/1E/1EP/1EU = a first-time download; the rest are updates
            # and redownloads, which are not new people.
            if f[i_type].strip().rstrip("F") in ("1", "1T", "1E", "1EP", "1EU", "IA1"):
                try:
                    total += int(f[i_units])
                except ValueError:
                    pass
        days.append({"date": day, "units": total})
    if not days:
        raise RuntimeError("no sales report available yet for this vendor number")
    days.sort(key=lambda r: r["date"])
    state["health"]["appleDownloads"] = {
        "daily": days, "total14d": sum(d["units"] for d in days),
    }
    return f"{sum(d['units'] for d in days)} first-time download(s) over {len(days)} day(s)"


def asks(state):
    """Pull the sentence a person actually WROTE. No summary, no score — the
    owner reads their words and follows the link to the rest."""
    wants, loves = [], []
    src = ([{"kind": "review", "who": r.get("author"), "where": r.get("store"),
             "text": f"{r.get('title','')} {r.get('body','')}", "url": r.get("url"),
             "date": r.get("date"), "rating": r.get("rating")} for r in state["reviews"]]
           + [{"kind": "mention", "who": m.get("author"), "where": m.get("source"),
               "text": m.get("excerpt"), "url": m.get("url"), "date": m.get("date")}
              for m in state["mentions"]])
    for s in src:
        for sent in sentences(s["text"]):
            row = {**{k: s[k] for k in ("kind", "who", "where", "url", "date")},
                   "text": clamp(sent, 260)}
            if WANT.search(sent):
                wants.append(row)
            elif LOVE.search(sent):
                loves.append(row)
    state["asks"] = wants[:60]
    state["loves"] = loves[:60]
    return f"{len(wants)} request(s), {len(loves)} bit(s) of praise"


# ─────────────────────────── Stores with no API at all — declared, not guessed

# Amazon's Submission API still answers `invalid_scope` (see tools/submit-amazon.py),
# Roku has no developer API, and LG/Samsung publish through a console only. Their
# state lives HERE so the dashboard shows the whole estate rather than the half of
# it that happens to be machine-readable. Update by hand when a state changes.
MANUAL = REPO / "ops" / "stores-manual.json"

MANUAL_SEED = {
    "_": ("Stores with no API. Edit this file when a state changes — the dashboard "
          "shows it beside the machine-read ones so the estate is never half-reported."),
    "stores": [
        {"store": "Amazon Appstore", "platform": "Fire TV", "state": "LIVE",
         "version": "1.42.x", "since": "2026-09-01",
         "note": "Submission API returns invalid_scope; console only.",
         "url": "https://developer.amazon.com/apps-and-games/console/apps/list.html"},
        {"store": "Roku Channel Store", "platform": "Roku", "state": "SUBMITTED",
         "version": "1.0.51", "since": "2026-09-08",
         "note": "Channel 881015. No developer API — check the Dashboard.",
         "url": "https://developer.roku.com/developer-channels/channels"},
        {"store": "LG Content Store", "platform": "webOS", "state": "NOT SUBMITTED",
         "version": None, "since": None,
         "note": "Package builds; Seller Lounge account is the owner step.",
         "url": "https://seller.lgappstv.com/"},
        {"store": "Samsung Apps TV", "platform": "Tizen", "state": "NOT SUBMITTED",
         "version": None, "since": None,
         "note": "Public Seller is US-only; needs the signing certificate.",
         "url": "https://seller.samsungapps.com/"},
        {"store": "Web (PWA)", "platform": "archivewatch.org", "state": "LIVE",
         "version": "rolling", "since": "2026-06-10",
         "note": "Ships on every Pages deploy.", "url": "https://archivewatch.org"},
    ],
}


def manual_stores(state):
    if not MANUAL.exists():
        MANUAL.parent.mkdir(parents=True, exist_ok=True)
        MANUAL.write_text(json.dumps(MANUAL_SEED, indent=1) + "\n", encoding="utf-8")
    rows = json.loads(MANUAL.read_text()).get("stores", [])
    for r in rows:
        r.setdefault("manual", True)
    state["stores"] += rows
    return f"{len(rows)} declared store(s)"


# ─────────────────────────────────────────────────────────────────── The run

SOURCES = [
    ("apple_stores", apple_stores),
    ("apple_reviews", apple_reviews),
    ("apple_rating", apple_rating),
    ("apple_performance", apple_performance),
    ("apple_downloads", apple_downloads),
    ("play_stores", play_stores),
    ("play_reviews", play_reviews),
    ("play_rating", play_rating),
    ("play_vitals", play_vitals),
    ("play_crashes", play_crashes),
    ("play_users", play_users),
    ("play_reports", play_reports),
    ("manual_stores", manual_stores),
    ("social_programme", social_programme),
    ("social_reach", social_reach),
    ("social_replies", social_replies),
    ("social_liveness", social_liveness),
    ("youtube_channel", youtube_channel),
    ("mentions_reddit", mentions_reddit),
    ("mentions_hn", mentions_hn),
    ("mentions_lemmy", mentions_lemmy),
    ("mentions_news", mentions_news),
    ("mentions_bluesky", mentions_bluesky),
    ("mentions_mastodon", mentions_mastodon),
    ("github", github),
    ("workflows", workflows),
    ("catalog", catalog),
    ("distribution", distribution),
    ("asks", asks),                                  # must run last: it reads the rest
]


_MENTION_OWNER = {
    "mentions_reddit": ("Reddit",), "mentions_hn": ("Hacker News",),
    "mentions_lemmy": ("Lemmy",), "mentions_news": ("News",),
    "mentions_bluesky": ("Bluesky",), "mentions_mastodon": ("Mastodon",),
    "social_replies": ("Bluesky reply",), "youtube_channel": ("YouTube comment",),
}


def _owned_by(mention, source_name) -> bool:
    return mention.get("source") in _MENTION_OWNER.get(source_name, ())


def blank():
    return {"stores": [], "ratings": [], "reviews": [], "mentions": [],
            "distribution": {},
            "social": {}, "health": {}, "github": {}, "asks": [], "loves": [],
            "sources": {}}


def dedupe(rows, key):
    seen, out = set(), []
    for r in rows:
        k = key(r)
        if k in seen:
            continue
        seen.add(k)
        out.append(r)
    return out


def history_row(state):
    """One compact line per day. Numbers only — this is the series that has to
    survive forever, so nothing in it may grow."""
    ap = next((r for r in state["ratings"] if r["store"] == "App Store"), {})
    pl = next((r for r in state["ratings"] if r["store"] == "Google Play"), {})
    per = state.get("social", {}).get("byPlatform", {})
    reach = state.get("social", {}).get("reach", {})
    cat = state.get("health", {}).get("catalog", {})
    return {
        "date": today(),
        "appleRating": ap.get("average"), "appleRatings": ap.get("count"),
        "playRating": pl.get("average"), "playRatings": pl.get("count"),
        "reviews": len(state["reviews"]),
        "mentions": len(state["mentions"]),
        "posts": state.get("social", {}).get("totalPosts"),
        "likes": sum(int(p.get("likes") or 0) for p in per.values()),
        "followers": sum(int((v or {}).get("followers") or 0) for v in reach.values()),
        "stars": state.get("github", {}).get("stars"),
        "views14d": state.get("github", {}).get("views14d"),
        "catalogItems": cat.get("items"),
        "urgent": sum(1 for f in state.get("health", {}).get("workflows", [])
                      if f.get("severity") in ("BROKEN", "KILLED")),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write ops/pulse.json")
    ap.add_argument("--only", help="comma-separated source names")
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args()

    want = set(s.strip() for s in a.only.split(",")) if a.only else None

    out = Path(a.out)
    prev = {}
    if out.exists():
        try:
            prev = json.loads(out.read_text())
        except json.JSONDecodeError:
            prev = {}

    # A PARTIAL run must not delete what it did not collect. `--only` starts
    # from the last reading and replaces just the parts its sources produce —
    # otherwise a quick local `--only apple_reviews` silently drops every
    # mention CI gathered, and the page reports a confident zero for readers
    # that were simply not asked. (This is the same rule as `sources`, one
    # level up: absence is not evidence.)
    state = blank()
    if want:
        for key in ("stores", "ratings", "reviews", "mentions", "social",
                    "health", "github", "asks", "loves", "distribution"):
            if key in prev:
                state[key] = prev[key]
        state["sources"] = dict(prev.get("sources") or {})
        # ...and the sections these sources DO own are cleared, so a reader that
        # now returns nothing shrinks its section instead of stacking onto it.
        owns = {
            "apple_stores": ["stores"], "play_stores": ["stores"], "manual_stores": ["stores"],
            "apple_reviews": ["reviews"], "play_reviews": ["reviews"],
            "apple_rating": ["ratings"], "play_rating": ["ratings"],
            "asks": ["asks", "loves"], "distribution": ["distribution"],
            "github": ["github"], "social_programme": ["social"],
        }
        for src in want:
            for key in owns.get(src, []):
                state[key] = blank()[key]
        # mentions are unioned below, so a re-run adds to them rather than
        # replacing — no per-source clearing here

    print(f"pulse — {now()}\n")
    for name, fn in SOURCES:
        if want and name not in want:
            continue
        try:
            note = fn(state)
            state["sources"][name] = {"ok": True, "note": note, "at": now()}
            print(f"  {'ok':<4} {name:<18} {note}")
        except Exception as e:                       # noqa: BLE001 — one source, never the run
            state["sources"][name] = {"ok": False, "note": str(e)[:200], "at": now()}
            print(f"  {'--':<4} {name:<18} {str(e)[:110]}")

    # A source that FAILED keeps its last good value, marked stale. Dropping it
    # would put a hole where four reviews were, and a hole reads as "there are
    # none" — the same confident-zero this whole tool exists to avoid.
    OWNS = {"apple_stores": "stores", "play_stores": "stores", "manual_stores": "stores",
            "apple_reviews": "reviews", "play_reviews": "reviews",
            "apple_rating": "ratings", "play_rating": "ratings",
            "distribution": "distribution", "github": "github",
            "social_programme": "social", "catalog": None}
    stale = {}
    for name, res in state["sources"].items():
        key = OWNS.get(name)
        if res["ok"] or not key or not prev.get(key):
            continue
        if not state.get(key):                       # nothing collected for it
            state[key] = prev[key]
            stale[key] = prev.get("generatedAt")
        elif key in ("stores", "ratings", "reviews"):
            have = {r.get("store") for r in state[key]}
            carried = [r for r in prev[key] if r.get("store") not in have]
            if carried:
                state[key] = state[key] + carried
                stale[key] = prev.get("generatedAt")
    # `health` is one dict shared by many readers, so the generic carry above
    # cannot rescue a single failed one. Carry the sub-keys individually: the
    # Play install reports read fine on the dev Mac and 403 in CI until a
    # Console grant reaches the bucket ACLs, and dropping them meanwhile would
    # replace a real reading with a hole.
    HEALTH_OWNS = {"play_reports": "playInstalls", "play_crashes": "playCrashes",
                   "play_users": "playUsers", "play_vitals": "playVitals",
                   "apple_downloads": "appleDownloads", "apple_performance": "applePerf",
                   "catalog": "catalog"}
    prev_health = prev.get("health") or {}
    for name, key in HEALTH_OWNS.items():
        res = state["sources"].get(name)
        if res and not res["ok"] and not state["health"].get(key) and prev_health.get(key):
            state["health"][key] = prev_health[key]
            stale[key] = prev.get("generatedAt")
    state["stale"] = stale

    # Mentions and reviews ACCUMULATE. Somebody who posted about us yesterday
    # still posted about us today, and these searches are fuzzy — Bluesky's
    # returned a real mention on one run and not the next. Replacing the list
    # each day would make a genuine finding evaporate because a search did not
    # repeat, which is the same lie as a confident zero, told slowly.
    state["reviews"] = dedupe(
        sorted(state["reviews"] + (prev.get("reviews") or []),
               key=lambda r: r.get("date") or "", reverse=True),
        lambda r: (r.get("store"), r.get("id")))[:MAX_REVIEWS]
    state["mentions"] = dedupe(
        sorted(state["mentions"] + (prev.get("mentions") or []),
               key=lambda m: m.get("date") or "", reverse=True),
        lambda m: m.get("url"))[:MAX_MENTIONS]

    hist = [h for h in prev.get("history", []) if h.get("date") != today()]
    hist.append(history_row(state))
    state["history"] = hist[-MAX_HISTORY:]
    state["generatedAt"] = now()
    try:                                             # the ONE version number (Decision 101)
        text = (REPO / "AppVersion.xcconfig").read_text()
        state["repoVersion"] = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", text, re.M).group(1)
        state["repoBuild"] = re.search(r"^CURRENT_PROJECT_VERSION\s*=\s*(\S+)", text, re.M).group(1)
    except Exception:                                # noqa: BLE001
        pass
    state["_"] = ("Written by tools/pulse_collect.py. `history` is the series and is "
                  "append-only per day; everything else is the latest reading. A source "
                  "that could not answer says so in `sources` — never assume a zero.")

    ok = sum(1 for v in state["sources"].values() if v["ok"])
    print(f"\n{ok}/{len(state['sources'])} source(s) answered · "
          f"{len(state['reviews'])} review(s) · {len(state['mentions'])} mention(s) · "
          f"{len(state['asks'])} request(s)")

    if a.apply:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(state, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"wrote {out} ({out.stat().st_size // 1024} KB, {len(state['history'])} history row(s))")
    else:
        print("(dry run — pass --apply to write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
