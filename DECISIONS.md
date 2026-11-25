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
- 161–170 → `docs/decisions/DECISIONS-161-170.md`
- 171–178 → `docs/decisions/DECISIONS-171-178.md`
- 179+ → below, in full

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

### 161–170 — `docs/decisions/DECISIONS-161-170.md`

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

### 171–178 — `docs/decisions/DECISIONS-171-178.md`

- 171 — Top Rated ranks each title by the largest crowd that rated it, against that crowd's own average; every rating names its crowd
- 172 — An identity must fit the file it is on, a fragment is never recommended, and a copyright claim belongs to the film, not the copy
- 173 — The pipeline fails loudly: pipefail everywhere, nothing publishes from a cancelled or failed build, and a publish carries its deletions
- 174 — A cartoon of racist caricature is never recommended and always findable, on a record a reader can open or the title's own tags
- 175 — A complete notice removes a title unless the file contradicts it; the file is read automatically, and a requester's name never reaches the repository
- 176 — The catalog is swapped into place under another name; the release is never without it, and a missing asset is never a first run
- 177 — A checker that can no longer find a known claim refuses to clear anyone, and a hidden series takes its episodes and its uploads with it
- 178 — A series' year comes from evidence about the series, is searched for continually, and is never borrowed from a same-named film

### 179+ — in full below

- 179 — A printed renewal is read to its chapter and its damaged date, a compilation is judged file by file, and a stored year yields to a later date of the item's own
- 180 — On a TV box the catalog refresh waits, runs at background priority, and is applied off screen
- 181 — A film page carries archive.org's own words about the item from a file the viewer never loads, and its lastmod is the day it changed
- 182 — On the iPhone Duo a push lands in the stack on screen, and sidebar places exist only while there is a sidebar
- 183 — A layout that changes with width keeps its controls: one AnyLayout, never ViewThatFits around a menu
- 184 — Every renewal the law allows is read: a 1964-77 work's renewal counts whenever it was registered
- 185 — The viewer arranges channels and makes one from a playlist; every sync writer carries both, and an audio nudge never moves the player's clock
- 186 — No stored key for the owner's routes, and no secret in cleartext on disk
- 187 — A catalog writer waits in line, and a scheduled Mac job runs on Intel

---

## 179 — A printed renewal is read to its chapter and its damaged date, a compilation is judged file by file, and a stored year yields to a later date of the item's own
*Date: 2026-11-04*

`fetch_cce_renewals` treats the text between two renewal numbers as one entry and
reads "a series of photoplays" and its chapters (`s`, `ch`, `sr` for a serial), the
1974-77 "(Cody of the pony express, episode no. 5)" form, chapters a cross-reference
names, and a year OCR ruined, from the renewal date. `corroborate_copyright` matches a
serial by its series, a chapter's name never as a film, and refuses a row whose printed
reels contradict the file. `compilation_claims` asks each file of a whole-series item by
its own title; `audit_tv_rights` writes `<item>@<token>` lines to `takedowns.json` with
`until`, the year the work leaves copyright, and `"rule": "file"`. `build_bundle_series`
gives a file the date its own title prints, else its film record's release.
`remediate_catalog.own_later_year` moves a pre-age-line year when the item's id, a
decade opening its title, or the uploader's account of the making names a later one;
`audio_track` hides an audio upload wearing a film's identity.

**Why**: the owner, 2026-11-04: *"The goal is the best possible data and the best
possible database,"* and *"everything that can be displayed is displayed."* The reader
needed an entry whole in one paragraph with a clean date: 123 serial headers in print,
2 in the table, every October lost to "0ct". It had read 11,910 of about 21,000 renewals,
so Laura, The Killers, Notorious and Scarface passed as presumed public domain. A renewal
falls in a work's 28th year, so its date fixes the original's: 8,109 of 8,319 clean
entries agree, and the rest are OCR'd years ("31Mar59" for 39). Flip the Frog had to come
down whole because a bundle stamps one year on every file. The rights audit trusted a
bare date, and a stock-footage house types the subject's: Yesterday's Newsreel, a 1950s
TV show, read 1915.

