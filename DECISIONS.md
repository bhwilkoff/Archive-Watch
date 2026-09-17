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
- 116+ → below, in full

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

### 116+ — in full below

- 116 — A data contract is a test, not a docstring; and a client may not crash on a shape
- 117 — Roku's ingestion scores the CHANNEL INDEX, not the file; a withheld asset freezes its last verdict, so fit the poster instead
- 118 — A captioned film streams like any other and draws its cues in the overlay; a whole-film HLS segment ignores every buffer ceiling
- 119 — A television hands over a link as a CODE; the encoder is proven against an independent reference at every version, never against itself
- 120 — Social media is hosted where there is no ingest delay; a platform that could not post FAILS, and archive.org keeps only the video
- 121 — Correction to 119: Roku DOES share playlists, and a decision's closing paragraph outlives the hour it was true for
- 122 — Roku never RECEIVES a shared playlist, and the legacy tier never sends one; both are closed, not deferred
- 123 — Pulse replaces the vendor consoles: every store is read by the route it actually offers, and a reading that cannot be trusted is refused rather than written
- 124 — A checked source's synopsis always beats the uploader's, every synopsis carries its provenance, and the client SAYS it
- 125 — Credits with no surviving id are residue unless the cast proves the film; and the same cast dates an upload-dated film
- 126 — A request that must be answered rides its own field; a shared query record served once per bump merges whatever lands on it together

---

## 116 — A data contract is a test, not a docstring; and a client may not crash on a shape
*Date: 2026-09-11*

`tools/test_details_contract.py` asserts the shape of the detail shards, and
`build_web_details.py` emits exactly one cast shape: **always a list**,
`[name] | [name, path] | [name, path, id]`. The Roku Detail screen reads both
shapes anyway, and `PosterTile.onContent` returns unless its nodes exist.

**Why**: Roku's store analytics showed 16 crashes in two days at
`DetailScreen.brs:781` — `c.Count()` over the cast. The channel was correct
and the data was not. `build_web_details.py` documented the three-shape
contract in its own header and then wrote

    cast.append(entry[0] if len(entry) == 1 else entry)

so a cast member with no TMDb profile arrived as a **bare string**. A
BrightScript String has no `Count()`, so opening Detail crashed the channel
on any such film: **2,798 entries across 1,716 films**, 5.4% of the catalog.

The part worth keeping is why it survived so long. `watch.js` reads the same
field and happens to test `Array.isArray(c)`, handling both shapes without
comment. One client's tolerance made the defect invisible to every other
client — the web looked fine, so the data looked fine, and the only place the
truth appeared was a crash log from a platform that trusted the docstring. A
second reader coping is not evidence of a correct contract; it is what hides
an incorrect one.

**How to apply**: when a producer's docstring states a shape, a test asserts
it — over the real artifact, not only over unit fixtures (`--shards`). Fix the
PRODUCER first when the defect is in data: republishing the shards fixed the
**live, already-shipped** 1.0.51 channel with no store review, where the
client fix waits on certification. Then fix the client anyway, because a
client may not crash on a data shape. And note the SceneGraph trap the second
crash was: a field declared with `onChange=` in an XML `<interface>` can fire
while the component is still being built, BEFORE `init()` has assigned node
references — guard the handler and re-apply content at the end of `init()`,
or an early-arriving `itemContent` leaves the tile blank forever.

## 117 — Roku's ingestion scores the CHANNEL INDEX, not the file; a withheld asset freezes its last verdict, so fit the poster instead
*Date: 2026-09-11*

A film whose poster is the wrong SHAPE gets a fitted 2:3 rendition
(`tools/fit_roku_covers.py`) rather than being dropped from the Roku Search
feed. The rendition scales the original to fit INSIDE a 400x600 canvas and
fills the bars with a blurred copy of itself, so the artwork is never cropped
and never stretched (Decision 097 intact). The files ride the `roku-covers`
tarball that deploy-pages restores to `_site/roku-search/covers`, which is the
one host Roku's fetcher can read — archive.org refuses it.

**Why**: the owner reported the registered feed stuck at 98% while the
standalone validator scored the SAME URL at 100%. Both readings are correct
and they score different things. The validator scores the FILE. The registered
ingestion scores the CHANNEL INDEX — and it counts an asset it is RECONCILING
(removing, because our feed stopped listing it) as a rejection, reporting the
errors from when that asset was last present.

