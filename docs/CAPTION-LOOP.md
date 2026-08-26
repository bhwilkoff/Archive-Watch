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

- 2026-08-26 tick 23 — **W7 Day the Earth Caught Fire (1961 British
  sci-fi): captions fully green** — glass matched the UNSHIFTED file
  7/8, judge measured "subtitles match (24% agreement)" (D062's 27s-late
  finding for this title is cured in the card served today), 0 bursts
  (second film validating the corpus re-pace), monotonic. The one FAIL
  was the instrument: audio_continuous counted 11 metronomic exactly-10s
  emission gaps as dropouts on the LOUDEST track of the day (median rms
  0.046, zero stalls, playhead advancing) — the meter emits only when
  the tap delivered buffers that 5s window, and some mux shapes feed the
  tap in decode-ahead bursts while the renderer plays smoothly. Fixed
  the assertion: a gap counts only when CORROBORATED (zero-rms at an
  edge, or a stall/failure inside the window); uncorroborated gaps are
  reported as tap-delivery batching. Regrade of this run: 0 corroborated
  / 11 uncorroborated -> PASS. Next: cartoon cell (Betty Boop).

- 2026-08-26 tick 22 — **IMPACT 11/11 PASS — the burst complaint is
  CLOSED end-to-end on the film that reproduced it.** After F-9 (retime
  -22.03s at source) + tick 21's merge fix, w1-impact-verify3: glass
  matches the published file 22/23 (was 0/23), median dwell 3.8s (was
  2.0s), 1/45 changes under 1.2s (was 13/66), ZERO burst windows (was
  8-9), no judge shift, schedule monotonic, blanks all real gaps.
  One intermediate run died in the launch window (4th today) — reboot
  cured it again; if a 4th-plus death recurs, consider a pre-flight
  launch+kill warmup in atv_scenario. Next: Day the Earth Caught Fire
  (1961 breadth cell; its file was D062's 27s-late example, and the
  corpus re-pace touched most files — good compound check).

- 2026-08-26 tick 21 — **THE BURST FIX (F-10 root cause), fleet-wide.**
  Impact verify run: glass matched the UNSHIFTED corrected file (13/17),
  no judge shift — F-9 closed on the device — but pacing still failed
  (9 bursts on glass) and the published file itself measured 187
  three-in-3s windows, 112 cues under 1.0s, min dwell 0.35s. pace_vtt's
  1.0s floor was CAPPED BY THE NEXT CUE START: in rapid dialogue there
  is no empty space to extend into, so the floor was unachievable. Fix
  = `_merge_rapid_cues` in pace_vtt (build_subtitle_assets): contiguous
  fragments (gap <=0.75s) whose available span is under reading time
  merge into one cue (<=3 lines, <=120 chars; two short one-liners
  join into a 42-char line). Impact: 1,701 -> 1,269 cues, min dwell
  1.00s, 0 under 1.0s, bursts 187 -> 14, median 2.89s, monotonic, no
  overlaps. Applied CORPUS-WIDE with per-file safety gates (validate +
  monotonic + end-drift <=5s): **6,579 of 8,503 files re-paced, 3.22M
  cue adjustments**, 1,504 left untouched by the gate. Also caught
  before publish: ffsubsync had dropped Impact's X-TIMESTAMP-MAP header
  (iOS/macOS HLS caption timing) — restored; the merge pass preserves
  headers. Published through the guarded path. ATV re-verify of Impact
  queued against the merged file.

- 2026-08-26 tick 20 — **W7 White Zombie (1932 horror, colorized card,
  published file): 11/11 PASS** after the device reboot — median dwell
  4.4s, 0 bursts, 0 sub-1.2s changes, glass matched the published cue
  14/16, playhead/audio continuous, no notices. The two prior attempts
  died in the launch window (capture-daemon degradation — reboot is the
  cure, now twice-proven) and one launch env miss (atv_scenario needs
  DEVELOPER_DIR exported for devicectl). Impact verify run queued
  against the now-live corrected VTT (site serves first cue at 74.47s).

- 2026-08-26 tick 19 — **F-9 FIXED AT SOURCE and PUBLISHED**: ffsubsync
  against Impact720p's SERVED copy measured offset -22.03s, scale 1.000
  — exactly the -22.0s the 2026-08-10 sweep recorded for "Impact",
  proving the retime never landed in THIS card's published file (retime
  landed on a different card / was overwritten). Corrected, physics-
  validated, and re-paced (1,165 cues under reading time — F-10's scale
  in one film); published through the guarded path (8,503 files,
  deploy dispatched). ATV re-verify queued (expect: no judge shift,
  glass matches unshifted file, pacing green). White Zombie run died in
  the launch window again (second today post-reboot; capture-daemon
  degradation) — device rebooted, re-run queued; note the index serves
  a COLORIZED card for this title.

- 2026-08-26 tick 18 — **Breadth pays off run one: Impact (1949) is the
  first film to REPRODUCE the owner's complaint** (8 real burst
  windows, 13 sub-1.2s changes on the glass; w7-impact-file). Three
  finds: **F-9** the published VTT runs ~18.8s LATE against the served
  copy (the judge caught + corrected it live — likely a copy switch
  since the 2026-08-10 retime; pipeline invariant needed: a copy
  switch invalidates subtitle retimes); **F-10 FIXED** — none of the
  three source-level fixers (sync_subtitles_audio, fix_subtitle_sync,
  fix_subtitle_rate) re-paced after correcting, so D059 pacing never
  reached corrected files — all three now pace_vtt on write;
  instrument: glass_matches_file now honours the judge's live shift.
  Deck: Impact covered (engine of record = shifted file; pacing gap
  found). Next: Meet John Doe / White Zombie / cartoon / episode.

