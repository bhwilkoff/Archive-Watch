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
- 081+ → below, in full

When this file grows past ~120 KB, roll the oldest full entries into a
new archive file and extend the index — never trim, edit, or summarize
an entry in place.

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

### 081+ — in full below

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

---

## 081 — A drift correction may not rewind the captions past the viewer
*Date: 2026-08-17*

`LiveCaptions.driftCheck` clamps its re-anchor so the earliest not-yet-shown
cue still lands at or after the furthest playhead the display has reached, and
skips a correction that clamps to nothing. `line(at:)` tracks that playhead.

**Why**: the owner reported The Incredible Machine's generated captions as
undependable — a film with no subtitle file, so this is our engine's own
output. Traced on the Apple TV (`AW_CAPTION_TRACE=1`), the engine looked
healthy: lead built to 121s, no surrender, coherent text. But it corrected
drift THREE times in four minutes, and correction #3 re-anchored by -12.4s,
after which LATER audio mapped EARLIER than what had already been shown:

    cue raw 190.8-191.9 -> film 349.5-351.8   "Basically visual creatures."
    drift correction #3: re-anchored by -12.4s
    cue raw 192.0-194.3 -> film 339.5-344.2   "of all our information through our"

Ten seconds backwards. The schedule then re-crossed ground the playhead had
left, so fragments displayed out of order and lines went missing — which is
exactly what "undependable" looks like from the sofa, on an engine whose text
was fine.

Decision 074 added the correction for a real fault (a seeked scout receives a
burst of pre-target audio and every cue maps late) and was right to. What it
did not bound is the direction: subtracting from `contentOffset` shifts EVERY
cue, including ones already on screen, and nothing stopped the result landing
behind the viewer.

**How to apply**: the mapping running ahead is worth fixing; dragging cues
behind the playhead to fix it is not — a caption that arrives late can still
be read, one that arrives for a moment already passed cannot. Measure the
property, not the symptom: the assertion is "no mapped cue time regresses",
computed from the trace, which is what separated this from the blank ticks
that sit beside it (~32% of ticks, unchanged before and after, and inherent —
silence and music produce no cues). Never judge a correction by whether it
fired; judge it by whether the schedule stayed monotonic.

**Consequences**: measured on the same film, same conditions — 2 backwards
jumps (worst -15.0s) before, 0 after, with 5 clamps firing. Corrections still
happen (4 in the after-run); they are simply bounded now.

## 082 — The LocalMediaServer passes every Mac gate and FAILS on the device; Phase 1 does not cut over
*Date: 2026-08-17*

Decision 079's Phase-1 keystone — a loopback HTTP server fronting the
resilience engine, so AVPlayer sees a plain `http://127.0.0.1` asset and every
native media feature becomes eligible again — is **not** promoted to the
default path. It stays behind `AW_PROXY_EXP=1`. The Mac gates all pass; the
Apple TV does not.

**Why**: measured. Mac-side, against a local range server so archive.org is
never storrmed, the proxy is byte-identical to origin across a FULL
472,697,906-byte film (0 mismatches), across 72 concurrent interleaved reads
in the two-cursor pattern AVFoundation issues on a badly muxed file, and
through the Decision-076 10 Mbps throttled gate — where the player still
advances 5.9s in 6s. On the device, three runs of the same film gave three
different outcomes:

    run 1   played 5 minutes, 0 stalls, buffer 200s+, system caption
            track OFFERED and SELECTED through the proxy
    run 2   itemFailed x2 at t=0, NSURLError -1008 "resource unavailable"
            (OSStatus -16848); the film never started
    run 3   proxy listening, item created, then NOTHING for 3.5 minutes —
            no ready, no failure, no buffer telemetry

**How to apply**: the harness validates the SERVER, in-process, where the same
process both serves and plays. On tvOS the consumer is `mediaserverd`, a
SEPARATE process reaching the app's loopback listener, and that hop is what
the Mac never exercises — a byte-perfect server proves nothing about it. Do
not read a green harness as readiness for a path whose defining hop it cannot
test. If this is picked up again, the first question is not the server's
correctness (settled) but whether a third-party tvOS app's loopback listener
is reliably reachable by mediaserverd at all, measured over many runs — one
success proves nothing when the failure is intermittent.

**Consequences**: tvOS keeps Decision 072's single pipeline —
`ResilientStreamLoader` for every title, our own engine captioning the
uncaptioned. That path is what the owner is running and what the last several
verified fixes were measured against. What the proxy would have bought (native
generated-caption eligibility) is worth little here anyway: Decision 068
measured the system's generated track as offered but never emitting on this
beta, and run 1 above reproduced exactly that through the proxy. The stress
harness earned its keep regardless — it is what exonerated the delivery path
for the owner's audio-static report.

## 083 — `excluded` is shared state: a tool that hides items must register its marker, and the reconcile must say when one hasn't
*Date: 2026-08-18*

`audit_rights.py`'s FOREIGN list now includes the playback verifiers'
markers — `playbackDead` (check_liveness: the video is gone) and
`playbackReason` / `strictFail` / `needsReSource` (verify_playback_strict: no
moov atom, mdat past EOF) — plus `codecUnsupported` (audit_codecs: AV1/VP9 no
Apple device decodes). The reconcile also PRINTS any unregistered
exclusion-looking marker it un-hides.

**Why**: `excluded` is written by six tools and reconciled by one. On every
publish `audit_rights --apply` restores anything that is no longer a rights
hide, skipping markers other tools own — and three tools had never been added
to that list. Measured on a normal build:

    un-hid items carrying UNREGISTERED exclusion markers:
      playbackDead x253  playbackReason x636  strictReason x384  posterDead x3
    [apply] excluded=7369 un-hidden=676

So films MEASURED unplayable — dead video, truncated files, codecs no Apple
device can decode — were being restored to every surface on every build, for
as long as those verifiers have existed. Both workflows reported success
throughout. This is the owner's oldest complaint ("all titles visible in the
app should play") with a mechanism behind it, and it was invisible from the
playback code because nothing in the app was wrong.

After registering: un-hidden 676 -> 40, served DB 31,652 -> 31,138 items, and
zero visible films carry any of the four markers.

**How to apply**: a new tool that sets `excluded` MUST add its marker to
FOREIGN in the same change, or its work lasts exactly until the next publish.
Judge a candidate by its VALUE DISTRIBUTION, never its name: `strictReason`
looks like a failure marker and was in the first draft of this fix, but 20,629
of the 26,163 items carrying it say `decoded` — it records the verifier's
outcome, and registering it would have frozen most of the catalog against
legitimate rights un-hides, a worse bug than the one being fixed. `posterDead`
is excluded for the same reason: it demotes a poster, it never hides a film.
The printed warning finds candidates by name because that is cheap and catches
the omission; deciding which are real is a judgement the warning cannot make.

**Consequences**: the warning is the durable part — the next tool to forget
gets named on the next build instead of silently losing its work. Two markers
remain unregistered ON PURPOSE and will keep appearing in that line; that is
correct, not a leak.

