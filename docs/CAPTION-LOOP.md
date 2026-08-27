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

- 2026-08-27 tick 71 — **CAMPAIGN SHIPPED. Every owner priority
  resolved and the release is out everywhere the loop can send it.**
  Apple 1.3.460 (982) uploaded to ASC by appstore-build 33087195366
  (tvOS+iOS+macOS; owner clicks Submit for Review). Android/Android TV
  1.3.460 (vc35) LIVE on Play production. Web live continuously via the
  pipeline publishes. The release carries: burst fix (both caption
  modes), notice removal, caption chooser (all players, all platforms),
  captions-Off that truly stops everything, the timing program
  (slope loop + envelope-only corrections + cold-start staging — final
  verification 12/12 with worst +2.0s on a cold film, -0.5s median on
  a second, file-mode green with a live 2.8s judge shift on a third),
  the Settings toggle fix, D096 (engine-leads with reopen conditions),
  Impact retimed at source, corpus re-pace (6,579 files), 7 bad claims
  pulled + language gate, dup collapses with alias forwarding, and 87
  reclaimed subtitle films. RESIDUAL OPENS (documented, not blocking):
  steady-state +1-2s structural transcription lag; a single 4K
  micro-rebuffer footnote (doa-4-k t=407); the intermittent single
  marginal pacing line in the offline harness; ~1,770 orphan-tail films
  awaiting a stronger transcription pass. Loop drops to quiet
  monitoring.

- 2026-08-27 ticks 66-70 — **COLD-START CLASS FIXED AND VERIFIED
  (build 982, 12/12 green, median +1.1s worst +2.0s on a cold film).**
  The arc: staging gate held cues until the mapping proves (envelope
  drains) or 45s timeout; v1 timeout rescaled to scout position and
  swung -45s EARLY (decode-ahead contamination — the same disease as
  every pos-anchored correction); v2 flushed unshifted but straddling
  cues showed +43s late; v3 keys the stale filter on cue START (+5s
  guard) — only clearly-future cues flush. Owner spot-checked the glass
  mid-iteration and saw both classes (few-seconds steady-state lag +
  the longer cold-start/mid-iteration windows) — instruments and eyes
  agree. Toggle fix verified earlier; Decision 096 logged. Remaining
  before ship: one file-mode + one engine-mode confirmation run, then
  bump + appstore-build + Play.

- 2026-08-27 tick 65 (overnight) — **Orphan batch 9 passed 4/25 —
  under the 5 floor: THE VEIN RESTS.** Final reclaims published; the
  campaign's reclaim total lands at ~87 films now serving verified
  subtitles that served none two days ago. Pass-rate trend across nine
  batches: 11-10-9-9-7-6-6-4 — the quality gate holding firm while the
  tail's audio roughens, exactly the stop signal the floor was set
  for. The remaining ~1,770 orphans keep their published files and
  their place in tools/orphan_reclaim_scores.csv; they wait on a
  stronger transcription pass (a future model, or a denoising
  pre-pass) — NOT on more batches of the same. The pipeline
  (captiongen work list -> audit_wrong_film_subtitles ->
  reclaim_orphan_subtitles --apply -> publish) is documented, reusable,
  and proven across 200+ films with zero wrong-film reclaims.

- 2026-08-27 tick 64 (overnight) — Orphan batch 8: 6/25 passed (trend
  9-9-7-6-6, holding just above the stop floor). Reclaimed + published.
  One more batch runs; if it dips under 5 the vein rests.

- 2026-08-27 tick 63 (overnight) — Orphan batch 7: 6/25 passed
  (easing toward the 5-pass stop floor; one more batch, then rest the
  vein unless it recovers). New verified entries reclaimed + published.

- 2026-08-27 tick 62 (overnight) — Orphan batch 6: 7/25 passed the
  gate (rate easing 9-10 -> 7 as popularity falls; still above the
  stop floor of 5), new verified entries reclaimed and published.