- 2026-08-26 tick 17 — **F-8 symptom VERIFIED FIXED on the Mac glass**
  (f8-verify.png): playback 3+ minutes in and advancing (both pre-fix
  runs froze inside the first minute) with an engine caption rendered
  mid-dialogue ("Right, Billy, he's thinking."). Honest caveat: this
  run never hit an idle reset, so the RESCUE itself has not been
  observed firing — the arm-condition fix is the same monitor already
  proven on the HLS path; a forced-stall pass (throttled server) can
  prove the fire later if wanted. This was also the W4 macOS behavior
  pass: Automatic on macOS = engine captions on the glass, VERIFIED.
  Owner directive landed mid-tick: BREADTH-FIRST deck (16 cells) —
  His Girl Friday retired to calibration duty; Impact (1949) running
  on the ATV as the first breadth cell.

- 2026-08-26 tick 16 — **F-8 found + root-caused + fixed (merely-fixed;
  verify run live)**: the macOS on-glass pass froze twice within the
  first minute (38s, 55s — window-scoped screenshots; the scout
  streamed the same file happily on its own loader, exonerating network
  + file). Root cause: the stall/failure rescue was armed only for
  subtitleHLS != nil, written before D067 gave uncaptioned films a
  plain AVPlayerItem(url:) — so EVERY uncaptioned macOS-27 film has
  played with no loader and no stall rescue since D067, frozen forever
  by one archive.org idle reset. Fix: the direct-URL branch arms the
  same CaptionStallMonitor + failed-status rescue (rebuild on the
  resilient loader, resume position); the fallback no longer
  double-starts the engine and honours captions Off. AW_CAPTION_CHOICE
  env hook added (harness-drivable choice). Verification run playing
  now. Also: mac captures are WINDOW-SCOPED from here (the first was a
  full-desktop grab — privacy lesson).

- 2026-08-26 tick 15 — **W4 macOS parity BUILT (merely-fixed)**: the
  shared sheet's picker now feeds macOS through a session store
  (Detail and the player are different WINDOWS on macOS, so a local
  @State cannot reach across; CaptionChoiceSession carries it).
  Automatic/Off drop the captioned-HLS wrapper at the player-window
  call site; Off also gates startLiveCaptions. All three platforms
  build green (1.3.443/965). W4 now spans tvOS (glass-verified) + iOS
  (sheet-verified) + macOS (build-verified). TV left alone again this
  tick. Remaining W4 tail: macOS on-glass pass, iOS hardware behavior
  pass, episode-menu glass pass.

- 2026-08-26 tick 14 — **W4 iOS parity: picker UI VERIFIED in the sim,
  plumbing merely-fixed** (build/qa/ios-2026-08-26/w4-ios-picker.png):
  the subtitles sheet gains "Captions for playback" — Subtitle File /
  Automatic / Off segmented, defaulting to File on file films — and the
  choice reshapes the ASSET at playback start in PlayerView_iOS (File =
  captioned-HLS; Automatic/Off = plain paths, engine gated off for Off).
  Also fixed a reachability gap the change exposed: the subtitles
  button only showed for films WITHOUT subtitles, making the picker
  unreachable exactly where choosing matters — it is now the caption
  hub for every playable title. iOS + tvOS build green (1.3.442/964).
  Behavior half needs hardware with speech models (owner's iPhone) —
  the TV was deliberately left alone this tick (owner is at it).

- 2026-08-26 tick 13 — **W7 silent negative control VERIFIED** (clean
  re-run w7-silent-rerun-1787756457, app alive throughout): the engine
  displayed ZERO lines across a 4-minute silent-film run — no
  hallucinated captions from the musical score, no notices. The 6
  flagged frames were Caligari's OWN intertitle cards in the OCR band
  ("MIRACLES! SIDESHOWS — ALL NEW"); the assertion now judges the
  engine's display trace, not the film's printed text. Owner watched
  this run live and correctly noted the film has no dialogue — that was
  the point of the control, and the app behaved exactly right.

- 2026-08-26 tick 12 — **Caligari negative-control run INVALIDATED, not
  failed**: the app died ~7s post-launch and the 25/25 "captions" were
  home-screen labels (A0 caught it). Bisect on the device: with
  AW_NO_CAPTIONS alive at 40s, WITH captions ALSO alive at 40s + engine
  running + playback ready — the death does not reproduce without
  capture pressure, so it lands in the documented observer-artifact
  class (launch-window jetsam under 4K captures, heavy pre-reboot day).
  No app bug chargeable on this evidence; clean re-run queued. Harness
  self-lesson: my own bisect loop retried launches 45x against a
  SLEEPING TV — raw devicectl launches must wake first, always.
  (W3 macOS re-measure skipped deliberately: this Mac is still build
  26A5388g, the exact build D067 measured — re-running is repetition,
  not measurement. The tvOS-side W3 re-measure remains queued.)

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