## 084 — Record the EVIDENCE, not just the verdict; a colour reading vetoes a merge only when it is confident
*Date: 2026-08-18*

`classify_color.py` now stores `colorSat` — the measured saturation — beside
`colorMode`, and the two consumers that act on a B&W reading require it to be
CONFIDENT before they do anything destructive: `build_sqlite._color_compatible`
(Decision 040's guard, which refuses to merge two same-titled copies whose
colour disagrees) and `verify_external_match.py`'s Tier 3 (Decision 026, which
CLEARS a match's artwork and year when a B&W film is matched to a modern
release). Confident means outside 4.0–14.0; a missing `colorSat` counts as
confident, so every item measured before today behaves exactly as it did.
An upload that says "colorized" in its title or id still blocks a merge
whatever its chroma reads — a stated version difference beats a statistic.

**Why**: the owner has reported duplicate cards twice. Auditing the shelves
found 36 films split into two cards purely by a colour disagreement, and the
merge rule was behaving correctly on incorrect data. Decision 025 called the
saturation split "decisive" on a calibration set where it is — a clean B&W scan
reads 0.0 and a healthy colour print 15–25. It is not decisive everywhere.
Measured against films whose real colour is a matter of record:

    Lonely Wives (1931)        B&W     SATAVG 0.00   <- the clean case
    Not of This Earth (1957)   B&W     SATAVG 9.00   -> read as COLOR
    Scared to Death (1947)     COLOR   SATAVG 7.10   -> read as BW (Cinecolor)
    Eagle in a Cage (1972)     COLOR   SATAVG 7.65   -> read as BW
    Death Rides a Horse (1967) COLOR   SATAVG 8.49   (frames spanned 2.1-15.8)

A B&W film reading HIGHER than a colour one is not a threshold wanting a nudge;
it is two populations that overlap in this statistic, and no amount of extra
frames separates them — one film's frames alone spanned 2.1 to 15.8. Chroma
percentiles were tried and overlap too (SATHIGH: colour 11.0–23.3, B&W 0.0–10.0).
So the fix is not a better threshold, it is admitting when the measurement does
not know: a guard should abstain on weak evidence rather than veto on it.

The reason this was invisible is the part worth generalising. `colorMode` stored
the verdict and discarded the number, so a coin-flip at 8.1 was indistinguishable
downstream from a certainty at 0.0. The same shape sits next to it: `matchVerified`
stores `True` and not which tier fired, so the blast radius of Tier 3 cannot be
counted from the catalog at all — 781 items are `bw` with a year ≥1970 and
therefore eligible to have had their artwork and year cleared on a reading that
may have been a coin-flip, and there is no way to tell which. Decision 056 was
the same lesson in a different field: `playbackVerified` recorded THAT a title
played and not WHEN, so a check three months stale looked identical to one made
yesterday.

**How to apply**: when a pipeline step makes a judgement from a measurement,
persist the measurement. A downstream consumer cannot weigh a verdict it cannot
see the evidence for, and a threshold that is right for most of a population is
a coin-flip for the part of it that lands near the line — which is exactly the
part that surfaces as a user-visible defect, because that is what a disputed
case IS. Do not widen the confidence band to "fix" more duplicates: the guard's
real job (keeping a B&W original apart from a colour remake) is asserted by
`tools/test_color_guard.py`, whose first row is the negative control — a clean
B&W reading against a clean colour one must STILL block. Re-measure a disputed
set with `classify_color.py --ids-file` (ids from `audit_color_disputes.py`),
never a full re-sweep: probing 30,000 items to settle 70 is the kind of local
archive.org sweep that has stalled the owner's Apple TV.

**Consequences**: nothing changes until the disputed readings are re-measured —
the relaxation is keyed on evidence that does not exist yet for any item, which
is what makes it additive (Decision 020). `color-classify.yml` gained a
`recheck_disputed` input that measures exactly the disputed ids. `colorSat` is
an additive JSON key the clients ignore. The other consumers of `colorMode` —
Cartoon Mode's colour preference and Party Play's B&W exclusion — are unchanged
and want no confidence gate: preferring colour on a weak reading costs a viewer
nothing, where clearing a film's artwork on one is destructive.

**Amendment (same day, found by relaxing the above)**: two further faults, both
of which the colour flag had been hiding.

*The guard is TWO gates, not one.* `_color_compatible` tests an edge between two
copies; `_consistent` tests the component they form, and it rejected any mixed
colour group outright. Relaxing only the edge changed nothing — the pair passed
and the component was thrown away. Both gates now abstain on the same evidence.
Whenever a rule exists at two levels, a change to one is a no-op until the other
agrees, and a no-op that looks like a fix is worse than no fix at all.

*An item a series spine owns must NEVER merge as a film.* `merge_film_duplicates`
clustered on `contentType in _FILM_TYPES`, and an episode is still typed as film
in `catalog.json` until the DB materializes it (Decision 045) — so spine-owned
episodes were in scope the whole time. Three seasons of "It Takes a Worried Man"
share a title, share a 1,800s runtime, and sit inside the year span every film
test allows, so every test says one work: `tools/test_color_guard.py` measures
that unguarded they collapse to ONE card, deleting two seasons. The only thing
that had ever kept them apart was an accident — their colour readings happened
to disagree. `_playable_episode_aids()` is now resolved BEFORE the merge and
passed in as an exclusion set.

**How to apply**: never let a film-level rule run over items the TV spines own —
cluster on ownership, not on the contentType the catalog happens to carry at
that moment. And when relaxing a guard, look for what else that guard was
accidentally protecting: it had two jobs and only one of them was written down.

## 085 — A merged-away id forwards to its survivor; a favorite must not vanish because a duplicate was collapsed
*Date: 2026-08-18*

`build_sqlite` now emits an `item_aliases(oldID, newID)` table recording where
every copy collapsed by Decision 040's duplicate merge went, and `CatalogDB`
consults it whenever a saved id fails to resolve — in `item(_:)` (Detail, deep
links, Top Shelf resume) and `itemsByIDs(_:)` (Favorites, Continue Watching,
playlists, history). Aliases are chased transitively, so a copy merged into a
copy that was itself merged still forwards to the final survivor.

**Why**: Decision 040 collapses re-uploads of one film into a single best card
and DROPS the losers from the item list. Nothing recorded where they went —
`duplicateMergedInto` appears in `audit_rights.py`'s FOREIGN list but is never
written by anything. Both library surfaces resolve strictly by id
(`dbItemsByIDs`, `dbItem`), and an unresolvable id is silently filtered out. So
a viewer who favorited or was part-way through a losing copy loses it: the
favorite disappears and the watch position is gone, while the film is still in
the app, one row away, under the survivor's id. Nineteen ids were merged in the
2026-08-18 colour pass alone, on top of ~208 (Decision 040) and ~360 (040a)
earlier — every one a potential silent deletion from somebody's library.

Nothing about this is visible from the playback or library code, because
nothing is broken there: the query is correct, the row is genuinely absent, and
the disappearance looks like the viewer never saved it.