Measured across six ingestions of three different feeds:

    job 3   3,106 assets   passed 3,052   errors 54   reconciled  --
    job 4   2,903 assets   passed 2,849   errors 54   reconciled 249
    job 5   3,106 assets   passed 3,052   errors 54   reconciled  54
    job 6   3,106 assets   passed 3,052   errors 54   reconciled  54
    job 7   3,755 assets   passed 3,701   errors 54   reconciled   0
    job 8   3,755 assets   passed 3,702   errors 53   reconciled   0
    job 9   3,755 assets   passed 3,702   errors 53   reconciled   0

The id list is BYTE-IDENTICAL across a feed that changed size by 203 assets,
and while those ids were absent NONE of them was in the feed at all. Roku's
own report download named the cause in one line — `Invalid aspect ratio
ASPECT_RATIO_4_3 for main image ... Image will be removed`, then `All images
have been removed. An asset must have at least one image.` Every one was a
Wikimedia still our own gate had since dropped, and dropping them is what
made the records permanent.

**The cost was never 54 films.** 835 of 3,972 eligible titles were being
withheld for the proportions of their poster alone — rights-evidenced,
playable, professionally illustrated films kept out of Roku Search because a
1918 press still is 4:3. Fitting them took the feed from 3,106 to 3,755 and
approved titles from 3,052 to 3,702.

**How to apply**: prefer a conformant rendition to withholding an asset, and
keep the negative controls — a 16x16 favicon and a non-image are REFUSED
rather than letterboxed in, and a map entry whose file did not reach the
tarball still withholds the film, because a 404 to Roku is worse than the
off-aspect image it replaces. Do NOT tighten the aspect tolerance to chase a
percentage: that experiment was run (1% both ways, 2026-09-11) and DISPROVED
its own premise — removing all 203 assets outside 1% changed the error count
by exactly zero, because the real failures were far outside any plausible
band and already excluded. Tolerances stay at the values measured from Roku's
own approvals (2:3 4%, 16:9 1.5%).

**Consequences**: **the fix worked completely, and the 53 are phantoms.**
Job 9's report download settles it three ways at once. The fitted covers were
all accepted — the feed grew by exactly 649 assets and APPROVED TITLES GREW BY
EXACTLY 649 (3,052 -> 3,701), with `reconciledCount` 0. The error count did not
move. And every remaining error cites
`https://thumb.wikimedia.org/.../500px-To_the_Highest_Bidder_(1918)_-_1.jpg`
for an asset the live feed serves a 400x600 cover for — a URL that appears
NOWHERE in the current file, which was re-fetched and confirmed at 3,755 assets
with all 53 ids present and all 53 carrying an archivewatch.org cover. Roku
parsed that file (`parsedCount` 3,755) and still replayed a stored verdict and
a stored URL. The error object is persisted per asset, not regenerated, and a
changed image does not invalidate it. The file itself validates at **100%**
(2026-09-11 15:44 UTC, 3,755 assets). Clearing a stale per-asset record is a
Partner Success request, and Partner Success is the required next step anyway
to publish the feed to end users. Two report traps worth keeping: `issuesList`
and the summary panel LAG one job behind the job API, and the asset-id search
box filters that stale list client-side with no network request.


## 118 — A captioned film streams like any other and draws its cues in the overlay; a whole-film HLS segment ignores every buffer ceiling
*Date: 2026-09-11*

On iOS and macOS a film with subtitles now plays through
`ResilientStreamLoader` — the same asset every other film uses — and its
WebVTT is rendered by the caption overlay. The HLS wrappers that carried the
track as a native rendition (`CaptionedHLSLoader` for a published track,
`LocalSubtitleHLSLoader` for one fetched on device) are referenced by nothing.
This is Decision 070, which tvOS has run since August, finally carried to the
other two platforms.

**Why**: a viewer on a phone reported *The Grapes of Wrath* playing "about five
minutes and then stops". The wrapper's playlist declares the whole MP4 as ONE
segment, and a segment is AVFoundation's atomic buffering unit, so
`preferredForwardBufferDuration` is ignored and the entire film is pulled into
memory. Measured on that exact film (2.19 GB),
`tools/test_captioned_buffer_growth.swift`, one shape per process:

    wrapper            4,195s buffered vs 300s asked (14x)   1,368 MB, climbing
    resilient loader     193s buffered vs 300s asked            55 MB, flat

