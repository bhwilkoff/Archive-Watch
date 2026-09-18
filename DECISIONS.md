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
- 123+ → below, in full

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

### 123+ — in full below

- 123 — Pulse replaces the vendor consoles: every store is read by the route it actually offers, and a reading that cannot be trusted is refused rather than written
- 124 — A checked source's synopsis always beats the uploader's, every synopsis carries its provenance, and the client SAYS it
- 125 — Credits with no surviving id are residue unless the cast proves the film; and the same cast dates an upload-dated film
- 126 — A request that must be answered rides its own field; a shared query record served once per bump merges whatever lands on it together
- 127 — Watch Together goes public through an ON-DEVICE studio that speaks RTMPS itself: native frameworks, our own publisher, no encoder dependency
- 128 — A public client gets the flow each platform actually offers, not the one we prefer; and a missing credential is a STATE
- 129 — Android runs the SAME Studio with GLES in Core Image's place, and the host sees the PROGRAM because `setVideoSurface` is exclusive
- 130 — A runtime rule is proved on the PRODUCT path or it is not proved; a skip is not a pass, and the instrument is the first suspect

---

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