**How to apply**: any pipeline step that DROPS an item a viewer could have
saved must leave a forwarding address — favorites, playlists, watch progress
and Top Shelf resume are all keyed by `archiveID`, and dropping one is a
deletion from the user's data, not just the catalog. Filter aliases to
survivors that actually exist in the built DB before inserting, so a forwarding
row can never point at another hole. Keep the un-aliased lookup
(`itemsByIDsDirect`) for resolving the survivor itself, or resolution recurses.
This does NOT apply to `excluded` items (Decisions 027/044/083): those are
hidden deliberately — a rights or playability judgement — and forwarding a
viewer to a different film would be worse than the item being gone.

**Amendment 2026-08-20 — the OTHER dedup path had no forwarding at all.**
`item_aliases` was populated only by `merge_film_duplicates`. `dedupe_by_imdb`
runs BEFORE it, drops every non-winning copy that shares an IMDb id, and
recorded nothing — **6,158 ids on the live catalog against the 551 the alias
table covered**, an order of magnitude more silent deletions than the path this
decision was written for. Found by asserting that a restored film was reachable
by its own archiveID and getting a FAIL: the film was visible, under a better
id, and the id I asked about had been dropped with no forwarding address.

Both maps are now unioned and chased as ONE, because the paths compose — an id
dropped by the imdb dedup forwards to a winner a later film merge may itself
drop, and chasing each map separately dead-ends on exactly that hop. Measured:
551 -> 5,395 alias rows, 0 pointing at a dead id, 0 self-referential, and every
one of the 1,325 ids still without a forwarding address is an `excluded` item
whose whole IMDb group is hidden — nowhere to forward, and forwarding a hidden
item to a different film is what this decision already forbids. Zero VISIBLE
items are stranded.

Forwarding now exists on EVERY platform, which it did not before: the Apple
`CatalogDB` had it, **Android downloaded the same SQLite and never queried the
table**, and web could not — its data plane is `catalog-index.json` plus detail
shards, so `build_sqlite --aliases-out` emits `aliases.json` beside the index
and `watch.js` fetches it LAZILY, only when a saved id actually misses (~300 KB
against a 6.2 MB index; a miss is rare, so paying it on every page load would be
the wrong trade). Web's detail route REDIRECTS to the survivor rather than
patching the row, so Details, playback and the favourite toggle all land on the
canonical id. Two traps worth keeping: Android's alias query is wrapped in
`runCatching` because a device holding a cached DB from before the table existed
has no aliases — an older catalog, not an error (the Apple twin gets this free,
since `pairRows` returns `[]` on a failed prepare) — and its queries run
SEQUENTIALLY, never nested, because the `Mutex` in `dbCall` is not reentrant.

**Consequences**: `item_aliases` is a new table older clients simply never
query, so it is additive per Decision 020. It is small (hundreds of rows) and
rebuilt from scratch every publish, so it stays consistent with whatever the
current merge decided. Cross-device sync is unaffected — the saved id is still
the old one, and each device forwards it locally at read time.

## 086 — A shelf that declares itself television may contain television
*Date: 2026-08-18*

`CatalogDB.shelf()` takes `allowStandaloneTV`, set by any shelf whose
featured.json declaration says `"category": "tv-series"`, and for those shelves
it drops `tv-special` from the exclusion list. `tv-episode` stays excluded
everywhere on Home — a loose episode belongs to a series and should be reached
through it (Decision 045). Film shelves are untouched.

**Why**: four Classic TV shelves have never rendered a single tile. `1950s
Television`, `1960s Television`, `1970s Television` and `Classic Television` are
declared in featured.json, filled by the pipeline every day — 463, 279 and 253
members, all playable, all carrying designed artwork — and `notStandaloneTV`
excluded `tv-special` from EVERY shelf, which is their entire membership. The
queries returned zero, the shelves fell under `minPerShelf = 9`, and Home simply
omitted them. Measured after the change: 381, 246, 227 and 950 eligible tiles.

Nothing failed. The SQL was valid, the rows were really excluded, and a hidden
shelf looks exactly like a shelf that was never configured. This is the third
appearance of one shape — a WHERE clause that contradicts the surface's own
purpose. The Classic TV browse tile returned zero for weeks the same way
(2026-06-11), and Decision 050's Hidden Gems was empty on four platforms for
five weeks. `browseSQL` already carries the fix for its half: "when the caller
EXPLICITLY asks for tv-series, they ARE the result set." `shelf()` never got it.

**How to apply**: an exclusion written to keep a content type OUT of the wrong
surface must not apply to a surface that exists FOR that type — check whether
the caller asked for it before filtering it away. The declaration is the signal
here and it was already in the data: featured.json states each shelf's category,
so the shelf itself says what belongs in it. Do not extend this to `tv-episode`
to make a shelf look fuller. When a shelf is hidden by `minPerShelf`, ask
whether it is genuinely thin or whether something upstream is emptying it —
hiding is a presentation rule, not a diagnosis.

**VERIFIED ON THE DEVICE** (2026-08-18, Bedroom Apple TV, Debug build of
1.3.433): an OCR sweep of Home found "1950s Television", "1960s Television",
"1970s Television" and "Classic Television" on the glass, each with a full row
of tiles carrying designed artwork — Captain Video and His Video Rangers, Date
with the Angels, The Eve Arden Show, Stingray, T.H.E. Cat, Ozzie and Harriet.
Screenshot evidence, not the app's own report (the standing rule for tvOS).

**Consequences**: four shelves appear on Home for the first time, on tvOS, iOS
and macOS (all three share `CatalogDB`). Android and web query the same DB and
need the same conditional to match — a parity follow-up. `editors-picks` remains
hidden with 5 eligible items against the 9-tile minimum: that one really is thin,
and the fix is editorial — more curated picks in featured.json — not code.

## 087 — A TV match whose era contradicts the item's OWN collection is cleared
*Date: 2026-08-19*

`verify_external_match.py` gains Tier 0b: for a standalone TV item (no series
spine) whose archive.org collection states a decade — `classic_tv_1950s` and
friends — ask TMDb what the matched work actually is, and if its first-air year
falls more than 15 years outside that decade, clear the artwork and the external
ids. `--era-only` targets exactly the judgeable set; `TMDB_BEARER_TOKEN` is wired
into `verify-matches.yml`, and without it the tier abstains and says so.

**Why**: a 1950s game show was on the owner's Apple TV wearing the poster of the
2012 anime *Another*. The item's year had already been cleared for being
impossible, but the poster came from the same match and stayed. Every existing
tier abstained on it correctly — no Archive imdb id, no Archive date, no year for
the colour gate — so the tool held no evidence at all. The evidence it was never
asked for is what the match POINTS AT.

The signal has to come from the item, not the match: the collection dates it,
independently, and 194 of the 211 suspicious items carry one. Measured over the
full set before shipping — 29 of 203 contradicted, and reading the list settled
it: "Howdy Doody's Christmas" matched to a 2026 title, the Nixon–Khrushchev
Moscow debate to "Nixone" (2018), "The Big Lift" to *Dash Kappei* (1981), "Secret
Mission" to a 1990 Arabic series. One pattern throughout — a short or generic
title fragment matched to a modern series with a similar name.

