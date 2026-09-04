#!/usr/bin/env python3
"""Roku PLAYBACK audit — does a film actually play on the device, or not.

This is the Roku twin of `tools/download_audit.py` and the tvOS functional
harness: the app is never allowed to grade its own work. Every claim here comes
from one of two external oracles.

  1. **ECP `/query/media-player`** — Roku's OWN account of the video plane:
     state, error, codec, resolution, and a position that has to ADVANCE
     between samples. This is the trustworthy one, and it matters more here
     than on any other platform: on several Roku SoCs the video plane is not
     composited into `screencap`, so a screenshot of a playing film is a black
     rectangle. A screenshot CANNOT prove playback on Roku.
  2. **The BrightScript console on 8085** — what the channel says it is doing.
     Used only for things ECP cannot see: that the deep link was accepted, that
     the shard resolved a url, that a bookmark was written to a registry no
     external tool can read, and how many times the stall watchdog fired.

Each film is driven by a DEEP LINK rather than by remote presses, so a run is
deterministic and a failure names a film instead of a sequence of keys.

  python3 tools/roku_playback_audit.py                 # varied sample, 6 films
  python3 tools/roku_playback_audit.py --n 12
  python3 tools/roku_playback_audit.py --ids a b c     # exactly these
  python3 tools/roku_playback_audit.py --soak 300      # one film, long watch

Exit status is non-zero if any film fails a REQUIRED check, so this can gate a
release the way `submit-play.sh` gates an Android upload.
"""
import argparse
import json
import os
import random
import socket
import sys
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import roku  # noqa: E402  — the device harness owns HOST/ECP and the installer

INDEX_URL = "https://archivewatch.org/catalog-index.json"

# Decision 077's bar, borrowed: a film starts within 30 seconds or it has
# failed, whatever the buffer is doing. The clock starts when the CHANNEL
# accepts the link, never at process launch — a cold channel boot spends ~14s
# parsing the catalog, and charging that to the film measures the wrong thing.
# The first run of this harness did exactly that and reported three healthy
# films as broken.
START_DEADLINE = 30.0

# ECP reports position and duration in MILLISECONDS.
MS = 1000.0

REQUIRED = ["accepted", "resolved", "started", "advanced", "no_error", "error_shown"]


class Console(threading.Thread):
    """Tails the BrightScript debug console for the length of the run.

    Push-only: nothing is ever sent. A run that cannot open 8085 still audits —
    it just reports SKIP for the console-only checks rather than pretending.
    """

    def __init__(self):
        super().__init__(daemon=True)
        self.lines = []
        self.lock = threading.Lock()
        self.stop = False
        self.ok = False

    def run(self):
        try:
            s = socket.create_connection((roku.HOST, 8085), timeout=5)
        except OSError:
            return
        self.ok = True
        s.settimeout(1)
        buf = ""
        while not self.stop:
            try:
                chunk = s.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            buf += chunk.decode(errors="replace")
            *whole, buf = buf.split("\n")
            with self.lock:
                self.lines.extend(l.strip() for l in whole)
        s.close()

    def since(self, mark):
        with self.lock:
            return self.lines[mark:]

    def mark(self):
        with self.lock:
            return len(self.lines)


def media_player():
    """Roku's own report on the video plane. Returns {} when it will not answer."""
    try:
        xml = roku.curl(f"{roku.ECP}/query/media-player")
        root = ET.fromstring(xml)
    except Exception:
        return {}
    fmt = root.find("format")
    def num(tag):
        # The element text carries its UNIT: "<position>37871 ms</position>".
        # A bare int() throws on that and returns None, which reads downstream
        # as "the device would not tell us" rather than "the parser is wrong" —
        # every film in this run reported an empty position list while playing
        # perfectly.
        t = (root.findtext(tag) or "").strip()
        digits = "".join(c for c in t if c.isdigit())
        return int(digits) if digits else None
    return {
        "state": root.get("state"),
        "error": root.get("error"),
        "position": num("position"),
        "duration": num("duration"),
        "video": fmt.get("video") if fmt is not None else None,
        "audio": fmt.get("audio") if fmt is not None else None,
        "res": fmt.get("video_res") if fmt is not None else None,
    }


