#!/usr/bin/env python3
"""External-observation scenario runner for the paired Apple TV.

Watches what the DEVICE actually outputs — screenshots OCR'd for on-glass
captions/notices, console diagnostics for playhead/buffer/audio — and grades
explicit assertions. The app's own claims are never the evidence for what a
viewer sees; the screen is.

Usage:
  python3 tools/atv_scenario.py --title "His Girl Friday" --minutes 6
  python3 tools/atv_scenario.py --item his_girl_friday --minutes 6 \
      [--vtt auto] [--outdir /tmp/atvrun]

Requires: /tmp/awocr (swiftc -O tools/ScreenOCR/main.swift -o /tmp/awocr),
a paired ATV (DEVICE below), the app installed with diagnostics env support.
"""
import argparse, json, re, subprocess, sys, time, urllib.request
from datetime import datetime
from pathlib import Path

DEVICE = "C3FBA9DE-4A60-555B-A65F-80D6809A275B"
BUNDLE = "app.archivewatch.tvos"
OCR = "/tmp/awocr"
SHOT_EVERY = 4.0   # 4K captures pressure the device's screenshot daemon;
                   # 2.5s coincided with jetsam events on ~every run
PYATV = "/tmp/pyatv-venv/bin/atvremote"
PYATV_ARGS = ["--address", "10.0.0.223", "--id", "7A:3F:0C:4E:20:1E",
              "--protocol", "companion"]


def sh(cmd, timeout=90, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)


def resolve_card(title):
    """The card the APP serves for this film — never a hardcoded id. The His
    Girl Friday lesson: tests ran green against an id the app no longer
    surfaced while the viewer watched a different copy fail."""
    idx = json.loads(urllib.request.urlopen(
        "https://archivewatch.org/catalog-index.json").read())
    items = idx["items"] if isinstance(idx, dict) and "items" in idx else idx
    hits = [r for r in items if isinstance(r, list) and isinstance(r[1], str)
            and r[1].lower() == title.lower()]
    if not hits:
        hits = [r for r in items if isinstance(r, list) and isinstance(r[1], str)
                and title.lower() in r[1].lower()]
    if not hits:
        sys.exit(f"no card found for {title!r}")
    return hits[0][0]


def wake_tv():
    """The TV sleeps between runs; installs work asleep but launches and
    screenshots do NOT, and devicectl has no wake verb. pyatv's Companion
    protocol does (one-time PIN pairing, credentials in ~/.pyatv.conf)."""
    try:
        r = sh([PYATV] + PYATV_ARGS + ["power_state"], timeout=30)
        if "PowerState.On" in r.stdout:
            return
        print("[scenario] TV asleep — waking it")
        sh([PYATV] + PYATV_ARGS + ["turn_on"], timeout=30)
        time.sleep(6)
    except Exception as e:
        print(f"[scenario] wake attempt failed (continuing): {e}")


def launch(item, outdir):
    # NO --console: a console stream cannot coexist with the screenshot
    # captures (two devicectl sessions kill the stream — measured). The app
    # writes diagnostics to Documents/awdiag.log (AW_DIAG_FILE=1) and the
    # harness copies it out afterwards.
    env = {"AW_START_ITEM": item, "AW_AUTOPLAY": "1", "AW_DIAG_FILE": "1",
           "AW_PLAYBACK_DIAG": "1", "AW_AUDIO_DIAG": "1", "AW_CAPTION_TRACE": "1"}
    r = sh(["xcrun", "devicectl", "device", "process", "launch",
            "--terminate-existing", "--device", DEVICE,
            "-e", json.dumps(env), BUNDLE], timeout=60)
    if "Launched application" not in (r.stdout + r.stderr):
        sys.exit(f"launch failed: {r.stdout[-400:]} {r.stderr[-400:]}")
    return outdir / "awdiag.log"


def pull_diag(outdir):
    log = outdir / "awdiag.log"
    r = sh(["xcrun", "devicectl", "device", "copy", "from", "--device", DEVICE,
            "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE,
            "--source", "Library/Caches/awdiag.log", "--destination", str(log)],
           timeout=120)
    if not log.exists():
        print(f"[scenario] diag copy failed: {r.stdout[-300:]} {r.stderr[-300:]}")
    return log


def capture_loop(outdir, minutes):
    shots = []
    deadline = time.time() + minutes * 60
    i = 0
    while time.time() < deadline:
        p = outdir / f"shot-{i:04d}.png"
        r = sh(["xcrun", "devicectl", "device", "capture", "screenshot",
                "--device", DEVICE, "--destination", str(p)], timeout=30)
        if p.exists():
            shots.append((time.time(), p))
        i += 1
        time.sleep(max(0, SHOT_EVERY - 1.0))
    return shots


def ocr(shots):
    out = {}
    paths = [str(p) for _, p in shots]
    for chunk in (paths[i:i+20] for i in range(0, len(paths), 20)):
        r = sh([OCR] + chunk, timeout=600)
        for line in r.stdout.splitlines():
            try:
                d = json.loads(line)
                out[d["file"]] = d
            except json.JSONDecodeError:
                pass
    return out