A phone's media pipeline is jetsammed long before a 129-minute feature ends,
and ~5 minutes is where a mobile link reaches that ceiling. Decision 070
measured the same thing on a 3 GB Apple TV (`-11819` at ~100s) and fixed tvOS;
the memory note recording why iOS and macOS were scoped out said in as many
words that "low-RAM iPhones plausibly have the same bomb."

**Three things this turned out to reach that the tvOS fix did not.** The iOS 27
branch played the PUBLISHED master directly — ordinary https, so the system
could offer a generated track beside the authored one — and that playlist is
the same single segment (`#EXT-X-TARGETDURATION:7740`, one `EXTINF`). The
on-device-subtitles path writes the identical shape one directory over, so a
viewer who FETCHED subtitles for an uncaptioned film armed the same bomb.
And `makeLocalItem` rebuilt the wrapper on every AirPlay return and every
caption-type switch, so a fix confined to the start path would have been undone
by the first route change.

**How to apply**: never hand AVFoundation a playlist whose segment is longer
than the buffer you intend it to keep — the ceiling is advisory against a
segment boundary and absolute within one. Judge the shape by MEASURING
`loadedTimeRanges` against what was asked, not by reading the property back.
Run each shape in its OWN PROCESS: the first run of the harness played both in
sequence and the control's opening footprint — 1079, 541, 147 MB, falling —
was the wrapper's memory still being reclaimed, which is Decision 065's trap
one instrument over. And keep the two renderers' gates separate: the file
renderer and the caption engine used to share one flag because they never ran
together, and a captioned film now draws its published file WHILE the engine
listens to judge it (Decisions 062 / 073), so one flag would be two writers
fighting over one label.

**Consequences**: the native CC menu is gone for these films on iOS and macOS,
as it has been on tvOS since Decision 070 — the transport menu's caption-type
control covers the switch. Restoring it means SEGMENTING the playlist, which
needs fMP4; Decision 106 already built exactly that for tvOS 27 (`MP4Fragmenter`
+ `LocalMediaServer`) and it is the follow-up, not a rewrite. The subtitle
review keeps its job under a new verdict: it no longer decides whether to
deselect a native track, it decides which of the two renderers keeps the line.
`tools/test_captioned_asset_shape.py` is the cheap guard that stops the wrapper
coming back, negative-controlled both ways (it fires on a planted use, and a
comment naming the loader does not trip it — the branches that replaced these
loaders name them on purpose).

## 119 — A television hands over a link as a CODE; the encoder is proven against an independent reference at every version, never against itself
*Date: 2026-09-12*

The web-TV build draws a playlist's share URL as a QR code (`tv.js`, ported
from `roku/components/QR.brs` and extended from versions 1-10 to **1-40**).
`watch.js` feature-detects `window.AWTV.shareQR` and defers to it, so the
phone and desktop paths are untouched. The version and alignment tables are
MACHINE-GENERATED from an independent reference; version-info bits are
computed. `tools/test_tv_qr.mjs` proves the encoder two ways.

**Why**: a television has neither route the other platforms use.
`navigator.share` does not exist on Tizen or webOS, and a clipboard the viewer
cannot paste out of is not a way to share anything — so Share on a TV either
copied to nowhere or reported "Could not make a link". The owner asked for
exactly this: share playlists "from all native apps and have them publish to a
archivewatch.org link that can be shared (QR codes for TV-based native apps)".

**v10 was nowhere near enough, and the measurement is the argument.** Against
REAL catalogue ids — synthetic ids flattered an earlier version of this same
measurement fivefold — a share link runs 116 characters for one film and
1,048-1,328 for fifty, which is v23-v27. Version 10 holds 271 bytes, so the
encoder as it stood could only ever have drawn a one-to-three film playlist.