def warm_channel(console, timeout=45):
    """Get the channel running and its catalog parsed BEFORE any film is timed.

    `/launch` on a channel that is not running is a cold start; on one that is,
    the parameters arrive through roInput and nothing restarts. Warming once
    means every film in a run is measured on the same warm path a viewer with
    the app already open would take, and it is also the only way the roInput
    branch gets exercised at all.
    """
    # The mark is taken BEFORE the launch. The debug console replays recent
    # output when a client attaches, so an "AWSVC ready" from a PREVIOUS run is
    # sitting in the buffer and reading the whole log answers the wrong
    # question — the first version of this returned "warm in 0.0s" for a
    # channel that was not running at all.
    # Already running is already warm. `/launch` with no parameters does NOT
    # restart a channel that is in the foreground — it answers 204 and changes
    # nothing — so waiting for a fresh "AWSVC ready" that will never be printed
    # fails a perfectly healthy device.
    if "Archive Watch" in roku.curl(f"{roku.ECP}/query/active-app"):
        return 0.0

    mark = console.mark()
    roku.curl("-X", "POST", f"{roku.ECP}/launch/dev")
    t0 = time.time()
    while time.time() - t0 < timeout:
        active = "Archive Watch" in roku.curl(f"{roku.ECP}/query/active-app")
        if active:
            if not console.ok:
                if time.time() - t0 > 20:
                    return round(time.time() - t0, 1)
            elif any("AWSVC ready" in l for l in console.since(mark)):
                return round(time.time() - t0, 1)
        time.sleep(1.0)
    return None


def stop_playback(tries=8):
    """Get the device to a state where NOTHING is playing, before timing a film.

    Without this every check is contaminated by the film before it: the state
    still reads "play", so the next film "starts" in 0.1s and the harness
    measures the wrong picture entirely. Back leaves the player, which also
    writes the abandoned film's final bookmark.
    """
    for _ in range(tries):
        mp = media_player()
        if not mp or mp.get("state") not in ("play", "buffer", "pause", "startup"):
            return True
        roku.curl("-X", "POST", f"{roku.ECP}/keypress/Back")
        time.sleep(1.5)
    return False


def load_index(cache):
    if os.path.exists(cache) and time.time() - os.path.getmtime(cache) < 86400:
        return json.load(open(cache))
    with urllib.request.urlopen(INDEX_URL, timeout=120) as r:
        data = json.loads(r.read().decode())
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    json.dump(data, open(cache, "w"))
    return data


def pick_candidates(index, n, seed):
    """A VARIED sample, and a different one on every run.

    The standing rule in this repo is breadth over repetition — re-testing the
    same film proves only that the same film still works. Films are bucketed by
    content type and the sample is drawn round-robin across the buckets, so a
    run of six covers six kinds of thing rather than six comedies. Duration
    extremes are deliberately included: the shortest items are the ones whose
    derivative is most often missing, and the longest are where the stall
    watchdog earns its keep.
    """
    rng = random.Random(seed)
    buckets = {}
    for r in index["items"]:
        # id, title, year, type, poster, pro, keywords, backdrop
        if not r[0] or not r[1]:
            continue
        # A series id names a spine, not a file. Deep-linking one with
        # mediaType=movie asks the channel to play something that has no url;
        # series drill-in is its own parity row and its own test.
        if str(r[0]).startswith("series:") or r[3] == "tv-series":
            continue
        buckets.setdefault((r[3] or "unknown"), []).append(r)
    for v in buckets.values():
        rng.shuffle(v)
        # Professionally-presented items first: those are what Home shows, so a
        # failure there is a failure a viewer would actually meet.
        v.sort(key=lambda r: 0 if r[5] == 1 else 1)
    order = sorted(buckets.keys())
    rng.shuffle(order)
    out, i = [], 0
    while len(out) < n and any(buckets[k] for k in order):
        k = order[i % len(order)]
        if buckets[k]:
            out.append(buckets[k].pop(0))
        i += 1
    return out


