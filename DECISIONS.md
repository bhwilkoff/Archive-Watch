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
- 171+ → below, in full

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

### 171+ — in full below

- 171 — Top Rated ranks each title by the largest crowd that rated it, against that crowd's own average; every rating names its crowd
- 172 — An identity must fit the file it is on, a fragment is never recommended, and a copyright claim belongs to the film, not the copy
- 173 — The pipeline fails loudly: pipefail everywhere, nothing publishes from a cancelled or failed build, and a publish carries its deletions
- 174 — A cartoon of racist caricature is never recommended and always findable, on a record a reader can open or the title's own tags
- 175 — A complete notice removes a title unless the file contradicts it; the file is read automatically, and a requester's name never reaches the repository
- 176 — The catalog is swapped into place under another name; the release is never without it, and a missing asset is never a first run
- 177 — A checker that can no longer find a known claim refuses to clear anyone, and a hidden series takes its episodes and its uploads with it
- 178 — A series' year comes from evidence about the series, is searched for continually, and is never borrowed from a same-named film
- 179 — A printed renewal is read to its chapter and its damaged date, a compilation is judged file by file, and a stored year yields to a later date of the item's own

---

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

## 174 — A cartoon of racist caricature is never recommended and always findable, on a record a reader can open or the title's own tags
*Date: 2026-10-28*