**How to apply**: a title alone is not a claim in a compilation: the bare match took The
Mechanical Cow (Oswald 1927) for a CBS cartoon of 1937. A row counts for a claimant who
renewed three titles of that compilation, or in the same filing batch, and a release
before the age line is free whatever year its registration carries. A year in an id must
be date-shaped; read as any number, it took Space: 1999, Studio One's "1984" and KNTV's
accession numbers (Decision 169). A person's lines in `takedowns.json` and an
`agent-reviewed` year are never touched by a rule. `CCE_RULE` re-asks every pre-1950
title when the table changes. Tests: `test_cce_renewals`, `test_compilation_claims`,
`test_date_plausibility`.

**Consequences**: the first rights-audit after this lands hides 830 or so visible items
on printed renewals. Flip the Frog's renewed files return from 2027 to 2029 by `until`
and the next rebuild. A compilation's file with no film record and no printed date keeps
the item's year and is judged by its renewal's date. Sermons in folksoundomy (no sermon
collection, feature length) wear film identities still; the rule leaves them.

## 180 — On a TV box the catalog refresh waits, runs at background priority, and is applied off screen
*Date: 2026-11-05*

A television re-checks the catalog every 24 hours, not 6. With a downloaded catalog in
place a refresh waits 45 seconds after launch, runs at `THREAD_PRIORITY_BACKGROUND`, and
parks its result as `catalog.sqlite.next`; it swaps in when the app leaves the screen or
at the next launch. Only the seed is replaced at once. Coil decodes two images at a time,
television posters do not crossfade, and `baseline-prof.txt` compiles the app's screens
ahead of time. Catalog-fed lazy lists pass through `uniqueBy` (`test_android_list_keys.py`).

**Why**: the owner, 2026-11-05: Play's user-perceived crash and ANR rates are too high.
Measured over 28 days: ANR 1.5% (limit 0.47%), crash 0.69% (limit 1.09%). 21 of 22 ANRs
were on Android 14 TV boxes, and their other threads were downloading, inflating 246 MB,
querying and decoding at once; stacks with an idle main thread were the CPU taken from
it. Reproduced on the Google TV: 353 frames skipped in a row (5.9 s, over the 5 s limit)
during a refresh, 166 (2.8 s) after, one debug run each. The Cast crashes were already
fixed in versionCode 70.

**How to apply**: never swap the catalog under a viewer once one is working. A new heavy
background job runs at background priority and waits out launch. To measure, delete
`catalog.lastcheck` with a real `run-as rm`: an `sh -c` through adb silently did nothing
and produced a false improvement. The price is a catalog up to a day old on a TV, plus
the session it is staged in, so a takedown can take that long to reach one.

## 181 — A film page carries archive.org's own words about the item from a file the viewer never loads, and its lastmod is the day it changed
*Date: 2026-11-09*

`build_web_details.py` writes `page-extras/{shard}.json` beside `details/`: the
uploader's full description (to 1,500 characters), archive.org subjects with
search keywords removed (`page_subjects`), named collections and language.
Only `build_share_pages.py` reads it; deploy-pages leaves it out of the site.
Each deploy publishes `page-state.json` (hash and date per sitemap URL) and the
next reads it from the live site, so `<lastmod>` is the day a page's bytes last
changed. A 404 seeds every page with today; an unparseable file starts over; a
site that cannot be reached fails the deploy.

**Why**: the owner, 2026-11-09, on Search Console: *"fix the site map and
database to the extent that we can without making it worse for our users."*
22,493 pages sat "Discovered, currently not indexed" and 454 "Crawled", and
13,116 of 40,601 film pages had no synopsis over 200 characters, no cast and no
reviews, while 33,667 items carry archive.org subjects no page showed. The
sitemap had no dates at all. Putting the fields in `details/` would have added
about 15 MB across shards the viewer fetches on every Detail. The subjects
include uploaders' keyword lists (2,384 "stock footage" is real; 416 "silent
film streaming" is not), which on a page read as keyword stuffing.

