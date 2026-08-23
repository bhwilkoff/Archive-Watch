# Archive Watch — Architecture Decisions 061-080 (archive)

Verbatim archive of DECISIONS.md entries 061-080, moved here 2026-08-23 to
keep the always-in-context DECISIONS.md small (Decision 092). The
append-only rule still binds: never edit or remove these entries.
The index of every decision lives in /DECISIONS.md.

---

## 061 — From 27 the SYSTEM captions our films; the app's job is to get out of the way
*Date: 2026-08-10*

Apple generates subtitles on device for video that carries none, from iOS/tvOS/
macOS/visionOS 27, automatically, for any app using AVPlayerViewController or
AVPlayerView — which all three of ours do. So the implementation is subtractive:
`SystemCaptions.waitForLegibleOption` polls the player for a legible option, and
when one exists `LiveCaptions` never starts on any platform. Apple's own
captions win: they live in the native subtitle menu, obey the viewer's
Accessibility caption settings and style, survive scrubbing, and cost no second
stream.

**Why**: two things had to be true before the app could rely on it, and neither
was answerable from Apple's documentation — the WWDC26 session names HLS and
file-based content, and archive.org serves a PROGRESSIVE MP4 through a custom
`AVAssetResourceLoaderDelegate`, which is exactly the property that disqualifies
us from video AirPlay (Decision 051). Measured on macOS 27.0 (26A5388g) against
a live archive.org film, both answers are yes within one second, direct AND
through the shipped `ResilientStreamLoader`:

    plain https MP4:              1s — 1 option(s): English (US) Transcribed
    through ResilientStreamLoader: 1s — 1 option(s): English (US) Transcribed

Without the stand-down, upgrade day would have produced DOUBLE captions on every
uncaptioned film — the system's track and our differently-timed overlay on top of
each other — on iOS and macOS, where our engine works. That regression was
already live on this macOS 27 machine and is what the harness caught.

**How to apply**: never draw captions over a player without first asking whether
the system already offers a legible option — `AVPlayerItem.
selectableMediaSelectionOptions(in:)` (new in 27) is where a generated track
appears, since it is not in the file and the asset's own group cannot list it.
Do NOT auto-select the generated option on the viewer's behalf: whether captions
appear is their Accessibility preference, and our old always-on overlay was
quietly overriding it. Do not add an app setting for generated subtitles —
Apple's session is explicit that no opt-in exists, and a toggle that controls
nothing is the dead control Decision 056 already removed once. Keep
`tools/test_system_generated_subtitles.swift` green: it runs the shipped loader,
so it will notice if a change there ever costs us the system's captions the way
one cost us AirPlay.

**Consequences**: on 27, tvOS finally gets captions — the platform Decision 060
showed can never run our own engine, because an Apple TV has no speech models.
Nothing needs to ship for that: a device upgrading to tvOS 27 captions our films
whether or not the app is rebuilt. What this build adds is the stand-down, so
the platforms that DO run our engine hand over cleanly instead of doubling up.
Below 27 nothing changes: no legible option ever appears for a bare MP4, the
poll costs one wait, and `LiveCaptions` proceeds exactly as before.

## 062 — A published subtitle track is checked against what is being said, not trusted
*Date: 2026-08-10*

When a film ships with subtitles, the app now listens to the first ~3 minutes
with the `LiveCaptions` scout, compares the published cues against its own
transcript (`SubtitleAgreement`), and acts on one of three verdicts: keep the
file as published (and stop listening); SHIFT it, showing the same human words
at corrected times through our overlay; or abandon it and caption live, because
the file belongs to a different cut or a different film. Wired on iOS, macOS and
tvOS (`SubtitleReview`).

**Why**: owner report — "many times the automatic captions are far better than
the subtitles file". A published file goes wrong in two ways that are both
invisible until somebody watches: it belongs to a DIFFERENT CUT (the failure
Decision 026 exists for, on the subtitle plane), or it is RIGHT BUT OUT OF SYNC,
which is by far the commoner fault. Neither is judgeable from the file alone —
and both are obvious the moment there is an independent estimate of what is
being said, which the device now produces for free. Measured while building
this: **The Day the Earth Caught Fire ships with its subtitles 27 seconds
late.** That is not a subtle defect; it is unwatchable, and it looks like a
broken app rather than a broken file.

Keeping the two faults distinct is the point. A mismatched file should be
abandoned; a shifted one must be SHIFTED, because human words with corrected
timing beat a machine transcript on both text and timing, and discarding it
would throw away the better source.

**How to apply**: score word PRESENCE near the expected time, swept over
candidate offsets — never sequence alignment. A machine transcript mishears
individual words constantly, and demanding order scores a good match as a bad
one. Drop words under four characters: an unrelated file scores well on "the"
and "a" alone, which is the exact false match this exists to catch. Calibrate
thresholds against real files and re-measure when the recognizer changes — a
true match scores ~44% and a mismatch ~3%, so the separation is wide but the
absolute numbers are LOW, and the first thresholds (guessed at 0.55) rejected a
genuinely matching file. State the correction as "seconds to ADD", never "how
late it is": the second phrasing is what produced a sign error that moved a
27s-late file further out of sync. Returning NO VERDICT is a valid answer and
must stay distinct from disagreement — silence, an intertitle stretch or a
sparse transcript are not evidence against a file.