`remediate_catalog.racist_caricature` sets `noRecommend` (reason "racist
caricature — …", the Decision 149 mechanism) on a title named by a sourced list
in `shared/editorial/racist_caricature.json` (the Censored Eleven Warner Bros.
withdrew in 1968; Scrub Me Mama with a Boogie Beat, Little Black Sambo, Tokio
Jokio from their own articles; the Bosko and Inki series), or on an ANIMATION
item whose own TMDb keywords or archive.org subjects name racism, racial or
ethnic stereotype, blackface or the Censored Eleven. It leaves Party Play,
Cartoon Mode, Surprise, shelves, channels and More Like This, and stays in
Search, Detail and Browse. 73 visible cards on 2026-10-28.

**Why**: the owner, 2026-10-28: *"make it so that racist cartoons don't
continually show up on the party play and cartoon features of the surprise
surface"* — *"'scrub me mama with a boogie beat' has got to be the most racist
cartoon I've ever seen and it has shown up repeatedly."* That title carried no
tag in the catalog, so no rule over the data could have caught it: the worst
offenders are often the least described. Bare "banned" was measured and left
out: it also tags Betty Boop shorts cut for the Hays Code.

**How to apply**: add a title with a source a reader can open (`add`, a list,
or a `series` pattern), never on a hunch; exempt one in `not` with its reason.
A picker that chooses for the viewer must skip `noRecommend` (the web Party
Play now checks it as well as the pool builder). Uncertain cases left for the
owner: Cannibal Capers, Jungle Drums, Uncle Tom and Little Eva.

## 175 — A complete notice removes a title unless the file contradicts it; the file is read automatically, and a requester's name never reaches the repository
*Date: 2026-11-04*

Removal requests arrive by a form on `takedown.html`, by email to the DMCA agent
(DMCA-1083942, shared with Ear Drama) or from Google, and become cases in a
private D1 table. `takedown-check.yml` reads each file named: a burned-in logo, a
soundtrack on a silent film, and whether the claim names the title or one word
of it. A complete notice removes the title unless that evidence contradicts it;
a contradiction opens an issue the owner answers with `remove` or `keep`.
`takedowns.json` takes an item, one file or a whole series, and holds a date and
a case number only. Runbook: `docs/TAKEDOWNS.md`.

**Why**: the owner, on the first two notices (2026-11-04): *"If it is a copyright
work, we should remove it. We are a public domain streaming app"*, *"any piece of
content that we serve should be able to receive a request"*, *"We need to protect
folks privacy"*, and *"Manual review might be quite difficult."* The notices showed
why the file has to be read. Metadata cleared both. `Madame Dubarry`, a 1919 film,
was an ARTE broadcast with a logo and soundtrack that archive.org's record never
mentions, so the claim may have been sound. `Home Movie: 97390: Unidentified` was
claimed as "UNIDENTIFIED", a word match. The repository and Actions logs are public,
so `takedowns.json` could not keep the `from` field it was built with. Reading frames
for pixels that do not change scored ARTE's translucent logo 0; a gradient that
points the same way in every frame scored it 111, against 0 for ten clean films.

**How to apply**: never ask a requester for more than 17 U.S.C. 512(c)(3) does.
Decision 151's readable evidence is the bar for what WE hide unprompted, not for a
notice. A file that could not be read must not hold a removal back. Nothing a
requester wrote may reach the workflow's log or an issue, including the name of the
work. A new kind of served content needs a key in `takedown_lib.blocked` and a
control in `test_takedowns.py`. The soundtrack test belongs to a request; the owner
declined a catalog-wide scan. Tune the logo threshold against
`takedown_check.LOGO_MIN`'s measurements, never by a list of ids.

## 176 — The catalog is swapped into place under another name; the release is never without it, and a missing asset is never a first run
*Date: 2026-11-04*

`catalog_release.publish` uploads to `catalog.json.gz.next-*`, renames the old asset
aside, renames the new one into place, and only then deletes the old. `fetch` waits
six minutes for an asset that is not listed and then fails; only `--bootstrap`, typed
by a person, seeds a release. A publisher that loses the name re-merges and tries
again (Decision 173's carrying of deletions still applies).

**Why**: `gh release upload --clobber` deletes before it uploads, so for about a
minute of every publish there was no catalog. Three runs fell in that gap in four
days: TMDb enrich could not fetch (41438592015), Color collided on the name
(41344444991), and the rights audit was told "bootstrap", went on with no catalog
and crashed (41792247208). That last answer is the dangerous one: Decision 089
already said a missing asset is an emergency.

**How to apply**: never call `release upload --clobber` on an asset other jobs
read. Proved against a real throwaway release, because a fake cannot prove GitHub
accepts the calls.

## 177 — A checker that can no longer find a known claim refuses to clear anyone, and a hidden series takes its episodes and its uploads with it
*Date: 2026-11-04*

`corroborate_copyright` asks the Office about Kiss Me Deadly before each run and
stops if the known renewal is not found. It reads the Office's new record (the class
is the number's prefix; the only date is the renewal's, so a renewal must fall 27 to
29 years after the film) and reads three pages. Stamps from the blind window are
void. A rebuilt series card keeps what the audits wrote (`AUDIT_FIELDS`). A hidden
series leaves publish-db's build, and a claim on a show reaches its source uploads.

**Why**: a viewer's list of series led to an investigation that found the Office had
changed its response around 2026-10-28. `renewal_in` skipped every record, so about
700 titles were stamped "no claim found" and the runs stayed green: ENGINEERING-PROCESS
§2 again. Each tv-canonical run also wiped a series card's evidence, and the nightly
check used to restore it, so the two faults together put 16 renewed series (278
episodes) back on screen, Banacek and Ironside among them. A hidden card had also
never stopped its episodes. Separately, Decision 172's fragment flag deleted 21
serials on 11-01: a serial's card plays chapter one, so it reads as a piece of itself.

**How to apply**: any reader of an outside service needs a canary: a fact that must
come back true, checked before anything is recorded. A new audit field on a series
card goes in `AUDIT_FIELDS`. Bundle series may be blocked by any `noRecommend` reason
except `fragment`. The 28-year window misses a late renewal; that is left for a person
rather than widened, because the original date is no longer published.

## 178 — A series' year comes from evidence about the series, is searched for continually, and is never borrowed from a same-named film
*Date: 2026-11-04*

`shared/editorial/series_years.json` holds each series' year with where it came from.
`enrich_series_years.py` fills it in every TV rebuild (an episode's air date, TVmaze on
an exact title, the show's own overview), an entry marked `reviewed` is a person's, and
remediate puts it on the card. A reviewed year survives the rule against pre-television
years, and a year before 1888 is no year. A work with a renewal on record leaves through
`takedowns.json`, its series and its source uploads together, the case naming the renewal.

**Why**: the owner, 2026-11-04: *"We should be constantly searching for that information
and making sure that everything that can be displayed in the app is displayed. The goal
is the best possible data and the best possible database."* Thirty-two shows sat hidden
with no year. Restoring the years the spines held would have been worse than hiding
them: a title match had given Columbia's 1941 The Iron Claw the year of Pathe's 1916
film, and the same for The Secret Code, Winners of the West and Daredevils of the Red
Circle, so 1940s serials passed as public domain by age. A Great Courses lecture read
1801 and a 1997 telenovela 1905. A Holocaust denial video was live as a 1918 film.

**How to apply**: a year on a bundle spine is a claim, not a fact: check chapters and
episode counts against the work. `-1960` in a slug is a placeholder. Men into Space and
Alan Watts stay undated on purpose; their rights are the owner's call. A hide for want
of a year says nothing against a show (1.47.18), so never treat it as a claim.

**Consequences**: `cce_renewals.json` barely reads "a series of photoplays" entries,
which is why Flash Gordon and Batman read as free; the renewals here were found in the
raw text, and the parser is the open fix. A bundle stamps one year on every file, so
per-file claims in compilations (Flip the Frog, early Warner cartoons) are still open.

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
