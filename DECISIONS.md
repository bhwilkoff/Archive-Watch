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
- 127–145 → `docs/decisions/DECISIONS-127-145.md`
- 146–160 → `docs/decisions/DECISIONS-146-160.md`
- 161+ → below, in full

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

### 127–145 — `docs/decisions/DECISIONS-127-145.md`

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
- 144 — Channels run on one clock: the pipeline publishes the timeline, every client plays it and shows it in local time
- 145 — The IPTV feeds carry everything the apps show, television as series, and a channel never joins a film's last scrap

### 146–160 — `docs/decisions/DECISIONS-146-160.md`

- 146 — The Creation Studio clips any title the apps show; fair use is its rule, not the broadcast tier
- 147 — A film the system can caption plays through the loopback proxy, paced to twice its bitrate
- 148 — Older Apple TVs are served by the tvOS 26 floor, not a second app; the floor is held below 27
- 149 — Propaganda is never recommended and always findable; "true propaganda" is the Nazi state's, on evidence a reader can open
- 150 — A cleared match leaves nothing it filled unless something independent vouches for it
- 151 — A title leaves the catalog on a copyright claim a reader can open; not knowing is not a claim
- 152 — Sourced evidence of a free licence outranks the popularity check
- 153 — A work made with Archive Watch claims Creative Commons or fair use, never public domain
- 154 — The Android floor is a floor, not a ceiling: modern devices get modern features, gated by OS version
- 155 — The iPhone/iPad floor is iOS 18: the XS and XR come back, iOS 26 features are gated, and iOS 12 is the website's job
- 156 — A foreign film URAA restored is never recommended and always findable
- 157 — Pre-1950 renewals are read from the printed Catalog of Copyright Entries
- 158 — A colorized copy is a version of its black-and-white film, never the default
- 159 — An undated upload a reviewer judged modern is hidden until it is identified
- 160 — Every sound is held to the age of its own picture, and the audio clock is the wall clock

### 161+ — in full below

- 161 — A narrow link is answered with the bitrate before a dropped frame, and a drop ends at the next keyframe it can ask for
- 162 — The Samsung TV floor is 2022 (Tizen 6.5, Chromium 85), held by a polyfill file and a build gate
- 163 — archive.org's own trailer collection outweighs the silent-era guard
- 164 — Roblox is shelved: the films are what it cannot carry well
- 165 — The Play build's floor is Android 7, because Play's automatic protection requires it; Fire TV keeps Android 6
- 166 — A series held in one archive.org item is a series: its files become episodes, `<item>@<token>`, on evidence the item itself gives
- 167 — A whole series filed in one item and matched onto a TVmaze show becomes that show's episodes, placed by title
- 168 — Correction to 167: each file of a whole-series item is judged by its own year; its item answers only for the licence
- 169 — A single-episode upload is placed by its own file name and id, and a person's "never serve this" binds every series
- 170 — A sort is remembered per kind of grid and television starts A–Z; a playlist's place among playlists is synced, and every sync writer carries it
- 171 — Top Rated ranks each title by the largest crowd that rated it, against that crowd's own average; every rating names its crowd
- 172 — An identity must fit the file it is on, a fragment is never recommended, and a copyright claim belongs to the film, not the copy
- 173 — The pipeline fails loudly: pipefail everywhere, nothing publishes from a cancelled or failed build, and a publish carries its deletions

---

## 161 — A narrow link is answered with the bitrate before a dropped frame, and a drop ends at the next keyframe it can ask for
*Date: 2026-10-02*

`RTMPPublisher.send(video:)` returns how full its queue is, what the link carried
over the last second while a queue stood, and whether a drop is under way; the
engine steps the bitrate down past 60% of the §6.4a budget — straight to 80% of
the measured link — asks for a keyframe as soon as a drop has drained to half the
budget, and steps back up 20% after ten clear seconds (WATCH-TOGETHER §6.4b).

**Why**: the owner: *"It said dropped 451 (it did stutter occasionally)."* §6.4a's
drop was the only defence, and each drop froze the picture until the next
scheduled keyframe, up to two seconds. On one throttle (6 Mbps program, 1.8 Mbps
link) dropping alone lost 263 frames; stepping by quarters 80; stepping to the
measured link 0. A queue depth is a symptom; what the link carried is the number
to steer by.

