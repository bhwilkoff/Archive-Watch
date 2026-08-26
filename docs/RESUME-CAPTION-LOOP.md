# RESUME — the caption loop (pick up here after any compaction)

Campaign brief + audit matrix + loop log: `docs/CAPTION-LOOP.md`. Read that
first. This file is the operating manual: cadence, tick shape, and the
harness facts a fresh context must not re-learn.

## Cadence — a commitment

ScheduleWakeup, **300 seconds**, never lengthened without the owner. LARGE
work per tick — a scenario run + its analysis, or a fix + device
re-verification — never a check-and-wait. If the loop is ever found
unarmed, re-arm immediately. Between-tick state lives in the DOCS and in
`build/qa/atv-<date>/` run dirs (newest dir = where the rotation stands),
never in session memory. Commit + push every verified unit
(`git pull --rebase` first — crons write to main).

## Tick shape

One meaty unit per tick, highest-risk first:

1. **W2 verify** — 2–3 films on the ATV: `preparing_notice_never_shows`
   green across warm-up (build 958+ is installed).
2. **W5 verify** — the un-clipped subtitles sheet on iPhone hardware
   ("Ben 15 Pro" is paired; try `devicectl device capture screenshot` on
   it; fall back to the iPhone simulator for pure layout).
3. **W1 timing** — run the era deck; `caption_pacing` grades bursts and
   too-fast dwells from the engine's displayed-line trace; on a FAIL, pull
   `awdiag.log`, find the mechanism (late-finalized analyzer batches vs
   display pacing vs drift clamps), fix, re-verify same film.
4. **W3 default-first** — re-measure whether the SYSTEM generated track
   EMITS on current tvOS 27 (Settings → Caption Diagnostics, driven by
   warmed presses + OCR; D068 measured "offered, never emits" on an early
   beta). If it emits now: architecture pivot (system leads, engine
   understudy) — that is an owner-visible decision entry.
5. **W4 picker** — build the caption-type chooser (Off / Automatic /
   Subtitle file / human tracks) per player; verify by driving the menu
   with presses + OCR.
6. **W6/W7** — the full screen audit + era/genre matrix sweep; log every
   cell in CAPTION-LOOP.md.

Runner: `python3 tools/atv_scenario.py --title "<Title>" --minutes 4
--name w1-<slug> [--expect-captions no]` → grade line + `report.json`.

## The era deck (resolve by TITLE at runtime, never a hardcoded id)

His Girl Friday (1940 dialogue-dense; published VTT) · The Incredible
Machine (narration; engine) · Meet John Doe (1941) · The Day the Earth
Caught Fire (1961) · a 1950s TV episode via series drill-in · a silent
(The Cabinet of Dr. Caligari or any 1920s title; `--expect-captions no`) ·
a cartoon (music-heavy) · an early talkie (1929–33) · Night of the Living
Dead (1968). Vary titles across laps — the finds come from VARIATION, not
lap repetition (Tidbits reshape lesson).

## Harness facts (do not re-learn)

- Devices: ATV "Ben Bedroom" `C3FBA9DE-4A60-555B-A65F-80D6809A275B`;
  iPhone "Ben 15 Pro" `988DE0A7-63DB-561C-B5FA-2BAAB60643E1`; iPad
  `AC5377E9-6053-51DE-8E65-D88A4E9345FA`. `DEVELOPER_DIR` must be
  Xcode-beta for devicectl.
- pyatv: durable venv `~/.pyatv-venv` (python3.12 — breaks on 3.14),
  credentials `~/.pyatv.conf`, Companion id `7A:3F:0C:4E:20:1E` at
  `10.0.0.223`. **Warmed presses only** (`power_state <key>` on one
  connection) — a fresh connection DROPS its press. Presses do not reset
  the sleep timer. Press decay is cumulative; `devicectl device reboot`
  is the reset.
- OCR: `/tmp/awocr` from `swiftc -O tools/ScreenOCR/main.swift` — /tmp is
  cleared between days; rebuild when missing.
- Installs work while the TV sleeps; launches/screenshots do not.
  ~80 captures/day degrades the screenshot daemon → reboot the device.
  Two devicectl sessions kill a console stream — the app writes
  `Library/Caches/awdiag.log` instead (`AW_DIAG_FILE=1`).
- Simulators have NO speech models: engine behavior is hardware/Mac-only;
  sims are for layout (W5) and screen audits only.
- Ground truth for a timing dispute = local transcription of the exact
  film region (`/tmp/awlive`-style harness, D069); scout `currentTime()`
  is NOT ground truth.
- Hook→view wiring is the recurring harness bug class: an env hook parsed
  but not wired on ONE platform silently grades the wrong screen. Verify
  a hook fires on the platform under test before trusting a run.

## Standing prompt (what each wakeup does)

Work `docs/CAPTION-LOOP.md` top of the backlog; run/verify on the DEVICE;
update the loop log (VERIFIED vs MERELY-FIXED); commit + push; re-arm.
Never end a tick early for context reasons; a compaction lands here.
