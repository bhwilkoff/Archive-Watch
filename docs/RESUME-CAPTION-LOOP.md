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

## The breadth deck (OWNER RULE 2026-08-26: a wider swath, never the same film twice)

**Second owner rule (2026-08-26): ENGLISH-DIALOGUE films only.** A
foreign-language film has no English speech to caption, so it tests nothing
a viewer cares about here. The one language-mismatch negative control
(Street Angel, w7-foreign) is done; never schedule another non-English
title unless the owner asks for that class specifically. Check the card's
language in /tmp/catalog.sqlite before picking.

Every run picks a NEW title. His Girl Friday is RETIRED except as a
one-run calibration control after an instrument change, or to re-verify
a fix on the exact film that exposed it. Covered so far: His Girl Friday
(file mode), The Incredible Machine (engine/narration), Caligari
(silent negative control). Uncovered cells, work top-down and CHECK OFF
in the loop log:

- Impact (1949 noir; corrected published VTT — file mode on a non-HGF file)
- Meet John Doe (1941; engine on 40s optical sound)
- The Day the Earth Caught Fire (1961; the historically-27s-late VTT, now corrected)
- Night of the Living Dead (1968; engine)
- White Zombie (1932 early talkie, poor audio — system-declines class)
- Carnival of Souls (1962; known-poor audio, judge calibration case)
- The Vampire Bat (1933; corrected VTT)
- Horror Hotel (1960; corrected VTT)
- Scared to Death (1947 colour; engine)
- D.O.A. (1949; engine)
- a Popeye or Betty Boop cartoon (music-heavy; near-negative control)
- Steamboat Willie or another 1920s cartoon (silent negative control #2)
- a 1950s TV EPISODE via series drill-in (episode player path!)
- a foreign-language film (what does the engine do with non-English speech?)
- Sita Sings the Blues (2008 music-heavy colour; modern audio)
- The General (1926; silent negative control #3)

Titles resolve by TITLE at runtime (resolve_card); if one is missing
from the catalog, log it and take the next. The finds come from
VARIATION (Tidbits reshape lesson + owner directive).

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

- Background scenario runs: NEVER pipe through `tail` (a killed task then
  shows zero output — stream raw and read the file); keep runs ≤ ~7 min
  total (background tasks can be reaped); the durable run dir survives a
  kill and says how far it got.
- Transport-menu driving: ONE atvremote invocation, one connection —
  `power_state up delay=1400 right delay=800 ... select` — never
  screenshots between steps (the bar auto-hides in ~5s and stray
  presses SEEK the film). Verify a selection by its diag line
  ("caption choice -> ..."), then the glass.

## Standing prompt (what each wakeup does)

Work `docs/CAPTION-LOOP.md` top of the backlog; run/verify on the DEVICE;
update the loop log (VERIFIED vs MERELY-FIXED); commit + push; re-arm.
Never end a tick early for context reasons; a compaction lands here.
