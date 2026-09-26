# Archive Watch — Architecture & Technology Decisions

Entries are ordered by date. This file is **append-only** — never
edit or remove past decisions. Platform noted where specific;
unlabeled = both.

## Format

- **Entries 001–015** use the older "Decision / Rationale /
  Alternatives / Trade-offs" format. They stay as-is.
- **Entries 016 onward** use the lead-with-WHY format — see the
  `architectural-decision-log` skill. The new entry template:

  ```
  ## NNN — Short imperative title
  *Date: YYYY-MM-DD*

  One paragraph stating the concrete decision. Lead with WHAT in
  specific terms — the first sentence is the choice.

  **Why**: the constraint, past incident, or alternative-rejected
  that makes this choice make sense.

  **How to apply**: when the next developer encounters this
  decision, what should they do or not do?

  (Optional) **Consequences**: forward-looking implications.
  ```

Each new entry must answer: *"what would the next developer get
wrong if they didn't know this?"* — if the answer is "nothing," the
entry isn't earning its keep.

Invoke `/decision` to log a new entry.

---

## Where entries live

This file is loaded into every session's context, so it holds the
format rules, the complete INDEX of every decision, and only the most
recent entries in full. Older entries are archived VERBATIM — moved,
never edited; append-only binds in the archives too (Decision 092):

- 001–030 → `docs/decisions/DECISIONS-001-030.md`
- 031–060 → `docs/decisions/DECISIONS-031-060.md`
- 061–080 → `docs/decisions/DECISIONS-061-080.md`
- 081–115 → `docs/decisions/DECISIONS-081-115.md`
- 116–122 → `docs/decisions/DECISIONS-116-122.md`
- 123–126 → `docs/decisions/DECISIONS-123-126.md`
- 127+ → below, in full

Keep this file under ~50 KB: when it grows past that, roll the oldest
full entries into a new archive file and extend the index — never trim,
edit, or summarize an entry in place. (The ceiling was ~120 KB from
2026-08-23 to 2026-09-14; it was lowered because this file is loaded
into every session and the index alone carries every title.)

---

## Index

### 001–030 — `docs/decisions/DECISIONS-001-030.md`

- 001 — Vanilla HTML/CSS/JS for Web
- 002 — Xcode Project at Repository Root
- 003 — Shared Version Config (xcconfig)
- 004 — SwiftUI + @Observable + SwiftData (iOS)
- 005 — Dual-Platform Feature Parity Model
- 006 — tvOS as the primary (only consumer) platform
- 007 — TMDb as primary metadata provider (non-commercial tier)
- 008 — Identifier-chaining enrichment cascade
- 009 — No user accounts; all state local
- 010 — Free App Store release (resolves TMDb commercial question)
- 011 — Hybrid curation: editor's picks + popularity-driven shelves
- 012 — Adult content filter on by default
- 013 — Per-category accent colors
- 014 — Random actions are M1 features
- 015 — tvOS home screen integration: Top Shelf + NSUserActivity + App Intents; skip Apple TV App partner program for v1
- 016 — Canonical TV spine from TVmaze; Archive items map onto it
- 017 — Deliver the catalog as a prebuilt SQLite DB on GitHub Pages
- 018 — Full catalog.json lives in a GitHub Release, not git
- 019 — On-device catalog DB decompression via Apple's Compression framework
- 020 — Catalog-mutating builds must be additive (merge-guarded), never replace
- 021 — Stream Archive video through a custom AVAssetResourceLoaderDelegate
- 022 — Sign in with Apple + CloudKit private DB for cross-Apple-TV sync
- 023 — Frame-extracted covers are hosted on an archive.org item, wired as generated art
- 024 — Cover frames are selected on-device with Apple Vision, not a paid API
- 025 — Color vs B&W is classified from video frames (ffmpeg saturation), stored as `colorMode`
- 026 — External matches are verified against the Archive item's OWN signals
- 027 — Copyright rights audit: hide modern non-PD titles behind a reversible `excluded` flag, confirmed by the Archive's OWN licenseurl
- 028 — Expand to iOS / Web / Android as fully-native apps over the SAME data plane; per-ecosystem sync on the user's own cloud
- 029 — Web viewer data plane: catalog-index + metadata API now; chunked SQLite via Actions-deployed Pages later
- 030 — archivewatch.org is the site root: viewer at /, editorial tool at /curate/

### 031–060 — `docs/decisions/DECISIONS-031-060.md`

- 031 — Stream loader delivers bytes as they arrive and pins the storage node
- 032 — Title-first PD discovery: a metadata-sourced wants list hunted on archive.org
- 033 — Clip Studio: native on-device clip/GIF/fan-edit creation differentiates the phone apps
- 034 — Stream loader fails over across Archive storage nodes
- 035 — Hide orphaned TV-episode duplicates; clear unanchored episode posters
- 036 — TV never appears in Movies; orphan episodes fold into series spines
- 037 — Player title+description overlay that fades with the transport controls
- 038 — "Open in Callsheet" via the callsheet:// URL scheme (iOS only)
- 039 — Subtitles: layered sources, side-loaded as tracks; archive.org ASR first
- 039a — Whisper auto-captioning runs in CI (sharded macOS), not on the owner's Mac
- 040 — Collapse same-film re-uploads into one best card (title + single-imdb anchor + runtime), grafting metadata
- 040a — Extend the dup-merge to multi-imdb attach + no-imdb runtime-corroborated sets
- 041 — archive.org community signals: harvested, used for sort/best-copy, surfaced as vote-floored shelves + pipeline-filtered reviews
- 039b — Whisper auto-captioning ABANDONED; subtitles come from archive.org ASR + OpenSubtitles only
- 042 — macOS "Creation Studio": a Mac-exclusive multi-clip editor, not the iOS app resized
- 043 — Drop archive.org auto-ASR captions; broaden title artifact cleaning
- 044 — Enforce the QC gates EVERY build: auto-apply rights, footprint-gate bogus CC, validate poster liveness, clear orphan auto-subtitle HLS
- 045 — Playable TV episodes are first-class catalog items (materialized in the DB)
- 046 — Backfill rich API metadata into the DB, tiered by use (blob / FTS / join table)
- 047 — Expand to smart TVs via TWO builds, not six; Cast/AirPlay for the closed platforms; Roku deferred
- 048 — A run that never started is not a failure to read; it is a failure to retry
- 049 — The Top Shelf rotates over published pools; personal and editorial rows MERGE
- 050 — Shelf membership that depends on an internal score is COMPUTED in the pipeline, never restated in a client
- 051 — AirPlay hands the RECEIVER a published URL; the resilient loader is a local-only path
- 052 — Trailers are removed as DATA, judged on runtime evidence the catalog already holds
- 053 — First paint comes from the CACHED catalog; the bundled seed is for first launch only
- 054 — On-device subtitles are served by a resource loader; a `file://` HLS master never plays
- 055 — "Already attempted" markers are per-source, or a second source can never run
- 056 — Verification freshness is tiered by visibility; a stale "verified" is invisible
- 057 — A run destroyed in the concurrency queue is retried; a long job may not hold the lock for hours
- 058 — Live captions are transcribed AHEAD of playback by a muted scout, never tapped from playback
- 059 — A caption is never replaced before its words are spoken, or before it can be read
- 060 — The Speech API shipping on a platform is not the model shipping; ask `AssetInventory.status`

### 061–080 — `docs/decisions/DECISIONS-061-080.md`