**How to apply**: never answer congestion with resolution or frame rate (§6.5).
`setLinkAdaptation(false)` / `AW_STUDIO_LINK_ADAPT=off` is the control, and §8.6
runs with it so it keeps testing the last resort. A throttle the program fits
under proves nothing — §8.79 refuses to judge unless its control drops frames.

## 162 — The Samsung TV floor is 2022 (Tizen 6.5, Chromium 85), held by a polyfill file and a build gate
*Date: 2026-10-03*

The Tizen package declares `required_version="6.5"` and is released to the
2022-2026 model groups. The shared web code that runs inside it stays within
Chromium 85: `js/compat.js` loads before every other script and fills
`AbortSignal.timeout` and `replaceChildren`; the CSS uses longhands instead of
`inset`/`padding-inline`/`margin-inline`, `:focus` instead of `:focus-visible`
on TV, and puts `color-mix()` and `overflow: clip` behind `@supports`.
`tools/test_tv_compat.py` enforces the CSS rules (with planted controls) and
`tv/build-tv-packages.sh` refuses to package when it fails.

**Why**: the owner, preparing the Samsung submission: *"I'd like to be able to
support everything from 2022 onward."* The config had claimed Tizen 6.0, but
nothing ever ran the app on an engine older than the test set's Chromium 120.
Rendered in a real Chromium 85 build, Home was empty (`replaceChildren` threw
while drawing it, and every bounded fetch threw on `AbortSignal.timeout`), the
overscan padding was gone, sheets fell out of center, and the category tiles
had no color because `color-mix()` with `var()` passes the parser and fails at
compute time, voiding the fallback written above it.

**How to apply**: a new web-platform feature in code the TV loads is checked
against Chromium 85 first; fill it in `js/compat.js`, gate it with
`@supports`, or don't use it. Never raise `required_version` to dodge a fix:
that drops a model year from the store silently. Re-render the TV layer in the
Chromium 85 snapshot after a CSS change (recipe: docs/tizen-submission.md
§2b), with a fresh profile every run.

## 163 — archive.org's own trailer collection outweighs the silent-era guard
*Date: 2026-10-08*

An item in archive.org's `movie_trailers` collection that runs five minutes or
less, is dated 1905 or later, is not a commercial and does not say "trailer",
"preview" or "teaser" in its title is a trailer posing as its feature, whatever
its era: `remediate_catalog._archive_trailer` hides it as `excludedReason:
trailer` and records `trailerEvidence`. Decision 052's other tests are unchanged.

**Why**: the first iPhone Duo screenshots ranked films by votes, and the
catalog's only "The Kid" was `turner_video_9` — a 119-second Turner Classic
Movies promo carrying the film's identity and 144k votes; three copies of The
Gold Rush were the same. Decision 052 spares short silents because a four-minute
silent is usually a surviving fragment, and that guard is right in general —
but here the archive's own collection says what the file is. Measured: 64 visible
items in the collection; 50 hide (The Kid, The Gold Rush, Nosferatu, Caligari,
The General, Wings...), 14 stay (Abraham Lincoln and Know Your Enemy: Japan run
feature length, The Great Train Robbery 12 minutes, Sherlock Holmes Baffled is a
1900 film that is a minute long, and the vintage trailers titled as trailers).

**How to apply**: an honestly labeled vintage trailer is an archival object and
stays; only one wearing a film's identity leaves. A real film wrongly filed in
the collection comes back by evidence (a runtime over five minutes, a year
before 1905), never by dropping the collection test. `tools/test_trailer_collection.py`
holds the case and five controls.

## 164 — Roblox is shelved: the films are what it cannot carry well
*Date: 2026-10-15*

Archive Watch does not build for Roblox. The research stays in
`docs/research/ROBLOX.md` and `docs/research/roblox/01-09`, with the pathway
and the conditions for reopening in ROBLOX.md §8. Nothing was built, no
account was created and no Robux were spent.