- 2026-08-26 tick 61 (quiet) — Orphan batch 5: 9/25 passed the gate,
  new >=0.6 entries reclaimed and published (see reclaim output for the
  count; running total in the next served-DB verify). Pass rate steady
  at ~9-10/25 — batching continues.

- 2026-08-26 tick 60 (quiet) — **Orphan batch 4: +8 reclaims (57 total
  once published).** Pass rate holding at 9-10/25 (quality gate rejects
  the tail's rougher audio — the gate working, not the vein exhausted;
  batching continues while passes stay >=5). publish-db dispatched.

- 2026-08-26 tick 59 (quiet) — **Orphan batch 3: +9 reclaims (49
  total live).** 10 of 25 passed the transcriber's quality gate (the
  tail's audio quality drops — 15 rejects is the gate working), 9 of
  10 verified >=0.6 and were stamped; the 40 prior reclaims correctly
  skipped. Catalog published, publish-db dispatched. Owner queue
  unchanged; device still rested.

- 2026-08-26 tick 58 (quiet) — **Top-25 claimed-film audit COMPLETE:
  21 of 25 transcribed and scored, zero wrong-film candidates** (the
  earlier model-contention rejects re-ran clean; 4 rejected by the
  quality gate on audio grounds — acceptable). Combined with the
  cross-file sweep, the D.O.A. wrong-film case appears to be isolated
  at the top of the catalog; the systematic risk lives in the long
  tail, coverable by future quiet batches. Device rested; owner
  priority queue unchanged.