**How to apply**: never verify a QR encoder against itself. Every failure mode
here — a mistranscribed alignment centre, a format-info axis swap, a shifted
data bit — produces a clean-looking square of noise, so a golden file generated
from the code it tests asserts nothing. Compare against an INDEPENDENT
implementation, and compare on STRUCTURE rather than output: assert that
exactly one of the eight masks reproduces the reference, which proves the bit
stream, ECC, interleave, function patterns, placement and format info while
staying agnostic about mask selection — a penalty heuristic no two
implementations agree on (adding the spec's penalty rule 3 made agreement
WORSE here, 4/8 to 3/8, which is why the port keeps the Roku file's rule set).
Size each vector to its version's exact capacity so a wrong table row cannot
hide. Then decode the RENDERED screenshot, which is the only check that covers
the canvas, the scaling and the screen.

**What that found**: `QR.brs` listed v10's alignment centres as `[6, 28, 52]`
where the spec says **50** — the third centre advances by exactly 4 a version.
Every version-10 code the shipped Roku channel ever drew was malformed and
unreadable. It survived because v10 needs 232+ bytes and that encoder only ever
draws a ~50-character `/item/` URL. This is the fourth time in this project a
transcribed table has been wrong and the reason the new tables are generated.

**And two defects only the glass showed**, neither visible to any unit test: a
1,048-character URL printed in full overflowed the panel and pushed the only
button off the bottom of the screen (the link is now written out only when it
is short enough to key in with a remote), and a flex column with a `max-height`
SHRINKS its children, clipping the remaining copy to half a line — the panel
fitted and its contents did not. The panel caps at 86vh rather than 92 because
a television overscans about 5% a side and that last row is the button.

**Consequences**: **Roku still cannot share a playlist.** Its encoder is now
correct but remains v1-10, and BrightScript has no deflate — the share format
carries an uncompressed `0`-prefixed variant precisely so a Roku can encode
one, which makes its links longer than every other platform's. Porting the
v11-40 extension back is a separate piece of work.

## 120 — Social media is hosted where there is no ingest delay; a platform that could not post FAILS, and archive.org keeps only the video
*Date: 2026-09-13*

The daily post's CARDS are published to a `social-media` branch and handed to
Meta as `raw.githubusercontent.com` URLs. The teaser clip stays on archive.org.
And a platform that was scheduled, connected, and could not post now FAILS the
run instead of printing `(skipped — ...)`: only two reasons pass quietly, no
credential and no teaser for a platform that needs one.

**Why**: the owner, three days in — *"I still only see two posts on Instagram
and Threads."* Both Meta platforms had last posted on 2026-09-10, under six
consecutive GREEN runs, and the reason was printed in plain sight every time:

    posted: bsky...   posted: mastodon...   posted: youtube...
    (skipped — no public media URL (set SOCIAL_MEDIA_BASE_URL))  x2

Meta FETCHES media by URL rather than accepting bytes, so a card must be
servable before it is offered. archive.org is an ARCHIVE: a freshly PUT object
is not servable until its task queue catches up, and that queue's latency is
not a number you can wait out. Measured with `social_post.py --probe-media`,
which was built for exactly this question because the IAS3 keys live only in
CI and the latency could not be read from anyone's machine:

    0/3 media served after 604s      (all three served by 16 minutes)
    under 30s on the 8th and the 10th

A deadline cannot cover a variable that ranges from half a minute to a third
of an hour. So the host is the thing to change, not the number.

**How to apply**: the split is measured, not preferred. `raw.githubusercontent`
has no ingest step and returns `image/jpeg` for a `.jpg` — and
`application/octet-stream` for a `.mp4`, which Meta refuses. A GitHub Release
asset is no better: GitHub stores `video/mp4` on the asset and still serves
`application/octet-stream` from the download URL (checked, not inherited — the
existing note in `social_post.py` saying Release assets cannot work is
correct). So images go to the branch, video stays on archive.org, and a day
whose clip is not ready posts the CARD instead of a Reel, which the Instagram
adapter already did. A slow archive.org day now costs the video, never the
post.

**NOT YET PROVEN: that Meta will fetch from `raw.githubusercontent` at all.**
The first live run after this change posted an Instagram REEL
(`/reel/DdO8opgjxa_/`), and a REELS container carries only `video_url` — so
the card URL was never offered. That path is exercised the first day the clip
is not ready, and the loud-failure rule below is what makes it safe to find
out that way rather than by another three silent days.

**The classification is the part that matters most.** A platform returning
`(None, reason)` took the quiet skip branch and could never reach `failures`;
only an exception could. The comment above `failures` already stated the
intended rule — "scheduled AND connected AND then refused" — and an
unfetchable media URL satisfies all three while being filed as a cadence skip.
A new skip reason must now be declared benign deliberately; a bare literal
that is not in `BENIGN_SKIPS` fails the test that guards this.

**Consequences**: `tools/test_social_media_gate.py` was written on 2026-09-11
for this same incident and stayed GREEN through all six failures, because it
asserted the CONSEQUENCE (`if failures: return 1`) and never the
classification that decides what enters `failures` — so the list it reasoned
about simply stayed empty. A guard that checks the downstream effect of a rule
is not a guard on the rule. It now tests the rule itself, controlled both
ways. Related: Decision 107 (a red X means THIS run could not do its job) and
108 (a reader that cannot read says so, and never a zero).

## 121 — Correction to 119: Roku DOES share playlists, and a decision's closing paragraph outlives the hour it was true for
*Date: 2026-09-13*

Decision 119 ends: *"**Roku still cannot share a playlist.** Its encoder is
now correct but remains v1-10 ... Porting the v11-40 extension back to Roku is
a separate piece of work."* That is false, and was false within the same
session it was written — the extension landed, and `roku/components/QR.brs`
carries all 40 versions today.

**Why this needs its own entry**: DECISIONS.md is append-only, so 119 cannot be
edited, and a reader who stops at its Consequences paragraph concludes that a
shipped, working feature does not exist and may rebuild it.

**The evidence, taken independently a day later** on a Streaming Stick 4K
(15.3.4), after a week of unrelated TV work: Library -> `*` on the playlist row
-> Share this playlist draws a code; a screenshot of the TELEVISION decodes to
**448 characters** — the exact share URL, carrying `creature feature` and its
10 archive ids. 448 bytes at EC level L is **version 15**, five past the
claimed ceiling.

**How to apply**: when a decision's body and its Consequences paragraph are
written at different moments, the Consequences are the part that rots — they
are where "still open" and "a separate piece of work" live, and they are
written last, before the work they describe as remaining sometimes gets done in
the same sitting. Before repeating a "cannot" from an entry, check the code.
`docs/PLAYLIST-SHARING.md` had the same stale paragraph sitting directly above
its own refutation; it is now marked rather than deleted, because a wrong claim
that was read and believed is worth seeing.

**A device note worth more than the correction**: the Roku Options panel is
ROW-CONTEXTUAL. Opened over Continue Watching it offers only "Play all in this
row" and "App settings" — "Share this playlist" is absent, which reads exactly
like the feature not being there. Focus must be on the playlist row first. That
is how an hour could have been spent confirming the stale claim instead of
disproving it.

## 122 — Roku never RECEIVES a shared playlist, and the legacy tier never sends one; both are closed, not deferred
*Date: 2026-09-14*

Two owner rulings, recorded so neither is re-litigated. (1) **Roku receiving a
shared playlist is refused permanently** — not "deferred", not "pending a
server". (2) **Playlist sharing is switched OFF on the legacy Roku tier**
(`AWCan("shareList")`), while ITEM sharing stays on every tier.

**Why (1)**: a channel's only inbound route is a deep link carrying
`contentId` + `mediaType`, delivered by Roku's own surfaces — the Channel
Store, Roku Search, or ECP on the local network. A person holding a link on
their phone has no way to hand it to the box: no share target, and the Roku
mobile app cannot send an arbitrary URL to a channel. The channel COULD parse
`contentId=list:<blob>` — it already treats contentId as a command channel for
the `selftest:` verbs — so this is a DELIVERY limit and no channel code fixes
it. The only workaround is a short code the viewer types, which needs a server
to expand it, and that trades away the property the whole design rests on: the
playlist rides INSIDE the link, we host nothing, and there is no account at
either end. Asked directly, the owner: **"Roku receiving is not worth a
server."** Do not cost this out again; a future session that thinks it has
found a clever route should check whether the route requires us to store a
playlist, and stop there if it does.

**Why (2)**: a playlist link is 1,048-1,328 characters, which is a **v23-v27**
QR code. Measured in `docs/PLAYLIST-SHARING.md`: v14 cost 2,642 ms before two
fixes (one scanline per MODULE row; deriving scale from the display box) took
it to 1,131 ms, and the mask penalty alone should run ~1.7 s at full size on a
Streaming Stick 4K — several times that on a Roku 2 XD's 600 MHz ARM11, with
nothing on screen to say the box is working. The file already recorded the fix
— move the encode into a Task node behind a "preparing" state — as "the next
thing to do if anyone reports a slow card".

It will not be done. The owner: **"Old devices do not need full playlist
sharing support."** That is Decision-era capability policy working in the
direction it was written for — *legacy never sets the ceiling*, and a feature a
current Roku does well is switched off below rather than degraded for
everyone. The legacy viewer keeps every other route into a playlist: building
one, playing one, and opening one shared FROM another device.

**How to apply**: gate at the AFFORDANCE, not inside the encoder — the row
simply is not offered in Library Options on that tier, so nothing draws a
control that then apologises. Keep item sharing untouched: a `/item/` link is
~50 characters, a v4 code, which is what the Roku encoder drew for its entire
life before playlists existed and has never been slow. And note what this does
NOT change: `QR.brs` still carries all 40 versions (Decision 121), because the
tier gate is a product decision and a correct encoder is not conditional on
one.

**Consequences**: the sharing matrix's Roku row is final — **sends on modern,
never receives, does not send on legacy** — and the docs should stop carrying
it as an open item.

## 123 — Pulse replaces the vendor consoles: every store is read by the route it actually offers, and a reading that cannot be trusted is refused rather than written
*Date: 2026-09-14*

Pulse is the one place the owner reads how the app is doing — seven views by
audience, a tab per platform, daily. Three rules bind it beyond Decision 108's:
**a store is read by the route it actually offers**, **a reading that is mostly
carried-forward is REFUSED rather than written**, and **absence is written,
never drawn as a zero**. Binding detail: `docs/PULSE-ANALYTICS.md`.

**Why**: the owner — *"The whole point of Pulse is that I never have to go into
the individual dashboards."* That is a higher bar than a summary page, and it
fails the moment one number is stale, one is invented, or one platform is
quietly missing. All three happened in a day.

**The route is the finding, every time.** Amazon publishes no acquisition
endpoint and no live-version endpoint — but for a FREE app every install is a
`$0.00 Charge` row in the SALES report, and an EDIT is seeded from the live
build, so both questions are answerable by asking something else. Roku
publishes no API at all and never will, and answers by DELIVERING its Looker
dashboards to an endpoint we already ran. Play's install export was called
broken and was merely lagging twice over. In each case the first answer —
"there is no API for that" — was our claim, not the vendor's.

**How to apply**: before recording that a vendor exposes nothing, ask what it
DOES expose and in what shape; Decision 109 started this list and every entry
since has been found the same way. Distinguish the vendor's error codes
precisely — Amazon's *"Report not found"* (real route, no data) versus
*"Unable to fetch the request scope"* (no such route) is the difference between
waiting and rebuilding. Never delete a vendor-side object you did not create:
the live-version reader creates an edit only when none exists, because an
existing one is somebody's in-flight submission.

**And guard the reading itself.** CI holds every credential and a laptop holds
a few, so a local `--apply` writes a mostly carried-forward file that silently
replaces fresher numbers — which is how macOS vanished from Reach hours after
being fixed. `HEALTH_OWNS` must name every key a reader writes or a dark reader
DELETES its section rather than preserving it. And a missing column must never
default to zero: Roku reported 0 installs for a platform with 112 because the
day's rows came from a different report.

**Consequences**: five stores now answer for themselves — Apple, Play, Amazon
and the web by API or counter, Roku by delivery — and each declares its own
route on the page, so "declared by hand" appears only where it is true. What no
route can reach is named on the page rather than omitted: Apple's retention and
session analytics 403 for this key, and Play withholds ratings below a minimum
audience.

## 124 — A checked source's synopsis always beats the uploader's, every synopsis carries its provenance, and the client SAYS it
*Date: 2026-09-16*

`tools/synopsis_provenance.py` gives every visible synopsis a `synopsisSource`
— `tmdb`, `omdb`, `wikipedia`, `tvmaze`, `agent-reviewed`, or `archive` (the
uploader's own description) — and REPLACES unstamped or uploader text with
TMDb's overview wherever the item has a `tmdbID`. Every client draws the
source under the synopsis: "Synopsis from TMDb", "Synopsis from Wikipedia",
or "Uploader's description on archive.org". Roku, whose Detail has no room
for a caption row, prefixes the uploader case in-line.

**Why**: the owner — "I continue to find descriptions and other metadata that
are not appropriate for the films... many instances of uploader information
and reviews instead of information about the film." Measured before the
change: 27,159 visible items carried a synopsis and **22,192 had no source
stamp** — archive.org's `description`, i.e. whatever the uploader typed.
6,304 of those matched uploader/review markers ("I've been researching newly
public domain films from 1929 and earlier, so I'm uploading the best
copies…" as the synopsis of *Devil May Care*; "The acting is still awful"
for *The Wild Women of Wongo*). **11,229 of them had a tmdbID**, so an
accurate overview had existed the whole time: the TMDb fillers were written
to fill EMPTY synopses only ("never overwrites") and did not stamp what they
wrote, so nothing downstream could tell TMDb's text from a reviewer's.

**How to apply**: never write a synopsis without a `synopsisSource`; a
writer that cannot name its source is writing the uploader's text and must
say `archive`. Prefer a checked source over the uploader whenever one
exists, and never overwrite a checked source with a lower one (the
precedence here is tmdb ≥ omdb ≥ wikipedia ≥ tvmaze over archive; the four
checked sources are left as they stand). Label every source on screen, not
only the weak one — a caption that appears only on bad records is a warning
nobody reads; one that appears on every record is provenance, which is the
learning-orientation answer (expose the structure, let the viewer weigh it).
The TMDb overviews are cached in `shared/editorial/tmdb_overview_cache.json`
(committed) so the rule costs no fetch on a rebuild.

**Consequences**: uploader-only text remains for the ~9,000 items with no
external id, labeled. The remaining unchecked fields are the next audit:
`director` and `cast` carried without any external id (1,139 / 758 visible
items, from the Archive `creator` field), `genres` inferred from subjects
(controlled vocabulary, not a source), and the canonical-title adoption that
Decision 123's sweep showed can hide a wrong match.

## 125 — Credits with no surviving id are residue unless the cast proves the film; and the same cast dates an upload-dated film
*Date: 2026-09-16*

`remediate_catalog.strip_unanchored_tmdb_residue` removes TMDb credit rows
(cast with `character` / `tmdbPersonID`, and the director, countries and
ratings that arrive in the same credits call), `metaSource = "tmdb"` fields
(writer, studios, release date, tagline, keywords...) and a `languageSource =
"tmdb"` language from any film item with NO surviving external id — UNLESS
`cast_residue_fixes` proves the credits are the film's own: three or more of
those names are the cast of a TMDb film carrying the item's own title
(article-insensitive, containment) within fifteen years. That same anchor
DATES the item: when its archive id names no year and its catalog year is
1978+ while the anchored film's is more than five years earlier, the film's
year is adopted (`yearSource: "cast-anchored-tmdb"`). Series cards and
anything with a tvmazeID/tvdbID are out of scope; a wikidataQID is an
identity, not a cast source, so Wikidata-only items ARE judged.
`tools/anchor_orphan_credits.py` grows the offline caches by TMDb title
search, keeping a film only when ≥3 cast names agree.

**Why**: the owner's audit — *"uploader information and reviews instead of
information about the film"* — reached the credits. Decision 087 clears a
wrong match's ids and artwork ONLY, on the correct ground that director and
cast can also come from the Archive item; the 2026-09-08 residue strip only
reaches items the verifier stamped. Measured 2026-09-16: **916 visible no-id
items carried TMDb credit rows.** A NetZero commercial reel titled "501" wore
the 2008 Danish film "501" entire — director, writer, studio, release date,
20 IMDb votes, Danish language, ten cast members with TMDb person ids — and
no marker of any kind. A Dragnet episode was credited to *The Big Bounce*
(2004, Owen Wilson), a War of 1812 newsreel to the 2011 PBS documentary,
Keaton's *Cops* to a 2016 Austrian film, a Michael Shayne episode to Mario
Bava, a 1956 Producers' Showcase to Omar Sy. And a `wikidataQID` had been
shielding the worst: *Godzilla* (1954) wore Aaron Taylor-Johnson, *The Fast
and the Furious* (1955) Paul Walker, *Panique* (1946) its 1977 remake.

The evidence is in the fields, not in a marker: `metaSource`/`languageSource`
`= "tmdb"` are written only against a tmdbID, and a cast row with `character`
can only be a TMDb credit. With every id gone, each describes the film the
match pointed at.

**The keep side cost more than the strip.** A first pass cleared 352 visible
items and ~40% of them were CORRECT credits with the id gone for an
unrelated reason — *All the Fine Young Cannibals*, *Cold Turkey* (1925), Night
of the Living Dead, *Three Ages* (Keaton, uploader-dated 2006). "No id" is not
evidence of a wrong film; the cast reverse-matched to a same-titled film IS
evidence of the right one. Three refinements, each from a false positive read
off the list: name-only votes (a `None` profile path broke the strict key,
160 items); article-insensitive containment ("The Werewolf of Washington" /
"Werewolf of Washington"; "Lady Snowblood 2: Love Song of Vengeance"); and a
15-year window, because *Die Sister, Die!* is 1972 AND 1978, *I Eat Your
Skin* 1964 and 1971 — same film, production vs release — while a remake is
decades away. Net: 269 visible items lose another film's credits; 6 pre-1961
features that the rights audit was about to hide as "confirmed modern" get
their real year instead.

**How to apply**: never judge residue by the presence of an id alone in
either direction — an id can be missing on a correct film and present on a
wrong one (Decision 026). When a rule clears, look for what it clears that
was RIGHT, and find the evidence that separates the two; here it was already
in the caches. Keep the two rules' thresholds distinct: the strict
(name, profile) vote at ≥2 CLEARS on a >5-year contradiction; the name-only
vote at ≥3 with a title agreement KEEPS. Do not restore a cleared tmdbID
from the anchor — a verifier removed it for a reason this rule does not
re-litigate; the credits stay, the id does not. Run `anchor_orphan_credits`
locally when the cleared count jumps: it is the only network step and it
writes nothing to the catalog.

**Consequences**: 19 items whose ONLY year evidence was a cleared match's
release date now fall to the owner's 09-11 `no_evidence` hide — among them
one copy of *L'Arrivée d'un train en gare de La Ciotat* — which is that
policy working on truer data, not a defect here. The rights confirm CANNOT
run from CI any longer (archive.org refuses the runner: 4/4 failed on each of
the last three days) and was run locally over its 116 stuck targets; a
follow-up is to move that step to the owner's Mac on a schedule.

## 126 — A request that must be answered rides its own field; a shared query record served once per bump merges whatever lands on it together
*Date: 2026-09-17*

The Roku channel's single-id lookup — what a deep link and Detail's index
fallback use — no longer goes through `CatalogService`'s query fields. It
has its own pair, `lookupId` / `lookupResult`, served from each event's own
data, and the answer names the id it is for so the Scene matches it to the
request it still holds. `qId` is gone.

**Why**: Roku certification failed the Search Beta channel (ticket 110523):
"The Content and search beta channel found, but it redirects to the
channel's home screen instead of playing the video" — The General, The Sky
Pilot, The Ten Commandments. Reproduced on the Streaming Stick 4K against
the store channel, the beta channel and the sideload:

    AWDEEP contentId=TheGeneral720p1926 mediaType=movie
    AWSVC query # 2 ... ids= 14 ... id=TheGeneral720p1926
    AWSVC resolveIds asked= 14 found= 11

`CatalogService` reads every `q*` field as ONE record and serves only the
newest `queryId` — by design, so a burst of keystrokes costs one scan. On a
cold start Continue Watching's `resolveIds` (`qIds`, 14 ids) and the queued
deep link (`qId`) both bump before the task attaches its observer; the task
runs the merged record once, `runQuery` dispatches the `qIds` branch first,
and the Scene's results handler — which checks `pendingUserItems` before
`pendingDeepLink` — hands the answer to the user-items branch. The deep
link is never answered. A device with no watch history has no `qIds` to
merge with, so the harness (fresh sideloads) never saw it, and the memory
"deep-link demo film TheGeneral720p1926 verified playing" was true on the
day it was written.

**How to apply**: coalescing is right for a *query* — the viewer only wants
the latest page — and wrong for a *request* that a specific caller is
waiting on. When a field on a shared service must be answered, give it its
own field and its own result, serve from `msg.GetData()` rather than the
field (two ids set back to back are two answers), and tag the answer with
what it answers so a stale one is ignored rather than misrouted. Do not fix
this by reordering the branches in `runQuery`: whichever branch runs, the
other request's `pending*` flag is left set and misroutes the next result.
And test deep links on a device WITH history — the empty-registry case is
the one that always passes.

**Consequences**: `roku/manifest` 1.0.75, packaged and uploaded to the beta
(881088, published) and the store (881015, App Behavior Analysis queued).
The feed's own "Submit for review" is disabled while its status is FEED
VALIDATED — that status means "undergoing deep-linking certification", so
the re-test is asked for on the ticket, not re-submitted in the Dashboard.
Verified on the glass before upload: three cold-start links on the Stick
with history present, one roInput link mid-film, and Hintertreppe on the
Roku 2 XD (legacy tier) — `media-player state=play` for each.