def parse_console(log):
    """wall-time -> playhead map (AWBUF), audio samples, stalls, verdicts.
    The diag file's lines are `<epoch.millis> <message>`."""
    buf, aud, events, shown = [], [], [], []
    if not log.exists():
        return buf, aud, events, shown
    for line in open(log, errors="ignore"):
        m = re.match(r"^(\d{10}\.\d{3}) (.*)", line)
        if not m:
            continue
        wall, msg = float(m.group(1)), m.group(2)
        if "AWBUF" in msg:
            bm = re.search(r"t=(\d+) ahead=(\d+)", msg)
            if bm:
                buf.append((wall, int(bm.group(1)), int(bm.group(2))))
        elif "AWAUD rms" in msg:
            aud.append(wall)
        elif " show: " in msg:
            shown.append((wall, msg.split(" show: ", 1)[1]))
        elif any(k in msg for k in ("AWSTALL", "itemFailed", "subtitle review",
                                    "scout playing", "scout silenced", "AWNUDGE",
                                    "AWLIFE")):
            events.append(f"{wall:.1f} {msg}")
    return buf, aud, events, shown


def playhead_at(buf, wall):
    if not buf:
        return None
    best = min(buf, key=lambda b: abs(b[0] - wall))
    if abs(best[0] - wall) > 12:
        return None
    return best[1] + (wall - best[0])


def fetch_vtt(item):
    try:
        body = urllib.request.urlopen(
            f"https://archivewatch.org/subs/{item}/en.vtt").read().decode()
    except Exception:
        return None
    cues, block = [], []
    for line in body.splitlines():
        m = re.match(r"(\d+):(\d+):(\d+)\.(\d+) --> (\d+):(\d+):(\d+)\.(\d+)", line)
        if m:
            g = list(map(int, m.groups()))
            block = [g[0]*3600+g[1]*60+g[2]+g[3]/1000,
                     g[4]*3600+g[5]*60+g[6]+g[7]/1000]
        elif block and line.strip() and not line.strip().isdigit() \
                and not line.startswith(("WEBVTT", "X-TIMESTAMP")):
            block.append(line.strip())
        elif not line.strip() and len(block) > 2:
            cues.append((block[0], block[1], " ".join(block[2:]))); block = []
    return cues or None


