# Caption Loop — the automatic-captions campaign (owner brief 2026-08-26)

Owner's brief, verbatim anchors: captions "generate pretty consistently.
However, they are often wrongly timed (move too quickly or go in large
bursts)"; the "Generating Automatic Captions" notice on Apple TV "shows for
far too long and is almost entirely unneeded"; "Automatic captions happen
perfectly within the Photos app on my phone for any video that has even a
little bit of audio. I want it to be this simple and fluid… on any apple
device that is capable"; "we are still utilizing too much custom work and
getting in our own way rather than using the default way"; "I also still
don't see any way to choose between the different captions types… (choosing
automatic captions vs a transcript/subtitles file)"; the iPhone captions
info sheet is "cut off on the sides"; "create a comprehensive audit of all
screens that you can test and go through many different videos (different
eras, genres, etc.)".

**The bar: the Photos app.** No notices, no ceremony — captions simply
appear, correctly timed, on any device that can make them.

Method: `docs/AUTONOMOUS-LOOPS` + `DEVICE-HARNESSES` doctrine in the
Universal template; harness = `tools/atv_scenario.py` + ScreenOCR +
`AW_CAPTION_TRACE` diag, extended per the Tidbits upgrades. All three
physical devices are paired: Ben Bedroom (Apple TV 4K, tvOS 27), Ben 15 Pro
(iPhone), iPad Pro 12.9. Simulators have NO speech models — engine behavior
is verified on hardware or the Mac harness only.

## Workstreams

- **W1 — Timing correctness** (bursts, too-fast): measure on-glass cue
  timing against locally transcribed ground truth per era/genre; suspects:
  display pacing (D059), analyzer batch finalization (bursts = late-final
  cues arriving together), scout-rate mapping, drift clamps (D081).