**Why**: the owner, after the research: *"I don't think we should pursue the
roblox platform for the time being. Make sure that we have fully documented the
pathway, but I don't think that it is worth the time and effort for such a
compromised experience."* Roblox plays only video it hosts: 5-minute assets at
2,000 Robux each (~$400 a feature, ~$7M for the catalog). The free route that
stays inside its rules, films as moderated image flipbooks, plays at 256x192
and 12 fps and suits only a curated silent program. Streaming from off-platform,
as "YouTube in Roblox" projects do, is what Roblox staff told creators not to
do. The theaters, rooms, interface and tooling all fit; the films do not.

**How to apply**: do not start Roblox work on a new idea for playback alone;
reopen only on a trigger in ROBLOX.md §8.1 (video terms, URL playback, the
VideoPlayer API, a real image quota, or the owner choosing a silent
cinematheque), and then follow §8.2's order: free measurements before any
spend or build. Whatever changes, never stream frames from off-platform or hide
video inside images.

## 165 — The Play build's floor is Android 7, because Play's automatic protection requires it; Fire TV keeps Android 6
*Date: 2026-10-15*

The `google` flavor declares `minSdk = 24` (Android 7.0); the `amazon` flavor
keeps `minSdk = 23` (Android 6.0), so Decision 141's floor now holds for Fire
TV only.

**Why**: the crash-fix release (versionCode 67) was refused at upload — *"Play
automatic protection requires a minimum SDK version of 24 or higher. The
uploaded App Bundle has a minimum SDK version of 23."* versionCode 66 had
uploaded at 23 on 2026-09-30, so the requirement arrived on Play's side in
between. Asked to choose between switching automatic protection off, raising
the Play floor, or holding the release, the owner chose to raise the Play
floor. Play withholds per-API user counts below its minimum audience, so how
many Android 6 viewers this drops could not be measured; they keep the version
they have and stop receiving Play updates.

**How to apply**: do not lower the google flavor below 24 while automatic
protection is on. Fire TV is the Android 6 build now: lint NewApi and
`canHostShow` still have to hold at 23 there, and the ISRG roots in
network_security_config.xml are still what let it download the catalog.

## 166 — A series held in one archive.org item is a series: its files become episodes, `<item>@<token>`, on evidence the item itself gives
*Date: 2026-10-18*

An archive.org item whose files are a whole show or serial — `UFO.complete`
(26 files), Leave It to Beaver's six seasons in one item, Spy Smasher's 12
chapters — becomes a spine of its own (`tools/build_bundle_series.py`, in
tv-canonical before the reconcile that makes its card). Each file is an
episode with the id `<item>@<token>`: `e01` (no season), `s2e05`, or
`x-<slug>` for an unnumbered extra, and the token is the file's own number,
never its position. The spine and every episode carry `sourceID`; the item's
own card is not published and its id forwards to `series:<slug>`; its TV
shelves pass to the series card (never its film shelves: Decision 036).
Every client splits an id at the first `@` to reach archive.org, and lists
only the episode's own file and its derivatives as copies.

**Why**: the owner, 2026-10-18 — *"We have many serialized tv shows in the
database. These should function in the same way, especially if we have the
data/metadata to support it."* They were film cards that played one file of
dozens, with no episodes, progress or next. Measured over the catalog: 8,421
items fetched (an item ≥3x its default file and ≥45 files), 241 parse as
numbered works, **141 shows and 3,589 episodes** pass the rules below, every
sampled file and still answers 200. `@` because archive.org ids never contain
it, the Worker's id regexes accept it, and it is safe in a URL path and the
Roku registry; `/` broke deep links and the 404 router, `~` the Worker.

**What is NOT a series**, each measured against a real false positive: a
film in pieces (`nosferatu-1of5`, a DVD's `VTS_01_3`, any `reel1`; "Part 3"
only when the item is typed television — Insurrection, 1966, is an eight-part
drama), numbered works with no MP4 (Apple's player opens no Ogg or Matroska,
and no visible film card carries one), commercial breaks, home movies, audio
items, anything `noRecommend` or in archive.org's own `deemphasize`
collection (a numbered "Protocols of the Elders of Zion" audiobook passed
every file rule). Numbered files alone are lectures, launch coverage and
audiobooks as often as shows, so a series needs evidence of its own: episode
words in its file names (episode/ep/chapter/E01/S01E01), a television
typing, a title per episode, a run of ten or more, or its own metadata saying
serial/series/episodes. Two uploads of one show: the fuller is the spine; a
serial in halves with no number in common is merged (`sourceIDs`).

