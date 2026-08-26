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
import os as _os
# Durable venv (Tidbits: pyatv needs python3.12; /tmp gets cleared).
PYATV = _os.path.expanduser("~/.pyatv-venv/bin/atvremote")
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
    protocol does (one-time PIN pairing, credentials in ~/.pyatv.conf).
    POLLED, never fire-and-forget (Tidbits harness lesson): turn_on only
    sends the request, and a launch into the doze window comes up
    BACKGROUNDED, which mimics an app bug. Gives up loudly."""
    for attempt in range(3):
        try:
            r = sh([PYATV] + PYATV_ARGS + ["power_state"], timeout=30)
            if "PowerState.On" in r.stdout:
                return True
            print(f"[scenario] TV asleep — waking (attempt {attempt + 1})")
            sh([PYATV] + PYATV_ARGS + ["turn_on"], timeout=30)
            for _ in range(8):
                time.sleep(3)
                r = sh([PYATV] + PYATV_ARGS + ["power_state"], timeout=30)
                if "PowerState.On" in r.stdout:
                    time.sleep(2)   # let the home screen settle
                    return True
        except Exception as e:
            print(f"[scenario] wake attempt failed: {e}")
    print("[scenario] COULD NOT WAKE THE TV — captures will be blind")
    return False


def press(key):
    """One Siri-remote press over Companion, WARMED: a fresh single-command
    connection drops its press (measured in Tidbits at up to 100% within a
    long session), so run power_state first on the same connection. Presses
    do NOT reset the box's sleep timer — long interactive probes must expect
    sleep regardless. Companion press decay is cumulative; a
    `devicectl device reboot` is the reset."""
    return sh([PYATV] + PYATV_ARGS + ["power_state", key], timeout=30)


HOME_SCREEN_RX = re.compile(
    r"prime video|pluto|fubo|Apple TV\+|Select up for full screen|"
    r"\d{1,2}:\d{2} [AP]M", re.I)


def frame_is_home_screen(png):
    """Alive is not frontmost: a doze-window launch comes up backgrounded and
    the captures then grade the tvOS home screen (Tidbits F-004)."""
    try:
        r = sh([OCR, str(png)], timeout=60)
        d = json.loads(r.stdout.splitlines()[0])
        text = " ".join(d.get("allText", []) if isinstance(d.get("allText"), list)
                        else [t.get("text", "") for t in d.get("allText", [])])
        return bool(HOME_SCREEN_RX.search(text))
    except Exception:
        return False


EXTRA_ENV = {}


def launch(item, outdir):
    # NO --console: a console stream cannot coexist with the screenshot
    # captures (two devicectl sessions kill the stream — measured). The app
    # writes diagnostics to Documents/awdiag.log (AW_DIAG_FILE=1) and the
    # harness copies it out afterwards.
    env = {"AW_START_ITEM": item, "AW_AUTOPLAY": "1", "AW_DIAG_FILE": "1",
           "AW_PLAYBACK_DIAG": "1", "AW_AUDIO_DIAG": "1", "AW_CAPTION_TRACE": "1"}
    env.update(EXTRA_ENV)
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
            if p.stat().st_size < 300_000:
                print(f"[scenario] frame {i} is {p.stat().st_size}B — doze "
                      "signature; re-waking (window logged, frames kept)")
                wake_tv()
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


def diag_text_early(log):
    return log.read_text(errors="ignore") if log.exists() else ""


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
            rm = re.search(r"rms=([\d.]+)", msg)
            aud.append((wall, float(rm.group(1)) if rm else -1.0))
        elif "show[cue=" in msg:
            # Trace format: `trace t=104.0 show[cue=103.0]: Even ten minutes…`
            # The old " show: " pattern matched NOTHING, so `shown` was empty
            # and caption_pacing / glass_matches_engine silently never graded
            # — an assertion that cannot fire is not an assertion.
            shown.append((wall, msg.split("]: ", 1)[1] if "]: " in msg else msg))
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


def card_has_subtitle_claim(item):
    """Does the SERVED CATALOG say this card has a subtitle track?

    A published subs/<id>/en.vtt is not enough: QC passes that drop a
    caption claim (D043 ASR removal, D044 orphan clearing, validation
    'empty') clean the CATALOG but never the published assets, so the site
    holds ORPHAN files the app deliberately ignores. Grading the glass
    against an orphan scores 0/N on a correct ENGINE display (Minnie the
    Moocher, w7-cartoon: descriptive orphan file on the site, no
    subtitleHLS in the DB, app correctly ran the engine). The catalog row
    is what the app reads, so it is what the grader must read.
    """
    for db in ("/tmp/catalog.sqlite",):
        try:
            out = subprocess.run(
                ["sqlite3", db,
                 f"SELECT json_extract(json,'$.subtitleHLS') FROM item_json "
                 f"WHERE archiveID='{item}'"],
                capture_output=True, text=True, timeout=20)
            return bool(out.stdout.strip())
        except Exception:
            continue
    return True    # no local DB to consult: keep the old behavior


def fetch_vtt(item):
    if not card_has_subtitle_claim(item):
        return None
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
    ap.add_argument("--name", default=None,
                    help="run name for the durable build/qa/ tree")
    ap.add_argument("--caption-choice", choices=["file", "automatic", "off"],
                    help="seed CaptionChoiceSession via AW_CAPTION_CHOICE")
    ap.add_argument("--expect-captions", choices=["auto", "yes", "no"],
                    default="auto",
                    help="'no' = negative control (a silent film generating "
                         "captions is a FAILURE); 'auto' judges from the "
                         "published-VTT presence")
    args = ap.parse_args()
    if args.caption_choice:
        EXTRA_ENV["AW_CAPTION_CHOICE"] = args.caption_choice
    item = args.item or resolve_card(args.title)
    # Durable, never /tmp: background tasks get reaped and a capture you
    # cannot return to is a capture you have to take twice.
    day = datetime.now().strftime("%Y-%m-%d")
    run_name = args.name or item[:32]
    outdir = Path(args.outdir or
                  f"build/qa/atv-{day}/{run_name}-{int(time.time())}")
    outdir.mkdir(parents=True, exist_ok=True)
    print(f"[scenario] card: {item}  ->  {outdir}")

    wake_tv()
    launch(item, outdir)
    time.sleep(8)                      # let playback begin
    # Foreground guard: a doze-window launch comes up BACKGROUNDED and every
    # capture then grades the tvOS home screen instead of the app.
    probe_png = outdir / "probe-foreground.png"
    sh(["xcrun", "devicectl", "device", "capture", "screenshot",
        "--device", DEVICE, "--destination", str(probe_png)], timeout=30)
    if probe_png.exists() and frame_is_home_screen(probe_png):
        print("[scenario] app launched BACKGROUNDED (home screen on glass) — "
              "waking + relaunching once")
        wake_tv()
        launch(item, outdir)
        time.sleep(8)
    # LAUNCH-WINDOW DEATH RETRY. ~2 in 10 launches die silently within the
    # first seconds — no crash report, no app jetsam event, only the 4K
    # screenshot daemon being jetsammed for its own limit around the same
    # runs: the observer perturbs the system. One retry keeps a scenario
    # about the APP, not about capture-induced memory pressure; a death
    # after the retry still fails app_alive_to_end honestly.
    # Probes reach 30s: 2026-08-26 deaths landed 20-30s post-launch, past
    # the old (0, 15) window, so four runs captured a dead app for 4 minutes
    # each. A SECOND death escalates to a device reboot — the manual recipe
    # that cured every one of those runs — because a plain relaunch onto a
    # degraded capture daemon tends to die the same way.
    deaths = 0
    for probe_at in (0, 15, 15):      # cumulative 0s, 15s, 30s
        if probe_at: time.sleep(probe_at)
        probe = sh(["xcrun", "devicectl", "device", "info", "processes",
                    "--device", DEVICE], timeout=60)
        if "ArchiveWatch.app/ArchiveWatch" in probe.stdout:
            continue
        deaths += 1
        if deaths == 1:
            print("[scenario] app died in launch window — one retry")
        else:
            print("[scenario] app died AGAIN — rebooting the device "
                  "(capture-daemon degradation; the proven cure)")
            sh(["xcrun", "devicectl", "device", "reboot", "--device", DEVICE],
               timeout=120)
            deadline = time.time() + 240
            while time.time() < deadline:
                time.sleep(10)
                r = sh([PYATV] + PYATV_ARGS + ["power_state"], timeout=30)
                if "PowerState" in r.stdout:
                    break
            time.sleep(10)
            wake_tv()
        launch(item, outdir)
        time.sleep(8)
    shots = capture_loop(outdir, args.minutes)
    print(f"[scenario] {len(shots)} screenshots")

    log = pull_diag(outdir)
    texts = ocr(shots)
    buf, aud, events, shown = parse_console(log)
    vtt = fetch_vtt(item)
    # The judge corrects a mistimed published file LIVE (D062): the glass then
    # shows the file's words at SHIFTED times, and matching against the
    # unshifted VTT scores 0/23 on a correct display (Impact, w7-impact-file:
    # "subtitles ran 18.8s late; corrected"). Apply the same shift here.
    if vtt and log.exists():
        m = None
        for m in re.finditer(r"subtitles ran ([\d.]+)s (late|early); corrected", diag_text_early(log)):
            pass
        if m:
            delta = float(m.group(1)) * (-1 if m.group(2) == "late" else 1)
            vtt = [(s + delta, e + delta, txt) for s, e, txt in vtt]
            print(f"[scenario] judge shifted the file {m.group(1)}s {m.group(2)} — "
                  "matching against the shifted cues")

    # ── Assertions ─────────────────────────────────────────────────────────
    report = {"item": item, "shots": len(shots), "assertions": {}}

    diag_text = log.read_text(errors="ignore") if log.exists() else ""

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

    # A. Notices. "Preparing automatic captions" was DELETED outright (owner
    #    2026-08-26: "shows for far too long and is almost entirely unneeded";
    #    the Photos app shows nothing) — so its appearance on even ONE frame
    #    is a regression. Failure/model notices remain legitimate but bounded
    #    (12s by code; 16s here for capture quantization).
    prep_frames = [p.name for _, p in shots
                   if any("preparing" in s.lower()
                          for s in texts.get(p.name, {}).get("captionRegion", []))]
    grade("preparing_notice_never_shows", not prep_frames,
          f"'Preparing…' on {len(prep_frames)}/{len(shots)} frames"
          + (f" (first: {prep_frames[0]})" if prep_frames else ""))
    other_notice = [p.name for _, p in shots
                    if any(k in s.lower() for k in ("unavailable", "downloading the speech")
                           for s in texts.get(p.name, {}).get("captionRegion", []))]
    grade("failure_notice_bounded", len(other_notice) * SHOT_EVERY <= 16,
          f"failure/model notice on {len(other_notice)}/{len(shots)} frames "
          f"(~{len(other_notice)*SHOT_EVERY:.0f}s)")

    # B. Playback advances (no long freeze): playhead strictly increases.
    #    Startup pre-roll is exempt: samples at t=0 while the buffer fills
    #    (Carnival of Souls: three t=0 samples, ahead 0->11, then perfect
    #    advancement) are D077's domain (30s bound to start), not a freeze.
    frozen = 0
    for (w1, t1, _), (w2, t2, _) in zip(buf, buf[1:]):
        if w2 - w1 > 4 and t2 <= t1 and t1 > 0:
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
    #    A MISSING emission alone is not silence: the meter drains on a 5s
    #    tick and emits only when the tap delivered buffers that window, and
    #    on some mux shapes AVFoundation feeds the tap in decode-ahead BURSTS
    #    while the renderer plays smoothly from its own buffer (Day the Earth
    #    Caught Fire: 11 metronomic exactly-10s gaps, median rms 0.046 — the
    #    loudest of three films that day — zero stalls, captions matched at
    #    the playhead). A gap is a dropout only when CORROBORATED: a zero-rms
    #    sample at either edge, or a stall/failure event inside the window.
    tap_died = log.exists() and any("tap died" in l for l in open(log, errors="ignore"))
    ev_times = []
    for e in stalls:
        try:
            ev_times.append(float(e.split()[0]))
        except ValueError:
            pass
    gaps = uncorro = 0
    for (a, ra), (b, rb) in zip(aud, aud[1:]):
        if b - a <= 6:
            continue
        if ra < 0.001 or rb < 0.001 or any(a < t < b for t in ev_times):
            gaps += 1
        else:
            uncorro += 1
    covered = (aud[-1][0] - aud[0][0]) if len(aud) > 2 else 0
    ok = (len(aud) > 10 and gaps == 0) or (tap_died and gaps == 0 and len(aud) >= 2)
    grade("audio_continuous", ok,
          f"{len(aud)} rms samples over {covered:.0f}s, {gaps} corroborated gaps>6s"
          + (f", {uncorro} uncorroborated (tap delivery batching)" if uncorro else "")
          + (" (tap died — instrument blind after that; no gaps while alive)" if tap_died else ""))

    # E. Captions on the GLASS: fraction of frames with caption text while
    #    dialogue should be present (any-caption presence), and — file mode —
    #    the on-glass text must match the published cue at the playhead.
    # The judge can DISCARD a wrong file mid-run ("subtitles don't match
    # this film (4%) — captioning instead", D.O.A./doa_ipod) and the app
    # switches to the engine. Frames after that moment must be graded
    # against the ENGINE, not the file the app just rejected — grading a
    # correct recovery against the discarded file scored 9/30.
    switch_wall = None
    if log.exists():
        for line in open(log, errors="ignore"):
            m = re.match(r"^(\d{10}\.\d{3}) .*captioning instead", line)
            if m:
                switch_wall = float(m.group(1))
                break
    cap_frames = 0
    matches = checks = 0
    for wall, p in shots:
        region = texts.get(p.name, {}).get("captionRegion", [])
        if not region:
            continue
        cap_frames += 1
        t = playhead_at(buf, wall)
        in_file_mode = vtt and (switch_wall is None or wall < switch_wall)
        if in_file_mode and t is not None:
            covering = [c for c in vtt if c[0] - 1.5 <= t <= c[1] + 1.5]
            if covering:
                checks += 1
                glass = norm(" ".join(region))
                if any(norm(c[2])[:24] in glass or glass[:24] in norm(c[2])
                       for c in covering if len(norm(c[2])) >= 8):
                    matches += 1
    if switch_wall is not None:
        print(f"[scenario] judge discarded the file mid-run — frames after "
              f"{switch_wall:.0f} grade against the engine")
    if args.expect_captions == "no":
        # NEGATIVE CONTROL (silent films, music-only): a caption generated
        # where there is no speech is a hallucination shipping to a viewer.
        # Judge what the APP DREW, not what the film printed: a 1920s film is
        # full of intertitle cards whose text reaches the OCR band (Caligari's
        # own "MIRACLES! SIDESHOWS" graded as 6 phantom captions,
        # w7-silent-rerun). The engine's display trace is the record of what
        # it drew; OCR text with no engine line behind it is the film's own.
        grade("silent_negative_control",
              len(shown) == 0 and not prep_frames and not other_notice,
              f"engine displayed {len(shown)} lines; caption-band OCR hits on "
              f"{cap_frames}/{len(shots)} frames (film's own intertitles are "
              "not counted)")
    else:
        grade("captions_on_glass", cap_frames >= max(3, len(shots) * 0.15),
              f"caption text on {cap_frames}/{len(shots)} frames")
    if args.expect_captions != "no" and vtt:
        # Fail only on POSITIVE evidence of mismatch. A sparse-dialogue
        # window (Carnival of Souls: organ score, 4 checkable moments in
        # 3.5min, 3 matched) is thin evidence, not failure — with few
        # checks require only a majority; with none there is nothing to
        # judge and captions_on_glass carries the presence claim.
        ratio = matches / max(1, checks)
        ok = (ratio >= 0.7 if checks >= 5 else
              ratio >= 0.5 if checks >= 1 else True)
        grade("glass_matches_file", ok,
              f"{matches}/{checks} on-glass captions match the published cue at the playhead"
              + ("" if checks >= 5 else f" (sparse dialogue window — {checks} checkable)")
              + (" (file-mode frames only — judge discarded the file mid-run)"
                 if switch_wall is not None else ""))
    if args.expect_captions != "no" and shown and (not vtt or switch_wall is not None):
        # ENGINE captions (no published file): the glass must show what the
        # engine says it displayed, close in wall time. This proves the pipe
        # end-to-end (engine -> overlay -> pixels) and rejects the ttcrb1
        # failure mode where "captions" were home-screen labels. Timing vs
        # the AUDIO is the drift-bound's job; this asserts display fidelity.
        em = ec = 0
        for wall, p in shots:
            if switch_wall is not None and wall < switch_wall:
                continue
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

    # F. The caption SCHEDULE never runs backwards. Decision 081: a drift
    #    correction shifts every cue, and an unbounded one re-anchored The
    #    Incredible Machine by -12.4s so LATER audio mapped EARLIER than what
    #    was already on screen — fragments out of order, which is precisely
    #    what "undependable captions" looked like from the sofa while the
    #    engine's own text was fine. Needs AW_CAPTION_TRACE=1.
    # What was actually SHOWN, in the order it was shown — not the creation-time
    # mapping lines, whose values go stale the moment a correction shifts the
    # cues they described.
    mapped = [float(m.group(1)) for m in
              re.finditer(r"show\[cue=([\d.]+)\]", diag_text)]
    regressions = [(a, b) for a, b in zip(mapped, mapped[1:]) if b < a - 0.5]
    if mapped:
        grade("caption_schedule_monotonic", not regressions,
              f"{len(mapped)} displayed cues, {len(regressions)} ran backwards"
              + (f" (worst {min(b - a for a, b in regressions):.1f}s)" if regressions else ""))

    # G. A blank caption means SILENCE, not a dropped line. Reconstructing this
    #    from the trace does not work — a drift correction moves the cue list
    #    after the mapping lines were written — so the display SELF-REPORTS how
    #    many cues bracket the playhead. Reconstruction claimed 12 of 19 blanks
    #    were drops; the self-report said 0 of 20.
    blanks = [int(m.group(1)) for m in
              re.finditer(r"blank, cues bracketing=(\d+)", diag_text)]
    if blanks:
        drops = [b for b in blanks if b > 0]
        grade("blank_captions_are_gaps", not drops,
              f"{len(blanks)} blank ticks, {len(drops)} had a cue that should have shown")

    # H. PACING (owner 2026-08-26: captions "are often wrongly timed (move
    #    too quickly or go in large bursts)"). Judge the DISPLAY sequence the
    #    engine reports (wall time of each distinct line change): a caption
    #    replaced faster than anyone reads is "too fast"; several distinct
    #    lines inside a 3s window is a "burst" (late-finalized cues arriving
    #    together). Reading-time floor is ~2.5 words/s (Decision 059).
    changes = []
    last_text = None
    for w, s in shown:
        ns = norm(s)
        if ns and ns != last_text:
            changes.append((w, ns))
            last_text = ns
    if len(changes) >= 8:
        dwells = [b - a for (a, _), (b, _) in zip(changes, changes[1:])]
        fast = [d for d in dwells if d < 1.2]
        med = sorted(dwells)[len(dwells) // 2]
        # A burst is pathological only when a line inside it was UNREADABLE.
        # Three short conversational lines in 3s is rapid dialogue, correctly
        # timed (f3-tim-verify: "Uh, this is our sister / Oh I see / Oh, just
        # a minute" flagged as the lone "burst" of a clean run).
        bursts = 0
        for i in range(len(changes) - 2):
            if changes[i + 2][0] - changes[i][0] < 3.0 and any(
                    changes[j + 1][0] - changes[j][0] < 1.0 for j in (i, i + 1)):
                bursts += 1
        report["pacing"] = {"changes": len(changes),
                           "median_dwell_s": round(med, 2),
                           "fast_fraction": round(len(fast) / len(dwells), 2),
                           "burst_windows": bursts}
        grade("caption_pacing", med >= 2.0 and len(fast) <= len(dwells) * 0.2
              and bursts == 0,
              f"median dwell {med:.1f}s, {len(fast)}/{len(dwells)} changes "
              f"<1.2s, {bursts} burst windows (3+ lines in 3s)")

    (outdir / "report.json").write_text(json.dumps(report, indent=1))
    failed = [k for k, v in report["assertions"].items() if not v["pass"]]
    print(f"\nRESULT: {'OK' if not failed else 'FAIL — ' + ', '.join(failed)}")
    print(f"report: {outdir}/report.json")
    sys.exit(0 if not failed else 1)


if __name__ == "__main__":
    main()