**How to apply**: query **/tv only**. A first draft tried `/movie` then `/tv` and
produced five false positives out of twelve, because a TMDb id is namespaced by
type — movie 3002 and tv 3002 are unrelated works, so The Benny Hill Show
"contradicted" its 1950s collection with 1999. Asked of `/tv` it answers 1969 and
agrees. Never widen the endpoint for coverage: an id that 404s on `/tv` is one we
cannot interpret, and abstaining is the answer. Clear artwork and ids only, never
guess a replacement — a bad match must degrade to the item's own Archive frame,
not to a different wrong poster. And note the marker trap: `is_candidate` skips
anything already `matchVerified`, so a NEW tier judges nothing until the marker
is bypassed (the first run reported zero for exactly this reason). `--era-only`
narrows the target SET, not the tiers — those items are re-judged by all of them.

**VERIFIED ON THE DEVICE** (Bedroom Apple TV): the 1950s Television row now reads
I Love Lucy 1953, Morey Amsterdam Show 1950, Robert Montgomery Presents 1956,
Captain Video, The Eve Arden Show 1957, The Roy Rogers Show — every item
era-appropriate, every poster its own show, no anime.

**Amendment 2026-08-20 — the imdb half, and two ways it did nothing first.**
The tier now also resolves an `imdbID` through OMDb, which needs no new secret
because this tool already holds an OMDb key. Verified in the served DB: Siskel &
Ebert's *Man Trouble* episode (matched to a 1930 film), *The Long Trail* from
Schlitz Playhouse (a 1917 short), a Paul Revere segment (a 1930 German feature)
and the 1975 sitcom *Two's Company* (a 1936 film) all lost their artwork and
ids, while The Johnny Carson Show (1953), The Sound of Jazz (1957), The Benny
Hill Show (1969) and Newhart (1982) kept theirs. Every one of the cleared five
was OMDb `Type=movie` — a television programme matched to a FILM.

Unlike the tmdb path there is no cross-type collision to guard against: an imdb
id names one work, where a tmdb id is namespaced per type.

It reported almost nothing TWICE before it worked, both times because a
selection step upstream never handed it the population — `is_candidate` skipping
anything already `matchVerified`, then `--era-only` still requiring a `tmdbID`
after the lookup had been widened. Neither failed; both returned a small number
that looked like a finding. When a new rule reports a suspiciously low count,
check what was actually offered to it before believing the count.

**Consequences**: 46 cleared of 447 on the first run, alongside 22 `cleared_year`
and 6 `cleared_bw` from the pre-existing tiers finally reaching items the marker
had hidden. Two judgement calls sit at the 15-year line and are the rows to
revisit if it is ever tuned: Doctor Who matched to the 2005 revival rather than
the 1963 original, and Betty White Show, where 1954 and 1977 series share a name.

## 088 — A liveness check expires; `posterChecked` gets a visibility-tiered TTL
*Date: 2026-08-20*

`validate_posters.py` records `posterCheckedAt` and re-checks an item once its
check goes stale: 14 days for anything eligible to lead Home (designed art,
playable), 90 days for the tail. Targets sort oldest-check-first within
popularity, so the catch-up drains the least-recently-verified rather than
re-walking the same head nightly, and the existing `--limit` bounds it.

**Why**: `posterChecked` was a permanent boolean, so the nightly guard reported
**"0 posters to verify"** against a 40,715-item catalog — it had verified
everything once and could never look again. Meanwhile a probe of 60 Home-eligible
posters found 2 already 404, both `m.media-amazon.com`, which rotates its image
hashes continuously (Decision 044 measured ~62% of omdb posters dead). A poster
alive in June is not evidence about today, and the guard built to catch that had
quietly switched itself off.

This is Decision 056 one field over — there `playbackVerified` recorded THAT a
title played and not WHEN, so a three-month-old check looked identical to
yesterday's. Fourth instance of the same class in two days, alongside `colorMode`
without its saturation (084) and `matchVerified` without its tier (087's
amendment).

**How to apply**: any check against data that can rot needs a timestamp and a TTL
proportional to how visible the claim is — a boolean "checked" is a claim about
the past pretending to be a claim about now. Keep the transient/dead split: a
429 or 5xx must leave the item UNMARKED for retry, never demote it (679 of this
run's failures were transient, and marking them dead would have stripped good
artwork from hundreds of items).

**VERIFIED end to end**: the first run checked 5,820 posters and demoted 137 to
the Archive thumbnail with `hasRealArtwork=False`. Re-probing the same 60-poster
sample after publishing: **0 dead, down from 2**, with the Home-eligible pool
falling 19,058 -> 18,944.

**Consequences**: 727 items now carry `posterDead`, and 472 of them are flagged
`hasRealArtwork=1` again — which is correct, not a contradiction. Those were
re-sourced after demotion: 447 generated frame covers (Decision 023), 17 Commons,
8 TVDb/TMDb. `posterDead` is a durable wants-marker and the re-covering pass
consumed it exactly as intended, so the whole chain — die, demote, mark,
re-source, re-flag — is observably working.

## 089 — A shared index publishes only what it can prove it did not shrink; a missing asset is an emergency, not a first run
*Date: 2026-08-20*

`subtitle.sqlite` is appended to by two workflows — `subtitle-index.yml` (cues)
and `word-index.yml` (word timings) — through one release asset. Both now
snapshot the index's row counts immediately after restoring it
(`tools/sqlite_publish_guard.py snapshot`) and refuse to upload if any table
came out smaller (`check`). Their restore treats only a NON-EXISTENT release as
a first run: a release whose asset has vanished fails the step. And publish is
no longer plain `always()` — it still runs when the COMPUTE step is killed,
which is why `always()` is there, but never when the RESTORE failed.

**Why**: measured in the published artifact — `words=90,084`, `aligned=7`, one
run's output. Two days earlier it held **702,148**. The chain contains its own
control:

    08-18 03:42  subtitle-index uploaded the raw 1.17 GB subtitle.sqlite beside
                 the .zz. `--clobber` DELETES before replacing; the raw upload
                 422'd; BOTH assets were left deleted.
    08-18/19     word-index restore hit "no assets to download" and FAILED,
                 twice, publishing nothing. It has no `|| true`.
    08-19 22:36  subtitle-index hit the IDENTICAL condition, its
                 `|| echo "first run — no existing index"` swallowed it, and it
                 rebuilt 4,000 films from zero and republished over the index.

The workflow without the swallow refused to proceed; the one with it destroyed
the data. Nothing failed — the destroying run is green. This is the same
clobber pattern fixed in `subtitles.yml` on 2026-08-09 and missed here, which
is the argument for a guard rather than a third careful reading: the pattern
has now been found three times by noticing the damage.