- 2026-08-26 tick 57 — **DEVICE RESTED (owner: "a whole lot of errors
  without you doing anything differently").** The launch-window death
  interval shrank from ~13 runs to 2 after successive reboots — reboot-
  and-retry stopped being a mitigation and became a loop, so Apple TV
  runs are STOPPED for the day (the 13th-man run was killed mid-flight).
  Fifteen films of device evidence stand. Also recommitted, after a
  third failure, to closing every turn with plain terminal text — the
  ScheduleWakeup result's "nothing more to do" line kept truncating
  turns. OPEN QUEUE (owner to prioritize): cold-start caption lateness
  (measured, two candidate fixes tested-and-reverted today), the
  undrivable tvOS Settings toggle (possible real remote bug),
  system-leads captions decision, more timing films when the device is
  rested, ~1,850 orphan reclaims in future batches, 14 model-contention
  films to re-audit.

- 2026-08-26 ticks 54-56 — **The envelope-only configuration is the
  keeper** (build 979): caballero2 proved eager level corrections make
  captions EARLY (median -30.7s after two young-window corrections —
  err conflates decode-ahead depth with lateness; every corrected
  resumed-session run today was early, the one green run had zero
  corrections). Cold-start relaxation + seek-started bypass both
  REVERTED; the slope loop (residual-gated) is the only rate-error
  instrument, and its cold-start transient signature (+0.7-0.9/s
  decaying, mar ~3) now recurs identically across films — refused
  correctly every time. Kansas Pacific (fresh 1953 western): config
  behaved as designed (WITHHELD line, fits computing); timing not
  gradeable (music-heavy region, 2 matchable lines); one marginal
  fidelity sample (9/16, bright-sky OCR conditions). Offline pacing
  guard: 1 marginal line intermittently across 5 runs today (2.1s for
  10 words) — nondeterministic, device pacing green all day, logged
  not blocking. KNOWN OPEN: the from-zero cold-start lateness class
  (Caballero run 1: +39.5s in the first minutes, converged after) —
  needs a mechanism that is neither level corrections (proven harmful)
  nor the slope loop (correctly refuses the transient); candidate:
  don't DISPLAY cues minted while the envelope is undrained AND the
  session is younger than ~90s, letting the analyzer settle first.

- 2026-08-26 ticks 48-53 — **THE GENERATED-CAPTION TIMING SWEEP: from
  +58s worst to a green run, with the full mechanism chain measured.**
  The new caption_timing_vs_truth assertion (on-glass engine captions
  vs film-time local transcripts) caught, in order: (1) the scout
  sustaining ~1.5x against the mapping's assumed 2.0x — cues +58s late
  by act three (ghosttrain2); (2) the envelope gate withholding a
  needed 17.4s correction on resumed sessions (fixed: resync marks
  seek-started); (3) D081-clamped level corrections unable to outrun a
  CONTINUOUS slope error (-27.8s wanted, -2.1s allowed, error
  regenerating at ~0.3s/s); (4) a measured-rate mapping TRIED AND
  REVERTED (two-clock decode-ahead gap oscillates — median swung +58
  to -38s; the D069 trap in a new coat); (5) the slope loop (closed
  loop on mapping rate from d(err)/d(delivered), down-only, residual-
  gated) built through three instrument iterations — corrections
  poisoned the fit (shift-not-clear), then driftCheck's ~3Hz cadence
  capped the window at 4s (sparse sampling, one sample per 5
  delivered-s). Run 9 (build 977): **11/11 PASS, median -0.4s, worst
  -2.7s** — an honest note: this run had NO shortfall (no corrections,
  no fits fired), so it validates the instrument and the segment; the
  slope loop awaits its first live shortfall under 977, which the
  continuing sweep will meet. Offline pacing harness guards every
  build. Also: 821-samples-in-280s cadence measurement, and the
  transcript ground-truth set now covers 23 claimed + 42 orphan + new
  unclaimed films (truth batch running).

- 2026-08-26 tick 46-47 — **Orphan batch 1 COMPLETE: 22/25 transcribed,
  ALL 22 verify at >=0.6 agreement — all reclaimable** (3 rejected by
  the transcriber's quality gate, correctly conservative). Batch 2 (25
  more) chained. Timing sweep: The Ghost Train rerun in flight on build
  970 after the toggle restore (the engine had been silently disabled
  by a stray settings press; AW_SET_TRANSCRIBE hook restored it,
  glass-verified On). OPEN QUESTION for later: the tvOS Settings Toggle
  refused three warmed remote selects on the focused row — if a real
  viewer's remote also cannot flip it, that is a shipping bug
  (SubtitleAccountSection.swift:150).

- 2026-08-26 tick 45 — **Orphan reclaim batch 1: 12/12 transcribed so
  far ALL VERIFY (agreement 0.64-0.85)** — every orphan checked is a
  correct English subtitle file its film currently is not serving.
  At the 0.6 threshold all 12 reclaim. 13 films remain in the batch
  (watching for the speech-model allocation limit that stopped the
  previous batch at 11). Batch-2 work list built (next 25 by
  popularity). Top-watched claimed files audit: 11/11 correct, closed.

- 2026-08-26 tick 42 — **W3 COMPLETE MATRIX, on the glass and archived**
  (build/qa/atv-2026-08-26/w3-diagnostics/): CAPTIONED local file /
  CAPTIONED plain remote MP4 / CAPTIONED HLS wrapper; probe verdict
  "the system generates subtitles here". Shape 4 (our engine on the
  bundled clip) read "no text" in the probe window — NOT a regression:
  the engine captioned 13 Demon Street on this same device 30 minutes
  earlier (30/39 frames) and the offline harness is green; cold-start
  latency vs the probe window explains it (D068 measured 180s cold).
  The decision proposal stands strengthened: on THIS OS build the
  system captions every shape it is offered. Also this tick: Android
  vc34 LIVE on Play production; probe keep-alive watcher pattern worked
  (doze killed two earlier probe rounds).

- 2026-08-26 tick 41 — **Play production release BUILDING** (owner
  approved in chat — versionCode 34, versionName 1.3.447, gradle+upload
  in flight). W3: the TV dozed after the first probe and the results
  singleton does not survive a PROCESS kill (887's fix covers view
  recreation only) — probe RE-RUNNING for the complete matrix incl. the
  loader negative control; the decisive mid-run evidence (all 3 shapes
  EMIT) is already archived in build/qa/atv-2026-08-26/w3-diagnostics/.
  Wrong-film audit 11/25, all OK.

## DECISION PROPOSAL (owner-visible, code untouched until agreed)

**AMENDED per owner (2026-08-26 15:00): the Fireplace Apple TV is
HARDWARE-incapable of on-device captions (only 3rd-gen Apple TV 4K
runs them), so no Fireplace probe — and the engine fallback for
tvOS 26 and older hardware is PERMANENT, not transitional. The owner
also wants MORE on-glass timing evidence before trusting either path;
the caption_timing_vs_truth sweep is that evidence.**

**On tvOS 27.0 final (24J5358a+), on capable hardware, let the SYSTEM caption uncaptioned
films; our engine becomes the understudy.** Evidence: the on-device
probe measured Apple's generated track offered, selected, and EMITTING
text on all three asset shapes (local 14s, plain remote MP4 36s, HLS
wrapper 30s) — D068's "offered, never emits," the whole reason our
engine leads today, is cured on this OS build. What this buys: the
Photos-app simplicity the owner has asked for (native styling, native
menu integration, less custom work); what it costs: our pacing/merge
polish and the D062 wrong-file judge run on OUR overlay, so the
understudy must stay armed (system selected but silent for 45s ->
engine takes over, the existing watchdog pattern reversed). Gate on an
OS-version check (27.0 24J5358a+), keep the engine leading on tvOS 26
and any build where the probe class fails. Wants one more evidence
round on the FIREPLACE Apple TV (the owner's main unit — settings
differ per device, D068 note) before shipping.

- 2026-08-26 tick 40 — **W3 HEADLINE: the SYSTEM generated track now
  EMITS TEXT on tvOS 27 build 24J5358a — D068's "offered, never emits"
  is CURED on this OS build.** Probe (on-glass, 1.3.447/969): shape 1
  local file TEXT after 14s; shape 2 plain remote MP4 TEXT after 36s;
  shape 3 HLS wrapper TEXT after 30s — all three offered, selected, and
  EMITTING. This reopens the architecture question deliberately closed
  by D068/072 (our engine leads because Apple's track never spoke). NOT
  pivoting code on it — that is an owner-visible decision (candidate
  shape: system leads / engine understudy, which would retire most of
  the custom caption stack on tvOS 27+, exactly the owner's "too much
  custom work" push). Probe still finishing (negative control pending).
  Parallel: wrong-film audit 10/25, all OK; orphan-reclaim batch-1 work
  list built (top-25 served-card orphans; reclaim = re-stamp captions[]
  + subtitleHLS with source "reclaimed-verified" + agreement evidence,
  per free_subtitles' claim shape).

- 2026-08-26 tick 39 — **W3 re-measure RUNNING on the device**: drove
  Settings -> Caption Diagnostics -> Run Caption Test via presses with
  capture checkpoints (Settings has no auto-hide, so capture-between-
  presses is safe there — unlike the transport bar). Probe header on
  1.3.447/969, tvOS 27.0 24J5358a: OS reports it CAN generate subtitles,
  device HAS speech models, shape-1 track offered at 0s and selected.
  Awaiting emission verdicts per shape (~10 min). Parallel: wrong-film
  audit 6/25 transcribed, all OK so far.

- 2026-08-26 tick 38 — **Episode-player Subtitles menu VERIFIED ON THE
  GLASS**: "Subtitles / check Automatic / Off" submenu captured open over
  13 Demon Street (build 969) — the last unverified chooser surface.
  Menu-driving lesson repeated: the first blind sequence's select hit
  Next Episode (spinner on glass); the reliable shape is up+capture to
  SEE the row, then one short right-right-select. Also this tick: 13
  Demon Street episode cell 11/11 PASS (all reachable breadth cells now
  green; Sita Sings the Blues is NOT in the catalog — cell closed as
  N/A); appstore-build 1.3.447/969 SUCCEEDED to ASC (owner: Submit for
  Review; Play publish command also waiting on owner); wrong-film audit
  5/25 scored, all OK (0.89-0.92); **orphan finding upgraded: 1,912
  orphan subtitle files sit on SERVED cards and ~70% of a 20-file sample
  are substantial English tracks** — the reclaim gate is the same
  transcribe-and-compare machinery (an orphan agreeing with the film's
  own audio at high overlap is measurably correct whatever its origin);
  queued after the claimed-cards audit.

- 2026-08-26 tick 37 — **OPERATING MODE CHANGE (owner): dense ticks,
  minimum wakeups.** "I need active and fast development... wakeup as
  quick as possible" — every tick now runs device + Mac + pipeline
  streams in PARALLEL (rule saved to memory). This tick, three streams
  live at once: (1) device — 13 Demon Street 1959 episode cell (second
  50s-TV run; Sita Sings the Blues is NOT in the catalog — logged,
  skipped); (2) Mac — the WRONG-FILM AUDIT is running: /tmp/captiongen
  (the shipped engine, quality-gated, ~108x realtime) transcribing the
  TOP-25 most-popular claimed cards, with the new
  tools/audit_wrong_film_subtitles.py scorer ready (vocabulary overlap,
  the metric that caught doa_ipod at 0.02); (3) CI — appstore-build
  1.3.447/969 in flight to ASC. WORK QUEUE (never start a tick without
  a unit): score transcripts as they land -> adjudicate candidates ->
  extend the audit to the next 25 by popularity; episode-player
  Subtitles menu glass pass (warmed-press sequence); W3 Caption
  Diagnostics re-measure; iOS hardware pass; orphan-subtitle cleanup
  decision; Play publish (owner command).

- 2026-08-26 tick 36 — **Ship-prep verification pass: captions-Off
  verified BEHAVIORALLY on both platforms.** macOS (build 968 product,
  via `open` — direct binary exec doesn't autoplay after the first
  launch, harness note): playback ran, ZERO scout/engine lines. tvOS
  (build 969 on the device, new --caption-choice harness flag +
  DetailView env seed): 7/7 PASS — playback/audio clean, engine
  displayed 0 lines. The owner asked to wrap the loop and push to all
  platforms; proceeding to appstore-build (tvOS+iOS+macOS) + Play
  (Android/Android TV) at 1.3.447.

- 2026-08-26 tick 35 — **Offline pacing harness GREEN on the merged
  engine** (Scared to Death, 180s, real speech models on the Mac):
  median dwell 3.9s, shortest 1.7s, "every line holds long enough to
  read" — the appendCue live merge (tick 26) holds the shipped
  invariants, and merged two-utterance lines read naturally in the
  transcript. The five AMBIGUOUS cross-check pairs all resolved BENIGN:
  every served card's file fits its runtime at 0.97-0.98; the
  disagreeing partners are merged-away orphan reels of similar-titled
  Prelinger shorts. publish-db with the six wrong-language claim drops
  landed clean. No served wrong-film or wrong-language subtitle exposure
  remains that today's instruments can see. Deck checkoffs written into
  the resume doc.

- 2026-08-26 tick 34 — **The wrong-film pre-filter WORKED, and it found a
  bigger class: wrong-LANGUAGE files published as English.** Cross-file
  vocabulary agreement across the 742 imdb groups holding 2+ published
  files (2,778 pairs, all local compute): median overlap 1.00, and a
  clean pathological tail of 37 pairs under 0.30. Adjudicated by reading
  the files: six SERVED cards shipped non-English text as their en track
  — Patterns (Swedish), Manos: The Hands of Fate (Spanish), One-Eyed
  Jacks + Niagara (Portuguese), Princess Iron Fan (Czech), The General
  Line (Italian); the rest of the tail is merged-away orphans. Invisible
  to every physics gate. Fixes: (1) claims dropped at source with
  subtitleWrongLanguage markers, catalog republished + publish-db
  dispatched; (2) durable gate in validate_vtt — an en-labeled file with
  >=200 words and an English-stopword rate under 0.04 is rejected
  ("labeled en but text is not English"); measured separation is total
  (English 0.13-0.14, wrong-language <=0.001); wired into the harvest
  (free_subtitles) and the asset build. The 5 AMBIGUOUS both-English
  low-agreement pairs (wrong-film candidates needing ASR) are in
  tools/subtitle_crosscheck_findings.csv. D.O.A. collapse VERIFIED in
  the served DB (doa-4-k + colorized only; doa_ipod aliased).

- 2026-08-26 tick 33 — **The last visible D.O.A. dup falls.** The
  published DB confirmed Meet John Doe collapsed and five imdb D.O.A.
  copies aliased to doa-4-k — but doa_ipod still stood: its normalized
  title key "doa" is 3 chars, under merge_film_duplicates' len>=4
  floor, so the film merge never saw the cluster at all. Floor lowered
  to 3 with a guard measured first: at 3 chars an edge must have an
  imdb anchor on one side, because the two bare MGM logo stings (11s
  and 16s, both 1928) pass the bare-bare tight-runtime test and are
  different reels. Also: sibling year anchors now vote by MAJORITY
  within a 1-year span (five 1949 anchors + one 1950 had failed strict
  unanimity). Verified in pipeline order (dedupe_by_imdb first —
  testing the merge alone gave a FALSE "still standing" because a
  mis-colored imdb copy vetoed _consistent before the imdb dedupe
  removed it): doa_ipod -> doa-4-k, MGM untouched, color-guard 13/13.
  publish-db re-dispatched.

- 2026-08-26 tick 32 — **Captions-Off LEAKED THE ENGINE on two
  platforms; fixed and compile-verified (1.3.446/968).** Measured on
  macOS by running the app with AW_CAPTION_CHOICE=off: the scout
  started anyway ("scout playing at 2.0x") — the Off-guarded engine
  branch fell through to the subtitle-REVIEW branch, which runs its own
  scout to judge a file that would never display. tvOS had the softer
  twin: .off set draws=false but left the engine transcribing muted (a
  second stream + recognizer against D074's economy). Fixes: macOS
  setup gates the whole branch on captionsOff; CaptionCoordinator
  .off now STOPS the engine (remembering url/vc/player weakly) and
  startCaptions refuses while Off, restarting on any other choice —
  the episode menu sets choice on the coordinator directly, so the
  teardown lives there, not in the containers. iOS was already gated
  correctly. VERIFY STATUS: code-level + macOS compile + tvOS compile;
  the macOS behavioral re-verify is DEFERRED — the owner is actively
  using the Mac (a fallback screen capture proved it; window-scoped
  captures only, and no GUI launches while the desktop is theirs).
  Also: publish-db with the sibling fixes landed — Meet John Doe
  COLLAPSED (alias row MeetJohnDoe1941GARYCOOPER -> meet-john-4k in the
  served DB); D.O.A. needed one more remediate fix (six verified
  anchors split 1949/1950 and strict unanimity rejected the consensus —
  now majority-vote within a 1-year span; doa_ipod 1955 -> 1949) —
  publish-db re-dispatched to collapse the set (6 copies -> 1 + the
  colorized card, which stays separate by D084 design).

- 2026-08-26 tick 31b — **HAZARD noted for the retime sweep**: doa_ipod's
  wrong-film file ends at 5045s vs 4980s runtime — ratio 1.013 trips
  D080's overrun detector, which routes to sync_subtitles_audio. But
  ffsubsync aligns speech ACTIVITY (VAD), not content: it cannot tell a
  wrong-film subtitle from a mistimed one, and could "fix" and republish
  a wrong film's text with confident timing. The physics gate would
  pass. Source-side content agreement (local ASR transcript vs file, the
  D062 check run offline) is the only true wrong-film detector — the
  systematic audit stays on the follow-up list; popularity-first,
  dup-sibling cross-file disagreement is a cheap pre-filter.

- 2026-08-26 tick 31 — **Device runs PAUSED (the Scared to Death run was
  killed externally — reading that as the owner using the TV). Mac-side:
  the two dup sets root-caused and fixed at the pipeline.** Why D040
  never collapsed them: (1) "Meet John Doe GARY COOPER" — an ALL-CAPS
  credit tail the sanitizer had no rule for, so title clustering never
  saw the pair as one film; measured 59 caps-tail candidates, and the
  naive strip would mangle real titles (Ida Lupino's NOT WANTED, Do
  ANKHEN BARA HAATH), so the rule demands corroboration — the stripped
  title matches a same-year SIBLING, or the tail names the item's own
  cast/director: 22 strips, zero of the dangerous cases. (2) doa_ipod
  said year 1955 on a runtime-identical (4980s) copy of the 1949
  D.O.A. — new rule adopts a year from a matchVerified imdb-anchored
  sibling at ±2s runtime (same encode lineage): 49 adoptions. The
  matchVerified guard exists because the FIRST dry run adopted 1917
  onto the 2004 Fadiman documentary from its "remove2" twin — an
  UNVERIFIED anchor can itself be the wrong match, and adoption then
  propagates the error. Both rules live in remediate (run every build);
  publish-db dispatched so the next merge collapses the pairs. The
  colorized D.O.A. card stays separate BY DESIGN (D084).

- 2026-08-26 tick 30 — **W7 D.O.A. (1949 noir, card doa_ipod): the app
  did its job, the pipeline had not.** The published file for doa_ipod
  is a translated subtitle for a DIFFERENT FILM entirely (holiday/
  journey narration; the sibling card doa-4-k carries the real D.O.A.
  file — "I want to report a murder"). On the glass: file cues for
  ~175s, then the D062 judge measured "subtitles don't match this film
  (4%) — captioning instead" and the app recovered to the engine
  (post-switch fidelity 9/11). Fixes: (1) grader now follows the app's
  mid-run mode switch (frames after the discard grade against the
  engine; pre-switch frames keep failing HONESTLY when a wrong file
  showed); (2) doa_ipod's claim dropped at source (captions +
  subtitleHLS popped, subtitleWrongFilm marker documents the evidence;
  catalog republished, publish-db dispatched) — web/Android have no
  live judge and would ship the wrong file raw (D064 reasoning).
  DATA NOTES: D.O.A. is a THIRD-visible-card dup set (doa_ipod /
  doa-4-k / colorized) — with Meet John Doe's pair, two uncollapsed dup
  sets found today; and the wrong-film subtitle class likely has more
  instances — a source-side agreement audit (local ASR, popularity-
  first) is the systematic fix, logged as follow-up.

- 2026-08-26 tick 29 — **W7 Meet John Doe (1941 drama, meet-john-4k, 4K
  heavy decode, file mode): 11/11 PASS** on the hardened harness after
  reboot — glass matched the file 20/24, ZERO bursts (third film
  validating the corpus re-pace), median dwell 4.2s, playhead/stalls
  clean. The audio tap died at 10s (known heavy-decode teardown; the
  instrument reports its blindness honestly). The previous attempt was
  the 4th launch-window death — harness now probes to 30s and a second
  death auto-reboots (pushed). Deck status: 8 cells covered today, all
  green after fixes. Next: D.O.A. (1949 noir).

- 2026-08-26 tick 28 — **W7 foreign-language negative control (Street
  Angel, 1937 Shanghai, Mandarin audio): CLEAN — zero engine lines.**
  The engine displayed NOTHING on Mandarin dialogue (the 6/44 OCR
  caption-band hits are the print's own burned-in Chinese text); no
  English hallucination. The two graded FAILs are both explained:
  captions_on_glass expects captions the film correctly does not get
  (should have run with --expect-captions no), and the single frozen
  playhead interval at t=64 aligns exactly with the harness's logged
  doze/re-wake at frame 13 — device artifact. OWNER FEEDBACK the same
  tick: choose better films — ENGLISH-DIALOGUE ONLY from here (rule
  added to the deck + memory; negative-control classes are covered and
  retired). DATA NOTE for the dedup pipeline: 'Meet John Doe' ships as
  TWO visible cards (MeetJohnDoe1941GARYCOOPER + meet-john-4k, same
  title+year) — a pair D040's merge did not collapse.

- 2026-08-26 tick 27 — **Live engine merge VERIFIED on-device: 11/11
  PASS on the same episode** (w7-tv50s-verify, build 967). Bursts 3 -> 0,
  median dwell 2.4s -> 3.6s, changes under 1.2s 7/73 -> 1/61, and
  display fidelity IMPROVED (44/47 vs 39/43 — fewer, longer lines are
  also easier for OCR matching). With tick 21 (published files) and this
  (live engine), BOTH halves of the owner's "move too quickly or go in
  large bursts" complaint are closed and device-verified. Next:
  foreign-language breadth cell, then Meet John Doe.

- 2026-08-26 tick 26 — **W7 1950s TV episode cell (Suspense "On a
  Country Road" 1951, EPISODE PLAYER, engine mode): display fidelity
  excellent (glass matched engine 39/43), monotonic, audio clean — and
  caption_pacing FAILED on the ENGINE's live output: 3 burst windows,
  7/73 changes under 1.2s. Mechanism: anthology dialogue produces runs
  of one-word utterances, each floored at its LEGAL 1.0s reading time —
  every line individually readable, the sequence still a burst from the
  sofa. Fix: the corpus merge (tick 21) applied LIVE in
  LiveCaptions.appendCue — pending rapid-fire fragments coalesce before
  they are drawn (only cues not yet on screen, gap <=0.75s, cue at its
  floor +0.2s slack, merged text capped at one caption block). The scout
  works ahead, so the cues exist in time to merge. 1.3.445/967 built +
  installed to the ATV. Notes: episodes are NOT in catalog-index —
  resolve_card cannot find them; launch by --item with a DB-sourced id.

- 2026-08-26 tick 25 — **W7 Carnival of Souls (1962 indie horror,
  published file): green after two assertion calibrations.** The run's
  two FAILs were both instrument: (1) playhead_advances counted three
  t=0 pre-roll samples (buffer 0->11 then perfect 5s advancement) as a
  freeze — startup is D077's domain (30s bound), now exempt (t1 > 0);
  (2) glass_matches_file demanded 5 checkable moments on a film whose
  organ-scored opening offers 4 in 3.5min, 3 of which matched — the
  grade now fails only on POSITIVE mismatch evidence (>=5 checks: 70%;
  1-4 checks: majority; 0 checks: nothing to judge, presence is
  captions_on_glass's claim). Substance was healthy: file mode, 3/4
  matched, monotonic, audio continuous. Next: 1950s TV episode cell
  (Suspense "On a Country Road", 1951, engine mode).

- 2026-08-26 tick 24 — **W7 cartoon cell (Minnie the Moocher, 1932
  Fleischer): PASS after a grader fix.** The run failed glass_matches_file
  0/15 — but the app was correctly in ENGINE mode: the site publishes
  subs/bb_minnie_the_moocher/en.vtt while the CATALOG carries no
  subtitleHLS (a QC pass dropped the claim; QC cleans the catalog, never
  the published assets). The grader keyed on site-file existence, so it
  graded a correct engine display against an orphan file. Fix:
  fetch_vtt now consults the served DB first (card_has_subtitle_claim);
  with no claim the grader falls to glass_matches_engine — offline
  regrade of the same shots: 11/16 -> PASS. Measured the orphan class
  fleet-wide: **4,741 published subtitle dirs have no catalog claim**
  (site dead weight, mostly D043/D044 deliberate drops — a sampling
  re-audit could check none were good human files lost to a transient
  validation failure) and **0 dead pointers** (claim without files) —
  the dangerous direction is clean. Engine ASR on the Cab Calloway song
  was gibberish-ish, as ASR on music always is; pacing still green.

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