**Consequences**: a captioned film now costs a bounded second stream (~3 minutes
at the scout's 2x) to be checked, and nothing after that — the scout stops on a
verdict. `Catalog.Item.publishedVTTURL` exposes the cue text the check needs.
The same judge could run in the PIPELINE to find mistimed files catalogue-wide
rather than per-viewer, on a machine that has speech models (Decision 060 rules
out hosted runners) — the 27-second file above is unlikely to be alone, and
fixing them at the source would help web and Android too.

## 063 — Hand captioning to the system only when it actually captions THIS film
*Date: 2026-08-10*

Decision 061 stood our engine down whenever the player offered a legible option.
That is amended: it stands down only after the system's track has been observed
to EMIT TEXT (`SystemCaptions.emitsCaptions`, via `AVPlayerItemLegibleOutput`
attached observe-only). Offering a track and producing captions are different
claims, and on this catalogue they come apart.

**Why**: measured on macOS 27 across three films. The system offered "English
(US) Transcribed" on all three and produced cues on ONE — *The Incredible
Machine* (1975), a clear narration. On *The Day the Earth Caught Fire* (1961) and
*Meet John Doe* (1941) it emitted **nothing at all** across five minutes each,
including with nothing else running in the process, while our own engine
transcribed both — 57.4% and 55.3% word error against their aligned published
human tracks. It appears to decline rather than guess on poor archival optical
sound, which is most of what this app holds. Standing down on the mere presence
of a track would therefore have left viewers with NO captions on exactly the
films that need them most, while the app quietly held an engine that would have
produced something.

Which of the two is more ACCURATE remains unmeasured: no film yet tested both
produced system captions AND had a human reference to score against. The
comparison harness is `tools/compare_caption_sources.swift` and it aligns the
reference before scoring — the first version did not, and reported 67.7% for a
transcript that scores 57.4% once the reference's own 27-second sync error is
removed (Decision 062). A benchmark that measures the reference's sync error and
calls it the engine's word error is worse than no benchmark.

**How to apply**: never treat an available caption track as a working one — for
the system's generated track, for a published file (Decision 062), or for a
future source. Attach the legible output observe-only
(`suppressesPlayerRendering = false`); suppressing rendering to inspect a track
would blank the very captions being checked. Keep the wait bounded (~75s): the
system's cues arrive in late batches, measured ~75s behind the playhead, so a
short check would wrongly conclude silence. If a later OS starts captioning
these soundtracks, this needs no change — it observes rather than assumes.

**Consequences**: on a film the system declines, the viewer gets our captions
instead of nothing, at the cost of one bounded extra stream. ~55% word error on
1940s–60s optical sound is the honest number for what an on-device recognizer
achieves here; it is not good, and it is a great deal better than a blank
screen. The two engines' relative accuracy is still an open question and needs a
film where both produce output.

## 064 — Mistimed subtitle files are corrected at the SOURCE, which is the only way most platforms get them right
*Date: 2026-08-10*

`tools/subtitle_sync_main.swift` (transcribe + judge) and
`tools/fix_subtitle_sync.py` (work / apply / publish) sweep the published
subtitle set, measure each file against a transcript of its own film using the
SHIPPED `SubtitleAgreement`, and rewrite the cue times of the ones that are out
of sync. Corrections go into `subs.tar.gz` on the `subtitle-assets` release,
which `deploy-pages` restores into the site — so one fix reaches web, Android
and every Apple platform at once, with no app build.

**Why**: Decision 062 checks a published file per viewer, per playback, but only
where the device can transcribe. That excludes **web** and **Android**, which
have no on-device transcription available to them at all, and **tvOS 26**, which
has no speech models (Decision 060). Those three platforms cannot help
themselves, and they are most of the audience. A file corrected at the source is
the only route by which they ever show the right subtitles — and it also spares
the platforms that CAN self-correct from doing the same work on every playback.

First real sweep, popularity-first: *Impact* (1949) ran **22 seconds late**
(agreement 6% → 60% once corrected) and *The Vampire Bat* **31 seconds late**
(5% → 37%). Both are now correct on every platform; verified live on
archivewatch.org after deploy.

**How to apply**: this cannot run in CI — a hosted runner has no speech models
and cannot install them (Decision 060), which is exactly what killed the central
auto-caption pipeline. Run it on a machine that has them. It is resumable
(verdicts append to JSONL, decided films are never re-listened to) and ordered by
popularity, because a mistimed file on a film nobody opens matters less than one
on the front page.

`apply` rewrites SHIFTS by default and only REPORTS mismatches. Deleting a
subtitle set is destructive and irreversible from a local snapshot, and the
mismatch threshold is not validated at this scale — the same precision-over-
recall rule that governs hiding items (Decisions 027/035/044). The first batch
justified that caution immediately: *Carnival of Souls* was judged a mismatch at
12%, and its audio is the known-bad case already on record in
`CaptionQuality`'s calibration (49 wpm) — a poor transcript, not necessarily a
wrong file. `--drop-mismatched` exists for when the evidence is reviewed.
Silence is never evidence: `unheard` and `no-verdict` change nothing.

**Consequences**: `publish` refuses to upload a set smaller than 7,000 files,
because republishing a shrunken snapshot would delete subtitles wholesale — the
failure that once served `404.html` as VTT with HTTP 200 (Decision 043 era). The
sweep runs at roughly one film every 2–3 minutes, so 7,391 films is a long
background job rather than a session; it is built to chip away, and the
popularity ordering means the value lands first.

## 065 — Generated subtitles need a track SELECTED and an asset without our resource loader
*Date: 2026-08-11*

Amends Decision 061, which was wrong on the load-bearing point. Handing captions
to the system now runs a full sequence (`SystemCaptions.handOver`): wait for an
offered option, SELECT it, confirm text actually flows, and — if it does not —
replace the player item with the DIRECT https URL, select again, and confirm
again. Our own engine stands down only when that ends in real text.

**Why**: an Apple TV on tvOS 27 showed file-based captions perfectly and never
an automatic one. Two independent causes, both measured on macOS 27 against a
live film:

1. **Nothing selected the generated track.** A published track rides a master
   playlist we generate, which declares `AUTOSELECT=YES,DEFAULT=YES`, so
   AVPlayer switches it on. A generated track is merely offered; the system
   lists it in the subtitle menu and leaves it off. That difference is entirely
   ours, and it is exactly the asymmetry the owner saw.
2. **Generated subtitles do not work through a custom `AVAssetResourceLoader`.**
   Same film, same moment:

       plain URL      option offered · first text at 34s
       aw-stream://   option offered · NEVER any text

   The system advertises the track either way and silently produces nothing
   through the loader — the same disqualification that rules out video AirPlay
   (Decision 051).

Decision 061 recorded that this DID work through the loader. That test only
checked an option was OFFERED, never that text was produced — the precise
distinction Decision 063 was written about two decisions later, applied to
everything except the measurement that started it.

**How to apply**: never treat an offered caption track as a working one, in any
direction — this is the third time that mistake has cost something (the poster
liveness gate, the system-declines case, and now this). Select before judging:
an unselected track emits nothing, so an emission check run first measures the
selection, not the recognizer. Keep the resilient loader as the DEFAULT and swap
only after the system has been given a fair chance and failed — films the system
was never going to caption keep Decisions 021/031/034 intact, and only the films
that gain captions pay for them. Never override a selection the viewer has made.
On swap, carry `externalMetadata` across on iOS/tvOS and NOT on macOS, whose
`AVPlayerItem` has no such property at all.

**Consequences**: a film the system captions loses resume-on-reset and node
failover for the rest of that playback. That is a real cost, accepted knowingly
because the alternative on an Apple TV is no captions at all — tvOS has no
speech models of its own (Decision 060), so the system's generated track is the
only captioning that platform will ever do.
`tools/test_system_caption_selection.swift` drives the shipped sequence and
fails if it ends without text.

## 066 — Catalog writers compute without the lock and take it only to merge a delta
*Date: 2026-08-11*

A workflow that mutates the catalog now runs as TWO jobs: a compute job holding
no lock, which snapshots the catalog, does its work, and emits a field-level
delta; and a short `apply` job holding `catalog-writers`, which fetches a FRESH
catalog, merges the delta, and publishes. `tools/catalog_delta.py` provides
`snapshot` / `extract` / `apply` generically, so an existing tool needs no
changes — the delta is derived by observing what the tool did.

**Why**: measured 2026-08-11 — 27 workflows held the single `catalog-writers`
lock for their ENTIRE run, and their average demand summed to **24.2 hours per
cycle** against a lock with 24 hours a day to give. Oversubscribed, which is the
root of most of what the preceding decisions patched: runs destroyed in the
queue as a matter of course (057), budgets measured in hours, killed runs
discarding work, and the clobber risk that 020 and the publish shrink-guard
exist for. The compute never needed the lock; only the mutation does, and the
mutation takes about two minutes.

    color-classify   lock held 52m  ->  21 SECONDS   (measured, real run)
    check-liveness   compute 1m unlocked, apply 1m locked, delta 0.0 MB

The merge is the load-bearing part, not the speed. Republishing a whole catalog
read hours earlier silently REVERTS whatever another writer published meanwhile
— the lock was compensating for the data model rather than protecting a real
invariant. A field-level merge does not: two workflows touching different fields
of the same item both survive.

**How to apply**: the lock is declared at WORKFLOW level in this repo, so it
covers every job in the run — splitting into two jobs changes nothing unless the
top-level `concurrency:` is REMOVED and re-declared on the apply job alone. Gate
every step after the "nothing changed" check on it: an empty-delta run skips the
fetch, and an ungated remediate step then runs against a catalog that is not
there. Emit the delta with `if: always()` and upload it the same way, so a run
killed mid-compute still contributes what it finished. Do NOT convert a workflow
whose tool ingests or deletes ITEMS wholesale without checking the delta shape
first — `extract` carries a new item whole, but a tool that rewrites the entire
item list is better left alone.

**Consequences**: a converted workflow's compute can be given a generous budget
without starving anything, and can be sharded, because it competes for nothing.
Decision 057's sweeper returns to being a backstop rather than load-bearing.
Converted so far: color-classify, check-liveness, free-subtitles; ~24 catalog
writers remain, and each is a mechanical change of the same shape. Measured cost
on the real catalog (140.6 MB, 40,671 items): snapshot 2.9s at 737 MB RSS, and a
661-item change produced a 0.0 MB delta.

## 067 — A film with no subtitles plays on the PLAIN url, because the resilient loader is never offered a generated track
*Date: 2026-08-12*

From 27 the system generates subtitles on device for video that carries none, and
Apple's position is that no app implementation is required. For an app that hands
AVPlayer an ordinary URL that is true. This app hands it a custom
`AVAssetResourceLoaderDelegate` (Decisions 021/031/034), so the asset shape is now
chosen UP FRONT: a film with no published subtitle track plays on the plain
`https` URL (`SystemCaptions.prefersDirectPlayback`), on tvOS, iOS and macOS, with
`CaptionStallMonitor` rebuilding on the resilient loader if that path stutters
persistently. A film that HAS published subtitles is untouched — its captioned-HLS
path works, and its subtitles are human.

**Why**: measured on macOS 27.0 (26A5388g), one shape per process, against a film
the system is known to caption:

    plain direct MP4 (/download URL)   option offered · TEXT in 33s
    node-resolved direct node URL      option offered · TEXT in 30s
    HLS master wrapping the same MP4   option offered · NEVER any text
    aw-stream:// resilient loader      NO OPTION EVER OFFERED

Both halves of that overturn what was recorded here. Decision 065 said the loader
path was "offered but silent" and built a four-stage handover on it — wait for the
track, select it, listen, and only then swap to the direct URL. **The swap was
gated behind a track that never arrives**, so on an Apple TV it could never run,
which is precisely the reported symptom: file-based captions working, generated
ones never appearing, across three shipped builds. And wrapping the MP4 in HLS —
the obvious reading of Apple's "HLS and file-based content" — does NOT qualify us
either; a single-segment playlist pointing at a remote MP4 is offered a track that
stays silent forever, exactly like the loader.

That "offered" reading came from a harness that probed several shapes in ONE
process, where a track left over from the previous player was counted as the
current one's. A shape IDENTICAL to the passing one failed later in the same run,
which is what exposed it. **One shape per process, or a result cannot be
attributed to a shape at all.**

**How to apply**: never assert that a caption track works because one was
OFFERED — this is the fourth time that exact conflation has cost something here
(poster liveness, the system declining, Decision 065, and now the measurement
065 itself rested on). Assert emitted TEXT. Do not gate the direct path on the
viewer's caption preference: "Generated Subtitles" is its own Settings toggle,
separate from the captions display type, so a viewer can have generated subtitles
on while the display type is still `.automatic` — gating there would leave the
menu empty for exactly the person who went looking for it. Keep referencing no 27
symbol: the App Store archive builds with the RELEASED Xcode (26.6) to clear
ITMS-90111, and reaching for `selectableMediaSelectionOptions(in:)` is what broke
build 876; a plain `#available` version check compiles fine and the generated
track appears in the asset's own legible group anyway. A film the system DECLINES
is a statement about that film's audio, not a failure of this path — it declines
on much of this catalogue's optical sound (Decision 063).

**Consequences**: films without subtitles give up resume-on-reset and node
failover on 27, in exchange for being captioned at all — the same trade already
made for captioned films ("smooth-without-CC beats stutter-with-CC"), with the
same stall fallback. The cost is bounded: AVFoundation pays the `/download` 302
once for a progressive read, not per chunk, which is what made it expensive under
the loader. `SystemCaptions.stage` is surfaced on tvOS when neither the system nor
our engine can caption, because an Apple TV is the only device that can answer
this and its console cannot be read from a development machine — three fixes
shipped on evidence gathered entirely on a Mac. `tools/test_system_caption_selection.swift`
drives the SHIPPED code in both modes and asserts the negative control too, so a
future change that makes the loader captionable is visible rather than silent;
`test_system_generated_subtitles.swift` is deleted, having asserted the disproven
claim. `hls_manifests` gained optional CHARACTERISTICS so machine-made and
translated renditions can carry `public.machine-generated` / `public.translation`
and be labelled "English Generated" / "Spanish Translated" by AVKit itself
("What's new in HTTP Live Streaming", WWDC26) — nothing carries it today, because
every published track is human.

## 068 — On tvOS our caption engine LEADS; the system's generated track is opportunistic
*Date: 2026-08-12*

For a film with no subtitle track on tvOS 27, `LiveCaptions` (the SpeechAnalyzer
scout that captions iOS and macOS) starts IMMEDIATELY, and the watch for the
system's generated track runs CONCURRENTLY with 300s patience — standing our
engine down only if the system's track ever actually emits text. Both automatic
paths are gated on the viewer's caption preference (`viewerWantsCaptions`); a
forced-only viewer gets neither engine nor note.

**Why**: measured on the owner's own Apple TV 4K (tvOS 27.0, 24J5346a), driven
directly from the dev Mac — the device is PAIRED, and
`devicectl device process launch --console` with an `AW_CAPTION_DIAG=1` hook
made it a readable oracle for the first time. Two findings, opposite in sign:

    system generated track   offered + selected on EVERY shape
                             (local file, plain remote MP4, HLS wrapper)
                             — NO TEXT in 10+ minutes of playback
    our SpeechAnalyzer scout ENGINE CUE after 14s on the same clip

tvOS 27 ships working speech models — `supported 45`, and installs completed on
demand (0 → 9 locales during the probes). **Decision 060 ("tvOS has no speech
models and never will") was true of tvOS 26 and is obsolete on 27.** Meanwhile
the system's generated track on this beta is a menu entry that never speaks in
a third-party app: blocking playback captions for 300s behind it was the delay
the owner kept reporting as "no captions". A real film then captioned end to
end through the real player on the device (`AW_START_ITEM` + `AW_AUTOPLAY`),
resuming at the viewer's watch position with cues flowing on the console.

Also measured on the way here, each worth keeping: the offer itself can arrive
MINUTES in (cold engine: local file offered nothing in 180s; same file offered
at 0s once warm) — so `handOver` is now ONE loop that polls, selects and
listens across its whole patience, never an offer-first gate a silent opening
can defeat. And an "offered" reading contaminates across probes in one process,
but EMITTED TEXT through an item's own legible output cannot — which is what
makes a multi-shape on-device probe valid where the macOS harness needed one
shape per process.

**How to apply**: never gate captions on the system track EMITTING before our
engine may start on tvOS — lead with ours, stand down if the system speaks.
Keep the stand-down: if a later beta (or a device where "Generated Subtitles"
genuinely works) starts emitting, the system's track wins on every count
(native menu, viewer style, no second stream). Films WITH published tracks
still skip the watch entirely — the judge (062) owns that path. Test tvOS ON
tvOS: the paired-device loop (build Debug → `devicectl install` → `launch
--console` with `AW_CAPTION_DIAG=1`) costs minutes; every prior fix here
shipped through ASC on Mac-only evidence and three of them were wrong. Keep
`caption-probe.mp4` (60s narration, captions in 14s on macOS AND on the ATV)
as the reference clip — probing with a random film conflates "device cannot
caption" with "film was declined" (063).

**Consequences**: Apple TV viewers get live captions on the ~19,200 bare
sound-era films (audit `tools/audit_caption_tiers.py`) at iOS/macOS quality,
starting ~15-30s into playback. Decision 067's plain-URL path stays: it costs
nothing, keeps the film eligible for the system's track the moment Apple fixes
emission, and the system-watch needs it. The Caption Diagnostics screen stays
in Settings as the standing experiment kit. tvOS 26 remains published-files
only. If a future tvOS beta makes the generated track emit, nothing needs to
ship — the stand-down is already listening.

## 069 — The scout's two clocks are platform traps: pin the pitch algorithm, map by rate, guard replays, follow the current player
*Date: 2026-08-12*

Four rules now bind the live-caption scout, each the corpse of a bug found by
tracing real playback on the paired Apple TV and convicted against GROUND TRUTH
(a locally transcribed copy of the same film region — the only arbiter when two
mappings disagree; scout `currentTime()` is NOT one, since the tap runs ahead of
the position clock by the audio queue's depth):

1. **`audioTimePitchAlgorithm = .timeDomain`, explicitly.** Under the platform
   default an Apple TV at 2x raced its position clock while delivering tapped
   audio at ~1x — half the film's audio would never have been transcribed, the
   lookahead never grew, and what audio arrived was mangled enough to garble
   the transcript. It also re-delivered already-tapped audio around rate
   transitions, which is where the "same minute of narration three times over"
   came from.

2. **Map analyzer time to film time by `offset + t × scoutRate` — never by the
   tap's presentation timestamps.** The anchoring "improvement" was built and
   reverted the same afternoon: macOS stamps the tap callback in FILM time, so
   anchors agree with the rate formula there — but tvOS stamps it in the
   COMPRESSED timeline, identical to the analyzer's own clock, so anchoring
   silently halved every cue and captions ran minutes early. Ground truth:
   "Temple of the Soul" is spoken at 1108.0; `805 + 151.6 × 2 = 1108.0` exactly,
   on both platforms. The rate formula is the only mapping that never reads the
   stamps, which is why it is the only one that holds everywhere.

3. **Drop tap buffers whose presentation stamp rewinds** (`highWater` in
   `BufferSink.append`). The scout never seeks backward, so an older stamp is a
   re-delivery; feeding it to the analyzer both duplicates the words and
   advances the clock, shifting every later cue.

4. **The display loop follows `observedPlayer`, not the player it was started
   with, and runs until CANCELLED, not while the engine runs.** tvOS's stall
   fallback REBUILDS the AVPlayer for the same URL (iOS/macOS swap the item on
   one player, which is why only the living room froze): the loop that captured
   the original player read a torn-down clock forever, and the caption at the
   resume position stayed on screen for the rest of the film — the owner's
   exact report. A loop conditioned on `isRunning` was the second freeze: it
   exited when the engine stopped and left the last label text standing.

Also in this wave: the stand-down for the system's generated track is
REVERSIBLE (`draws=false`, engine keeps running; a 45s-quiet watchdog brings
ours back), because on this tvOS beta that track refused to emit through ten
minutes of probing and then emitted mid-film in real playback — flaky in both
directions. Verified end to end on the device: our engine leads with
ground-truth-exact sync ("From cave wall to billboard" shown at t=28.5, spoken
at 28.2–28.4), the system's track took over ~30s in, and 260 consecutive
watchdog windows confirmed it kept speaking.

**How to apply**: `AW_CAPTION_TRACE=1` prints the playhead, every displayed-line
change, throttle transitions, and per-cue raw→film mappings — with the paired-
device loop it turns caption sync into a console read. When two clocks disagree,
cut the disputed film region with ffmpeg and transcribe it locally
(`/tmp/awlive "file:///tmp/region.mp4"`); that transcript is the ground truth,
nothing else is. Cold start is inherent: the scout begins AT the playhead, so
the first ~1–2 minutes after (re)start have sparse captions while the lead
builds — do not "fix" that by showing late-finalized cues (trailing captions
are the failure Decision 058 exists to prevent).


## 070 — The captioned-HLS wrapper is retired on tvOS; the overlay renders the subtitle file
*Date: 2026-08-13*

On tvOS, films with a subtitle file — published in the catalog or fetched on
the device — now play through `ResilientStreamLoader` like everything else,
and the FILE is rendered by the caption overlay (`CaptionCoordinator` file-cues
mode): the VTT is fetched and parsed at start, displayed at the viewer's system
caption preference exactly as the old track's `AUTOSELECT/DEFAULT` did, and
`SubtitleReview` judges it as before — a shift verdict now moves OUR cue times
directly, and preferLive discards the file for the transcript. The
single-segment HLS wrapper (`CaptionedHLSLoader` / `LocalSubtitleHLSLoader`
paths, Decision 039 Config C / 054) is no longer used for playback on tvOS.

**Why**: the wrapper's single MP4 "segment" made AVFoundation treat the ENTIRE
film as its atomic buffering unit. Measured on the Bedroom Apple TV with all
caption machinery disabled: `loadedTimeRanges` climbed to 5,300 seconds — the
whole 575 MB of His Girl Friday — while `preferredForwardBufferDuration` asked
for 300, and the item then died with AVError **-11819 (media services reset)**
at t≈100–117s in three consecutive runs: mediaserverd does not survive
swallowing a feature film on a 3 GB Apple TV. The death was invisible for
weeks because (a) it never happens on a Mac, where every prior verification
ran — the Mac has the memory — and (b) `handleLoadFailure` silently rebuilt
the player, so the visible symptom was only a mid-film "refresh". Worse, the
rebuild left the old player UNDEAD (pause() without detaching the item left
its pipeline running — clock advancing, rate=NaN, for the rest of the
session), and two live pipelines a rebuild-gap apart is exactly the owner's
"stuttering and sometimes repeating lines". The stutter, the refresh, the
restart-from-zero, the double captions and the mistimed captions were all
downstream of this one path.

**How to apply**: never hand AVFoundation a single-segment HLS wrapper around
a feature-length MP4 on a memory-constrained device — a "segment" is the unit
of buffering, and no preference caps it. `teardownPlayer` must
`replaceCurrentItem(with: nil)`, not just pause — measured: pause alone left
the pipeline live. A mid-playback item failure resumes from the exact current
position (persist-then-teardown), not from the periodic writer's last save.
The judge's shift gate accepts a decisive peak-over-zero margin (>0.12) even
under `matchAbove` — His Girl Friday's true offset scored 27% on a sparse
transcript and a "match" verdict showed the file 16s out of sync; the
four-control harness (`tools/test_subtitle_agreement.swift`) still passes.
The freeze guard waits 15s for the FIRST frame (a resume seek legitimately
takes seconds; its 3.5s threshold was nudging — a decoder flush — twice at
every resume point).

**Consequences**: captioned films on tvOS regain Decisions 021/031/034
resilience (they had NONE — the one path with no loader was carrying 16% of
the catalog, including nearly every popular film), scrubbing works (the
single-segment wrapper never could), and memory stays bounded. The native CC
menu no longer lists the file's track on tvOS — the overlay is the renderer;
a transport-menu subtitles toggle is the parity follow-up for viewers whose
system caption preference is off. iOS/macOS keep the wrapper for now (more
RAM, AirPlay handoff uses the published HLS per Decision 051) — but the same
bomb plausibly exists on low-RAM iPhones and the published HLS handed to an
AirPlay RECEIVER (an Apple TV) is still the single-segment shape; both are
open questions this decision deliberately leaves scoped out.

## 071 — The caption scout is MUTED on tvOS; a volume-0 second player races the main audio render
*Date: 2026-08-13*

On tvOS the live-caption scout (`LiveCaptions`, Decision 058) sets `isMuted =
true` instead of `volume = 0`. The audio processing tap still fires under
`isMuted` on tvOS 27 — measured: 23 correctly-mapped transcript cues from a
fully muted scout — so Decision 058's rule ("volume 0, but NOT isMuted:
muting can take the audio out of the render pipeline and the tap never
fires") is a platform fact about iOS/macOS, not tvOS, and those platforms
keep volume-0.

**Why**: the owner reported, across two builds, that "the audio often gets
swallowed by the captioning process" — picture running, captions synced,
soundtrack gone. Every existing diagnostic watches the clock or the buffer,
so a dead audio render with healthy video was invisible from the dev Mac;
an RMS meter tap on the MAIN player (`AW_AUDIO_DIAG=1`, AWAUD lines) made
it measurable. Measured on the Bedroom Apple TV: the main player's audio
render died for 33-34 seconds — video advancing, buffer full at ~200s —
with the dropout bracketed exactly by a volume-0 scout's active life, in
roughly half of the runs. A muted player does not contend for the audio
output; a volume-0 player is a full participant whose start/resume can race
another player's render and silently win.

**How to apply**: never run a second audible-pipeline AVPlayer alongside
playback on tvOS — mute it outright, and verify the tap still feeds (the
AWAUD meter plus cue-mapping traces answer both in one run). Two red
herrings cost hours and are worth remembering. First, `.timeDomain` looked
causal — dropping it "fixed" the race — until a self-identifying print
showed TimeDomain is the tvOS 27 platform DEFAULT, so the bisect arm had
changed nothing and both arms were coin-flips of a ~50% race; a bisect of a
nondeterministic fault needs repeated trials per arm, not one run each.
Second, a verification run measured the OLD binary after an unchecked
install; the scout now prints its pitch algorithm and mute mode so a run
identifies its own configuration. `AVPlayerItemSampleBufferOutput` (the
27 API built for scan-ahead decode without a second render) was evaluated
and rejected: HLS items only, and the scout plays progressive MP4s —
revisit if that restriction lifts.

**Consequences**: the owner's last unexplained symptom on build 899 falls.
tvOS scout behavior is otherwise unchanged (2x, subordinate socket,
throttle/yield, silenceScout detach). Related: 058 (the scout), 069 (the
pitch pin, restored after the herring), 070 (the undead-player mechanism
that taught the detach), and the AWAUD meter joins the permanent
env-gated diagnostics.

## 072 — One tvOS pipeline: every title plays through the resilient loader; the engine is the captioner
*Date: 2026-08-14*

On tvOS, every playback — captioned or not, film or episode — goes through
`ResilientStreamLoader`, and live captioning for uncaptioned titles comes from
OUR engine alone (Decision 068). Retired together: the plain-URL branch
(Decision 067's trade, movie player and episode player both), its
`CaptionStallMonitor`→`forceResilientFallback` safety net, and the
system-caption watch (`SystemCaptions.handOver` + the 45s emission watchdog).
Captioned files render through the overlay (Decision 070) as before.

**Why**: the owner's report on Till the Clouds Roll By named the seams, not a
bug: "drops frames even though it continues to play… captions come in and out
and sometimes make the video pause for a while as it refreshes the stream…
can we stop fixing them one at a time and solve for them as a fully working
system." The film's file is blameless — probed h.264 Main 720p at 1.9 Mbps —
but as an uncaptioned title it took the plain-URL path, which has NONE of
Decisions 021/031/034's resilience: archive.org's idle resets flush
AVFoundation's buffer (the original Decision-021 disease, reintroduced by
067's trade), the stall monitor answers by tearing down and rebuilding the
player mid-film ("pauses while it refreshes"), and the system-caption
watchdog yielded our captions to a generated track that this beta flickers on
and off ("captions come in and out"). Each piece was a rational patch; the
matrix of paths was the disease. What the trade bought — the system's
generated track — was measured on the owner's own Apple TV to be offered and
almost never emitting (Decision 068), while our engine captions the same
films in ~15s.

**How to apply**: on tvOS, do not add a playback path that bypasses
`ResilientStreamLoader` — if a future OS makes the system's generated track
actually emit through a loader-backed asset, revisit 067's trade THEN, with
the emission measured on a device first (offered ≠ selected ≠ emitting — the
lesson is now four decisions old). iOS and macOS keep their current paths:
the system's generated captions genuinely work there (measured text in ~33s
on macOS; the owner rates iOS "extremely well"), so the plain-URL trade still
buys something real on those platforms.

**Consequences**: `forceResilientPlayback` and the plain-path stall wiring in
the tvOS players are inert; the coordinator's engine-vs-system arbitration
on tvOS reduces to "engine leads, nothing else draws". Uncaptioned titles on
tvOS regain resume-on-reset, node pinning, and node failover. The
capability note (a device with no speech models says so once) stays.

Two companions shipped with it, both found chasing the same film on-device:

*Scout depth-hysteresis.* The scout's yield keyed on a binary buffer-health
flag that fires only when the buffer is already gone, and a 5s cooldown
resumed it straight back into the starvation — yield/resync/restart churn.
`throttle` now takes the MAIN buffer's depth in seconds: the viewer banks
120s before the scout may draw bandwidth at all, and it stands down the
moment the bank dips under 60.

*Loader block cache.* A long, oddly-muxed upload (Till the Clouds Roll By's
2 GB card) makes AVFoundation fetch its interleaved sample chunks in TINY
random dataRequests — 669 reads of 64 KB in one soak, each paying 60-180 ms
of request latency: an effective ~3-4 Mbps ceiling on a node that sustains
~100, decoder starving, buffer pinned at 0-4s for minutes. Small bounded
reads are now served from aligned 2 MB cached blocks (24-block LRU = 48 MB —
an 8-block cap THRASHED, the playhead's working set is ~50 MB; the next
block prefetches so the pattern's misses stay off the decode path). The
sequential 8 MB streaming path and every 021/031/034 invariant are
untouched — measured after: buffer sustained 63-103s where it had pinned at
0-4, stalls 5 -> 0, block re-fetches 6-7x -> at most 2x.

## 073 — The judge may not condemn a human subtitle file on a sparse transcript, nor nudge one inside its own noise
*Date: 2026-08-14*

Two asymmetric-caution gates in `SubtitleAgreement.judge`, both paid for by
His Girl Friday's RETIMED (correct) track in build 905: a `preferLive`
condemnation now requires the transcript to have actually heard at least 100
usable words — a session that resumes into music or mumble zero-scores a
perfect file, and one such window discarded the human track mid-film and
replaced it with machine captions ("no longer synced correctly... a huge
step backward"). And a shift smaller than 2.5s is adopted only when
agreement is dense (>=0.45): the judge's own offset noise on a sparse
transcript is ~1.5s, so noise-sized "corrections" were un-syncing a file
that was already right. Big shifts and dense-evidence small shifts still
correct; the 4-control harness holds; on-device re-proof: verdict "match",
10/10 displayed cues byte-matching the published VTT at the playhead.

**How to apply**: every verdict that makes a viewer's captions WORSE if
wrong (condemn, replace, shift) must clear an evidence floor scaled to its
cost, and "no opinion" must remain reachable from every code path — the
absence of proof that a file matches is not proof that it doesn't. When a
verdict varies run-to-run on the same film (match 41% / match 24% / shift
1.3 / preferLive 12% were all observed), that variance IS the measurement of
the judge's noise, and thresholds must sit outside it.

## 074 — Captions are an ECONOMY: every layer yields to playback on measured evidence, and the glass is the test
*Date: 2026-08-14*

The external-observation suite (`tools/atv_scenario.py` + `tools/ScreenOCR` +
the on-device diag file) is now the shipping gate for tvOS caption/playback
work: a scenario launches a film on the paired Apple TV, screenshots the GLASS,
OCRs the caption region, pulls `Library/Caches/awdiag.log`, and grades eight
assertions (app alive to end, no stuck notice, playhead advances, no stalls,
audio continuity, captions on glass, glass-matches-file for published VTTs,
glass-matches-engine otherwise). Six scenario rounds against it produced five
coordinated fixes, each one a layer of the same principle — a second stream
must EARN its bytes, and every claim is measured, never assumed:

1. **Drift bound (lower envelope)**: a seeked scout session on a badly-muxed
   file receives a burst of pre-target audio (+39s of raw clock measured), so
   `film = offset + raw×rate` maps every cue late — and the judge, reading the
   same ruler, condemned His Girl Friday's CORRECT file at 7%. The mapping is
   re-anchored when the 25s lower envelope of (predicted − scoutPosition)
   exceeds 15s. NEVER correct on the instantaneous error: the tap delivers in
   decode-ahead bursts and an instant-threshold corrector flapped 15 times in
   one run, corrupting the ruler in both directions.

2. **Exoneration sweep**: before any preferLive verdict the judge scores the
   file at every offset to ±75s. Unrelated content scores ~3% at EVERY offset,
   so a strong far-out match is fingerprint evidence the file describes this
   film and the fault is OUR clock — keep as published, never shift by a far
   offset. A rulerSuspect session (any drift correction) may keep a file but
   never shift or condemn without a doubled word floor.

3. **Resync = seek, never rebuild**: every stop/start resync built a fresh
   player item whose moov + preload fetch collided with struggling playback —
   stalls clustered 10-32s after each rebuild. `LiveCaptions.resync(to:)`
   seeks the existing scout; one asset per playback. The throttle never
   resumes a scout >45s behind the viewer (2x cannot catch 1x from behind).

4. **Surrender**: a running scout that cannot sustain 1.4x over 25s is in a
   race it mathematically loses — it detaches its item entirely (a paused
   item still buffers), keeps the cues it made, says the true thing once, and
   nothing restarts it that playback. Three playback-trouble episodes are the
   backstop. Gate on OBSERVED harm; a depth threshold alone locked captions
   out of files whose healthy steady-state buffer is structurally low.

5. **Slow-node rotation**: both remaining stalls came with NO second stream —
   single glacial requests (8 MB at 3.6 Mbps for 18.7s) on the pinned node.
   The idle timeout never fires on a trickle and Decision 034 rotates only on
   hard errors, so a slow-chunk watchdog cancels a chunk 6s in with under
   half its bytes and DEMOTES the node (slowHosts, forgiven when all are
   slow) — not blacklisted; 034's timeout rule stands. Resume is byte-exact.

**Why**: ten builds of caption fixes had shipped on self-reported evidence
while the owner kept seeing failures at the glass. The suite inverted that:
every one of these five faults was found by a failing scenario, three of them
in causal chains no console reading would have ordered correctly (condemnation
← drift ← seek-burst; stalls ← restart churn ← a resume that ignored scout
position). His Girl Friday now passes 7/7 repeatedly (108/112 on-glass
captions matching the published cue at the playhead); TtCRB-4K retains
weather-bound stalls on degraded archive.org afternoons even with playback
alone — that residual is a node/derivative question, not a caption one.

**How to apply**: no tvOS caption or playback change ships without a passing
scenario report — the app's own logs are diagnosis, never verdict. When a
scenario fails, read the diag around the failure times before theorizing; every
wrong fix this session came from a plausible mechanism the timeline disproved.
The launch-window app death under 4K screenshot capture is a HARNESS artifact
(observer-induced memory pressure; no crash report, no app jetsam) — the
runner retries once; do not chase it as an app bug without a report naming the
app. Scenario cards resolve by TITLE from the live index, never hardcoded ids.

## 075 — Controlled experiments over correlation: the LAN remux control, and the instrument that manufactured its own disease
*Date: 2026-08-14*

The harness gained CONTROL-EXPERIMENT hooks — `AW_URL_OVERRIDE` (play the
AW_START_ITEM film from any server) and `AW_NO_RESUME` — and their first use
settled a day of contradictory correlations in one run: the same 4K film,
stream-copy remuxed with faststart and served from the dev Mac over LAN
(range-capable server; python's http.server ignores Range and serves
byte-zero garbage that AVFoundation reports as "media damaged"), still
showed 16 metronomic ~10.4s audio gaps. That exonerated the file, the mux,
archive.org, node weather, and the scout (surrendered at 67s) in a single
stroke — and left exactly one rhythmic actor: the audio-meter watchdog,
which revived its dead tap by REPLACING the playing item's audioMix, then
detected the ~10s outage its own replacement caused, forever. Single-attach
control: zero gaps. The meter now attaches once, logs "tap died — no audio
evidence past this point", and never touches a playing item again.

**Why**: three loader interventions (audio-region prefetch, trailing-request
cap at two geometries) were built on correlations — each reshaped the
numbers, none removed the rhythm, because the causal story was wrong twice
over. The "41% wasted re-download" that motivated the runaway cap conflated
BOTH loaders' AWSTREAM lines: the scout's second stream is legitimate reads,
not AVFoundation re-requests. And the "audio dropouts" being chased were
manufactured by the chasing. A controlled experiment that removes variables
wholesale beats a week of correlation on live traffic.

**How to apply**: when a symptom survives three targeted fixes, stop fixing
and build the control that splits the hypothesis space in half. The
harness's audio evidence is now honestly bounded: tvOS tears the audioMix
tap down on heavy-decode items (17s lifetime on the 4K film, six clean
minutes on His Girl Friday) and the assertion grades only the tap's
lifetime — an instrument must say when it is blind, and must never perturb
what it measures (the same observer-effect class as the 4K-screenshot
launch-window deaths in 074). Tag or segregate per-loader diagnostics
before summing them. Keep AWERR/drop counters: zero decode errors across
every run is what kept "corrupt bytes" honestly excluded.

Also this session, from the owner's sofa reports: build 915's slow-chunk
watchdog cancelled at a 5.6 Mbps floor — a normal living-room speed — and
was the real "no video at all" / static / smeared-picture regression (now
0.2 Mbps/10s, a dead trickle only); The Oregon Trail's only file is AV1 in
an MP4 labelled "MPEG4" (no Apple TV can decode it; the Mac-side verifier
can) and now fails with an honest terminal error instead of audio over a
black screen — the codec-aware pipeline audit is queued; and the caption
overlay strips WebVTT markup it was rendering literally.

## 076 — Ship gates run under ADVERSE conditions: Release builds, throttled bandwidth, and playback owes the caption engine nothing
*Date: 2026-08-15*

Three standing rules born from the owner's report that build 925 made every
title without a subtitle file unplayable — a regression that passed every
harness gate, because every gate ran under conditions the failure needed
absent:

1. **The caption engine is a passenger, never a driver.** For a film with
   no subtitle file the engine ARMS at play-start but IGNITES only after
   playback has proven the link can afford a second stream (60s banked or
   30s healthy). On a link that can never afford it, captions are simply
   absent — no spinner, no notice, playback identical to a captioned
   title. Measured why: at ~10 Mbps the scout's startup probe + the AV1
   check's moov fetch + the player's own startup collided and the item
   load TIMED OUT — "unable to play," on every uncaptioned title, while
   captioned titles worked. That asymmetry was the owner's exact report
   and the diagnosis in one line.

2. **Ship gates run under the conditions viewers actually have.** Every
   fix through 925 was validated on Debug builds at whatever bandwidth
   archive.org happened to offer — usually 40-240 Mbps. The failures all
   needed ~10 Mbps to appear. `tools/throttled_range_server.py` (token-
   bucket range server; python's stock http.server ignores Range and
   feeds AVFoundation garbage) + `AW_URL_OVERRIDE`/`AW_NO_RESUME` make a
   bad morning reproducible ON DEMAND. A tvOS playback/caption change now
   ships only after a RELEASE-configuration scenario AND a 10 Mbps
   throttled run. The gate earned its keep the first day: it caught the
   loader fetching every byte 2-3x (AVFoundation walks an interleaved
   file with separate audio and video cursors over the same bytes, each
   served a private copy), which no fast-network run ever showed.

3. **Streaming delivery for the leading request is load-bearing** (the
   Decision 031 invariant, re-proven from the other side). Routing ALL
   requests through the shared block cache fixed the 2x duplication but
   held startup bytes hostage in whole 2MB blocks — 29s first-block
   fetches under slow-TTFB contention, item timeout, "unable to play"
   again. The follow-up that gets both (share bytes across cursors AND
   stream them as they arrive) is streaming block fills; it ships only
   through the throttled gate.

Also in the record: the slow-chunk watchdog is DELETED (regressed twice —
a 5.6 Mbps floor killed normal wifi; a 0.2 Mbps floor killed legitimately
slow startup probes; the 12s idle timeout already covers dead
connections). Failure notices are honest and bounded: "no audio to
transcribe" only when the track load SUCCEEDS and finds none, and
"Preparing automatic captions" expires at 45s. Harness caveats: launches
under 4K screenshot capture get the app SUSPENDED (no crash report, the
capture daemon jetsams for its own limit) — verify app behavior with
console-attached launches, use capture scenarios for glass evidence;
reboot the device between long harness sessions.

## 077 — A film starts within 30 seconds, or falls back to a copy that can (amends 021's no-downgrade rule)
*Date: 2026-08-15*

Owner decision, verbatim intent: "Fallback is only appropriate when the full
version isn't feasible. Please implement that change. Films should start
within 30 seconds. Waiting longer than that will lose users almost every
time." The player's load budget is now 25 seconds, and a startup failure
with a vetted fallback in hand switches to it IMMEDIATELY — never a retry of
the URL that just proved unservable. The chain: catalog-baked
`fallbackVideoURL` → a smaller archive-generated derivative on the same item
(prefetched during the load attempt by `ArchiveFallback`) → one retry of the
primary → an honest error naming the Archive's servers. Mid-film failures
never switch copies; resume stays seamless on the copy the viewer started.

**Why**: Decision 021 rejected bitrate ceilings so quality would never be
silently degraded — but it never considered a source that cannot serve the
file's bitrate AT ALL. Measured 2026-08-15: archive.org's US datacenter
served Till the Clouds Roll By's 5.7 Mbps 4K file at 2 Mbps with 25-second
first bytes, and the film's 720p sibling upload at 1.7 Mbps from the same
datacenter — no player on earth streams that. The old behavior (60s timeout,
same-URL retry, generic "request timed out" after two minutes) was honest
about nothing and lost the viewer every time. A watchable 845 MB copy of the
same film existed in the catalog the whole time.

**How to apply**: identity vetting happens in the PIPELINE, never at runtime
(Decision 026): `tools/bake_fallbacks.py` pairs each heavy item (>1.5 GB,
1,685 of them) with a meaningfully-lighter same-imdbID sibling copy — the
duplicate uploads Decision 040's merge collapses at DB-build time remain in
catalog.json with their URLs — else a same-item archive-generated derivative
(those are h.264 by construction; an uploader original labeled "MPEG4" can
hide AV1, which no Apple TV decodes — The Oregon Trail). Every candidate is
liveness-probed before baking (Decision 056). The field rides `item_json`,
additive per Decision 020. Runs in publish-db daily (new ingests only —
idempotent). Never fall back for a mid-film failure, and never fall back to
a copy that is not the SAME film by pipeline-vetted identity. tvOS shipped
first (1.3.407/929); iOS/macOS/Android/web parity is open work, as is a
small on-screen note when a fallback is playing.

**Consequences**: the app's honest terminal error ("The Internet Archive's
servers are struggling with this title right now...") appears only when the
best copy AND its fallback both fail to start — roughly 50 seconds worst
case, inside the owner's tolerance for a genuine outage. The 4K copy remains
the default every time; the fallback costs nothing until the moment nothing
else would have played.

## 078 — Watch history is a durable, union-merged record; progress is merely its most recent line
*Date: 2026-08-15*

Every playback on every Apple platform records through ONE write path,
`WatchProgress.record(in:)`: resume position (as before), plus firstWatchedAt,
playCount (a new session = a >6h gap between writes), and everCompleted /
completedAt. everCompleted is durable — once a title has been finished it is
"watched" forever, because before it existed a REWATCH reset the position and
silently erased the title's watched status on every synced device. Channel /
lineup tune-ins (ephemeral) now enter the history after 60 seconds of viewing
— dates and session count only, never position — so the record is complete
while Continue Watching keeps its no-channel-pollution invariant. The tvOS
Library gains a History section: every title ever played, most recent first.
CloudKit's merge treats history as a UNION (earliest first-watch, highest
play count, completed-anywhere = completed-everywhere) while position stays
last-writer-wins by lastWatchedAt.

**Why**: owner, 2026-08-15 — "a full record of every movie/video you have
ever watched and the ability to resume them from wherever you last stopped...
easy to see... no matter where you are or which device... the same across all
Apple devices." The store already synced positions; what it lacked was
durability (rewatches erased history), completeness (channels recorded
nothing), and a surface (nothing listed the full record).

**How to apply**: never persist progress with hand-rolled fetch/update code —
call `WatchProgress.record`; three platforms had three divergent persist
bodies and any future semantic lives in the helper once. History fields merge
as a union, NEVER last-writer-wins — two devices each know something true and
the merge must lose neither. All fields are optional so old stores migrate
lightweight and old sync payloads decode unchanged (the additive rule,
Decision 020, applied to SwiftData + the AWSync blobs). Proven on-device on
the Release build: record → relaunch → resume at the exact position.

**Consequences**: iOS/macOS Library History surfaces, Android/web local
history, and PARITY rows are open work. Cross-ecosystem sync (Android/web
seeing the same record) rides Decision 028's Google Drive App Data plan and
remains blocked on the owner creating the Google OAuth client.

## 079 — The Quality Program: research-first rebuild of playback, captions, sync, and choice
*Date: 2026-08-17*

Four commissioned research reports (docs/research/*.md, sources cited,
verified-vs-inferred marked) and their synthesis
(docs/PLAYBACK-ARCHITECTURE-RESEARCH.md) become the binding plan, with the
owner's approvals and one binding condition:

1. **LocalMediaServer** (loopback NWListener HTTP server fronting the ported
   ResilientStreamLoader engine) is approved UNDER THE NATIVE-FIRST
   CONDITION, owner verbatim: "if it in any way replaces the native APIs or
   makes it harder to take advantage of the native tools that Apple
   provides for its video apps, please research better/native solutions."
   The research's answer, recorded as the design rule: the proxy EXISTS to
   restore native-tool compatibility (a localhost URL is a plain HTTP asset;
   the custom scheme is what disqualified AirPlay, generated captions, and
   AVAssetReader), and the design must prefer DIRECT native playback for
   files verified compliant and well-served — the proxy is the resilience
   layer, not a replacement for native playback. Cutover gates: on-device
   proof that generated captions emit through the proxy; byte-diff vs
   origin over a full film; scenario suite green at full speed AND through
   the 10 Mbps throttled gate.
2. **History UX approved**: ONE History list (chronological dated plays);
   Watched becomes a derived badge on posters + a Detail toggle, never a
   second content list. Continue Watching stays. (The Trakt model.)
3. **Repair-and-rehost approved**: `archivewatch-fix-<slug>` items under
   the owner's archive.org account, only for the popular tail with no
   playable copy, clearly labeled as repairs linking the source item.
4. **alass + ffsubsync approved** as the catalog-wide subtitle-timing
   fixers (VAD-based, CI-runnable, applied only on ≤0.5s agreement); the
   on-device SpeechAnalyzer judge remains the runtime safety net and the
   only tool that can condemn a wrong-film file.

Per-platform nativeness reaffirmed (owner): tvOS built for tvOS, iOS for
iPhone, Android for Android — Decision 028's doctrine governs every phase.

**How to apply**: no playback/caption/sync architecture change ships outside
this plan without a new research pass (memory: feedback_research_before_fixes).
The phase gates are Decision 076's Release-build + throttled-gate scenarios.

## 080 — A subtitle file that ends after its film is provably mistimed; that one fact carries the whole detector
*Date: 2026-08-17*

Subtitle timing gains a second, independent fault class alongside Decision
062/064's constant offset: **drift**. `tools/audit_subtitle_rate.py` flags a
published file when its last cue ENDS after the film does — physically
impossible, so mistimed regardless of cause — and `tools/fix_subtitle_rate.py`
repairs the telecine subset by rescaling every cue by 23.976/25, gated on the
result landing inside the runtime, monotonic, cue-count unchanged. 44 files
repaired and published this pass; the corrections reach web, Android and every
Apple platform through the existing `subs.tar.gz` path with no app build.

**Why**: the owner reported Earth vs. the Flying Saucers' subtitles as
"incredibly poor". Measured — the file's last cue ends at 4994.8s on a
4818.7s film, 176 seconds past the end. Against speech transcribed locally at
two points 50 minutes apart it ran +51s late at the quarter mark and +184s
late near the end. It has no offset; it DRIFTS, because it was authored at
25fps and laid over a 23.976fps transfer. Decisions 062/064 search for one
constant offset and are structurally blind to that — no constant is right for
a file that is 0s off at the start and 200s off at the end, which is exactly
why every prior sweep left this film broken.

The repair is arithmetic, and that is measured rather than assumed: rescaling
by 23.976/25 matched the answer ffsubsync derived from the real audio to
within 0.4s at four points spanning the film. So this class needs no
download, no audio and no speech models, and runs in CI — lifting the
local-only constraint that has throttled Decision 064's sweep.

**How to apply**: detect on PHYSICS, never on pattern. The inference "ends
early at a telecine ratio" was built, measured, and DELETED: across 3,726
published files the distribution of (last cue end / runtime) is smooth and
rises monotonically toward 1.0 with NO spike at 0.9590, so a film with ~2:45
of end credits lands on that ratio by coincidence — the inference would have
rewritten 95 files with no evidence they were wrong (reefer_madness1938 is
one). Precision over recall, as in Decisions 035/064: leaving a bad file
alone costs captions on one film; rewriting a good one breaks a film that
worked. Read the cue END, not its start — reading the start mis-flags a
correct file whose final cue ends right at the runtime. Choose the tool by
fault class: alass models drift as splice shifts and pushed this same film's
last cue to 5176s, 344s WORSE than doing nothing; ffsubsync detects a
framerate scale and is the right tool when audio is available.

**Consequences**: the ratio gate is deliberately conservative and MISSES
films with end credits — Earth vs. the Flying Saucers itself reads 1.0366
rather than 1.0427 and had to be repaired from its audio-verified ffsubsync
output. 379 files are proven mistimed, 44 arithmetically repairable; the
remaining ~335 need the audio sweep (ffsubsync is VAD-based, so unlike
Decision 064 it needs no speech models and CAN run in CI — the cost is the
film download, popularity-first and resumable like every other sweep here).
A separate finding, not addressed: ~3% of popular captioned films advertise a
subtitle track whose VTT 404s — a dead promise the app currently makes.
`subtitleRateAudit` is an additive key older clients ignore.