def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--title")
    ap.add_argument("--item")
    ap.add_argument("--minutes", type=float, default=6)
    ap.add_argument("--outdir", default=None)
    args = ap.parse_args()
    item = args.item or resolve_card(args.title)
    outdir = Path(args.outdir or f"/tmp/atvrun-{item}-{int(time.time())}")
    outdir.mkdir(parents=True, exist_ok=True)
    print(f"[scenario] card: {item}  ->  {outdir}")

    wake_tv()
    launch(item, outdir)
    time.sleep(8)                      # let playback begin
    # LAUNCH-WINDOW DEATH RETRY. ~2 in 10 launches die silently within the
    # first seconds — no crash report, no app jetsam event, only the 4K
    # screenshot daemon being jetsammed for its own limit around the same
    # runs: the observer perturbs the system. One retry keeps a scenario
    # about the APP, not about capture-induced memory pressure; a death
    # after the retry still fails app_alive_to_end honestly.
    for probe_at in (0, 15):          # deaths observed at 4-15s post-launch
        if probe_at: time.sleep(probe_at)
        probe = sh(["xcrun", "devicectl", "device", "info", "processes",
                    "--device", DEVICE], timeout=60)
        if "ArchiveWatch.app/ArchiveWatch" not in probe.stdout:
            print("[scenario] app died in launch window — one retry")
            launch(item, outdir)
            time.sleep(8)
            break
    shots = capture_loop(outdir, args.minutes)
    print(f"[scenario] {len(shots)} screenshots")

    log = pull_diag(outdir)
    texts = ocr(shots)
    buf, aud, events, shown = parse_console(log)
    vtt = fetch_vtt(item)

    # ── Assertions ─────────────────────────────────────────────────────────
    report = {"item": item, "shots": len(shots), "assertions": {}}

    def grade(name, ok, evidence):
        report["assertions"][name] = {"pass": bool(ok), "evidence": evidence}
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {evidence}")

    # A0. The app must be ALIVE for the whole run. Scenario ttcrb1 graded
    # "captions on 45/52 frames" while the app had crashed 10s in — the OCR
    # was reading home-screen app labels in the caption region. The diag
    # file's last heartbeat is the evidence: the app writes AWBUF every 5s
    # while playing, so a last line more than 45s before capture ended means
    # the process died (or playback ended) mid-scenario.
    last_diag = 0.0
    if log.exists():
        for line in open(log, errors="ignore"):
            m = re.match(r"^(\d{10}\.\d{3}) ", line)
            if m:
                last_diag = max(last_diag, float(m.group(1)))
    capture_end = shots[-1][0] if shots else time.time()
    grade("app_alive_to_end", last_diag > 0 and capture_end - last_diag < 45,
          f"last diag heartbeat {capture_end - last_diag:.0f}s before capture end"
          if last_diag else "no diag heartbeats at all")

    # A. Stuck notice: "Preparing"/"unavailable" visible on many frames.
    notice_frames = [p.name for _, p in shots
                     if any("preparing" in t.lower() or "unavailable" in t.lower()
                            for t in texts.get(p.name, {}).get("captionRegion", []))]
    grade("no_stuck_notice", len(notice_frames) * SHOT_EVERY < 30,
          f"notice visible on {len(notice_frames)}/{len(shots)} frames "
          f"(~{len(notice_frames)*SHOT_EVERY:.0f}s)")

    # B. Playback advances (no long freeze): playhead strictly increases.
    frozen = 0
    for (w1, t1, _), (w2, t2, _) in zip(buf, buf[1:]):
        if w2 - w1 > 4 and t2 <= t1:
            frozen += 1
    grade("playhead_advances", frozen == 0 and len(buf) > 10,
          f"{len(buf)} buffer samples, {frozen} frozen intervals")

    # C. Stalls / item failures.
    stalls = [e for e in events if "AWSTALL" in e or "itemFailed" in e]
    grade("no_stalls", len(stalls) == 0, f"{len(stalls)} stall/failure events")

    # D. Audio continuity — graded ONLY over the tap's lifetime. tvOS tears
    #    the audioMix tap down on heavy-decode items (17s on the 4K film, six
    #    clean minutes on His Girl Friday) and it is NEVER re-attached: the
    #    watchdog that revived it by replacing the playing item's audioMix
    #    WAS the rhythmic "audio dropout" (16 metronomic fake gaps in a LAN
    #    control run; zero with a single attach). The app logs its blindness;
    #    a gap can only be counted while the instrument was alive.
    tap_died = log.exists() and any("tap died" in l for l in open(log, errors="ignore"))
    gaps = sum(1 for a, b in zip(aud, aud[1:]) if b - a > 6)
    covered = (aud[-1] - aud[0]) if len(aud) > 2 else 0
    ok = (len(aud) > 10 and gaps == 0) or (tap_died and gaps == 0 and len(aud) >= 2)
    grade("audio_continuous", ok,
          f"{len(aud)} rms samples over {covered:.0f}s, {gaps} gaps>6s"
          + (" (tap died — instrument blind after that; no gaps while alive)" if tap_died else ""))

    # E. Captions on the GLASS: fraction of frames with caption text while
    #    dialogue should be present (any-caption presence), and — file mode —
    #    the on-glass text must match the published cue at the playhead.
    cap_frames = 0
    matches = checks = 0
    for wall, p in shots:
        region = texts.get(p.name, {}).get("captionRegion", [])
        if not region:
            continue
        cap_frames += 1
        t = playhead_at(buf, wall)
        if vtt and t is not None:
            covering = [c for c in vtt if c[0] - 1.5 <= t <= c[1] + 1.5]
            if covering:
                checks += 1
                glass = norm(" ".join(region))
                if any(norm(c[2])[:24] in glass or glass[:24] in norm(c[2])
                       for c in covering if len(norm(c[2])) >= 8):
                    matches += 1
    grade("captions_on_glass", cap_frames >= max(3, len(shots) * 0.15),
          f"caption text on {cap_frames}/{len(shots)} frames")
    if vtt:
        grade("glass_matches_file", checks >= 5 and matches / max(1, checks) >= 0.7,
              f"{matches}/{checks} on-glass captions match the published cue at the playhead")
    elif shown:
        # ENGINE captions (no published file): the glass must show what the
        # engine says it displayed, close in wall time. This proves the pipe
        # end-to-end (engine -> overlay -> pixels) and rejects the ttcrb1
        # failure mode where "captions" were home-screen labels. Timing vs
        # the AUDIO is the drift-bound's job; this asserts display fidelity.
        em = ec = 0
        for wall, p in shots:
            region = texts.get(p.name, {}).get("captionRegion", [])
            if not region:
                continue
            near = [s for w, s in shown if abs(w - wall) <= 8]
            if not near:
                continue
            ec += 1
            glass = norm(" ".join(region))
            if any(norm(s)[:20] in glass or glass[:20] in norm(s)
                   for s in near if len(norm(s)) >= 8):
                em += 1
        grade("glass_matches_engine", ec >= 5 and em / max(1, ec) >= 0.6,
              f"{em}/{ec} on-glass captions match an engine-displayed line nearby in time")

    (outdir / "report.json").write_text(json.dumps(report, indent=1))
    failed = [k for k, v in report["assertions"].items() if not v["pass"]]
    print(f"\nRESULT: {'OK' if not failed else 'FAIL — ' + ', '.join(failed)}")
    print(f"report: {outdir}/report.json")
    sys.exit(0 if not failed else 1)


if __name__ == "__main__":
    main()