**How to apply**: a field only the film pages need goes in `page-extras/`,
never `details/`. A new subject filter rule gets a case in
`test_share_pages.py`. Never date the sitemap from the deploy or catalog
time. Search Console's 404 and redirect rows are hidden titles and merged ids
by design (WEB-DESIGN §3.2a); start a validation only on a row a change fixed.

## 182 — On the iPhone Duo a push lands in the stack on screen, and sidebar places exist only while there is a sidebar
*Date: 2026-11-10*

`Router.push` appends to `Router.stackTab`, the newest `NavigationStack` that
reported itself on screen (`tracksStack`), and only falls back to the selected
tab. `RootView` adds the sidebar places only when the width is regular AND
iOS 27's `isTabViewSidebarAvailable` is true; when the places go away, a selected
place hands its stack to the tab that holds it. Detail's hero takes at most 55%
of the measured height, and Clip Studio's timeline keeps its span and moment
when its width changes. Rules: iOS-DESIGN §2.8.

**Why**: the owner, 2026-11-10: *"I saw that the collections do not open
correctly."* On the open Duo in landscape the tabs move into a vertical strip
that shows every tab regardless of `defaultVisibility`, so Collections sat in
the "…" overflow. The overflow shows a tab without selecting it, so a tapped
collection was pushed onto Home's hidden stack. Found by tapping it on the
device (`DuoAuditUITests`), after a launch door had opened the same collection
fine: a door selects the tab, and a person does not. The same strip put Films
and TV beside Browse, and Surprise vanished because Home hid it on "regular
width" rather than on "there is a sidebar". Bsky Dreams' Duo work supplied the
other rules: measure the container, keep a person's place across the fold,
capture the display that is on.

**How to apply**: a new tab or place carries `tracksStack`. UI that is hidden
"because the sidebar has it" keys on `router.showsSidebarPlaces`. A size class
is not a height: anything sized for an iPad's height reads the measured height.
Test the Duo by tapping, not only by doors; a door can reach a state a person
cannot, and miss one a person can.

## 183 — A layout that changes with width keeps its controls: one AnyLayout, never ViewThatFits around a menu
*Date: 2026-11-12*

Detail's regular-width header (`DetailView_iOS.regularHeader`) is one
`AnyLayout` that switches between an `HStackLayout` and a `VStackLayout` over
the same hero and text column, chosen from the ScrollView's measured width:
two columns when the hero plus a 360pt text column fit. It replaced a
`ViewThatFits` whose two alternatives each built their own action buttons.

**Why**: the owner, 2026-11-11: *"very often when I press the more button
within the individual item detail page, the interface element closes before I
can select anything."* On the open Duo the vertical strip collapses and expands
as the page scrolls, so the content width moves between 867 and 951pt. Since
1.47.40 capped the hero at 55% of the height, two columns needed 948pt, right
between the two, and the header flipped as the strip moved. `ViewThatFits`'s
alternatives are separate views, so each flip destroyed the More button and
SwiftUI dismissed the menu it anchored. It could not reproduce on the iPhone 12
(compact width takes the other branch), and it did not exist before 1.47.40
(the fixed 460pt hero never fit two columns on the Duo).

**How to apply**: never put a `Menu`, `Picker`, text field or anything with
open state inside `ViewThatFits`; a width-dependent arrangement is one
`AnyLayout` over shared children. A threshold that sits between two widths a
screen really moves through is a defect: pick it so the common widths land
firmly on one side. `DuoAuditUITests.test_07`/`test_09` hold the menu open for
4 seconds at several moments after Detail appears.

## 184 — Every renewal the law allows is read: a 1964-77 work's renewal counts whenever it was registered
*Date: 2026-11-13*