def audit_film(row, console, watch_seconds, do_replay=True):
    aid, title = row[0], row[1]
    ctype = row[3] or "?"
    res = {"id": aid, "title": title, "type": ctype, "checks": {}, "notes": []}
    ck = res["checks"]
    # Quiesce FIRST, then mark the console, so nothing from the previous film
    # lands inside this film's evidence window.
    res["checks"]["quiesced"] = stop_playback()
    mark = console.mark()

    # `/input` hands the parameters to the RUNNING channel through roInput.
    # `/launch` does not: it closes and restarts the channel every time, which
    # the state trace shows plainly as "close -> startup" and which costs a
    # ~14s catalog parse per film. That restart is what made the first two runs
    # of this harness report healthy films as broken.
    q = urllib.parse.urlencode({"contentId": aid, "mediaType": "movie"})
    roku.curl("-X", "POST", f"{roku.ECP}/input?{q}")

    t0 = time.time()
    started, states, samples = None, [], []
    # `error` is STICKY: it describes the last media session, so a film that
    # failed leaves error="true" standing while the NEXT film starts up. Errors
    # before and after the start are therefore counted separately — otherwise
    # one broken film condemns whatever is audited after it.
    err_pre, err_post = None, None
    while time.time() - t0 < START_DEADLINE:
        mp = media_player()
        if mp:
            if not states or states[-1] != mp["state"]:
                states.append(mp["state"])
            if mp.get("error") not in (None, "false"):
                err_seen = mp.get("error")
            # Reaching "play" IS the start. The <position> element is absent
            # for the first seconds of playback, so requiring it here waits
            # for the wrong thing and times out on a film that is running.
            # Because nothing was playing when the link was sent, reaching
            # "play" IS this film starting. Do not also require a duration or
            # a position: both elements are ABSENT from the report for the
            # first seconds of playback, and waiting on them times out on a
            # film that is running perfectly well.
            if mp["state"] == "play":
                started = time.time() - t0
                samples.append(mp)
                break
        time.sleep(1.0)
    res["states"] = states

    log = console.since(mark)
    ck["accepted"] = any(f"AWDEEP contentId={aid}" in l for l in log) if console.ok else None
    resolved = [l for l in log if l.startswith("AWROKU detail ok " + aid)]
    if console.ok:
        ck["resolved"] = bool(resolved) and any("url=true" in l.lower() for l in resolved)
    else:
        ck["resolved"] = None

    ck["started"] = started is not None
    res["duration_ms"] = samples[-1].get("duration") if samples else None
    if started is not None:
        res["ttff"] = round(started, 1)
    else:
        res["notes"].append(
            f"never reached play in {START_DEADLINE:.0f}s (states seen: {' -> '.join(states) or 'none'})")

    if started is None:
        ck["advanced"] = False
        ck["no_error"] = err_pre is None
        # A film that cannot play must SAY SO. Dropping the viewer back on the
        # Detail screen with no message is indistinguishable from a dead
        # remote, and it is what this app did until this audit found it.
        if console.ok:
            ck["error_shown"] = any("AWPLAY failed-notice" in l for l in console.since(mark))
        else:
            ck["error_shown"] = None
        if err_pre:
            res["notes"].append(f"media-player reported error={err_pre} while starting")
        ck["codec"] = False
        if do_replay:
            ck["replay"] = None
        ck["bookmark"] = None
        return res

    # Watch it run. Position must strictly increase; anything else is a stall
    # even when the state still says "play".
    watch_from = time.time()
    deadline = watch_from + watch_seconds
    while time.time() < deadline:
        time.sleep(5)
        mp = media_player()
        if not mp:
            break
        samples.append(mp)
        if mp.get("error") not in (None, "false"):
            err_post = mp.get("error")
    watched = time.time() - watch_from
    posns = [s["position"] for s in samples if s["position"] is not None]
    if not posns:
        res["notes"].append("state reached play but ECP never reported a position")
    ck["advanced"] = len(posns) >= 2 and posns[-1] > posns[0]
    res["positions_s"] = [round(p / MS, 1) for p in posns]
    if len(posns) >= 2:
        # Wall-clock vs film-clock. A film that advances 4s of picture per 10s
        # of watching is technically "advancing" and is unwatchable; this is
        # the number that would catch it.
        # Against ACTUAL elapsed wall clock, not the requested watch length —
        # the loop overruns by a sample, and dividing by the request produced a
        # nonsensical 1.53x on films that were plainly playing in real time.
        span = (posns[-1] - posns[0]) / MS
        res["realtime_ratio"] = round(span / max(watched, 1), 2)
    ck["no_error"] = err_post is None
    if err_post:
        res["notes"].append(f"media-player reported error={err_post} during playback")

    last = samples[-1]
    ck["codec"] = bool(last.get("video") and last.get("audio"))
    res["codec"] = f"{last.get('video')}/{last.get('audio')} {last.get('res')}"
    if last.get("duration"):
        res["duration_min"] = round(last["duration"] / MS / 60, 1)

    if do_replay:
        before = last["position"]
        roku.curl("-X", "POST", f"{roku.ECP}/keypress/InstantReplay")
        time.sleep(4)
        mid = media_player()
        after = mid.get("position")
        # A 15s rewind, inside Roku's required 10-25s band. The check is that
        # it went BACKWARDS relative to where it would otherwise be, then kept
        # playing — a replay that lands the film in a dead state is worse than
        # no replay at all.
        if before is None or after is None:
            ck["replay"] = None
            res["notes"].append("replay not judged — ECP gave no position")
        else:
            ck["replay"] = (after < before + 4000 and mid.get("state") == "play")
            res["replay_s"] = f"{round(before / MS)} -> {round(after / MS)}"

    log = console.since(mark)
    if console.ok:
        ck["bookmark"] = any(l.startswith("AWPLAY bookmark") and aid in l for l in log)
    else:
        ck["bookmark"] = None
    stalls = [l for l in log if "AWPLAY stall" in l]
    recov = [l for l in log if "AWPLAY recover" in l]
    res["stalls"] = len(stalls)
    res["recoveries"] = len(recov)
    if recov:
        res["notes"].append(f"stall watchdog fired {len(recov)}x")
    return res