**How to apply**: never key an episode by its position or its file name —
a token that moved would lose every viewer's progress. A new client that
builds an archive.org URL from an id splits at the first `@`. Tune a false
positive by a rule with a control in `tools/test_bundle_series.py`, never by
a list of ids. The scan caches each item's verdict and the files a spine
needs (`shared/editorial/bundle_scan.json`, re-checked after 60 days or when
the item's size changes), so the build itself needs no network.

**Consequences**: serials typed as films (Spy Smasher, Flash Gordon, Radar
Men from the Moon) leave Movies for TV. A source item keeps its film card
until its `series:<slug>` card is in the catalog (`bundle_sources(cards)`),
because the card is made by tv-canonical's reconcile and the DB can be built
between the two. App builds made before this change show the series and play
its episodes, but split no ids, so archive.org details and copies for an `@`
episode fail until the next store builds. The bundled seed DB (first launch
only) still shows the source items as film cards until the downloaded catalog
replaces it.

## 167 — A whole series filed in one item and matched onto a TVmaze show becomes that show's episodes, placed by title
*Date: 2026-10-20*

When an item whose files are a whole show (Decision 166's rules) has been
matched onto a TVmaze spine, `build_canonical_tv.expand_bundles` replaces it
with one row per file, `<item>@<token>` with an episode-level `sourceID`, read
from `bundle_scan.json` (which now scans the items TVmaze spines serve, not only
catalog cards). Each file is placed on a canonical episode by its OWN TITLE
first, and by its number (and the season its item names: "Room-222-Season-2")
only when it states no title. A file whose episode is already played by another
copy is dropped; a file under four minutes, or under 40% of its episode's
running time, is not that episode. Items that are one episode each place first,
then the fullest upload, and a colorized upload last (Decision 158). The
re-pick is skipped for these files: by item id it would swap in the item's
largest file, another episode.

**Why**: a viewer, 2026-10-20, asking for Fireball XL5's 39 episodes and noting
the last entry under More episodes ended in a period. That entry was
`FireballXL5.complete`, 39 files, served as ONE episode titled "Fireball XL5."
and playing episode 25; the show page listed 5 of 39. Decision 166 never saw it
because its scan read catalog cards, and an item on a TVmaze spine is not one.
Measured over every TVmaze spine: 150 such items on 85 shows, ~4,800 files (The
Prisoner, Space: 1999, Supercar, The Dick Van Dyke Show, The Addams Family's five
uploads, Ozzie and Harriet's 436). Numbers alone mislead: the uploader numbered
by production, so "08. Space Immigrants" is TVmaze's 1x03.

**How to apply**: every tool that reads spine episodes must take the item from
`sourceID` (or `item_of`), never from the `@` id: the rights audit asks
archive.org about the item and removes all its files with it; the series audit,
the derivative repair and the re-pick leave these files alone; reconcile,
backfill and discovery count the item as served; `build_sqlite.bundle_sources`
forwards the item's id to the series. A bundle SPINE's source keeps its catalog
card (166); an item expanded into a TVmaze spine loses it. The colorized request
that raised this could not be met: archive.org holds 3 colorized Fireball XL5
episodes, not 39, and `FireballXL5.complete` is black and white (mean saturation
1.7 against 6.4 for the colorized upload). `tools/test_bundle_in_tvmaze.py`
holds the cases with a single-item, promo and fragment control, and gates the
tv-canonical build.

## 168 — Correction to 167: each file of a whole-series item is judged by its own year; its item answers only for the licence
*Date: 2026-10-20*

`audit_tv_rights` judges every episode of a TVmaze spine by the episode's OWN
year, and a file of a whole-series item (`X@s3e01`) asks archive.org about its
item `X` (`item_of`) for the licence and collections. It does not judge the
item as a whole, and it does not remove an item's other files when one is
removed. Decision 167's "removes all its files with it" was the defect, not the
rule.

**Why**: the first tv-canonical run with 167 keyed the year by item, so the first
1978 file of `George_and_Mildred` set the year for all 39, and every file was
removed, the 1976 and 1977 episodes with them; Logan's Run and The Tony Randall
Show lost their spines entirely (111 files in all). Judged per file: 47 files,
every one aired 1978 or later, and every show stays.

**How to apply**: never key the audit's `need` by item; fetch and cache by item,
judge by file. The 111 manifest rows were removed and the five spines restored
and rebuilt, since `tv_rights_removed.csv` re-removes by id on every run.
`test_tv_rights_items.py` holds a 1976 and a 1978 file of one upload.

## 169 — A single-episode upload is placed by its own file name and id, and a person's "never serve this" binds every series
*Date: 2026-10-27*

`build_canonical_tv.map_items_to_canonical` places an upload that is one
episode by its OWN words, its file name and archive.org id, never by the
`title` it carries: a title it states that names a TVmaze episode places it
there (exact, leading articles ignored, then fuzzy unless the candidates differ
only by a part number or the years disagree); a number it states ("S04E03",
"4x03", "Season 4, Episode 3") places it only when its title shares a word with
that slot or states none; a promo, trailer or "next week" reel is never placed
and is listed as "Promo: <episode>". Colorized singles place last (Decision
158), "colorized" is dropped from a show name before TVmaze is asked, and an
unplaced title loses the show's name in front. `not_films.json` and the new
`shared/editorial/episode_rejects.json` ({archiveID: {notIn: slug|"*", why}})
are dropped from every rebuilt spine.

**Why**: the owner, 2026-10-27: *"There is no reason to leave bad data rather
than investigating and fixing it."* 109 editorial ids warned "not in the
catalog" every build; they were series episodes, and reading their spines
found three defects. An episode is re-pooled carrying the canonical title of
the slot it holds, so a misplacement confirmed itself every build:
"s01e01.The.Speckled.Band" was Sherlock Holmes' "Cunningham Heritage", a 1953
Humphrey Bogart Jack Benny was 1951's 1x03, Twilight Zone promo reels were
"The Silence" and "The Parallel", Victory at Sea's "09_Sea_And_Sand" was 1x02.
Measured against TVmaze for all 236 spines: 306 placements change, about 230
of them files that now find their episode (Four Star Playhouse, William Tell,
The Buccaneers, Loretta Young), each reviewed against its file name. Second,
`not_films` bound only the catalog, so LTT101, a Looney Tunes rip from Tubi, was
some 260 episodes of the Looney Tunes spine through Decision 167. Third, other
programs sat inside shows with their years clamped to the show's run, where
the TV rights audit keeps an undated episode on the show's year: the 2002
Twilight Zone and 1995 Outer Limits revivals, 2020-21 Family Feud in The Smith
Family, 1999 Emmerdale, a Marvel cartoon clip in The Avengers (1961).

**How to apply**: never place a single upload by `title`; read `_own_texts`. A
wrong placement is fixed by a rule with a control in
`tools/test_tv_episode_placement.py` (gated in tv-canonical), never a list of
ids; an upload that is another program goes in `episode_rejects.json` with what
its own file or record says it is. A stated year was measured as a general
rule and refused: Space: 1999, Studio One's "1984" and a KNTV accession number
read as modern years. Editorial ids that are series episodes are reported as
such, and a `not_films` id a spine still serves is a warning.

## 170 — A sort is remembered per kind of grid and television starts A–Z; a playlist's place among playlists is synced, and every sync writer carries it
*Date: 2026-10-27*

Every Browse grid keeps the viewer's sort per KIND of grid — `browseSort.tv`,
`.browse`, `.category`, `.collection`, the same key names on every platform —
and television grids start on A–Z (the rest on Popular). Sort gains Z–A
everywhere. Top Rated orders a series by its TVmaze rating (`tvmazeRating`: a
spine field, a series-card field, the last `items` column, the index's rating
column for tv-series rows) and breaks every tie, ending in title. Playlists
gain "My Order": `Playlist.sortIndex`, synced with the list, a list with none
first; a playlist's films are arranged by the order of `archiveIDs`. Remove,
Rename and a confirmed Delete sit where the list is seen (iOS-DESIGN §4.2c,
§4.3a).

**Why**: a viewer, John Howard, over five emails (docs/USER-FEEDBACK-2026-10.md):
the sort reset on every visit, Top Rated looked like A–Z, and he could neither
remove a film from a list nor arrange one. The owner, 2026-10-27: *"A-Z sorting
by default makes sense with the ability to change and have it remember. Yes to
ratings on TV series (TV maze is great) and then please implement full manual
ordering for playlists, as it is a reasonable request."* Top Rated "looked like
A–Z" because no series card had any rating, every row tied, and SQLite returned
insertion order, which is slug order. Memory per kind rather than per grid: a
choice made in one genre is expected in the next.

**How to apply**: a new grid takes its sort from `SortMemory` (Apple),
`BrowseSort.remembered` (tvOS) or its platform's equivalent, never a bare
`@State`/`remember` default; Random/Shuffle is never remembered. The TVmaze
number is never displayed or written as IMDb's — it is its own column, guarded
by `columnExists` because older DBs lack it. Any code that writes playlists to
a sync store (CloudKit on Apple and web, Drive on Android and web) must read and
write `sortIndex`: a writer that rebuilds an entry from the fields it knows
erases the viewer's arrangement on every other device, and the web did exactly
that for unknown fields before this change. `Playlist.arrange` stamps only
lists whose place changed, so a move syncs as a move. A synced playlist keeps
its own `createdAt` (it used to take the pull time).

## 171 — Top Rated ranks each title by the largest crowd that rated it, against that crowd's own average; every rating names its crowd
*Date: 2026-10-27*

Every title's rating comes from the largest crowd that rated it: IMDb's users
(films, and now the series TVmaze or `build_episode_wants` can name on IMDb),
archive.org's own reviewers (avgRating/numReviews), or, for a series nothing
counted rates, TVmaze, which publishes no vote count. Top Rated sorts on
`ratingRank` (`tools/best_rating.py`): that rating's distance above its own
crowd's average for the same kind of title, in standard deviations, times
v / (v + prior) (IMDb 100 votes, archive.org 5 reviews, TVmaze one half). It
is an `items` column, rides in each title's JSON blob, and is index column 19
(`ratingRank100`, schema 16); the index's `rating10` is IMDb's alone again.
`tools/enrich_tv_ratings.py` (tv-canonical, before reconcile) writes
`seriesImdbID`, `imdbRating` and `imdbVotes` onto each spine from TVmaze's
`externals.imdb` and OMDb, accepting only an id OMDb calls a series; a one-item
series card takes its upload's reviewers. A rating names its crowd wherever it
is shown: IMDb's keeps the platform's star (the word "IMDb" where the line is
text), TVmaze's says "TVmaze", archive.org's stays in the community row.

**Why**: the owner, 2026-10-27, told that TVmaze rates 48 of the 236 TVmaze
shows: *"Please make use of the best ratings available per content."* TVmaze
names the IMDb id of 200 of them; the first run rated 170 series from IMDb
(Fawlty Towers 8.8 from 112,538 votes) before OMDb's daily quota stopped it.
Measured on the catalog, the old Top Rated led feature films with *Der Vierte
kommt nicht* (9.2 from 13 votes); 1,036 of 7,655 rated features had fewer than
50 votes. Ephemeral films had 713 IMDb ratings among 9,132; archive.org's
reviewers rate 5,971. archive.org's reviewers average 3.7 stars (7.4 of 10)
where IMDb's average our films 6.0, so a raw comparison would put every
reviewed short above every IMDb-rated one; each crowd is measured against
itself. TMDb was measured and left out: of 57 sampled films with a TMDb id and
no IMDb rating, 31 had no TMDb votes and none had 20. The IMDb rating sits on
the series CARD as `imdbRating`/`imdbVotes`, because every rights rule that
reads votes is gated to film types (all 457 series cards bucket the same with
150,000 votes added).

**How to apply**: a new sort or shelf that means "best rated" orders by
`ratingRank` and never by a raw rating. A new rating source joins
`best_rating.candidates` with a prior and a test case in
`tools/test_best_rating.py`; it is never mixed in a client. Never show a rating
without its crowd unless it is IMDb's. A series' TVmaze number stays on its
spine and card, never in `rating10`.

**Consequences**: a series' IMDb votes now reach `_pop_score`, so television's
Popular order follows IMDb's audience too. Series ratings refresh every 30 days
from `shared/editorial/omdb_series_cache.json`, apart from the films' OMDb
cache so the weekly TV build and the daily film backfill never commit one file.

## 172 — An identity must fit the file it is on, a fragment is never recommended, and a copyright claim belongs to the film, not the copy
*Date: 2026-10-28*

A title search with no year adopts a film only on an exact title whose TMDb
runtime is within 25% of the file (`tmdb_lib.search_movie`,
`omdb_lib.plausible_identity`); a dated search never takes a film released
more than two years away. What a yearless search already took is cleared
(`remediate_catalog.clear_yearless_match`, verdict `cleared_yearless_runtime`,
the Decision 150 scrub) when the matched film's runtime contradicts the file
(under half or over twice, at least 10 minutes apart). A card that plays a
fragment of the film it names (`fragment_of`: under 60% of the film, or a
part-named file under a whole-film title) keeps its identity and is
`noRecommend` with the reason "fragment — 20 of 94 min". A copy sharing an
imdbID with a copy hidden for a copyright claim is hidden under that copy's
own bucket (`copyrightClaimFrom`), unless it is overridden, government, freely
licensed on evidence, or the film is on the public-domain-by-defect list.
Clusters of copies that disagree on an id are settled by evidence already in
the build, and only when another member offers a positive alternative.

**Why**: the owner, 2026-10-27, *"There is no reason to leave bad data rather
than investigating and fixing it,"* and the audit of 2026-10-28, which
measured on the live catalog: a 19-second `silence` wearing Scorsese's 2016
film, a 14-minute reel as *Evolution* (2001), `74Help` as *Help!* (1965) on
the New Arrivals shelf — 116 visible yearless matches cleared; ~1,107 visible
cards headlining on the whole film's votes while playing 20 of 94 minutes
(Nosferatu, Caligari); and Sunset Boulevard hidden in four English copies and
served as its Mexican release *El ocaso de una vida* on three Home shelves,
with Gilda and The Hidden Fortress the same — 40 visible copies hide.

**How to apply**: never let a title search fill identity without a check the
file can answer (runtime, year). A fragment comes back to recommendations by
evidence (`runtime_match_keep.json`), never by loosening the ratio. A wrong
copyright propagation is cleared in `copyright_evidence_overrides.json`.
Tests: `test_yearless_match_identity.py`, `test_copyright_sibling.py`,
`test_title_identity_evidence.py`, `test_merge_split_anchor.py`, each seen
failing under a deliberate break.

## 173 — The pipeline fails loudly: pipefail everywhere, nothing publishes from a cancelled or failed build, and a publish carries its deletions
*Date: 2026-10-28*

Every workflow sets `defaults: run: shell: bash` (pipefail), held by
`tools/check_workflow_gates.py`; a step that tolerates a failure says so with
`::warning::`. publish-db uploads only when not cancelled and the build
succeeded, after checking the manifest's byte counts and the inflated `.zz`'s
hash against `catalog.sqlite`; `build_sqlite` writes to `.tmp` and renames into
place. tv-canonical drops `tv_rights_removed.csv` ids when it writes spines
and commits only after the TV rights step succeeds. `catalog_release.publish`
re-reads the release stamp just before upload, gzips the bytes it parsed,
carries this run's deletions onto a newer catalog, refuses a run that removes
more than 15%, and skips an unchanged upload.

**Why**: no workflow had pipefail, so 38+ `python … | tee` steps were green
when their script crashed; a cancelled publish-db's `always()` upload raced a
`build_sqlite` still writing (run 40399715287), saved only by the manifest
being written last; and the weekly TV rebuild re-added ~600 rights-removed
episodes that only a later step removed, a step the designed build timeout
could skip while the commit still pushed (ENGINEERING-PROCESS §2).

**How to apply**: a new workflow inherits the bash default; a new publish step
uses `!cancelled()` and an explicit success condition, never `always()`.