**How to apply**: `--clobber` is a DELETE followed by an upload, so any upload
that can fail leaves the asset gone — never pass it a file that might be
rejected (the raw 1.17 GB member is what 422'd), and never let a workflow
publish a rebuilt artifact without comparing it to what it restored. An
`|| true` / `|| echo` on a restore is only ever correct when the *absence
itself* is proven benign; "the asset is missing" is not that, and the way to
tell a genuine first run is that the RELEASE does not exist. The guard passes
on growth, equality, a missing baseline and an empty baseline, and fails naming
the table and both numbers — verified against the real index, including a
faithful replay of the 08-19 rebuild.

**Consequences**: the cue index rebuilt itself, but the `aligned` resume markers
are gone, so ~700k word timings must be re-derived against archive.org's refusal
of ubuntu runners. That failure rate — not a budget — is the real constraint on
this index.

**Correction 2026-08-20**: "months rather than a night" was too pessimistic, and
the error was reasoning in FILMS when the unit that matters is WORDS. The first
scheduled run after the guard landed did 13 films (30 of 43 audio downloads
still failed) and took the index from 90,084 to **262,436** — 37% of the loss
recovered in ONE run, because word count per film varies enormously and a
feature carries ~13k. Recovery is days, not months. The films/day figure was
right; using it to estimate word recovery was not. Complements Decision 057
(a budget that PUBLISHES, never a timeout that kills) and 083 (shared state
needs a registered guard, not a careful author).

## 090 — An auditor judges each workflow against its OWN cadence, never a fixed window
*Date: 2026-08-20*

`audit_workflow_health.py` sizes its lookback per workflow from that workflow's
own cron (`cron_period_hours`, ~2.5 periods) instead of a flat
`LOOKBACK_HOURS=36`, and reports **STALE** when a schedule has not produced a
completed run in over two of its own periods. Dispatch-only workflows keep the
fixed window, since they have no cadence to measure against.

**Why**: the daily report said "Nothing needs attention: every recent run
produced something" while **Canonical TV rebuild sat FAILED for four days**.
Nothing was wrong with `judge()` — the run never reached it. The loop skipped
any workflow whose newest completed run started before the cutoff
(`if started < cutoff: continue`), and a weekly job's newest run is ALWAYS
older than 36 hours. Measured across the fleet: 35 scheduled workflows, of
which **7 are weekly or monthly and were therefore structurally unauditable** —
faststart-derivatives (monthly), tvdb-movies, tv-canonical, community-signals,
rebuild-catalog, backfill-language, match-unmatched. The auditor built to catch
BROKEN/KILLED/DROPPED/SILENT could not see the slowest seven, which are exactly
the ones a human is least likely to notice unaided. Re-run after the change, it
named the tv-canonical failure immediately.

**How to apply**: an auditor's window is a property of the SUBJECT, not of the
auditor's own schedule — whenever the things being checked have different
periods, a single window is wrong for all but one of them. Judging an older run
is safe here because `judge()` returns None for a healthy run, so a monthly
workflow that succeeded produces no finding; only real faults are re-reported
each day, which is what an auditor is for. Do NOT respond to a stale finding by
widening the flat lookback — that reintroduces the same class of blindness one
cadence further out. STALE is deliberately distinct from FAILED: a schedule
that stopped firing produces no failing run to notice, so absence has to be its
own verdict.

**Consequences**: the fleet's slowest seven workflows become auditable for the
first time. Related: Decision 088 (a check against data that can rot needs a TTL
proportional to how visible the claim is — the same reasoning applied to
freshness rather than to coverage), and 089 (a green run that did nothing).

## 091 — A time budget measures the whole tool, not the phase that happens to carry it
*Date: 2026-08-20*

`build_canonical_tv.py --max-minutes` is now measured from process start, not
from the start of the rebuild loop, and the tool says so loudly when resolution
alone consumes the whole budget.

**Why**: the weekly TV rebuild died on its 180-minute step timeout on
2026-08-16, and the budget meant to prevent exactly that was real and working.
It was simply counting the wrong interval. Measured on run 32373160578:

    13:15:11  4124 raw targets; resolving + pooling…
    14:09:33  758 unique canonical shows, 2839 unmatched     <- 54m22s, UNBOUNDED
    14:14:52  build complete                                  <- 5m19s, budget honoured exactly

`resolve_and_pool` is network bound (every raw target against TVmaze at a 0.3s
throttle) and runs BEFORE the deadline was computed, so the production default
gave 54m + 150m = **204 minutes against a 180-minute timeout**. The arithmetic
was the whole bug.

**How to apply**: when a tool has two expensive phases, a deadline computed
between them bounds only the second — start the clock at process start. Do NOT
"fix" this by bounding `resolve_and_pool` naively: it returns `(shows,
unmatched)`, and `unmatched` feeds reconcile, which RECLASSIFIES those items OUT
of tv-series. A deadline there must distinguish "tried and did not match" from
"never tried", or it strips TV classification from shows it never looked at.
Deferring shows is safe and needs no such care — verified on the same run:
757 shows deferred, series files 485 -> 485, reconcile deleted 0 superseded and
0 orphan files.

**Consequences**: a run whose resolution outlasts the budget now rebuilds
nothing and says so, instead of timing out and losing the step. That is the
right trade — Decision 057's rule that a budget must PUBLISH rather than be
killed, applied one level up. The per-episode half of this (the deadline
reaching inside `rebuild_show`, degrading to --no-repick rather than dropping
episodes) is proven in the same run: "budget reached mid-show: 218 episode(s)
kept their existing video URL".

## 092 — DECISIONS.md holds the index + recent entries; older entries archive verbatim
*Date: 2026-08-23*

DECISIONS.md now contains the format rules, a complete INDEX of every
decision, and only the most recent entries in full; everything older is
moved VERBATIM into `docs/decisions/DECISIONS-<range>.md` archive files.
Append-only still binds everywhere: an archived entry is never edited or
summarized — a whole-entry MOVE into an archive is the only permitted
operation. When this file grows past ~120 KB, roll the oldest full
entries into a new archive file and extend the index.

**Why**: this file is imported into every Claude session's context
(CLAUDE.md references it), and at 262 KB it had become the largest
fixed cost of every session — crowding out the code actually being
worked on. The owner asked for it to stay under 150 KB. The index keeps
discoverability (each title already reads as its own one-line summary);
the full text of any entry is one file-open away, and nothing was
reworded in the move.

**How to apply**: `/decision` keeps appending new entries HERE, at the
bottom, and adds one index line. Citations of "Decision NNN" anywhere in
the repo stay correct — the index says which file holds NNN. Never edit
an archive file except to append a rolled-over entry block, and never
let a summary stand in for the entry itself.

## 093 — A red X is reserved for broken: backstops that published warn, and the auditor never re-alerts a failure that already emailed
*Date: 2026-08-23*

A workflow run fails ONLY when it has nothing to show. Two mechanisms
were failing runs that had done their job, and each red X emailed the
owner. (1) The step-timeout BACKSTOPS on `word-index` and
`free-subtitles` are now `continue-on-error`; a final verdict step fails
the run only when the backstop fired AND the published output did not
grow (the guard's row counts / the asset-file count are the evidence).
A backstop that fired on a run whose work still published leaves a
`::warning::` annotation instead. (2) `audit_workflow_health.py` no
longer exits 1 over a FAILED finding — that run's own red X already
emailed the owner, so the auditor's daily re-fail was a duplicate alert
repeated until the fix landed. Its urgent set is now exactly the
failures NOTHING ELSE alerts for: BROKEN (green but produced nothing)
and KILLED (cancelled with publish skipped — GitHub never emails about
cancelled runs). FAILED and STALE stay in the report.

**Why**: the owner asked to stop getting alerts for failed actions —
"if it isn't broken, it doesn't fail." Last week's failure emails were
Workflow health daily since 08-17, word-index three times, free-subs
once; every one was either a duplicate of an alert already sent or a
backstop timeout on a run that published its work (the 08-22 word-index
"failure" grew the index 373,516 → 484,848 words). An alert channel
that cries wolf daily is an alert channel the owner mutes — and then a
real break goes unread. Fewer, truer alerts protect the signal.

**How to apply**: when adding a compute step with a timeout backstop
ahead of an `always()` publish, pair it with a verdict step: backstop
fired + output grew → warn; backstop fired + nothing grew → fail. Never
let the verdict pass on a publish-step failure (a guard refusal or
upload error still fails the run through the publish step itself). In
the auditor, never add a severity to URGENT_SEVERITIES if the
underlying event already produces its own GitHub email — report it, and
let the one alert be the alert. The summary is still written on every
run for the findings that do not fail it.

**Consequences**: a genuinely hung-from-the-start run still goes red
(nothing grew). A backstop that fires repeatedly while publishing shows
up as warnings and in the health summary, not the inbox — if that
pattern needs escalation later, the verdict step is where a
consecutive-firing counter would go.

## 094 — Fleet hardening: stock index guarded and .zz-only, no unguarded restores, budgets everywhere, the big lock holder split
*Date: 2026-08-23*

A fleet-wide pass applying this repo's own decisions to every workflow
that had not yet received them, driven by a full audit of failure modes
and timing headroom. Five coordinated changes:

1. **The stock index gets the Decision-089 treatment it was missing.**
   `stock-index.yml` and `stock-tags.yml` restored `clips.sqlite` with
   `|| echo "first run"` — the EXACT swallow that let subtitle-index
   rebuild over a missing asset and destroy 702k word timings — and had
   no `sqlite_publish_guard` anywhere. Both now treat only a
   NON-EXISTENT release as a first run, snapshot row counts after
   restore, and refuse a shrunken publish. They also upload **only the
   .zz**: the raw 265 MB `clips.sqlite` member had no consumer (the
   Creation Studio downloads the .zz — verified in `StockIndex.swift`),
   and re-uploading a large raw member after `--clobber`'s delete is
   the exact failure that vanished the subtitle-index assets. The
   publish step retires the stale raw member once, self-healing.

2. **No restore is swallowed anywhere.** `deploy-pages.yml`'s
   `|| true` on the subs tarball meant one transient failure shipped a
   site with ZERO subtitle files — Pages then serves 404.html as VTT
   with HTTP 200 (measured 2026-08-09) until the next deploy. It now
   refuses: an old site beats a subtitle-less one, and deploys run many
   times a day so a refusal self-heals.

3. **Budgets that publish, wired where only timeouts stood** (Decisions
   057/091/093). `batch_covers.py` and `sync_subtitles_audio.py` gained
   `--max-minutes`; `cover-generation`, `subtitle-sync` and
   `stock-tags` gained the backstop-plus-verdict shape: budget stops
   the tool cleanly, the step timeout is a continue-on-error backstop,
   and a verdict step fails the run only when nothing was produced.
   `subtitle-sync`'s verdicts upload is retry-wrapped — it was the one
   un-retried `--clobber` in the fleet, on the resume ledger of all
   things.

4. **The biggest lock holder is split** (Decision 066).
   `cover-generation` held `catalog-writers` ~51 minutes DAILY — the
   largest steady hold, and the reason TMDb enrich measured a
   673-minute queue wait for a one-minute job. It now computes with no
   lock and applies a field-level delta in ~2 minutes. The Sunday
   pile-up (tv-canonical's 113m hold + community-signals at 09:00) is
   staggered: community-signals moved to Saturday.

5. **Best-effort steps are never silent.** The four `|| true` tool
   swallows (omdb-backfill — the workflow that once sat green with an
   EMPTY secret because of this exact pattern — discover-content's LoC
   feed, both resource-posters validators) now annotate a `::warning::`
   on failure instead of discarding the exit code.

**Why**: the owner asked for workflows "best engineered and least
likely to fail or take longer than their timeouts." The audit found the
patterns this repo has already paid for — the 089 swallow, the 057
timeout-kill, the 066 lock hold — each alive in workflows the original
fixes never reached. A rule that lives only in the workflow where its
incident happened is a rule the next workflow re-learns the expensive
way.

**How to apply**: a new workflow that appends to a shared SQLite index
MUST snapshot-and-check with `sqlite_publish_guard` and restore from
the .zz; never upload a raw multi-hundred-MB member. A new restore step
treats only release-nonexistence as first-run. A new long compute gets
a `--max-minutes` budget measured from process start, a backstop step
timeout with `continue-on-error`, and a produced-nothing verdict. A new
catalog writer starts life split (Decision 066) — compute unlocked,
apply short. `check_workflow_gates.py` validates the split shape; run
it after touching any apply job.

**Consequences**: remaining known holders of `catalog-writers` for
whole runs are small (rights-audit ~5m daily, match-unmatched ~4m
weekly, detect-trailers ~21m weekly, tv-canonical ~113m weekly — the
one Decision 066 flags as needing care, deliberately not converted
here). The stale raw `clips.sqlite` disappears on the next stock
publish; verified no in-flight or sweeper-eligible old-code stock runs
existed at merge time, so no old restore can meet the deleted asset.

## 095 — Queue displacement happens at JOB granularity too; the sweeper re-runs only zero-step jobs
*Date: 2026-08-24*

Amends Decision 057. The Decision-066 split created a new displacement
shape: a run's compute job succeeds and banks its deltas as an
artifact, and only its short `apply` job — pending on `catalog-writers`
— is destroyed when a newer arrival joins the queue (GitHub keeps ONE
pending job per group). `retry_infra_failures.py` now classifies a
cancelled run by SHAPE: no job ever ran a step → full `rerun`; some
jobs succeeded and every non-successful job has ZERO steps →
`rerun-failed-jobs`, which re-runs only the displaced jobs against the
banked artifact. A cancelled job that ran any step is still never
touched.

**Why**: measured 2026-08-24 — codec-audit's probe succeeded in 4
minutes, its 2-minute apply sat 70 minutes pending behind
discover-content's whole-run lock hold, and at the second the lock
freed, Monday's rebuild-catalog arrival displaced it. TMDb enrich was
displaced the same morning as a WHOLE run and healed automatically; the
codec run did not, because the sweeper's gate ("no job has any steps")
read the successful probe as a human-cancelled running job. Workflow
health then correctly failed over it — a KILLED run is the class
nothing else alerts — which is the email this fixes at the source.
Verified live: the dry run flagged exactly the stranded run and nothing
else; the real run re-ran only the apply job (probe untouched,
artifact consumed) to green.

**How to apply**: the no-side-effect guarantee is per-JOB: a job with
zero steps never did anything, whatever the run around it did. Never
widen the gate to re-run a cancelled job that has steps. This heals
displaced applies within a sweep tick; it does not reduce displacement
itself — that pressure drops as the remaining whole-run holders
(discover-content and omdb-backfill are the long ones left, ~1-2h
each; they also push to main, so their split needs care) convert per
Decision 066.

## 096 — tvOS stays ENGINE-led: the system's generated captions are proven only on clean audio, and the plain path they require re-imports a measured disease
*Date: 2026-08-27*

The system-leads pivot proposed on 2026-08-26 (after the on-device probe
showed Apple's generated track EMITTING on all three asset shapes) is
DECLINED. tvOS keeps Decision 072's single pipeline: every title through
ResilientStreamLoader, our engine captioning the uncaptioned, the system
track untouched.

**Why**: three measurements, taken together, decide it. (1) The probe's
emission evidence comes from the bundled 60-second narration clip — clean,
modern audio. On REAL archival films the same generation feature, measured
on macOS 27 (Decision 063), was offered on three films and emitted on ONE,
declining rough optical sound rather than guessing. A system-led tvOS would
leave the majority of uncaptioned films captionless behind a watchdog
delay. (2) The only full-film asset shape the system will caption is the
plain URL (the HLS wrapper is Decision 070's memory bomb; the loopback
proxy is Decision 082's intermittent mediaserverd reach), and the plain
path re-imports the Decision-021 disease the owner personally watched —
idle resets flushing the buffer, mid-film player rebuilds — which is
exactly why 072 retired it. (3) The engine it would displace now has
MEASURED timing: the 2026-08-26 sweep's caption_timing_vs_truth runs
median within a second on healthy segments, with the envelope-only
correction configuration proven across nine device iterations.

**How to apply**: do not re-enable `SystemCaptions.prefersDirectPlayback`
on tvOS while these three facts stand. The machinery stays
(selectIfWanted / emitsCaptions / handOver are used by the diagnostics
probe and the iOS/macOS paths, where the system IS the lead per
docs/CAPTIONS.md). REOPEN CONDITIONS, any one of which reopens the
question: evidence of system emission on real archival audio (extend
Caption Diagnostics with a real-film shape to gather it cheaply); a
resilient asset shape the system will caption (a proxy that passes
Decision 082's reachability bar, or an OS change accepting
custom-scheme assets); or the engine's quality materially regressing.
The Fireplace-class hardware constraint is permanent regardless: engine
fallback for tvOS 26 and non-generating devices is not transitional.


## 097 — A hero never reshapes its art: fit at the image's OWN aspect over an ambient wash, and Home shows professional posters only
*Date: 2026-08-31*

Two rules, one for every platform. (1) A Detail/series hero may crop only a
real landscape `backdropURL`. With no backdrop it renders `posterURL` WHOLE —
`ContentScale.Fit` / `contentMode: .fit` inside a 2:3 frame — over an ambient
crop-filled wash of the same art, drawn ABOVE the scrim. (2) Home shelves are
gated on `hasProfessionalArtwork`, never the weaker `hasDesignedArtwork`.

**Why**: the owner on the Fire TV — "the poster at the top of every individual
detail is poorly proportioned and very often cropped terribly (or not using the
professional poster at all)". `TvDetailScreen` did
`BackdropImage(url = backdropURL ?: posterURL)` with `ContentScale.Crop` into a
400dp full-width box (~2.4:1). Measured against the published catalog:

    no backdrop at all                      26,611 of 31,047   85.7%
      ...carrying a PROFESSIONAL poster     12,431             40.0%
    backdrop present but generated art           7

So a 2:3 poster was center-cropped to a horizontal sliver on the large majority
of Detail screens — The Ten Commandments, Suddenly, Reefer Madness, Caligari.
"Not using the professional poster" was the same bug: a sixth of a poster is
unrecognizable as one.

**Catalog art does NOT have one shape.** A first pass assumed 2:3 everywhere —
generated covers really are 600x900 and TMDb w500 is 500x750 — and forced the
hero into a 2:3 frame. On the device that letterboxed a landscape Commons still
inside a floating black box. Measured properly (5 samples per source, w/h):

    tmdb .67  omdb .68  tvdb .68  fanart .70  external .68  series .68
    generated .67        <- our frame covers ARE poster-shaped
    commons  .67-1.38    archive 1.28-1.76    wikidata 1.33-2.37   tvmaze .68-1.5

So `posterURL` is a poster for most sources and an arbitrary landscape still for
commons / archive / wikidata. The rule is therefore not "2:3" but "never reshape
it": `ContentScale.Fit`, height-bounded, width from the image's own intrinsic
size, so a poster stays a poster and a still stays a still.

**How to apply**: never pass art to a box that reshapes it — not a wide
crop-scaled box, and not a 2:3 frame either. `backdropURL
?: posterURL` is a bug wherever the destination is not the poster's own aspect —
it was live in five Android surfaces (TV Detail, phone Detail, series Detail,
search thumb at 96x54, and harmlessly in the TV Home hero, whose pool already
requires a backdrop). Draw the fit poster ABOVE the scrim: these scrims end
fully opaque, so a poster under one loses its bottom third. Gate Home on
`hasProfessionalArtwork` — `hasDesignedArtwork` still admits our frame covers,
which is what Public Domain Day was doing on tvOS, iOS and Android. Do NOT gate
user FAVORITES that way: those are the viewer's own titles, and hiding one for
its artwork is a different thing entirely from curating a shelf.

**Consequences**: Apple and web already followed both rules (iOS fixed
2026-06-11, web `isPro` throughout) — Android carried essentially all of the
defect, which is why it surfaced on the Fire TV. A shelf that cannot field 6
professional posters now hides rather than pad itself with frame grabs.

## 098 — SharePlay coordinates by archiveID, listens from launch, and never lets "Watch Together" play alone
*Date: 2026-09-01*

Watch Together ships on tvOS, iOS and macOS over one shared
`WatchTogether` service. Four rules bind it, each of which was a defect
first: the playback coordinator identifies content by **archiveID**, never
by URL; `listen()` is attached to a view present from the **first frame**,
never one gated on the catalog; a stall **suspends** the group centrally
from `attach`; and a share action resolves to a three-case outcome so it
can never fall through to solo playback. The binding detail lives in
`docs/SHAREPLAY.md`.

**Why**: each rule has a measured failure behind it.

*Identity.* Every title plays through a private `aw-stream://` URL
(Decision 072), and Decision 077 can swap to a different archive.org copy
mid-film — so two participants essentially never hold the same URL. Apple
documents `identifierForPlayerItem` for exactly this: it exists "to
establish identity of two items created from different URLs".

*Launch.* The owner moved a live call from the iPad to the Apple TV and
"the call dropped and the shareplay ended". `listen()` was attached to the
view that appears once `store.isReady`, and a continuation **cold-launches**
the app — so the TV sat on "Loading catalog…" reading a ~74 MB file with no
listener running, during precisely the window the system was handing the
session over. The same gate existed on iOS with a second edge: `pendingJoin`
can be set before the router exists, and `onChange` only fires for changes
it was present for, so the continuation case was the one it could miss.

*Stalls.* `beginStallSuspension` was public and **called by nothing, on any
platform**. Every player received a coordinator and none ever suspended it,
so a buffering viewer drifted out of sync instead of the group waiting —
on a catalog whose streams stall often enough to justify Decisions
021/031/034/077.

*Outcome.* `prepareForActivation()` answers `.activationDisabled` outside a
call. Returning a Bool there meant the film simply played: "If I start from
Archive watch and then select 'Watch Together' without a call being live, it
just plays the movie." A Bool cannot say WHY nothing happened, and "nothing
happened" is the one outcome a viewer must never be left with.

**How to apply**: never answer the coordinator delegate with a URL or
anything derived from the copy currently in hand — an unknown id returns a
fresh UUID, which correctly means "not the same content", because a group
that refuses to sync beats one syncing two different films. Never gate the
session listener on data loading; resolving the FILM may wait, joining the
SESSION may not, and any join router is keyed on the catalog version rather
than `onChange` alone. Never pass the caption scout to `attach` — it runs
muted at 2× (Decisions 058/069/072) and would drag the group with it. Do not
reach for Decision 051's AirPlay URL swap: AirPlay needs the RECEIVER to
fetch the media, while coordination exchanges only rate and time and each
participant loads its own asset. And keep stall bracketing in the shared
service, not in three players — the observer binds `object: nil` plus an
identity check on purpose, since an observer bound to the item seen at attach
time goes quiet on exactly the Decision-077 swap that follows a bad stall.

**Consequences**: `GroupActivitySharingController` — the system sheet that
picks people and PLACES the call — exists on UIKit and AppKit but **not on
tvOS** (checked in the 27.0 SDK), so the Apple TV explains rather than offers,
and the two kits differ in shape: UIKit presents a `UIViewController` and
reads `result` after dismissal, AppKit presents an `NSViewController` as a
sheet whose async `result` can simply be awaited. Verified end to end on real
hardware: a call started from the iPhone app, the film in sync on the iPad,
and the session surviving continuation to the Apple TV. Two things remain
unverified — the suspension path under a genuinely throttled network, and the
tvOS "start a call first" alert on the glass.

## 099 — Downloads are a background URLSession into Application Support; a downloaded film plays as a plain local file, and tvOS gets none
*Date: 2026-09-01*

Offline viewing ships on iOS, iPadOS and macOS. A film is fetched by a
**background `URLSession`** into **Application Support**, marked
`isExcludedFromBackup`, and played as a plain `AVPlayerItem(url: fileURL)`.
The viewer picks WHICH copy from the item's real file list. **tvOS gets
nothing**, deliberately. `DownloadedFilm` is the app's first device-local,
never-synced model.

**Why**, one constraint at a time — each of these ruled out the obvious
alternative:

*Not `AVAssetDownloadTask`.* Apple's asset downloader is HLS-only: it
consumes a playlist and produces a `.movpkg`, and does not accept a
progressive MP4 at all. Every film in this catalog is a progressive MP4 on
archive.org — the entire subject of Decisions 021/031/034. So the native path
for THIS catalog is `URLSessionConfiguration.background`, which hands the
transfer to `nsurlsessiond`: it runs while the app is suspended and finishes
even if the app is killed, relaunching us into `.backgroundTask(.urlSession:)`
to be told. A foreground session cannot survive a 900 MB film over airport
wifi and a locked phone.

*Not Caches.* Apple's data-storage guidelines put re-downloadable content the
user expects offline in Application Support with the backup exclusion. Caches
is purgeable — the system may delete a file between launches — which for this
feature means the film packed for a flight is gone at 30,000 feet. The
exclusion is not optional either: a 900 MB public-domain film in someone's
iCloud backup is a rejection.

*Nothing on tvOS, and this is permanent.* Apple TV gives an app a purgeable
Caches directory and ~500 KB of durable storage via `NSUserDefaults`; there is
no Documents directory at all. The `SubtitleStore` comment in this repo
already records the constraint. A download there is a promise the platform
will not let us keep, and an Apple TV is a plugged-in, always-connected device
in the first place. PARITY carries 🚫 with this reason, not ⏳.

*A local file gets none of the resilience machinery.* `ResilientStreamLoader`,
node pinning, failover and the stall watchdog all exist to survive a
connection archive.org keeps dropping. A `file://` URL has no connection to
lose, so the downloaded path is checked FIRST and is a bare
`AVPlayerItem(url:)` — the one carve-out from iOS-DESIGN §11.5, which governs
REMOTE video.

*Subtitles are rendered, not wrapped.* Everything else here puts a subtitle
track in front of AVKit as an HLS rendition, to get the native CC menu
(Decision 039). That shape cannot be reused: the master's video rendition is
an https URL to archive.org, and offline there is no archive.org — the whole
asset fails, not just the captions. Rewriting the segment to the local path is
an HLS shape nothing in this project has ever run, and Decisions 054 and 065
were both spent on exactly that class of unverified player shape. So a
downloaded film draws its downloaded WebVTT through the SAME overlay label the
caption engine has drawn into since Decision 070, selected by the caption-type
control that already exists so the two can never both draw.

*The copy picker shows real file facts.* `ArchiveVersions` already lists every
transfer on the item with its size; the sheet shows "480p · H.264 · 575 MB —
Archive derivative", not "Standard" and "High". On a phone with 9 GB free the
difference between a 2.4 GB uploader original and a 575 MB derivative IS the
decision, and the honest thing about the Archive is that a film exists there
in several conditions.

**How to apply**: ask `OfflineLibrary.videoURL(for:)` — the FILE SYSTEM —
whether a film is downloaded; never a `DownloadedFilm` row, which can outlive
its file (a restore, a Mac user in Finder). A transfer in flight writes to
`.partial` and is renamed only on success, so the presence of the final name
IS the completion signal and a half-file can never reach the player. Move the
temp file inside `didFinishDownloadingTo`, synchronously — it is deleted the
moment that method returns. Carry task identity in `taskDescription`: it is
the only thing the system restores across a process death. Do NOT add
predictive or automatic downloading of any kind (iOS-DESIGN §11.19) — the
viewer chooses what they carry, which is the whole learning-orientation case
for the feature.

**Consequences**: `DownloadedFilm` establishes iOS-DESIGN §9.7 — a model
naming a file on one device is never synced, and a bare `ctx.delete` is
correct for it, the single exception to §9.4. The app now asks whether there
is a network at all (`NetworkMonitor`, `NWPathMonitor`) and says so in one
banner; nothing GATES playback on it, because a monitor reports `.satisfied`
for a captive portal that serves nothing. Android parity is a follow-up over
Media3's `DownloadManager`, which does accept progressive MP4. Web is out of
scope: browser storage quota will not hold a feature film.

**NOT YET VERIFIED ON DEVICE**: a full download and offline playback on real
hardware, the background-relaunch path, and the downloaded-WebVTT overlay. All
three build green on iOS and macOS; none has been on the glass.