`corroborate_copyright.renewal_in` accepts a Copyright Office renewal of a work
from 1964 to 1977 registered at any time from its 27th year on
(`renewal_fits`); a work from before 1964 keeps the 27-to-29-year window. A
record titled for a season or volume ("Monty Python's flying circus.  Ser. 1,
ep. 1-13") is matched as its series (`_SEASON_TAIL`, after punctuation only).
`RULE` is 3, so every title checked under the old rule is asked again.

**Why**: the owner, 2026-11-13: *"You should look at more recent renewals. I
can't think of a reason for not looking at all of the renewals."* A viewer had
found Monty Python's Flying Circus (1969) on screen; Python (Monty) Pictures
registered its four renewals in 2006, 37 years on, and Decision 177's window
threw them away. From 1964 renewal is automatic (the Copyright Renewal Act of
1992) and registering it is optional at any point in the second term, so a
late record is the work's own. Before 1964 the renewal had to be filed in the
28th year: a later record under that title can only be another work, so that
window stays. Every renewal is of a pre-1978 work (later works have no renewal
term), which is what keeps an open window from catching a remake. Measured
before shipping: 0 of 10 public-domain canon titles matched (Night of the
Living Dead, The Last Man on Earth, Manos, Spider Baby...).

**How to apply**: never narrow a renewal window to what is common; bound it by
what the law makes possible. A wrong late match goes in
`copyright_evidence_overrides.json`. Test: `test_copyright_evidence.py`, seen
failing on the old rule.

## 185 — The viewer arranges channels and makes one from a playlist; every sync writer carries both, and an audio nudge never moves the player's clock
*Date: 2026-11-21*

A viewer's channel order is one synced record of guide ids (`drama`,
`user-<id>`): `ChannelArrangement` on Apple and its own CloudKit record
`channelOrder` (`[{ids, at}]`, seconds), `channelOrder {ids, at}` (ms) at the
top of the Drive blob, newest `at` wins. Channels it names come first in its
order; the rest follow where they stood; numbers stay with their channels. A
user channel may carry `playlistID`: it plays that playlist's first 300 stored
titles, minus series cards and titles with no file, IN ORDER, on
`ChannelScheduler.loop`, one clock from 2026-01-01 UTC. Audio Sync (±2 s, 0.1 s
steps, this title only) shifts only what is drawn or heard, never the player's
position: on tvOS the sound track's `tfdt` in the on-device remux, on Android a
`ForwardingRenderer` that hands the video renderer position + offset.

**Why**: a viewer, John Howard, 2026-11-17: *"People will want their favorite
channels grouped nearby"*, his own playlists *"as series programs for my custom
channels"*, and a 1971 Hee Haw tape whose sound drifts from the picture. The
owner, 2026-11-21, approved all three, the last *"with native tools ... a power
user feature"*. No player here has an audio-offset API. Offsetting Media3's
audio-sink clock (the obvious route) would have moved the scrubber, saved
progress and the Watch Together room clock and frozen on every step back;
shifting tvOS's video `tfdt` instead would have moved the scrubber and
captions. The playlist rule had three versions (Apple uncapped with series
cards, Android uncapped, the web with series cards), and any difference puts
one platform's clock off the others'.

**How to apply**: any code that writes channels or the order to a sync store
carries `playlistID` and `channelOrder` (Decision 170's lesson: a writer that
rebuilds an entry from the fields it knows erases the rest on every other
device). A change to which titles a playlist channel plays is made on every
platform at once. An audio offset never touches the position the player
reports. iOS and macOS have no Audio Sync: they play through the paced proxy
to keep the system's generated captions (Decision 147), and the remux would
lose them; that trade is the owner's. Roku has no user channels and no audio
delay. Tests: `test_web_channel_order.mjs`, `ChannelArrangementTest`,
`PlaylistChannelLoopTest`, `AudioSyncTest`, `test_fragmenter_audio_offset.swift`,
`test_audio_sync_offset.swift`; iPhone `AuditUITests.test_40`/`test_41`.