def mark_of(v):
    return {True: "PASS", False: "FAIL", None: "SKIP"}[v]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=6, help="how many films to audit")
    ap.add_argument("--ids", nargs="*", help="audit exactly these archive ids")
    ap.add_argument("--watch", type=float, default=20.0,
                    help="seconds to watch each film after it starts")
    ap.add_argument("--soak", type=float, default=0.0,
                    help="watch ONE film this long instead (exercises the stall watchdog)")
    ap.add_argument("--seed", default=None, help="sample seed (default: today)")
    args = ap.parse_args()

    console = Console()
    console.start()
    time.sleep(1.5)
    if not console.ok:
        print("NOTE: the debug console on 8085 is not readable — console-only "
              "checks will report SKIP, and every ECP check still runs.")

    cache = os.path.join(roku.REPO, "build", "qa", "catalog-index.json")
    index = load_index(cache)

    if args.ids:
        by_id = {r[0]: r for r in index["items"]}
        rows = []
        for i in args.ids:
            rows.append(by_id.get(i) or [i, i, None, "?", None, 0, "", None])
    else:
        seed = args.seed or time.strftime("%Y-%m-%d")
        rows = pick_candidates(index, args.n, seed)

    watch = args.soak if args.soak else args.watch
    if args.soak:
        rows = rows[:1]

    boot = warm_channel(console)
    if boot is None:
        print("the channel did not come up — nothing can be measured")
        sys.exit(1)
    print(f"channel warm in {boot}s")
    print(f"Roku playback audit — {len(rows)} film(s), {watch:.0f}s each, "
          f"host {roku.HOST}\n")
    results = []
    for row in rows:
        print(f"→ {row[1][:58]:58s} [{row[3]}] {row[0]}")
        r = audit_film(row, console, watch)
        results.append(r)
        line = "  " + "  ".join(f"{k}={mark_of(v)}" for k, v in r["checks"].items())
        print(line)
        if r.get("ttff") is not None:
            print(f"  start {r['ttff']}s  {r.get('codec')}  {r.get('duration_min')}min  "
                  f"pos {r.get('positions_s')}  realtime x{r.get('realtime_ratio')}  "
                  f"stalls {r.get('stalls', 0)}")
        for n in r["notes"]:
            print("  NOTE:", n)
        print()

    roku.curl("-X", "POST", f"{roku.ECP}/keypress/Home")
    console.stop = True

    total = sum(len(r["checks"]) for r in results)
    passed = sum(1 for r in results for v in r["checks"].values() if v is True)
    failed = [(r["id"], k) for r in results for k, v in r["checks"].items() if v is False]
    skipped = sum(1 for r in results for v in r["checks"].values() if v is None)
    print(f"{passed} PASS / {len(failed)} FAIL / {skipped} SKIP of {total} checks "
          f"across {len(results)} films")

    out = os.path.join(roku.QA_DIR, "playback-audit.json")
    os.makedirs(roku.QA_DIR, exist_ok=True)
    json.dump(results, open(out, "w"), indent=2)
    print("written:", out)

    hard = [f for f in failed if f[1] in REQUIRED]
    if hard:
        print("\nREQUIRED checks failed:")
        for i, k in hard:
            print(f"   {i}  {k}")
        sys.exit(1)


if __name__ == "__main__":
    main()