- **W2 — Notice removal**: DONE in code (the "Preparing automatic
  captions…" branch deleted; model-download + failure notices remain).
  Verify on the ATV: no notice across warm-up on 3 films.
- **W3 — Default-first architecture**: re-measure the SYSTEM generated
  track on CURRENT tvOS/iOS/macOS 27 builds (D068's "offered, never
  emits" was measured on an early beta; the OS has moved). Wherever the
  system emits, IT leads and our engine becomes the silent understudy
  (D063: the system declines poor archival audio, so the fallback stays).
  Target: delete custom arbitration wherever the OS now does the job.
- **W4 — Caption-type picker**: a Subtitles chooser in every player —
  Off / Automatic (engine or system) / Subtitle file (published VTT) /
  per-language human tracks — mirroring the video-source chooser. tvOS:
  transport-bar menu (the D070 parity follow-up). iOS/macOS: integrate
  with the native CC menu where tracks exist; add Automatic as a choice.
- **W5 — iPhone info sheet clipped**: DONE in code (fixed 460 pt width →
  cap). Verify on iPhone hardware/sim at portrait widths.
- **W6 — Screen audit**: every caption-touching surface on every Apple
  platform — Detail (Get Subtitles sheet), player overlay + notice, player
  CC/type menu, Settings (Automatic Captions section, Caption Diagnostics
  screen on tvOS), OpenSubtitles account flow — driven by deep-link env
  hooks, screenshot/OCR evidence per screen.
- **W7 — Era/genre video matrix** (each with era-appropriate expectations;
  a SILENT film generating captions is a FAILURE of the negative control):

| Era/genre probe | Expectation |
|---|---|
| Silent (1920s) | no captions generated, no notice, no failure text |
| Early talkie (1929–33, rough optical audio) | system may decline; engine captions or stays honestly silent |
| 1940s noir (dialogue-dense) | timed captions, no bursts, reading-pace hold |
| 1950s TV episode | as noir; episode player path |
| Narration documentary | long unbroken narration — burst stress case |
| Music-heavy / cartoon | sparse speech — no phantom cues during music |
| Published-VTT film | file track leads; judge only shifts on evidence (D073); picker can switch file↔automatic |
| Mistimed-VTT film | judge corrects or engine takes over; picker shows both |

## Evidence rules (binding)

On-glass OCR or it didn't happen (tvOS scenario runner; devicectl
screenshots on iPhone/iPad). Ground truth for timing = local transcription
of the exact film region (D069). Release builds for ship gates; throttled
runs for anything touching the loader. Every tick logs VERIFIED vs
MERELY-FIXED below. One experiment per process for platform-behavior
probes.

## Loop log (newest first)

- 2026-08-26 tick 11 — **W4 chooser fully VERIFIED on the glass, all
  three states**: checkmark tracked File→Automatic (menu-check-auto.png,
  with an engine line visible behind the open menu); Off registered
  ("caption choice -> off") with an EMPTY caption band on every
  following frame (w4-off-1787755586). Two harness mechanisms nailed:
  the mystery "restarts" were stray down+select presses hitting the
  native "From the Beginning" control after the menu auto-closed; and
  cumulative Companion press DECAY was eating selections — a device
  reboot restored 100% delivery (Tidbits' F-009 economy, now proven
  here). Episode-player menu remains build-verified only (reaching
  EpisodeAVPlayerContainer needs series drill-in navigation).
  W7 silent negative control (Caligari) launched.

- 2026-08-26 tick 10 — **W4 movie-player VERIFIED on the glass**
  (build/qa/atv-2026-08-26/w4-menu3): the Subtitles menu renders with
  the checkmark on Subtitle File (menu-open.png), selecting Automatic
  registers in the app's own diag ("caption choice -> automatic"), the
  engine resyncs to the playhead, and the glass shows its line at the
  playhead (auto-live.png "And a match." == the display trace).
  Choreography lesson learned the hard way: menu driving must be ONE
  unbroken warmed connection with inline delays — screenshots between
  steps outlive the bar's ~5s auto-hide, and stray presses SEEK the
  film (an earlier attempt silently seeked to 0 and read like a crash;
  the diag exonerated the app — no "caption choice" line, one LAUNCH).
  Episode-player menu + Off state still to verify.

- 2026-08-26 tick 9 — **F-3 VERIFIED FIXED on the device**
  (f3-tim-verify-1787753997, 1.3.440): 53 displayed cues, 0 ran
  backwards (was 2); ZERO drift corrections fired (was 6), one loud
  WITHHELD line naming the mechanism (floor 19.9s, chunk-deep tap
  decode-ahead). The lone pacing "burst" was legitimate rapid dialogue
  with readable dwells — grader tuned: a burst counts only when a dwell
  inside it is <1.0s (unreadable). W1 engine timing is now GREEN across
  the board on this film.

- 2026-08-26 tick 8 — **W4 episode-player parity BUILT (merely-fixed)**:
  the tvOS episode container gains the same Subtitles chooser
  (Automatic / Off — episodes are engine-only today) with checkmarks and
  menu rebuild on selection. Also confirmed episodes DO carry engine
  captions (the container grew liveCaptionURL in an earlier wave — my
  first read of the screen file was wrong; the wiring lives in the
  container). Builds green, 1.3.441/963. On-glass verification of both
  menus queued behind the F-3 verify run.

- 2026-08-26 tick 7 — **F-3 ROOT-CAUSED + fixed (merely-fixed, re-run
  queued)**: H1 (pause/resume) REFUTED by the trace — corrections #1-4
  all predate the first pause, firing every 25s from cold start with a
  floor (20-39s) that NEVER drained. Mechanism: on a chunky-interleave
  file the tap runs a permanent audio-chunk ahead of the scout's render,
  so D074's "healthy floor touches ~0" premise fails and every
  correction was SPURIOUS — six of them dragged correct cues -23s early
  and swapped a line mid-read each time. Strongest candidate yet for the
  owner's "wrongly timed". Fix: the envelope must prove itself on THIS
  file (floor < 5s once) before any correction on a from-zero session;
  seeked sessions — the only ones that can carry D074's injected burst —
  keep first-window correction rights. 1.3.440/962 built + installed;
  TIM re-run queued.

- 2026-08-26 tick 6 — **W1 engine run: pacing GREEN in engine mode too**
  (median dwell 4.4s, 4/67 fast, 0 bursts; glass_matches_engine 45/45;
  w1-tim-engine-1787753183). **F-3 OPEN**: caption_schedule_monotonic
  failed — 2 displayed cues ran backwards (worst -2.5s), each at the
  instant of a CLAMPED drift correction (#3: -19.5→-0.9s, #4:
  -18.7→-2.5s, "mapping floor ran ~27s ahead of the scout"). The clamp
  contains the harm to ~2s mid-read line swaps, but FOUR corrections in
  5 minutes on a healthy stream says the drift ESTIMATOR is over-firing
  — that is the root to chase (D074 lower-envelope), not the display.
  1.3.439 (W4 chooser) installed on the ATV for on-glass verification.

- 2026-08-26 tick 5 — **W4 tvOS chooser BUILT (merely-fixed)**: the
  transport bar's binary "Subtitles On/Off" is now a "Subtitles" menu —
  Subtitle File / Automatic / Off with checkmarks, mirroring the Version
  menu. CaptionCoordinator gained setCaptionChoice (an explicit File
  choice outranks the judge's discard — viewer agency; Automatic revives
  the engine via the existing resync path). tvOS builds green
  (1.3.439/961). NOT yet on-device-verified; install after the W1 run
  frees the ATV, then drive the menu with warmed presses. iOS/macOS
  pickers + episode player parity still open.

- 2026-08-26 tick 4 — **F-1 CLOSED, 10/10 green** on the honest re-measure
  (w2b-hgf-honest-1787752837): 21 blank ticks, 0 dropped cues; W2
  re-confirmed 0/41. Second instrument gap found by absence: the diag
  parser matched " show: " while the trace emits "show[cue=…]:" — pacing
  never graded. Fixed; validated against the real diag: 79 lines
  recovered, FILE-mode pacing is CLEAN (median dwell 2.94s, 0 fast, 0
  bursts). The owner's too-fast/burst complaint is therefore expected in
  ENGINE mode — Incredible Machine run queued.

- 2026-08-26 tick 3 — **W5 VERIFIED**: the subtitles sheet renders fully
  inside the sheet bounds on the iPhone 17 Pro simulator (same film as the
  owner's clipped screenshot; build/qa/ios-2026-08-26/w5-sheet.png). Added
  the AW_SHOW_SUBTITLES screen-audit hook (simctl cannot tap; a sheet
  nobody can open unattended is a sheet nobody can regression-test). The
  capability branch also verified: a model-less simulator correctly says
  "can't caption films by itself". Owner-device confirmation still worth a
  glance since the 27 branch shows different text.

- 2026-08-26 tick 2 — **F-1 root-caused as an INSTRUMENT defect**: in file
  mode the caption trace diagnosed blanks against the ENGINE's cue list
  while the display renders fileCues — a normal file-cue gap graded as
  "5 caption drops" (cross-source evidence). Trace now reads the same list
  the display renders (1.3.437/959, installed). Honest re-measure of
  w2-hgf queued. Display loop cadence measured: 150ms (quantization
  exonerated).
- 2026-08-26 tick 1 — **W2 VERIFIED on the glass**: 'Preparing…' on 0/52
  frames through a cold-start warm-up (build 958, w2-hgf-1787752331);
  9/10 assertions green incl. glass_matches_file 46/49. Upgraded runner's
  polled wake + durable run dirs worked first try.

- 2026-08-26 — Campaign opened. W2 + W5 fixed in code (unverified);
  architecture mapped: iOS runs BOTH system captions and our engine with
  hand-over arbitration; tvOS engine-only (D072). Devices confirmed
  paired. Tidbits harness survey in flight.