## 186 — No stored key for the owner's routes, and no secret in cleartext on disk (owner 2026-11-22)

**Rule**: the take-down Worker routes accept only a GitHub Actions OIDC token for `takedown-check.yml` on `main`
(`worker/src/github-oidc.js`), so `TAKEDOWN_TOKEN` is gone from GitHub, the Worker and the owner's disk. A secret
that has to exist lives in exactly one of two places: a GitHub Actions secret (CI), or the login Keychain as
`archivewatch:NAME` (a person's Mac, read at use time by `tools/keychain.py` and `tools/with_asc.sh`). The only
tool that moves a value is `tools/secrets.sh`, with fixed recipes and names. Nothing tracked may look like a secret
(`tools/test_no_secrets.py`, the `.githooks/pre-commit` hook, `secrets-check.yml`).

**Why**: the owner, 2026-11-22: *"I do not want to set or keep track of keys and passwords for this repo."* and *"You
should do all 4 if possible."* The plaintext copies (`~/.config/archivewatch/*.env`, the Play service account, the
keystores, `tools/asc-credentials.env`) were the ones an agent or a stray backup could read. Ear Drama proved the pattern
first (its Decision 085).

**How to apply**:
- A new owner route names its workflow in `OWNER_WORKFLOWS` and gets a refused-claims control in
  `tools/test_takedown_worker.mjs`; never a new shared token. `INGEST_TOKEN` stays only because Roku's report delivery
  puts it in a URL we do not control.
- A Keychain value goes in through `tools/secrets.sh keychain-import-file NAME FILE`; a tool reads it with
  `tools/keychain.py` and keeps its CI path (an environment variable) first. A `security -i` line holds about 2.6 KB, so
  items are chunked.
- The Play service account is still one file shared with Ear Drama; replacing it with workload identity federation is
  phase 2 and moves both apps together (`docs/SECRETS-PLAN.md`).
- `appstore-build.yml` and `appstore-submit.yml` are untouched on purpose (GitHub has held edits to them); the shell
  scripts they call keep sourcing the runner's own `tools/asc-credentials.env` first.

## 187 — A catalog writer waits in line, and a scheduled Mac job runs on Intel
*Date: 2026-11-25*

Every job in the `catalog-writers` group carries `queue: max`, so GitHub holds up to
100 of them in order instead of keeping one and cancelling the rest
(`check_workflow_gates.py` refuses a writer without it). The scheduled macOS jobs
(Verify playback, Cover generation, Faststart re-verify) run on `macos-15-intel`.
Ubuntu's ffmpeg is installed by `tools/ci_apt.sh`, which retries.

**Why**: the owner, 2026-11-25: *"Why do I still keep getting alerts for failed runs
on GitHub? The verify playback runs sometimes work and sometimes don't."* Ten of 25
Verify playback runs failed on their first attempt and not one ran our code: seven
were Apple-silicon jobs GitHub never placed ("not acquired by Runner of type hosted",
all since 2026-11-02, the same in other projects), three were the publish job
displaced in the queue (Decision 057). `retry_infra_failures.py` healed them, but the
owner is mailed when the first attempt fails. Measured before switching, 217 films on
both chips: 215 identical verdicts, and the two that differed were timeouts against
"all nodes unavailable", a network reading that needs three separate days before it
hides a film. Intel was faster (353 s against 435 s) and started in seconds while the
Apple-silicon job waited five minutes. Cover scores agree within 1 point on 7 of 8.

**How to apply**: `queue` is GitHub's since 2026-05-07 and cannot be combined with
`cancel-in-progress: true`; publish-db keeps that one, because a newer DB build
replaces an older one on purpose. Anything needing the Speech model or the Neural
Engine stays on Apple silicon (`auto-captions`), and so do the store builds. A job
that dispatches itself grows a queue now instead of collapsing into one pending run.
The retry sweeper stays as the backstop.