- 061 — From 27 the SYSTEM captions our films; the app's job is to get out of the way
- 062 — A published subtitle track is checked against what is being said, not trusted
- 063 — Hand captioning to the system only when it actually captions THIS film
- 064 — Mistimed subtitle files are corrected at the SOURCE, which is the only way most platforms get them right
- 065 — Generated subtitles need a track SELECTED and an asset without our resource loader
- 066 — Catalog writers compute without the lock and take it only to merge a delta
- 067 — A film with no subtitles plays on the PLAIN url, because the resilient loader is never offered a generated track
- 068 — On tvOS our caption engine LEADS; the system's generated track is opportunistic
- 069 — The scout's two clocks are platform traps: pin the pitch algorithm, map by rate, guard replays, follow the current player
- 070 — The captioned-HLS wrapper is retired on tvOS; the overlay renders the subtitle file
- 071 — The caption scout is MUTED on tvOS; a volume-0 second player races the main audio render
- 072 — One tvOS pipeline: every title plays through the resilient loader; the engine is the captioner
- 073 — The judge may not condemn a human subtitle file on a sparse transcript, nor nudge one inside its own noise
- 074 — Captions are an ECONOMY: every layer yields to playback on measured evidence, and the glass is the test
- 075 — Controlled experiments over correlation: the LAN remux control, and the instrument that manufactured its own disease
- 076 — Ship gates run under ADVERSE conditions: Release builds, throttled bandwidth, and playback owes the caption engine nothing
- 077 — A film starts within 30 seconds, or falls back to a copy that can (amends 021's no-downgrade rule)
- 078 — Watch history is a durable, union-merged record; progress is merely its most recent line
- 079 — The Quality Program: research-first rebuild of playback, captions, sync, and choice
- 080 — A subtitle file that ends after its film is provably mistimed; that one fact carries the whole detector

### 081–115 — `docs/decisions/DECISIONS-081-115.md`

- 081 — A drift correction may not rewind the captions past the viewer
- 082 — The LocalMediaServer passes every Mac gate and FAILS on the device; Phase 1 does not cut over
- 083 — `excluded` is shared state: a tool that hides items must register its marker, and the reconcile must say when one hasn't
- 084 — Record the EVIDENCE, not just the verdict; a colour reading vetoes a merge only when it is confident
- 085 — A merged-away id forwards to its survivor; a favorite must not vanish because a duplicate was collapsed
- 086 — A shelf that declares itself television may contain television
- 087 — A TV match whose era contradicts the item's OWN collection is cleared
- 088 — A liveness check expires; `posterChecked` gets a visibility-tiered TTL
- 089 — A shared index publishes only what it can prove it did not shrink; a missing asset is an emergency, not a first run
- 090 — An auditor judges each workflow against its OWN cadence, never a fixed window
- 091 — A time budget measures the whole tool, not the phase that happens to carry it
- 092 — DECISIONS.md holds the index + recent entries; older entries archive verbatim
- 093 — A red X is reserved for broken: backstops that published warn, and the auditor never re-alerts a failure that already emailed
- 094 — Fleet hardening: stock index guarded and .zz-only, no unguarded restores, budgets everywhere, the big lock holder split
- 095 — Queue displacement happens at JOB granularity too; the sweeper re-runs only zero-step jobs
- 096 — tvOS stays ENGINE-led: the system's generated captions are proven only on clean audio, and the plain path they require re-imports a measured disease
- 097 — A hero never reshapes its art: fit at the image's OWN aspect over an ambient wash, and Home shows professional posters only
- 098 — SharePlay coordinates by archiveID, listens from launch, and never lets "Watch Together" play alone
- 099 — Downloads are a background URLSession into Application Support; a downloaded film plays as a plain local file, and tvOS gets none
- 100 — A film's other release title is SHOWN, not reconciled; and a store's minSdk is a per-flavor decision
- 101 — The App Store submission is fully API-driven, and AppVersion.xcconfig is the ONE version number
- 102 — Google is Android's sync island and the WEB holds both; a deletion without a tombstone is a resurrection
- 103 — The player is not a tab: full-screen video renders outside the navigation scaffold, and PiP gets no chrome at all
- 104 — A `private` archive.org file is never a playable copy; the guard belongs in the picker, not the sweep
- 105 — The mature-content rule is ONE predicate: the apps' default-off setting and the web index's drop are the same function
- 106 — tvOS 27 loses the audio of a NON-FRAGMENTED mp4; remux to fMP4 and serve as HLS from the existing LocalMediaServer
- 107 — A red X means THIS run could not do its job; an auditor never fails, and a partial success is a warning
- 108 — One dashboard reads every channel; a reader that cannot read says so, and never a zero
- 109 — Store metrics come from the route each store actually offers, and each one's gotcha is written down
- 110 — A release builds in CI and is promoted, never rebuilt; the owner's machine is not a build server
- 111 — Amazon's APIs were one MAPPING away, and "no API" was our claim, not Amazon's
- 112 — Samsung ships US-only on Public Seller; the signing certificate is backed up beside the project
- 113 — The Roku Search feed advertises only what the rights audit KEEPS, never television, and its ids never change
- 114 — A bare CC claim rescues nothing, a 5,000-vote footprint in 1964-77 is a studio film, and a modern id wearing an old year is a wrong match
- 115 — A store's device count is the only place a minSdk regression is visible; the Fire TV build is gated on reaching Fire OS 7

### 116–122 — `docs/decisions/DECISIONS-116-122.md`

- 116 — A data contract is a test, not a docstring; and a client may not crash on a shape
- 117 — Roku's ingestion scores the CHANNEL INDEX, not the file; a withheld asset freezes its last verdict, so fit the poster instead
- 118 — A captioned film streams like any other and draws its cues in the overlay; a whole-film HLS segment ignores every buffer ceiling
- 119 — A television hands over a link as a CODE; the encoder is proven against an independent reference at every version, never against itself
- 120 — Social media is hosted where there is no ingest delay; a platform that could not post FAILS, and archive.org keeps only the video
- 121 — Correction to 119: Roku DOES share playlists, and a decision's closing paragraph outlives the hour it was true for
- 122 — Roku never RECEIVES a shared playlist, and the legacy tier never sends one; both are closed, not deferred

### 123–126 — `docs/decisions/DECISIONS-123-126.md`

- 123 — Pulse replaces the vendor consoles: every store is read by the route it actually offers, and a reading that cannot be trusted is refused rather than written
- 124 — A checked source's synopsis always beats the uploader's, every synopsis carries its provenance, and the client SAYS it
- 125 — Credits with no surviving id are residue unless the cast proves the film; and the same cast dates an upload-dated film
- 126 — A request that must be answered rides its own field; a shared query record served once per bump merges whatever lands on it together

### 127+ — in full below

- 127 — Watch Together goes public through an ON-DEVICE studio that speaks RTMPS itself: native frameworks, our own publisher, no encoder dependency
- 128 — A public client gets the flow each platform actually offers, not the one we prefer; and a missing credential is a STATE
- 129 — Android runs the SAME Studio with GLES in Core Image's place, and the host sees the PROGRAM because `setVideoSurface` is exclusive
- 130 — A runtime rule is proved on the PRODUCT path or it is not proved; a skip is not a pass, and the instrument is the first suspect
- 131 — Watch Together is THREE named things, each gated by hardware rather than by effort; a device says which it can do and why not the others
- 132 — A broadcast with no camera and no microphone is not Watch Together; the gate is that the HOST can be in the show
- 133 — A control is proved where its value LANDS, not where it is written; a shared type is not a shared code path
- 134 — A production surface owns its show end to end; and a macOS button says what it does at every width
- 135 — A picture is manipulated directly, not through sliders; and an uploader's attribution must not fork a film in two
- 136 — YouTube's quota belongs to the APP, so every read is spent on behalf of every host: slim sign-in, a quota extension, and a stream key that needs no API at all
- 137 — "Public domain by age" follows the calendar, never a literal year
- 138 — You are the show: going live needs the host, and the Studio captures only what a call runs in
- 139 — More Like This is ranked once, in the pipeline, by the people and series films share, and it says why
- 140 — An uploader's word is not enough: a modern or undated title kept only on its archive licence needs independent evidence
- 141 — Android runs from Android 6 (API 23) on every store; the floor is held by lint NewApi and by the bundled Let's Encrypt roots
- 142 — Watch Together is counted from what our servers and Google already see, never from the apps
- 143 — A room carries the host's copy, and every guest plays exactly that file

---

## 127 — Watch Together goes public through an ON-DEVICE studio that speaks RTMPS itself: native frameworks, our own publisher, no encoder dependency
*Date: 2026-09-17*

"Watch Together" is now one name with two halves — *with friends* (SharePlay,
Decision 098, unchanged) and *with the world* (a live broadcast to YouTube or
Twitch produced by **Watch Together Studio**). The Studio is on-device: the
app that holds the decoded film composites it with the camera and overlays,
mixes film audio with the microphone, encodes H.264/AAC with VideoToolbox and
AudioToolbox, and publishes RTMPS over `Network.framework` through an RTMP
client **we write**. Binding rules: `docs/WATCH-TOGETHER.md`.

**Why on-device**: YouTube and Twitch ingest RTMP/RTMPS from any encoder and
take nothing else from general creators (`docs/LIVE-RIFF-RESEARCH.md` §1 —
no WHIP, and Cloudflare's WHIP input cannot simulcast to RTMP). So either the
device encodes or a server does, and a server is a running cost and a thing
to operate for a free app with no accounts. The Apple devices we ship on
already decode the film, have a hardware encoder, and — on tvOS 17+ — can
borrow the iPhone as camera and mic through Continuity Camera. The server
path (guests by link, the web PWA) is Phase 4 and an owner decision.

**Why our own RTMP client rather than HaishinKit**: the project ships zero
third-party packages, deliberately, and every transport this app depends on
is one it owns and can read — the resilient stream loader (021), the HLS
fragmenter (106), the QR encoder (119), the Roku channel's whole stack. RTMP
is a small, fixed, documented protocol: a handshake, a chunk stream, four
AMF0 commands and FLV tags; Moblin (MIT) implements it in a few files and is
the reference for corners. A BSD dependency would bring a second concurrency
model, a second build system and an upstream we do not control into a
Swift-6-strict project, to save perhaps a thousand lines that we then could
not fix on the day YouTube changes a handshake. The harness cost is the same
either way.

**How to apply**: the film is composited from `AVPlayerItemVideoOutput`, never
screen-captured (ReplayKit is the fallback ONLY if Phase 0 measures that
composition cannot hold 30 fps on the iPhone 12, and that result goes in
WATCH-TOGETHER §9). Only rights-KEEP films reach the go-live sheet. Layouts
are presets. Health is never hidden. Stream keys are fetched by OAuth'd API
calls, never typed, never stored past the session, never logged. The
publisher is proven against a local `mediamtx` with `ffprobe` reading the
stream back (`tools/test_rtmp_publish.swift`) BEFORE any platform account is
involved, with a wrong key as the negative control.

**Consequences**: Phase 0 is a measurement, not a feature: a `StudioEngine`
and `RTMPPublisher` in shared code, a debug-only Studio Lab screen, and
numbers from the iPhone 12 and the Fireplace Apple TV. The two YouTube/Twitch
unknowns (the 50-subscriber rule for API streams; Twitch category) need test
channels the owner creates; the harness does not need them.

## 128 — A public client gets the flow each platform actually offers, not the one we prefer; and a missing credential is a STATE
*Date: 2026-09-17*

Watch Together Studio signs in to YouTube with **authorization code + PKCE
(S256)** through `ASWebAuthenticationSession`, and to Twitch with the **Device
Code Grant**. Two different flows, deliberately. Tokens live in the Keychain
(`…AfterFirstUnlockThisDeviceOnly`), and the redirect scheme is the **bundle
identifier**, not the reversed client id. With no client id configured, the
go-live sheet says sign-in is not set up in this build, names whose job it is,
and greys out Go Live. `Studio/StudioPlatformAuth.swift`;
`docs/WATCH-TOGETHER.md` §6.1.

**Why**: the app ships to devices, so it is a **public client** and can hold no
client secret. The plan was one flow — PKCE everywhere, which is the modern
correct answer for an installed app. Twitch does not support it. Its own
documentation for a public client offers the implicit grant or the device flow
and says nothing about PKCE (read 2026-09-17), and implicit returns **no
refresh token** — a host would re-authorise every few hours, which is the kind
of friction that quietly ends a feature. The device flow returns one and is the
same code path on a television as on a phone. So the shape of the code follows
what each platform will actually accept, not a symmetry that would have been
tidier to write.

**The redirect scheme is the more useful lesson.** Google documents two custom
schemes for an installed app: the reversed client id, or the reverse-DNS of a
domain you control. Almost every sample uses the reversed client id. It cannot
be used here, and the reason is not about OAuth at all: a URL scheme must be
declared in `Info.plist` at BUILD time, `ASWebAuthenticationSession` refuses to
start without the declaration, and the reversed client id is not known until
somebody pastes a client id into `Secrets.xcconfig`. Choosing it would have
turned "paste two strings" into "paste two strings and derive a third", with
the failure for getting it wrong being a sign-in that does not open.

**How to apply**: before designing an auth flow, read what the platform offers
a client of OUR type — the answer differs per platform and "it's OAuth 2" is
not the answer. Prove the request SHAPES before the credentials exist:
`tools/test_studio_signin.swift` sends deliberately invalid client ids to the
real endpoints, because a platform that rejects the CREDENTIAL has accepted the
REQUEST, and "invalid client" and "missing required parameter" are the two
answers that matter. Check PKCE against RFC 7636's own published vector, never
a golden file this code generated (Decision 119). And negative-control the
discriminator: the same request with `grant_type` removed must read differently,
or the check proves nothing (Decision 120). Save a refresh result ALWAYS —
Twitch's refresh tokens are one-time-use, so dropping the new one signs the
host out on the next call.

**And treat "no credential" as a state the screen can render.** Four defects in
that state were found only by putting it on an iPhone: a brand name mangled by
`rawValue.capitalized` ("Youtube") two lines above a hand-written "YouTube"; a
non-interactive `Label` taking the List's accent tint so a wrench read as a
button; a footer promising a sign-in the build could not offer, directly under
a row saying it was not set up; and a **Go Live button still pressable** that
would have failed inside the auth boundary. The first three are all the same
mistake — the unconfigured state was written as an absence rather than as a
screen somebody reads.

**Consequences**: the only remaining blocker on Watch Together's public half is
two strings in `Secrets.xcconfig` (`Secrets.xcconfig.example` carries the
registration steps). tvOS is the one unproven path: the session class exists
from tvOS 16 but `presentationContextProvider`,
`prefersEphemeralWebBrowserSession` and `cancel` are `API_UNAVAILABLE(tvos)`,
so the television presents the flow itself and that screen cannot be seen
until a client id exists. If it is unusable, the fallback is Google's device
flow — which does allow the `…/auth/youtube` scope, but requires a client
SECRET, and embedding one is a real cost rather than a formality.

## 129 — Android runs the SAME Studio with GLES in Core Image's place, and the host sees the PROGRAM because `setVideoSurface` is exclusive
*Date: 2026-09-17*

Watch Together Studio on Android is the Apple architecture with **GLES doing
Core Image's job**, and no third-party encoder — Decision 127's reasoning
carried over rather than re-argued. ExoPlayer decodes into a `SurfaceTexture`,
a GLES program samples it as an external OES texture and composites film,
camera tile and overlays **straight into MediaCodec's input Surface**, the
film's audio is tapped with Media3's `TeeAudioProcessor`, and our own Kotlin
`RtmpPublisher` — a port of the Swift one — sends it. RootEncoder is not used.
Rules: `docs/ANDROID-DESIGN.md` §9; measurements: `docs/WATCH-TOGETHER.md`
§6.2–§6.2l.

**Why the same architecture**: every Apple piece has a direct Android
counterpart, so the differences are all in the plumbing. Android is in fact
CHEAPER in the place that matters — compositing into the encoder's input
surface is zero-copy, where the Apple path renders through Core Image into a
`CVPixelBuffer` that VideoToolbox then reads.

**Why not Media3's own compositor**: `CompositionPlayer`, `Transformer` and
`VideoCompositor` — 2×2 grids, picture-in-picture layouts, a Lottie overlay
module — look like exactly this feature and are not. They compose MEDIA ITEMS
for preview and file EXPORT; nothing in 1.8–1.10 accepts a live camera as a
composition input or encodes a composed output in real time. A library that
ships the words "compositor" and "picture-in-picture" and still does not do
this is worth checking rather than assuming.

**THE ONE REAL DIVERGENCE, and it is a product decision rather than a
workaround.** On Apple, `AVPlayerItemVideoOutput` is a TAP: the player keeps
its own display and the Studio reads frames beside it. On Android,
`Player.setVideoSurface` is EXCLUSIVE — point the player at the Studio's
texture and the screen goes black; point it at the screen and the Studio gets
nothing. The first attempt did the latter and the readout honestly reported
`OFF` forever. So the engine draws the composed program TWICE, to two window
surfaces sharing one context: MediaCodec's input surface and the host's
screen. **The consequence is that an Android host sees the PROGRAM — film,
tile and lower third — rather than the bare film**, and that is better than
the Apple arrangement, not a concession: a host watching what their audience
is watching cannot be surprised by it.

**How to apply.** Four things on this path are silent when wrong, and every
one of them cost a run:

- `EGL_RECORDABLE_ANDROID` (0x3142) must be in the config attributes, or the
  driver may pick a config the encoder cannot consume — a black stream, not an
  error.
- MediaCodec emits **Annex-B**; RTMP wants **AVCC**. A server fed Annex-B
  accepts the publish and never identifies the track, which looks exactly like
  a network fault.
- `SurfaceTexture.setDefaultBufferSize` is not optional. Without it the
  decoder renders into a buffer that is not the film and everything else
  succeeds: frames arrive, `updateTexImage` works, the server records a
  perfectly healthy broadcast of nothing.
- `glViewport` belongs to the SURFACE, not the context. Two surfaces of
  different sizes share one context here, so the display pass inherits the
  encoder's viewport and draws the whole program into a corner of the screen.

And two timing rules with no analogue on Apple: **subtract the AAC encoder's
priming delay from audio timestamps** (measured at ~47 ms; 2048 samples at
44.1 kHz is 46.4 ms, and FLV has nowhere to carry an edit list, so the
timestamp is the only place to correct it), and **a broadcast must BEGIN with
a keyframe** — until one arrives, a joining viewer and a recording server have
nothing decodable while the stream looks live.

**Consequences**: the Studio is a **Google-flavour** feature (the `amazon`
flavour is minSdk 23 for Fire TV, which has no camera), and on Android "Watch
Together" means the WORLD half only, because there is no GroupActivities
equivalent and half a verb is not a verb. The engine, transport, encoder,
composite, audio, A/V alignment and rights gate are all proved on real
hardware; what is NOT proved is anything phone-shaped — a Google TV dongle
needs 37.4 ms a frame against a 33.3 ms budget even drawing once, so the
architecture is validated and its speed on a phone is not.

## 130 — A runtime rule is proved on the PRODUCT path or it is not proved; a skip is not a pass, and the instrument is the first suspect
*Date: 2026-09-17*

Every runtime rule in `docs/WATCH-TOGETHER.md` §6 must be exercised through the
path the app actually takes — the go-live surface, the engine the product
builds, the destination a host would reach — and the evidence must come from
outside our own optimism: a server's recording or byte counter, a photograph of
a screen, or a machine-readable line the app printed. `tools/test_studio_all.sh`
runs the §8 suite in one command and reports **pass, skip and fail as three
separate numbers**.

**Why**: §6 had five runtime rules and an audit found a defect in every one of
them, three implemented **nowhere** — and each had been believed because
something adjacent worked. The pattern in full:

- §6.3's idle timer was implemented only in `StudioLab`, behind `#if os(iOS)`,
  so tvOS never had it and the screen saver invalidated the encoder at 291 s.
- §6.2's audio session was configured only in `StudioLab` too, so on iOS the
  product began a show in `.playback`, which cannot record.
- §6.4's back-pressure cap was 2 MB, which at 2.5 Mbps is **6.4 seconds of
  latency**: it could not fire before the broadcast had stopped being live.
- §6.5 said `.serious` should halve the RESOLUTION, which an RTMP ingest will
  not accept mid-publish — the documented response would have destroyed the
  broadcast it was meant to save.
- §6.6 did not exist: a dropped link left the readout saying OFFLINE while
  nothing acted.
- §5's adaptive-step sentence was rendered by **no surface on any platform**;
  the only reader was a diagnostic log line.

**How to apply**: when a design doc states a runtime requirement, grep for
where it is actually set before believing it exists, and prefer a product path
over a harness even when the harness is easier. A harness can prove the logic
and still say nothing about where the logic RUNS — Android's reconnect
supervisor passed a JVM test and threw `NetworkOnMainThreadException` on every
attempt in the app, because the test called it from its own thread and the app
used Compose's main dispatcher.

**And distrust the instrument before the product.** In one session an
assertion judged `segs.last` and passed over the segment that mattered; a
readiness probe became the connection a severing proxy was meant to cut; a
throttle read from the client at full speed and so created a server-side rate
limit rather than congestion; `guard ma < mb` passed on 58.4 versus 58.3 bytes;
a bitrate test ran with no film against a ceiling nothing approached; totals
were compared across windows of different lengths; `print` to a pipe lost
everything when the process was killed; and a test runner reported PASS over
zero parsed results and then aborted silently while returning exit 0. In four
of those the verdict was the OPPOSITE of the truth, and in two a real defect
sat in the output the whole time.

So: **run the control that should obviously produce the opposite verdict**, and
when an assertion fires, do not accept the first explanation — a 1.63 s A/V
offset that looked exactly like a missing keyframe was a harness clock drifting
10 ms a frame.

**Consequences**: §6 is now implemented and measured on product paths on Apple
and Android, including §6.6's backoff read off a real run as 1/2/4/8/15/15/15 s
summing to its 60-second deadline. The suite is the mechanical form of this
decision; `--strict` makes a skip a failure. Owner-gated items are listed in
SCRATCHPAD rather than absorbed into "done".

## 131 — Watch Together is THREE named things, each gated by hardware rather than by effort; a device says which it can do and why not the others
*Date: 2026-09-20*

"Watch Together" names three features, and the names are binding: **With
Friends** (a SharePlay call with the film in sync), **With the World** (a
YouTube/Twitch broadcast with one camera and microphone), and **With Friends
and the World** (the film synced across Archive Watch instances while the
conversation runs on whatever calling service the participants already use —
Zoom, Meet, FaceTime, a phone call — captured by the host and mixed into the
broadcast). Which of the three a platform offers is decided by what the
hardware and the OS permit, and the canonical table is in `PARITY.md`
("What Watch Together MEANS on each platform"). **Every surface must state
which of the three THIS device can do, and why it cannot do the others** —
never a silently missing button.

**Why**: the owner asked for the boundaries in plain terms, and writing them
down showed that the question is not "how much have we built" but "what can
this device physically do". tvOS cannot START a SharePlay call because
`GroupActivitySharingController` does not exist there. A browser cannot speak
RTMP. Android has no GroupActivities equivalent, so half a verb is not a verb
(Decision 129). And only macOS can host the third mode, because
`AudioHardwareCreateProcessTap` is `API_UNAVAILABLE(ios, watchos, tvos)` —
which is what makes the owner's own proposal work at all, since a host who can
tap the call app means the APP never carries voice, and therefore needs no
relay, no NAT traversal and no running cost (SHAREPLAY §10; measured at §8.21,
82 dB of isolation between the tapped process and a second one playing at the
same time).

**And the third mode is the one that dissolves a problem rather than solving
it.** Several sessions went into a transport for guest voice — SharePlay is
Apple-only, a relay costs money, and the owner's constraint is that this app
costs $0 to run. Letting people use the call they already have removes the
transport entirely; what remains is sync, which is one or two orders of
magnitude cheaper than voice.

**How to apply**: when adding a Watch Together surface, first find the row in
PARITY's table — if the platform is 🚫 there, the answer is a sentence on the
screen, not an implementation. Do not invent a fourth phrase for one of the
three, and never call the third "multi-cam" or "group broadcast": it is the
second one with the first one's people in it. When a platform CANNOT do
something, treat that as a state with words, per Decision 128 — the four
defects found in the unconfigured sign-in state were all the same mistake,
an absence written where a screen was needed.

**Consequences, and a correction to Decision 129.** 129 says the Android
Studio is a **Google-flavour** feature. That is true only of the camera and
microphone: `CAMERA` and `RECORD_AUDIO` are declared in
`src/google/AndroidManifest.xml`, but all 18 Studio sources live in
`src/main/`, so the **Fire TV (`amazon`) build ships the engine, the publisher
and the Go Live dialog** — film-only, untested and undocumented. Separately,
`TvDetailScreen.kt:575` presents the Go Live dialog on **Google TV** with no
television check and no camera check, on boxes that have no camera and that
measured 37.4 ms a frame against a 33.3 ms budget with no hardware H.264
encoder at all. Both are OWNER decisions rather than obvious bugs — a
film-only broadcast from a television may be something to keep and describe
honestly, or an entry to gate — and both are listed in SCRATCHPAD rather than
quietly closed.

## 132 — A broadcast with no camera and no microphone is not Watch Together; the gate is that the HOST can be in the show
*Date: 2026-09-20*

Android's "Watch Together" entry — the television button and the phone's
overflow row, both — is gated on `Context.canHostWatchTogether()`: the device
must have **a camera AND a microphone**. Google TV and Fire TV therefore lose
the entry entirely; phones keep it. The predicate is
`StudioCapability.canHostShow(hasCamera:hasMicrophone:)`, and it asks for
`FEATURE_CAMERA_ANY` rather than `FEATURE_CAMERA`, because the latter means a
REAR camera and a front-facing-only device is exactly the shape that should
pass.

**Why**: the owner, on being shown that both television boxes were quietly
offering a film-only broadcast — *"There is no reason to build/have a feature
that shows as 'watch together' with only the ability to stream from the
Android/google/fire tv box without a camera and microphone to go along with it.
Everyone might as well just watch the movie on their own. The point of watching
together is to stream the video and have the ability to provide commentary or
conversation on top of it."*

That is a better rule than either option I had put in front of them (gate the
entry, or keep a film-only broadcast and describe it honestly), because it
names what the feature IS rather than what the hardware lacks. A film-only
broadcast is not a reduced Watch Together; it is a different and pointless
product — the audience could watch the same public-domain film themselves, from
the same archive, at the same quality.

**How to apply**: the test for a Watch Together surface is never "can this
device encode" — every box can, which is exactly why the defect survived. It is
"can a host be present in the show". Apply the predicate at EVERY entry point in
the same change: the phone's overflow row and the television's button are one
decision, and fixing one is how a defect survives in the other (§9.ttt found
this same pair once already). And do not reach for `isTelevision()` — the
question is about hardware, not form factor, so a television that did have a
camera would correctly pass, and a cameraless tablet would correctly fail.

**This narrows Decision 131's rule rather than contradicting it.** 131 says a
device states which of the three modes it can do instead of showing a missing
button. That holds for a capability the device COULD have and currently lacks —
an unconfigured sign-in, a camera not yet permitted. For a capability the
hardware can NEVER have, the entry is omitted outright: there is nothing for a
host to act on, and a permanent apology on a Detail screen is clutter rather
than information. The explanation belongs in PARITY's table, which is where the
question actually gets asked.

**Consequences**: on Android, "Watch Together" now means the phone and nothing
else, which also makes the untested Fire TV Studio path unreachable from the UI
rather than merely undocumented. Decision 129's "Google-flavour feature" is
accurate again in effect, though still not in the source layout — all 18 Studio
sources remain in `src/main/` and only the permissions are flavour-scoped.
tvOS is deliberately unaffected: it has no camera either, but it can BORROW an
iPhone through Continuity Camera, and that is the whole difference.

## 133 — A control is proved where its value LANDS, not where it is written; a shared type is not a shared code path
*Date: 2026-09-20*

Two rules, from one fault met six times in a day.

**First: a control is verified by reading the value at the ENGINE, or on the
wire, never by seeing the control move.** A picker that highlights, a switch
that flips and a request field that is populated are all evidence that a
surface works, and none is evidence that anything downstream received it.

**Second: putting a behaviour in a shared TYPE does not put it on a shared
PATH.** Before adding anything to `StudioSession`, `StudioEngine` or a shared
Kotlin object, establish which platforms actually execute that code — and
prefer wiring it into each platform's own loop over assuming one loop is
everyone's.

**Why**: the same defect appeared five times in the camera-placement work
alone, each found only because the previous one prompted a look:
`GoLiveTV.request()` built its request with `layout: .corner` hardcoded;
`DetailView` then called `setLayout(.corner)` with the value hardcoded a second
time, so fixing the first changed nothing; the **macOS go-live sheet never read
`request.layout` at all**, so every broadcast from the path a real host takes
went out as `corner` however they chose; Android's engine read the layout once
at arm, leaving the picker inert on the one platform whose picker exists only
while live; and the macOS panel opened on `.corner` over a show doing something
else. Each looked like it worked. Only the wire disagreed.

**And the sixth was self-inflicted while documenting the other five.** The
camera-stall recovery and the "film's audio is not being sent" warning were
added to `StudioSession.startPump` and committed as reaching "macOS and iOS".
**iOS never arms or starts `StudioSession`** — `StudioPlayerContainer_iOS`
owns its own engine and its own poll loop — so both were inert on the phone,
and `StudioControls_iOS` was reading a warning nothing wrote. The type was
shared; the path was not. It surfaced from a MISSING LOG LINE, not from
re-reading the code: §6.4 could not be measured on the phone because
`StudioSession.diag` writes to stderr, which reaches nothing on a device.

**How to apply**: drive the product and read the result from outside it — a
server's recording, the publisher's own counters, the framework's log. Three
separate proofs this session inverted on that alone. A `pts_time` histogram
showed an untroubled 30 fps through a "throttled" window because media time is
continuous by construction; the publisher's counters showed 1.8 fps and 834
dropped frames in the same window. An Android camera recovery logged
`recovery 1: no camera` over a camera that had just reconnected, because it
asked a stale `problem` string rather than what the re-open returned — the
framework's `CameraService::connect` and the tile in the stream both said
otherwise. And a devicectl screenshot SUCCEEDED against a sleeping television,
returning a valid all-black frame that reads exactly like an app drawing
nothing.

**Consequences**: `StudioSession.armLayout` removes the timing question from
every caller rather than adding a sixth that remembers it; `diag` now also
writes to `DiagFile` so a device harness can read it; the iOS container carries
the recovery, the warning and the health line itself; and a debug door must
drive the chain the PRODUCT drives — the macOS door waited for `isLive` and
called `setLayout` where the sheet arms, which is precisely why every bench run
looked correct while the product was wrong.

## 134 — A production surface owns its show end to end; and a macOS button says what it does at every width
*Date: 2026-09-22*

The macOS Watch Together Studio now contains the whole broadcast: a film
chooser that searches the catalogue, the film's own player in a SOURCE pane
beside the PROGRAM preview, the device pickers, the mixer, the output
settings, and the entire go-live checklist that used to live in a sheet over a
different window. Rule B13g's sheet is deleted; ⇧⌘L and the player's toolbar
button open the Studio instead. The ordinary player window becomes an optional
PROJECTION the host asks for, and the film MOVES to it rather than being
copied. Separately, no macOS button may abbreviate its label: a row of actions
keeps a small fixed set of primary buttons and folds the rest into a native
"More" menu, chosen by `ViewThatFits`. Rules: `docs/macOS-DESIGN.md` §D7–§D13.

**Why**: the owner ran the shipped Studio for the first time and reported six
things. Four of them were not defects in the build — they were places where a
rule written earlier was wrong, and the build implemented it faithfully.

- **§D1 gave the Studio a window and left the film in another one.** So the
  Studio was a window of controls for a show it did not contain, and a host who
  opened it with nothing playing was told to go and start a film elsewhere.
  *"There doesn't seem to be any way to 'add a movie' to the studio from the
  studio itself."*
- **Rule B13g put the go-live form in a sheet**, because it asked where a host
  PRESSES Go Live and never where a host DECIDES to. The owner found it by
  accident: *"I think I may have found it hidden behind a button on the video
  player (rather than in the studio for some reason.)"*
- **§D2 said "device changes take effect on the next broadcast"**, from a true
  fact (an `AVCaptureSession` is built once) and a wrong conclusion. The
  capture session is not the encoder: the camera tile is COMPOSITED, so the
  wire never learns which device made the pixels, and §D4's "not while live"
  belongs to resolution and frame rate alone.
- **"The Studio REPORTS, never REQUESTS"** came from tvOS, where a system
  prompt in a living room is a real intrusion. Carried to the Mac it meant
  nothing in the product path had ever called `requestAccess`, so
  `authorizationStatus` was `.notDetermined` for the life of the app and the
  camera row read **"not attached"** forever with nothing to press. That is not
  reporting; it is a dead end with a label on it.

**How to apply**: when a surface is named for an activity — a Studio, an
editor, a console — it owns that activity end to end. If a host has to leave it
to assemble the thing it produces, the surface is a control panel for someone
else's work. And when a rule and a report disagree, check whether the rule was
ever tested against the product rather than argued from a framework fact:
every one of the four above reads as correct engineering in isolation.

**The button rule is the same lesson in miniature, and it took two passes.**
The first answer to *"Button text should never be truncated or abbreviated"*
was a wrapping `Layout` — which kept the words and destroyed the design, since
seven large buttons reflowed into three ragged rows with "Share" stranded
alone. The owner: *"We don't want button wrapping. We want actual designed
buttons that say what they mean and perform like macOS buttons should."* So:
`ViewThatFits` over arrangements that were each DESIGNED, every control
`.fixedSize()` (without it the first arrangement always "fits", by squeezing),
and the overflow is a native menu that still says the words. No icon-only
fallback — an icon with a tooltip is an abbreviation with extra steps. The
rule reaches past buttons: the same narrow screen was rendering "Rev. Arthur
Di…" under a cast portrait.

**Consequences**: the Detail row names each action ONCE (`DetailAction`) and
renders it either as a control or as a menu item, because two parallel lists
is how the two copies drift. `StudioSession` gained `registerSurfacePlayer` /
`beginShow`, since §D7 reverses the old order — the player now exists BEFORE
the host decides to produce a show, and `attachIfArmed` only ever ran the
other way round. Closing either window ends what it was doing (§D12): a player
surface that goes away pauses and releases its player, which it never did, so
a film kept playing with no transport left to stop it and a second copy
started on the next open.

## 135 — A picture is manipulated directly, not through sliders; and an uploader's attribution must not fork a film in two
*Date: 2026-09-22*

The macOS Studio frames its camera by **direct manipulation of the tile in the
STREAM preview**, on OBS's canvas pattern: drag inside to move, a corner to
resize, an EDGE to reshape, scroll to zoom the source, ⌥-drag to pan it. The
four sliders that did the same job are deleted; what remains beside them is a
readout and a Reset. Separately, `build_sqlite._dupe_title_key` treats a
**double-quoted run at the END of a title as the title**, so
`Buster Keaton's "The Scarecrow"` clusters with `The Scarecrow`.
Rules: `docs/macOS-DESIGN.md` §D14a.

**Why the sliders were wrong, and it is not that there were four of them.**
§D14 modelled the tile as the preset's rectangle SCALED. A scale can make a
rectangle bigger or smaller and can never change its SHAPE — and cropping a
camera is exactly a change of shape. So the one thing the owner asked for
("only capture my face") was the one thing the control could not do, and the
zoom was standing in for it. *"Most people expect to crop the video frame
(size and shape of the actual video tile) rather than zoom and move."*

**What OBS gave us and where we improved on it.** OBS's canvas is the pattern
hosts already know: handles, drag-to-move, corner-versus-side, and Option-drag
for a separate crop mode that turns the edges green. We take everything except
the crop mode, because our tile is aspect-FILLED — reshaping the box IS the
crop, so one gesture does what OBS needs two and a modifier key for. Precision
is a readout rather than OBS's Edit Transform dialog: a watch-along host needs
to know the crop they are at far more than they need to type one.

**How to apply**: when a control describes something already on screen, put
the control ON the thing. Four sliders in another column were a second
description of a picture the host was already looking at, and the mismatch
between the two is where the clunkiness lived. And publish the composited rect
(`StudioHealth.cameraTile`) rather than re-deriving the layout in the view —
Decision 133's rule, in its geometric form.

**Two framework facts, each of which cost a run.** `.offset` is a RENDER
transform: the `NSView` behind an offset SwiftUI view stays where it was laid
out, so a scroll-catcher backing the tile reported the pane's corner as its own
frame. And AppKit dispatches `scrollWheel` to `hitTest`'s view and then up ITS
responder chain, so a representable in `.background` — a sibling of SwiftUI's
hosting view — is never on that chain; `.overlay` only trades it for a dead
drag. A local `NSEvent` monitor sees the event first and can still ask whether
the pointer is over it.

**The catalogue half is the same shape of error one layer down.** Decision 040
clusters re-uploads by NORMALISED TITLE and only then asks `_same_film`. Two
cards for one Buster Keaton short survived because the keys were
`busterkeatonsthescarecrow` and `scarecrow` — while `_same_film` returns True
for that pair, and was never consulted. **The obvious fix is wrong**: stripping
any leading `<Word>'s ` turns *Pandora's Box* into `box`. A double-quoted run
ANCHORED AT THE END is the uploader's actual convention and leaves unquoted
titles alone. **Measured before it shipped**: 121 titles change key into 49 new
clusters, every one a Keaton or Chaplin short beside its bare-titled twin. The
first draft also handled single quotes and produced `Let's Get Movin'` →
`s Get Movin`; the catalogue itself said the branch was not worth its damage.

**Consequences**: `StudioCameraFraming` is now a normalized tile rect plus zoom
and pan, and it is NOT per-layout — the crop follows the person, the preset
follows the show. The framing gestures are macOS-only and PARITY says so: a
pointer-and-scroll interaction does not port to a Siri Remote unchanged, and
inventing one per platform is a design question rather than a port. The
catalogue change needs a rebuild to take effect, and
`tools/test_quoted_title_merge.py` guards both the merge and the over-merge.

## 136 — YouTube's quota belongs to the APP, so every read is spent on behalf of every host: slim sign-in, a quota extension, and a stream key that needs no API at all
*Date: 2026-09-23*

YouTube Data API quota is counted per Google Cloud PROJECT — the one behind the
app's OAuth client id — not per signed-in user. Every host who signs in to
Archive Watch draws on the same 10,000 units a day. So the Studio does three
things at once: (1) the signed-in path spends as little as possible — chat is
read no faster than every 10 s, the viewer count every 60 s, a
`quotaExceeded` answer STOPS reading and says so rather than retrying, and
chat reading becomes something the host turns on; (2) the owner files
Google's YouTube API quota extension (the compliance audit, separate from
OAuth verification); (3) **"Use my own stream key"** is always offered — the
host pastes the key from YouTube Studio, exactly as in OBS, which calls no API
and spends no quota, and is the fallback when the shared quota is gone.

**Why**: the owner, on learning the store builds ship the app's client ids —
*"You are shipping my ID's inside of the apps instead of letting users set
their own up? You will need to figure out a much better way to use the api
quota as well, given that we want many people to use this as possible. Is
everyone's own api quota their own?"* It is not. The client id identifies the
APP (as OBS's and Streamlabs' do) and is public by design; users still sign in
as themselves and broadcast to their own channels. But the quota follows the
id, and the audit measured a two-hour show at ~7,700 units, ~7,200 of them
chat polling at YouTube's own 5 s interval — about one show a day for
everyone. "Bring your own Google Cloud project" does give each host their own
quota and was rejected as the DEFAULT: creating a project, enabling an API and
configuring a consent screen is a wall almost nobody climbs, which is the
opposite of "as many people as possible". Twitch is unaffected — its rate
limits are per user token.

**How to apply**: treat every YouTube call as spent on behalf of every other
host. Before adding one, price it (units x calls per show) and write the price
next to the call. Never retry a `quotaExceeded`; back off exponentially on
anything else. Every signed-in feature must degrade to "the broadcast still
works" when the quota is gone — the RTMP stream itself uses no API. And keep
the stream-key path first-class, not a debug door: it is the one route whose
capacity does not depend on Google.

**Consequences**: §8.56 holds the floor, the stop and the control. The
chat-opt-in UI and the stream-key path are the next Studio changes; the
extension is an owner action. The "Custom server" option already sends to any
RTMP address and is the seed of the stream-key path.

## 137 — "Public domain by age" follows the calendar, never a literal year
*Date: 2026-09-23*

The age line is computed, everywhere it is drawn: a US work is protected 95
years and enters the public domain on January 1 of year + 96, so the newest
public-domain year is `this year - 96` (1930, in 2026). `tools/audit_rights.py`
(`PD_BY_AGE = today.year - 95`, the first year NOT yet free),
`remediate_catalog.py`, `social_select.py`, and the Studio's
`StudioRights.lastPublicDomainYear()` on Apple and Android all compute it. The
on-air provenance line is now "Public domain — published 1930" with no
"before 19xx" clause to go stale.

**Why**: the audit carried the literal `1929` from 2024, and the Studio the
literal "before 1930". So two New Years had passed unapplied: 1,691 catalog
items from 1929-30 sat in `presumed_pd` — the ERA assumption the marquee, the
Roku feed's guaranteed tier and the Studio all refuse — when they are public
domain by AGE, the one claim nobody can argue. Those two years are the first
sound era, which is exactly what a watch-along needs (the owner: stop picking
films with no audio; the guaranteed tier had made that impossible by
construction). A 1930 film would also have gone on air labeled "published
1930, before 1930".

**How to apply**: never write a public-domain year as a literal. Measured
before shipping: 1,690 `presumed_pd -> safe_pd_age` and 1 `commercial_keep ->
safe_pd_age`, all keep-to-keep — nothing is hidden or un-hidden, because
`renewed_copyright_classic` and every hide bucket run BEFORE the age test. This
is the tier's own definition applied on the right date, not a widening of it;
widening `guaranteed` to other buckets remains the owner's call (Decision 027).

**Consequences**: the buckets move at the next catalog build and again every
January 1 with no code change; `tools/test_studio_rights.swift` pins the
date arithmetic (2026-12-31 -> 1930, 2027-01-01 -> 1931).

## 138 — You are the show: going live needs the host, and the Studio captures only what a call runs in
*Date: 2026-09-24*

Go Live now requires the host to be in the broadcast on every platform: a
camera AND a microphone, allowed and present (Mac and iPhone,
`StudioSession.hostAbsentReason()`), a paired iPhone as camera and microphone
(Apple TV), camera and microphone permissions (Android phone). The "Optional —
the film broadcasts fine on its own" line is gone; the refusal says "Going
live needs your camera and microphone — you are the show." Separately, the Mac
Studio's call-audio and guest-window pickers offer only calling apps and web
browsers (`StudioCallApps`), with a warning under a chosen browser.

**Why**: the owner, 2026-09-24 — *"Streaming a movie on your own serves no
purpose, as the movie on its own is already available via archive.org and
streaming it without a camera or microphone only puts another copy online with
no additional value being added."* Decision 132 had applied that to Android's
ENTRY on hardware grounds; this applies it at the moment of going live,
everywhere. The capture rule answers the owner's delegated editorial call on
the rights gap the launch audit found: the pickers could put ANY app's sound
or picture on air, which is a way around the rights gate. Restricting them to
what a call runs in keeps Decision 131's "use the call you already have"
working — including Meet and Zoom in a browser, which is how a great many
people call — while closing the door on a music or video app.

**How to apply**: a new way onto the air must pass `hostAbsentReason()` (or
its platform equivalent), and a new capture source must pass
`StudioCallApps.kind`. Extend `StudioCallApps.calls` when a calling app is
missing; never add a media player. The DEBUG bench doors still broadcast
without capture, because they test transport, not a show.

**Consequences**: §8.70 pins the classifier (calls, browsers, refused players,
a look-alike control). The guest-voice code (`StudioVoice*`, §8.18-20) was
deleted the same day at the owner's word — Decision 131 settled voice the
other way, and git keeps it.

## 139 — More Like This is ranked once, in the pipeline, by the people and series films share, and it says why
*Date: 2026-09-24*

`build_sqlite` now writes `item_related` (one row per film: up to ten related
archiveIDs and, for each, the strongest shared link — `franchise`, `director`,
`cast`, `writer` or `keyword`), computed by `tools/build_related.py` over the
rows that actually reached `items`. Clients read it and fall back to their
existing type + era query when a film has no row.

**Why**: every platform ranked "related" its own way — contentType, then ±10
years, then popularity, with tvOS alone re-scoring by director and collection
and the web using type and year only — so the same film had a different shelf
on every screen, and none of them used what the catalog knows best about how
films connect. 57% of visible titles carry TMDb cast with person ids and 9,807
people appear in two or more films; 217 franchises span 927 films (the
Rathbone Holmes, Why We Fight, Our Gang). Measured on the real catalog, the
pipeline ranking gives Metropolis → M, Dr. Mabuse, Woman in the Moon, Spies;
Nosferatu → Faust, Sunrise, The Last Laugh and Dracula (via Bram Stoker);
Detour → the rest of Edgar G. Ulmer. The reason exists because a shelf that
can say *why* two films belong together invites the viewer to follow a
thread — a director, a series, a writer — rather than scroll a feed.

**How to apply**: tune weights in `build_related.py`, never per client, and run
`tools/test_related.py` (a person must outrank a pile of rare keywords; a film
never lists another copy of itself; its control lifts the keyword cap and must
fail). Compute over post-merge, post-rights rows only: on `catalog.json`
directly the first draft filled Nosferatu's shelf with five Nosferatus.

**Consequences**: a row per LINK with its own index cost 15.5 MB raw / 5 MB
compressed (+16% on every download); one TAB-joined row per film costs 5.9 MB
raw / 1.9 MB compressed (+6%), accepted for 12,351 films with shelves. The web
and Roku read no SQLite and need the same data in their own channel (detail
shards / index) — not yet built. Whether the reason is SHOWN is a per-platform
design-doc question under the owner's essential-information rule, not settled
here.

## 140 — An uploader's word is not enough: a modern or undated title kept only on its archive licence needs independent evidence
*Date: 2026-09-25*

A title that `license_rescues` would keep, and whose year is 1978 or later or
unknown, is kept only when it carries `rightsCorroborated` — Wikidata records a
Creative Commons licence (P275) or public-domain status (P6216) on the item
whose Internet Archive ID (P724) is this archiveID, or
`shared/editorial/licence_evidence.json` names a source URL for it. Otherwise
it is `uploader_licence_only`, a HIDE bucket. The 1931-77 band keeps the renewal
rules' judgement. `tools/corroborate_licences.py` runs in rights-audit.

**Why**: the owner, asked about modern titles kept on an uploader's CC tag:
*"If you have proof of genuine creator CC, then you can release them.
Otherwise, it is clear that many of these have no business being in an app
built to watch the public domain. Unless we have evidence for CC or PD, an
uploader's word is not enough."* Measured first: the class was not the 55
modern titles the question described but 1,345 visible titles, 1,266 of them
undated (features, shorts, classic-TV episodes, commercials, drive-in ads,
junk such as "714 Z 2"). Shown that scale, the owner chose modern + undated.
Wikidata corroborates genuine creator releases — Star Wreck: In the
Pirkining, Fossils, Apartment 5A, Spirit Chaser — and 1,321 titles are hidden.

**How to apply**: never widen a rescue on the licence URL alone. To bring a
title back, add evidence: a Wikidata statement or a `licence_evidence.json`
entry whose `source` a reader can open. The hide is recomputed every build, so
evidence lifts it on the next publish. Ingest holds such uploads
(`held_modern_license`) on the same bucket, so the two cannot disagree.
`tools/test_audit_rights.py` pairs each case: hidden without evidence, kept with it.


## 141 — Android runs from Android 6 (API 23) on every store; the floor is held by lint NewApi and by the bundled Let's Encrypt roots
*Date: 2026-09-25*

The Google Play build's `minSdk` drops from 29 to **23**, the floor the Fire
TV flavor already shipped at (Decision 100). Twelve calls above API 23 in the
shared source are guarded or moved to AndroidX compat, and ISRG Root X1/X2 are
bundled as extra trust anchors in `res/xml/network_security_config.xml`.

**Why**: the owner asked what stopped older Android and Google TV devices from
being supported. Measured: no dependency needs more than 23 (the manifest merge
passes), so the floor of 29 was a number nobody had questioned. What DID stand
in the way was invisible from the build: lint NewApi found 12 calls that do
not exist below Android 7-8 — live hazards in the Fire TV build already — and
every endpoint the catalog and posters come from chains to Let's Encrypt,
which Android 6.0-7.0 do not trust, so on those devices the app would install
and then fail to download its catalog. Owner, choosing the floor: "Android 6+
(API 23)".

**How to apply**: keep `lint NewApi` clean at 23 for BOTH flavors before any
release (`./gradlew :app:lintGoogleRelease :app:lintAmazonRelease` with
NewApi); a call above 23 needs a `Build.VERSION.SDK_INT` guard or a Compat
equivalent. Never remove the ISRG trust anchors while any endpoint chains to
Let's Encrypt. No test device runs below Android 11, so Play's crash clusters
by API level are the first real evidence from 23-29; read them after release.


## 142 — Watch Together is counted from what our servers and Google already see, never from the apps
*Date: 2026-09-25*

Pulse counts rooms opened and guests joined from a tally the Worker keeps as it
creates rooms (`together_days`: day, kind, count — no film, code, token or
address), and counts YouTube broadcasts from Google Cloud Monitoring's
request counts for the app's OAuth project (`liveBroadcasts.insert`, 2xx).
No app sends anything new. Twitch and own-stream-key broadcasts are therefore
not counted, and the page says so.

**Why**: the owner asked to count rooms and streams "anonymously within our
privacy framework", and the framework is a published promise — privacy.html:
*"The apps have no analytics of any kind"* and *"The only thing an app ever
sends our server is a Watch Together room's playback position."* An app-side
"went live" ping would have counted every broadcast and broken that sentence,
while Google was reviewing that same page for OAuth verification. Offered both,
the owner chose Google's own counts and a room tally without the film.

**How to apply**: a new Pulse number about app usage must come from something a
server ALREADY receives to provide the feature, or from a vendor's own
reporting — never from a client sending a count. If a question cannot be
answered that way, the answer is a privacy.html change the owner makes, not a
reader. The Monitoring read must carry `x-goog-user-project: archive-watch`
(docs/PULSE-ANALYTICS.md §11).


## 143 — A room carries the host's copy, and every guest plays exactly that file
*Date: 2026-09-26*

A Watch Together room now stores `copy` — `<archive item>/<file name>`, the file
the host's player is showing — and every guest plays that file and no other:
the join screens, room links and debug doors read the room before a player is
built, `ArchiveVersions.preferredURL` answers the room's copy first on Apple and
Android, a downloaded file of another copy is skipped, and the pickers refuse
with a reason while in a room. The web plays `Together.copyURL(state.copy)`.
Rules: SHAREPLAY §11.14.

**Why**: the owner — *"The host chooses the video that all Watch Together
participants should be watching. There should be no way to choose the wrong one
via the four digit code."* The room held only the title, so each guest played
its own saved copy; the versions work that exposed merged uploads (Decision 040)
made that likelier, and copies differ in length (the two Keaton Scarecrows by
55 s), so a guest syncing to the host's position on another copy was on another
timeline. Measured before the fix: the live web guest played the title's
default while the host named another file.

**How to apply**: a room names a FILE on archive.org, never a URL — every client
builds the download URL from `<item>/<file>` with the same rules as the
Worker's `normalizeCopy`, so a room cannot point a guest's player at another
host. Any new join path must `prime` the room before building its player, and
any new play path must go through `preferredURL`. A host that predates `copy`
gets the title's DEFAULT copy for everyone, never each viewer's choice.

