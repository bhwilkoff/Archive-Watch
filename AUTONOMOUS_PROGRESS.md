# Autonomous Loop — Database Health + App Stability

Started 2026-07-18. Owner directive:

> "significant work on both the database health (videos that don't play, issues
> with metadata having the wrong title/description/length/category) as well as
> multiple instances of the app not functioning as expected after a long period
> of not using the app (screens not refreshing, account not syncing) … Every
> video should have the exact right metadata and it should also play every
> single time (otherwise it should not be available on the app and should
> certainly not be highlighted on the home screen) … ship new app versions
> across all platforms at the end of the loop."

Two workstreams — **DATA** (catalog health) and **APP** (stability/performance)
— run on one alternating cadence, converging on a cross-platform release wave.

---

## Cadence

```
tick % 6  →  workstream
  0       →  DATA — playability verification (coverage + hard gate)
  1       →  APP  — cold-resume / refresh / sync defect (Apple: tvOS+iOS+macOS)
  2       →  DATA — metadata correctness (runtime, synopsis, contentType, title)
  3       →  APP  — same defect class, Android + web parity
  4       →  DATA — shelf-quality gate + measurement re-run
  5       →  OPT  — net-remove lines; re-measure both scorecards
```

Every **3rd cycle** (ticks 17, 35, 53 …) the opt tick becomes a **RELEASE WAVE**:
ship all five platforms if — and only if — the exit criteria below are met.

One tick = one commit = one push = one CI run. Never batch.

---

## Exit criteria (must ALL be green to ship a release wave)

Baseline measured 2026-07-18 against the published `catalog.sqlite` (32,106
items, 21,860 on shelves); "now" re-measured after tick 12.

### DATA
| Metric | Baseline | Now | Gate |
|---|---|---|---|
| Shelf items byte-verified playable | 0 (marker didn't exist) | **14,146 / 21,825 (65%)** | ≥95%, re-verified within 90d |
| Unverified items on hero / community shelves | unbounded | **0 — gated (ticks 10, 12)** | 0 |
| Items missing runtime | 5,408 (17%) | **2,212** — shelf items **2%** | ✅ **MET** (≤3% of shelf items) |
| Items missing year | 5,409 | **5,168** | — |
| Empty synopsis | 4,763 (15%) | 4,763 | ~~≤5%~~ **NOT ACHIEVABLE — see tick 14** |
| Stub synopsis (<80 chars) | 3,940 (12%) | 3,940 | ~~≤10%~~ **NOT ACHIEVABLE — see tick 14** |
| contentType audited against real signals | never | never | audit shipped + applied |

Titles were already clean at baseline (168 suspicious of 32k — Decision 043
held), so they are not a gate. `documentary` (9 items) and `trailer` (10) are
near-dead categories; 1,511 `tv-special` is known orphan-episode residue
(Decisions 035/036) — both tracked as D7, not gates.

### APP — ✅ COMPLETE (ticks 1, 3, 7, 9, 11)
Every defect A1–A8 from the tick-0 audit is fixed on every platform that had it.
A resumed app now re-checks the catalog, re-queries its views, and re-syncs the
account; the editorial layer refreshes without an App Store release.

---

## Backlog

Populated from the tick-0 audits. Pulled in cadence order. `✅ shipped ·
⏳ open · 🔮 later`.

### DATA — why videos don't play, and why they still reach Home

**Root cause of "offending titles on the home screen":** `downloadURL` is not a
column in `items` (`build_sqlite.py:509-521`) — it lives only inside the
`item_json` blob. **No shelf/hero/browse SQL query can filter on playability,
so none does.** `shelf()`, `hiddenGems()`, `topRated()`, `mostDiscussed()`,
`communityFavorites()`, `watchingNow()`, `browseSQL()` and `randomPlayable()`
in `CatalogDB.swift` gate on artwork, votes and rights — never on whether the
video plays. Hero (`HomeView.swift:49-64`) is the same. Only *episodes* check
for a URL (`build_sqlite.py:590,738`).

**And verification never touches the bytes:** `check_liveness.py:64` fetches
`archive.org/metadata/{id}` only — no HEAD, no ranged GET, no content-type, no
codec. `archive_lib.pick_video:39-68` ranks derivatives by *filename extension
and format string*. A 0-byte or corrupt `.mp4` passes every gate we have.

| # | Item | State |
|---|---|---|
| D1 | ✅ Byte-level playability probe — ranged `bytes=0-1023` GET in `check_liveness`, assert 200/206 + `video/*` + `ftyp`/`moov`. Mirrors the pattern `validate_posters.py:76-77` already uses for images. | ✅ tick 2 |
| D2 | ✅ Add `playable` (and `downloadURL`) as real `items` columns in `build_sqlite.py` so queries *can* gate. | ✅ tick 6 |
| D3 | 🟡 Flip the gate: `playable=1` required on hero + all Home/community shelves + `randomPlayable()`. **Only after D1 coverage ≥95%** — flipping early empties Home. | 🟡 **hero gated tick 10** (its pool is small + popularity-skewed, so 244 verified candidates ≫ the 7 shown); broad shelves still pending coverage |
| D4 | ✅ Re-probe cadence: `livenessChecked` is a one-time marker today, so a URL that dies *after* its check is never re-probed. Add a 90-day TTL re-sweep. | ✅ tick 2 |
| D5 | ✅ Runtime truth — **nothing validates runtime against the file.** `remediate_catalog.py:352-357` says so outright. ffprobe the popularity head, write `trueRuntimeSeconds`, flag \|Δ\| > 20%. Closest existing proxy is `detect_trailers.py:46-60`. | ✅ tick 4 (no ffprobe needed — Archive's own file `length` is the authority) |
| D6 | Synopsis gap: 4,763 empty + 3,940 stubs. **Tick 14: NOT a coverage push — no source exists.** 98.5% of empty-synopsis items have no external ID; 78% of playable episodes have no spine overview and TVmaze doesn't have them either (Murphy Brown 5%, Four Star Playhouse 1%). | ⛔ blocked on data, not effort |
| D7 | 🟡 contentType audit — `documentary` (9 items) and `trailer` (10) are near-dead categories; 1,511 `tv-special` is orphan-episode residue (Decisions 035/036). | 🟡 **form errors fixed tick 16** (520 feature→short on file-verified runtime); **Documentary needs an OWNER decision — see tick 16** |
| D8 | ~~290 items carry no `downloadURL`~~ — **false alarm (tick 8):** all 290 are tv-series CARDS, which are navigational and correctly have no video of their own. 0 non-series items lack a URL. Dropping them would have removed 290 series from the app. | ✅ n/a |
| D9 | `repick_derivatives.py` is wired into **no workflow**. | 🔮 |

### APP — why a resumed app is stale

**Root cause:** `CatalogRefreshService.downloadDatabase()` is correct, but it is
reachable *only* from the once-per-process load path. tvOS `AppStore.swift:196`
sits inside `loadBundledData()`, called from `ContentView.swift:19` in a branch
that renders only while `!isReady` — once the seed DB opens, never again. iOS
`AppStore_iOS.swift:123` is memoized behind a `loadTask` retained forever
(`:100-104`). macOS the same. **A resumed process serves the catalog from its
last cold launch, forever.** The `scenePhase == .active` handlers that already
exist (`ContentView.swift:36`, `RootView_iOS.swift:72`,
`ArchiveWatchApp_macOS.swift:55`) call CloudKit sync — never the catalog.

View invalidation is **not** the bug: `dbGeneration`/`dbVersion` keying is
correct and complete on every platform. There is simply never a second swap.

| # | Defect | Confidence | Platforms |
|---|---|---|---|
| A1 | No catalog refresh on foreground — the reported "screens don't refresh". Needs `refreshIfStale()` + a `lastCheckedAt` TTL (~6h) called from the existing `scenePhase` handlers. | Very high | ✅ tvOS · ✅ iOS · ✅ macOS (tick 1) |
| A2 | Same on Android — `AppContainer.kt:58-63` `start()` runs `catalog.refresh()` once from `onCreate:23-27`. No `ProcessLifecycleOwner`/`ON_RESUME` observer. | Very high | ✅ Android (tick 3) |
| A3 | **`scenePhase` frozen inside the 60s sync loop.** `ContentView.swift:42-49` / `RootView_iOS.swift:76-83` read `scenePhase` *inside* a `.task {}` with no `id:` — the View struct is captured at appear time and never updates. If the view first appears while `.inactive` (common on cold launch), the periodic sync **never fires for the whole session**. One-line fix; silently disables sync today. | High | ✅ tvOS · ✅ iOS (tick 1) |
| A4 | No sync retry/backoff — `CloudKitSyncService.swift:120-122` swallows into `lastError` and waits for the next tick. Combined with A3, a user gets one foreground shot and no retry. **Likely the "account doesn't sync".** | Medium | ✅ all Apple (tick 7) |
| A5 | Web viewer never re-fetches — `watch.js:123-124` `Data.load()` runs once from `boot()`; no `visibilitychange`/`pageshow`/`focus`/`online` listener. | High | ✅ web (tick 3) |
| A6 | `featured.json` is bundle-only (`CatalogLoader.swift:12-20`) — curated shelves and `deprioritizedSeries` can't update without an App Store release. | Medium-high | ✅ all Apple (tick 9) |
| A7 | No `AVAudioSession` interruption observer (`PlayerView_iOS.swift:93-94` activates once). Audio stays dead after a post-background interruption. | Medium | ✅ iOS (tick 7) |
| A8 | Stale SW shell — `sw.js:53-56` cache-first with no revalidation, no `controllerchange` handler. A tab open for days never picks up a new build. | Low-medium | ✅ web (tick 11) |

---

## Tick log

### Tick 0 — 2026-07-18 — SETUP: charter + baseline
- **Context:** loop created. No prior autonomous state for these two workstreams.
- **Implementation:** this file — cadence, exit criteria, measured baseline
  against the live published DB.
- **Verification:** all numbers queried from the released `catalog.sqlite`
  (2026-07-18 16:56Z), not estimated. CI reviewed: all nightly catalog
  workflows green over the last 24h.
- **Next:** tick 1 = **A1 + A3 on Apple** (the two very-high/high-confidence
  defects that directly explain "screens don't refresh" and "account doesn't
  sync", and both are small, contained changes). Tick 2 = **D1** (byte-level
  playability probe), which must bank coverage for several days before D3 can
  flip the Home gate on.

### Sequencing note — why the Home gate can't flip first
D3 is the change the owner asked for literally ("should certainly not be
highlighted on the home screen"). It cannot ship first: only 45% of shelf items
have ever been verified, so gating on `playable=1` today would empty Home. The
order is forced — D1 builds the truth, CI banks coverage over days, D3 flips
the gate once ≥95%. The release wave is what makes all of it visible at once.

### Tick 1 — 2026-07-18 — APP: A1 + A3 on Apple (tvOS · iOS · macOS)
- **Context:** the two highest-confidence cold-resume defects from tick 0.
- **Implementation:**
  - `CatalogRefreshService` — added `lastCheckedAt` persistence, `isStale(ttl:)`,
    and `refreshIfStale(ttl:)` (6h default). `downloadDatabase` gained
    `onlyIfChanged:` so the resume path can distinguish "nothing new" from "here
    is a newer DB" and only bump `dbGeneration` on a real update. A completed
    round trip stamps `lastCheckedAt` even on 304, so the TTL throttles
    *re-checks*, not just re-downloads.
  - `AppStore.refreshCatalogIfStale()` (tvOS) and `AppStore_iOS` twin (iOS+macOS
    share the store) — swap in a newer DB, guarded on already-loaded.
  - Wired into the **existing** `scenePhase == .active` handlers at
    `ContentView.swift`, `RootView_iOS.swift`, `ArchiveWatchApp_macOS.swift`.
    (A1 closed on all three Apple platforms.)
  - **A3:** the 60s sync loops now use `.task(id: scenePhase)` with an early
    `guard`, replacing an unkeyed `.task` that captured `scenePhase` at appear
    time. Previously, if the view first appeared while `.inactive`, periodic
    sync never fired again for the whole session.
- **Verification:** `xcodebuild` BUILD SUCCEEDED on all three — tvOS, iOS
  (generic destinations) and macOS. SourceKit showed the usual phantom
  "Cannot find type in scope" cascade; ignored per CLAUDE.md, and the real
  compiler disagreed. Version 1.3.252 / build 774.
- **Lessons:** build recipe memory was stale — `/Applications/Xcode.app` no
  longer exists (beta only), there is no `ArchiveWatch-iOS` scheme, and a fresh
  Xcode needs `xcodebuild -downloadComponent MetalToolchain` once. Memory
  updated.
- **Next:** tick 2 = **D1**, the byte-level playability probe, which has to
  start banking coverage before D3 can gate Home.

### Tick 2 — 2026-07-18 — DATA: D1 + D4, byte-level playability probe
- **Context:** metadata liveness was never playability. `check_liveness` read
  `archive.org/metadata/{id}` and trusted that a *listed* derivative plays; a
  0-byte, truncated, or error-page `.mp4` passed every gate until a user hit play.
- **Implementation** (`tools/check_liveness.py`):
  - `probe_playable()` — ranged `bytes=0-1023` GET of the real video. Fails on
    404/410 on the file, a 0-byte body, an HTML/JSON error page, or a container
    signature that doesn't match the extension (`ftyp` for mp4/m4v, EBML for
    mkv/webm, `OggS`, `RIFF`). Unknown extensions are never failed for lack of a
    signature. Reads at most 1 KB then closes — a node that ignores `Range`
    answers 200 with the WHOLE file, so an uncapped stream would pull GBs/item.
  - New `unplayable` verdict → the same reversible `excluded` + `playbackDead`
    mechanism as a dead item; recovery clears it if the item comes back.
  - `playbackVerified` / `playbackCheckedAt` are markers **independent** of
    `livenessChecked`, so the whole metadata-only back catalog is re-queued for a
    first byte probe. **D4:** `--reprobe-days 90` re-verifies afterwards — a URL
    that dies *after* its check would otherwise never be re-probed.
  - Workflow moved weekly → **daily** (a ~22k backlog at 8k/run), with
    `no_probe` / `reprobe_days` dispatch inputs.
- **Verification:** probed 12 real popular catalog URLs — 11 verified, 1 left as
  transient (a genuinely unresponsive `dn600301.us` node, confirmed by hand), and
  a deliberately-missing file correctly failed with `derivative_http_404`. Then
  ran the real tool end-to-end on a 40-item catalog built from the live DB:
  **35 verified, 5 left for retry, 0 excluded** — the intended conservative
  behavior (never wrongly hide). Python + workflow YAML both parse.
- **Note:** archive.org answers **503**, not 404, for a missing item on the
  download path, so only a 404/410 on the *file* is treated as definitive.
- **Next:** tick 3 = APP, A2 + A5 (Android `ProcessLifecycleOwner` resume refresh
  and the web viewer's missing `visibilitychange` re-fetch) — the same defect
  class as tick 1, on the two platforms that still have it.

### Tick 3 — 2026-07-18 — APP: A2 + A5, resume refresh on Android + web
- **Context:** same defect class as tick 1, on the two platforms that still had
  it. Closes A1/A2/A5 across all five platforms.
- **Implementation:**
  - **Android** — `CatalogRepository` gained `isStale()` / `refreshIfStale()` on
    a 6h TTL backed by a `catalog.lastcheck` file, stamped on any completed
    round trip (including 304) so the TTL throttles *re-checks*, not just
    re-downloads. `AppContainer.observeForeground()` registers a
    `ProcessLifecycleOwner` `DefaultLifecycleObserver` whose `onStart` refreshes
    — previously `start()` from `Application.onCreate` was the only caller of
    `refresh()`, so a process Android kept alive across days of non-use served
    its cold-start catalog forever. Added the `lifecycle-process` dependency.
  - **Web** — `Data.loadedAt` + `Data.reloadIfStale()`, driven by
    `visibilitychange` / `pageshow` / `online` listeners in `boot()`. `load()`
    now clears `byID` first so a reload re-populates rather than accumulating.
    The re-render is **skipped while `<dialog id="player">` is open** so a
    refresh can never interrupt playback; data still updates and the next
    `route()` picks it up. A re-entrancy guard stops overlapping resumes.
- **Verification:** Android `assembleDebug` BUILD SUCCESSFUL; `watch.js` and
  `sw.js` both parse under `new Function(...)`. Confirmed from `sw.js:30-50`
  that the SW is **network-first for data URLs**, so the web re-fetch really
  does get fresh bytes — A5 was purely a missing listener, not a caching bug.
- **Next:** tick 4 = DATA. Read the finished liveness run's numbers, then D5
  (runtime truth via ffprobe) — the last uncovered metadata field.

### Tick 4 — 2026-07-18 — DATA: D5, runtime truth from the file itself
- **Context:** runtime was the one metadata field with NO correctness check
  anywhere — `remediate_catalog.py:352-357` says so in its own comment, and
  suggests "a CI file probe".
- **Key finding — no ffprobe pass was needed.** archive.org derives every
  derivative's `length` from the file at ingest, so the authoritative duration
  is already in the metadata `check_liveness` **was already fetching**, via a
  helper (`archive_lib.runtime_from_file`) it already called — but only when
  repointing a URL. Reconciling runtime is therefore nearly free, and rides the
  same daily cadence + 90-day re-probe as the playability check, so it
  self-heals instead of needing its own workflow.
- **Measured before building:** of 45 popular titles, 42 agreed with the file
  (≤25%), **2 were badly wrong** — `ThePinkPanther-cartoons` claimed 115 min
  over a 25 min file; `utopia` claimed 82 min over a 142 min file. ~4.5% drift
  plus 5,118 playable items with no runtime at all.
- **Implementation:** `apply_file_runtime()` records `fileRuntimeSeconds` on
  every alive item, fills a missing runtime, and corrects one that disagrees by
  >`RUNTIME_DRIFT` (25%), keeping the prior value in `runtimeWasSeconds` and
  stamping `runtimeSource="archive_file"`. The file wins because it is what the
  user actually watches — a catalog runtime matched from an external record may
  describe a different cut, or a different film.
- **Three defects caught in my own change before shipping:** the temp carrier
  key leaked into the catalog on the `unplayable` path (now popped on any
  non-alive verdict); `tally` was incremented off-lock from 12 threads (Counter
  `+=` isn't atomic — now under the existing lock); and the repoint path
  re-assigned `runtimeSeconds` from the same file, overwriting the reconciled
  value.
- **Verification:** end-to-end on 25 live items with two seeded controls — a
  wiped runtime and a bogus 99999. Result: 2 filled, 3 corrected, 0 leaks,
  25/25 carrying `fileRuntimeSeconds`. Spot-checked against reality: His Girl
  Friday filled to 5504s (actual 92 min), the 99999 corrected to 664s.
- **Next:** tick 5 = OPT — re-measure both scorecards against the freshly
  published DB once the liveness run lands, and net-remove lines.

### Tick 5 — 2026-07-18 — OPT: bound the lock my own change made expensive
- **Context:** the OPT tick's job is to catch what the feature ticks broke. It
  did — in tick 2's own workflow change.
- **The problem:** ticks 2 + 4 roughly doubled the per-item network cost (a byte
  probe on top of the metadata fetch) AND moved the workflow weekly → daily at
  **06:00 UTC**. But every catalog workflow shares one `catalog-writers`
  concurrency lock, and the nightly chain is deliberately ordered:
  `rights-audit 01:10 → validate-posters 02:15 → publish-db 04:30 →
  cover-generation 05:00 → free-subtitles 06:00`. A daily 2–3h job at 06:00
  would collide with free-subtitles and hold the lock across the morning,
  starving the chain that publishes the DB. The in-flight run has now been going
  ~100 min, which is what made the cost concrete.
- **Fix:**
  - `--max-minutes` (CI default **150**) — once the budget is spent, remaining
    items return `skipped_budget` instead of starting new probes, so the run
    finishes cleanly and publishes what it has. Items stay unmarked, so the next
    run resumes them; the tool was already resumable by design.
  - Schedule moved **06:00 → 10:00 UTC**, clear of the ordered chain, with the
    ordering written into the workflow comment so it isn't re-broken.
- **Verification:** ran with `--max-minutes 0.25` over 60 items — 30 processed,
  30 `skipped_budget`, and exactly 30 left unmarked for the next run. 0 temp-key
  leaks. YAML parses; cron confirmed as `0 10 * * *`.
- **Lesson:** a shared concurrency group makes "run it more often" a
  cross-workflow decision, not a local one. Any workflow in `catalog-writers`
  that grows its per-item cost needs a time budget, not just a limit.
- **Next:** tick 6 returns to DATA — D2, adding `playable` as a real `items`
  column so shelf queries *can* gate on it (D3 flips the gate once coverage
  clears the bar).

### Tick 6 — 2026-07-18 — DATA: D2 (`playable` column) + probe prioritisation
- **First real probe results** (run 29664795585, 8,000 items):
  `{alive: 7916, unreachable: 73, unplayable: 10, dead: 1}`. **The byte probe
  caught 10 items that the metadata check called healthy** — the "doesn't play"
  class, previously invisible. Published DB now carries 3,063 verified items.
- **Finding — the probe was spending its budget on invisible copies.** 7,565 of
  the 8,000 probed were IMDb-cluster members, but only 3,063 of 7,916 alive ones
  survived into the DB: cluster members are mostly duplicate uploads that
  `dedupe_by_imdb`/`merge_film_duplicates` merge away. Coverage of what users
  actually see was climbing far slower than the run count suggested. Sort is now
  **shelf-assigned first, then popularity, with cluster membership only as the
  final tiebreak** — the dead-winner-hides-siblings concern is still served
  (metadata liveness is the cheap half), just not ahead of everything a user
  will open.
- **D2:** `items.playable` — promoted out of the `item_json` blob so shelf,
  hero, and browse queries **can** gate at all. Plus a composite
  `idx_items_playable(playable, popularityScore DESC)` matching how every shelf
  query orders. 1 = byte-verified; 0 = has a URL but unproven (episodes are 0 —
  `check_liveness` walks catalog items, not series spines).
- **Two defects caught by actually running the build:**
  `INSERT INTO items` hardcoded `"?" * 29` in **two** places, so the new column
  failed the build outright — the kind of break that would have taken down every
  nightly publish. Replaced with `_insert_many()`, which derives the placeholder
  count from the rows so the next column can't repeat it; then a second pass to
  make it no-op on an empty batch (the hardcoded literal had been accidentally
  safe there).
- **Verification:** real `build_sqlite` run over an 800-item live slice —
  builds clean, `playable=1` count (77) matches `item_json.playbackVerified`
  exactly, index present, and the gate query returns sensible popular titles.
- **Next:** tick 7 = APP (A4 sync retry/backoff, A7 audio-session interruption).
  D3 — the actual Home gate — waits on coverage; at ~14% of shelf items it would
  still empty Home. The re-prioritised daily run is what moves that number.

### Tick 7 — 2026-07-18 — APP: A4 sync retry/backoff + A7 audio interruption
- **A4 — a dropped sync stayed dropped.** `CloudKitSyncService.sync()` caught any
  error into `lastError` and returned; the next attempt was the 60s tick or a
  foreground event. Combined with the (now-fixed) frozen-`scenePhase` bug, a user
  could get exactly ONE attempt per session — the "account doesn't sync"
  symptom. The body moved to a throwing `performSync()`, wrapped in a retry loop
  (3 attempts) that distinguishes transient from permanent:
  `retryDelay(for:attempt:)` honours `CKError.retryAfterSeconds` when CloudKit
  supplies it, else 2s/4s/8s backoff for `.networkUnavailable`, `.networkFailure`,
  `.serviceUnavailable`, `.requestRateLimited`, `.zoneBusy`, `.internalError`, and
  returns nil (don't retry) for permanent ones — not signed in, quota, permission.
  A successful retry clears `lastError`, so Settings stops showing a stale failure.
- **A7 — audio stayed dead after an interruption.** `PlayerView_iOS` activated the
  `.playback` session once at player creation and had **no interruption observer
  anywhere** in the target. A call/alarm/Siri deactivates the session and pauses
  playback; nothing reactivated it, so after an interruption — the common case
  when the app has been backgrounded a while — audio never came back until the
  player was rebuilt. Added the observer next to the existing background/foreground
  pair: on `.ended`, reactivate the session and resume **only** when the system
  sets `.shouldResume`. Torn down with the others.
- **Two compile errors caught by building rather than assuming:** `Notification`
  isn't `Sendable`, so capturing it into `MainActor.assumeIsolated` is a Swift 6
  data-race error — the primitives are now extracted before the isolation
  boundary; and a parameter/usage naming slip (`optionsRaw` vs `optsRaw`).
- **Verification:** BUILD SUCCEEDED on tvOS, iOS, and macOS at 1.3.258 / 780.
- **Next:** tick 8 = DATA. Re-measure playability coverage after the
  re-prioritised daily run, and start D6 (synopsis coverage) or D8 (the 290
  items with no downloadURL) depending on what the numbers show.

### Tick 8 — 2026-07-18 — DATA: year recovery; two backlog items corrected
- **D8 was wrong.** All 290 "no downloadURL" items are tv-series **cards** —
  navigational, no video of their own; 0 non-series items lack a URL. Acting on
  the backlog without checking would have deleted 290 series from the app.
- **Bug found in tick 6's own prioritisation.** The sort keyed on the stored
  `shelves` field, but only **934** of the 21,860 items in the published
  `item_shelves` table have one — the rest are assigned at build time by
  `build_sqlite._shelf_ids_for()` from their COLLECTIONS. So "shelf-first" was
  promoting ~4% of what users see. Now approximates visibility with signals that
  exist in `catalog.json`: designed artwork (the Home/browse gate) then
  popularity (how every shelf orders), cluster membership last.
- **Year: measured a tempting fix and rejected it.** 4,101 shelf items have no
  year. Archive metadata has a `date` for 30/30 sampled — but it is usually the
  **upload** date: `ThePink.Panther1963` reports 2015 for a 1963 film. Filling
  from it would corrupt decade browse *and* could push PD titles into the rights
  audit's post-1978 bucket and hide them. **Not done.**
- **What shipped instead:** `remediate_catalog` already had `source_year()` — a
  vetted extractor (parenthesised years win; `720p`/`1920x1080` stripped so they
  can't pose as years) used only to CORRECT wrong matches, never to FILL a
  missing one. Now it fills when the year is absent, stamping
  `yearSource="source_naming"`. **233 recovered**, decade spread plausible for a
  PD catalog (peaks in the 1930s and 1970s), spot-checks correct
  (`haider-2014`→2014, `grey-gardens-1975`→1975).
- **Also fixed:** a later rule (the B&W-vs-modern wrong-match check) can null a
  year this pass just filled, which left a `yearSource` marker describing a value
  that no longer existed. A sweep at the end of `remediate()` drops those — 3
  observed, now 0.
- **Verification:** full 32k-item catalog run — no-year 5,409 → 5,176, 0 stale
  markers, and the existing 666 title cleanings still fire (no regression).
- **Next:** tick 9 = APP (A6 bundle-only `featured.json`, or A8 SW staleness).
  Then re-measure coverage once the re-prioritised probe run lands.

### Tick 9 — 2026-07-18 — APP: A6, editorial config goes remote
- **Context:** `loadFeatured()` read only the bundled JSON. The catalog refreshed
  daily, but the editorial layer ON TOP of it — curated shelves, category tiles,
  `deprioritizedSeries`, the adult-collection list — was frozen at build time. A
  curation fix could not reach users without an App Store release. That directly
  limits this loop: data improvements land, editorial ones don't.
- **Implementation:** ETag-conditional GET of `archivewatch.org/featured.json`
  with a 6h TTL, cached in Caches, bundled copy as fallback. The payload is
  **decoded before it is cached**, so a malformed or truncated response can never
  replace a good local copy. Wired into the `refreshCatalogIfStale()` resume path
  from tick 1 on all three Apple platforms; when no new DB arrives, the fresh
  `demotedIDs` are re-applied to the live DB with a generation bump so views
  re-query.
- **Verification:** the served file is byte-identical to the repo copy the app
  bundles (12,643 bytes, same 11 top-level keys, `deprioritizedSeries` present),
  so the decode path is proven compatible rather than assumed. BUILD SUCCEEDED on
  tvOS, iOS, macOS at 1.3.260 / 782.
- **Next:** tick 10 = DATA. Re-measure coverage from the re-prioritised run and
  decide whether D3 (the Home playability gate) is close enough to stage behind a
  threshold, or whether coverage needs more days first.

### Tick 10 — 2026-07-18 — DATA: D3 staged — the hero is gated
- **Context:** the full gate is still blocked (~14% shelf coverage), but that
  framing treated all surfaces as one problem. They aren't.
- **Insight:** the hero draws **7** items from a small, popularity-skewed pool —
  and popularity is exactly what the probe prioritises. Measured per popularity
  band on the live DB: top-500 45% verified, top-1000 42%, top-3000 33%. The real
  hero pool (top 3000 ∩ designed art ∩ has backdrop) is 758 candidates, of which
  **244 are already verified** — 35× what the hero shows.
- **Shipped:** the marquee now prefers byte-verified items on tvOS, iOS and
  macOS, with a floor — fall back to the full pool if fewer than 7 qualify, so
  the hero can never go empty. The fallback becomes unreachable as coverage
  climbs; no follow-up needed to "turn it on".
- **Model:** `Catalog.Item.playbackVerified` (optional, so older catalogs decode
  unchanged) + `isPlaybackVerified`.
- **Verification:** BUILD SUCCEEDED on tvOS, iOS, macOS at 1.3.261 / 783.
- **Note:** broad Home shelves and Browse stay ungated deliberately — at 14%
  coverage they'd lose most of their content. They gate in a later tick once the
  daily probe has banked enough, and the same floor pattern applies.
- **Next:** tick 11 = APP (A8, the last open defect) or an opt tick; then
  re-measure once the re-prioritised run publishes.

### Tick 11 — 2026-07-18 — APP: A8, self-healing web shell (LAST stability defect)
- **Context:** the SW served the shell cache-first with no revalidation. Two
  failure modes: a long-open tab never picked up a new build, and a deploy that
  changed `watch.js` **without bumping `SHELL`** froze every existing install
  permanently — nothing ever re-fetched the asset.
- **Implementation:** shell fetches are now stale-while-revalidate — cache
  answers instantly, a background fetch refreshes the entry (kept alive with
  `e.waitUntil`) so the next load is correct without depending on a version bump.
  Data URLs stay network-first. Client side: the registration is retained so the
  tick-3 resume path also calls `reg.update()`, and a `controllerchange` listener
  reloads once so page code matches the controlling worker. **Both guarded on the
  player dialog being closed** — a background update must never kill a film
  mid-playback.
- **Verification:** both files parse; all six `SHELL_URLS` resolve 200 live (one
  404 there rejects `addAll` and the worker never installs at all — worth
  checking explicitly, since the failure is silent).
- **Milestone: the APP workstream is COMPLETE.** A1–A8, every defect from the
  tick-0 audit, fixed across all five platforms.
- **Next:** the loop is now DATA-only. Tick 12 re-measures coverage from the
  budget-bounded run and extends the playability gate from the hero to the
  community shelves as coverage allows.

### Tick 12 — 2026-07-18 — DATA: community shelves gated; targeting fix validated
- **The re-prioritised run proved tick 6's fix.** Same 8,000-item budget, targets
  sorted by visibility instead of cluster membership:
  `{alive: 7507, dead: 127, unplayable: 93, runtime_filled: 1195,
  runtime_corrected: 614, unreachable: 254, skipped_budget: 15}`.
  **220 broken items found vs 11 in the first run — 20× the yield** for the same
  cost, because it stopped probing duplicates that get merged away.
- **Published DB movement:** byte-verified 3,063 → **9,796**; shelf coverage
  13.8% → **44.6%**; no-runtime 5,408 → 4,294; no-year 5,409 → 5,168. The
  `--max-minutes` budget worked as designed (only 15 skipped).
- **Gate extended:** the four community shelves (Top Rated, Most Discussed,
  Community Favorites, Watching Now) now require `playable = 1`. Safe because
  each draws from a population that is 78–88% verified and shows only 24 —
  confirmed against the live DB that all four still return a full 24 gated.
- **Regression guarded:** `playable` postdates shipped builds, so a new app on a
  still-cached older DB would hit "no such column" — and `items()` returns `[]`
  on a failed prepare, which would have **silently emptied these shelves**.
  `CatalogDB` probes the column once at open (`columnExists`) and drops the
  clause when absent. Also hit (and fixed) Swift's "self used before all stored
  properties are initialized" — the probe has to precede the `metaInt` guard.
- **Deliberately NOT gated:** Browse and Search. The full catalog stays
  reachable; only surfaces that SHOWCASE a title are gated.
- **Next:** tick 13 = APP/opt. The APP backlog is empty, so this is an opt tick:
  re-measure, and consider whether Home's generic shelves can gate yet (they draw
  from far larger pools, so they need more coverage than 45%).

### Tick 13 — 2026-07-18 — OPT: seed-DB fallback verified; planning collapsed
- **Audited what ticks 10/12 might have broken.** The bundled `seed.sqlite` —
  what renders FIRST PAINT — has no `playable` column (it predates tick 6).
  Confirmed directly: a gated query against it errors `no such column`. Since
  `items()` returns `[]` on a failed prepare, that would have **silently emptied
  the community shelves on first launch**. Tick 12's `columnExists` probe drops
  the clause instead; the ungated query returns 639 candidates. The guard was
  load-bearing, not defensive padding.
- **And it's permanent, not temporary:** `publish-db` runs `build_sqlite` (which
  builds both DBs) but commits only `catalog-index.json`, `details/`,
  `channel-pools.json`, `episodes-index.json` — **never `seed.sqlite`**. The
  committed seed is from 2026-06-28 and will not gain the column from CI, so
  first paint stays ungated by design until someone regenerates it by hand.
- **Net −11 lines:** the Scorecard section duplicated the exit-criteria baseline
  column and its prose was superseded by tick-12 numbers. Collapsed into one
  baseline/now/gate table; APP marked complete.
- **Next:** tick 14 = DATA. Synopsis is now the largest untouched gap (4,763
  empty + 3,940 stubs, unchanged since baseline) — measure what is actually
  recoverable before building anything, per the tick-8 lesson.

### Tick 14 — 2026-07-18 — DATA: synopsis measured, declared unrecoverable
- **Shipped nothing. That is the finding.** Per the tick-8 lesson, measured
  before building — and no viable source exists.
- **Source 1, external IDs:** of 4,763 empty synopses, **72** have an IMDb ID
  and 33 a TMDb ID. TMDb/OMDb enrichment cannot reach 98.5% of them.
- **Source 2, series spines:** the gap is dominated by `tv-episode` (3,753 of
  8,699). Measured the spines: **3,662 of 4,683 playable episodes (78%) have no
  overview**, concentrated in Murphy Brown (246), Brian Henderson (116), SNL
  (110), Four Star Playhouse (101).
- **Source 3, TVmaze:** doesn't have them either for vintage PD TV — Murphy
  Brown **5%**, Four Star Playhouse **1%**, One Step Beyond 8%, SNL 41%.
  `tools/backfill_tv_episode_meta.py` already exists and is in **no workflow**
  (like `repick_derivatives.py`), but its docstring's "~60% summaries" does not
  hold here: a 12-series run yielded 0 overviews (1 real air date, kept). Wiring
  it would add recurring cost for ~nothing.
- **Criterion corrected:** the tick-0 synopsis gates (≤5% empty, ≤10% stub) are
  **not achievable** with any available source. Marked NOT ACHIEVABLE explicitly
  rather than left in place to silently block every future release wave — I set
  them with less information than I have now, and saying so beats quietly
  relaxing them.
- **Source 4, unevaluated:** archive.org's own `description` field. Could not be
  measured — archive.org is returning **503 site-wide** ("Internet Archive:
  Temporarily Offline"). Genuinely still open; worth a tick when it recovers.
- **The outage validates the conservative design:** 503 is treated as
  unreachable/retry, never as dead. Had it been treated as definitive, a
  site-wide outage would have marked thousands of items dead and hidden them.
- **Next:** tick 15 = APP/opt. DATA's remaining live work is coverage-driven
  (the daily probe) plus D7 (contentType audit); re-check archive.org for the
  description source when it's back.

### Tick 15 — 2026-07-19 — OPT: ran the app (first end-to-end verification)
- **Gap addressed:** everything in ticks 1–14 was build-verified only. The hero
  and shelf gates had never been *observed*. archive.org was still 503, so this
  was the right tick for it (no archive dependency).
- **Verified on the tvOS 26.5 simulator against the real published catalog:**
  - Launches, opens the bundled seed, downloads `catalog.sqlite.zz` from the
    release and swaps in the full DB (confirmed in `os_log`).
  - **Home renders with a full 7-item hero carousel** — tick 10's playability
    gate did not starve it, which is exactly what the floor fallback existed to
    prevent. Verified, not assumed.
  - **Runtime is visibly correct** on the hero: "1969 · 1h 1m · Directed by
    Jesús Franco" — tick 4's reconciliation reaching the UI.
- **Found, NOT fixed — pre-existing DB-swap warning:**
  `BUG IN CLIENT OF libsqlite3.dylib: database integrity compromised by API
  violation: vnode unlinked while in use … Library/Caches/catalog.sqlite`.
  `downloadDatabase` removes the live file while an old `CatalogDB` handle is
  open. Pre-existing (the `mmap_size=0` PRAGMA already guards the related crash
  class) and the app works — but **tick 1 added a second swap path, so it now
  fires more often**. Deserves its own change (open the new DB at a fresh path,
  close the old handle, then unlink), not a hasty re-architecture.
- **Environment limit:** AppleScript key-driving of the focus engine doesn't work
  here (needs Accessibility/TCC grants), so the lower shelves couldn't be
  scrolled to on-sim; the SQL check (24/24 per gated shelf) stands in.
- **Next:** tick 16 = DATA. Re-check archive.org; if up, evaluate its
  `description` field as the last synopsis source. Otherwise take D7
  (contentType audit), which is catalog-local.

### Tick 16 — 2026-07-19 — DATA: D7, 520 objectively wrong content types fixed
- **Context:** archive.org now times out entirely, so this took D7's
  catalog-local half.
- **Enabled by tick 4:** runtime is trustworthy now, which makes an objective
  form error checkable. **520 items typed `feature-film` have a FILE-VERIFIED
  duration under 40 min** (Academy short boundary) — "Malice in the Palace" (15m
  Stooges short), "The Battle Of Midway" (18m), "Hemp for Victory" (13m).
- **Rule discipline:** acts ONLY on `fileRuntimeSeconds` (archive.org's own
  per-derivative length), never on an externally-matched runtime — that is
  exactly the value that can describe a different cut or film. **One-directional:**
  short → feature is NOT safe, since a short-film item with a long file is
  usually a compilation reel.
- **Verified:** feature-film 11,059 → 10,536; short-film 3,578 → 4,097. Inspected
  the risky 37–39m boundary — all genuinely shorts (e.g. "The Hunt for Gollum",
  a 38m fan film).
- **⚠️ OWNER DECISION NEEDED — the Documentary category is starved.** 1,113 items
  carry the Documentary **genre**; only **9** have `contentType='documentary'`,
  so the tile is count-gated off Home (needs ≥30) and documentaries are
  unbrowsable as a category. **Reclassifying is the wrong fix:** `contentType` is
  a FORM axis (silent / feature / short) and Documentary is a GENRE — moving the
  396 silent documentaries would gut Silent Era to fill Documentary. The real
  question is whether that category should resolve **by genre**, which changes
  what a category *means* (partition → overlapping facet). That is IA, not a
  defect, so it is surfaced rather than decided here.
- **Next:** tick 17 = the scheduled RELEASE-WAVE slot. Assess against the exit
  criteria and report honestly which are met; playability coverage (45%) is below
  the 95% gate, so the wave likely slips pending more probe days.

### Tick 17 — 2026-07-19 — RELEASE WAVE: assessed → **HOLD**
| Criterion | Status |
|---|---|
| APP defects A1–A8, all platforms | ✅ complete |
| Unverified titles on hero / community shelves | ✅ **0** |
| contentType form errors | ✅ 520 fixed (tick 16) |
| All five platforms build clean @ 1.3.268/790 | ✅ tvOS · iOS · macOS · Android · web |
| **Shelf playability coverage ≥95%** | ❌ **45%** (9,741/21,841) — binding |
| Synopsis gates | ⛔ not achievable (tick 14) |
| Documentary category | ⚠️ owner decision (tick 16) |

- **Why hold:** coverage is the one binding gap, and it needs more daily probe
  runs. archive.org has been down for hours (503 → timeout → 502), so tonight's
  runs bank little.
- **The distinction worth stating:** the owner's actual complaint — don't
  *highlight* titles that don't play — **is** satisfied, because every surface
  that showcases a title is gated. The 95% criterion was set to allow gating
  Browse too, which is stricter than the complaint. Both are worth having; one
  is done.
- **Not auto-submitting.** Store submission is outward-facing and effectively
  irreversible (App Review, public release), and this project's docs make it
  owner-triggered. Staged so it's one command when wanted.
- **Assessed and deliberately NOT fixed:** `cover-generation.yml` failed tonight
  after **9 consecutive successes** — `no upload log … run upload_covers.py
  first`, i.e. the generate/upload stage produced nothing because archive.org is
  down. Transient collateral, not a defect. Masking the exit code would hide
  real failures later.
- **Next:** tick 18 = DATA. If archive.org is back, the daily 10:00 UTC probe
  resumes banking coverage; otherwise hold and do catalog-local work.

### Tick 18 — 2026-07-19 — APP: fix the DB-swap unlink + a double download
- **Context:** archive.org still 502, so coverage can't move. Took the tick-15
  finding instead — a defect **my own tick-1 change amplified**.
- **Defect 1 — use-after-unlink.** The swap did `removeItem` + `moveItem`,
  unlinking a file the open `CatalogDB` was still reading; libsqlite3 logged
  *"database integrity compromised by API violation: vnode unlinked while in
  use"*. Survivable (the old handle drops moments later) but real — and tick 1's
  second swap path made it routine rather than once-per-launch.
  **Fix:** each download lands in its own generation (`catalog-<stamp>.sqlite`,
  recorded in UserDefaults), so a file anything might be reading is never
  mutated. Superseded generations are swept at the **start of the next
  download**, never during a swap. Bounded at ~2 DBs. The legacy path is still
  read for existing installs and explicitly **protected from the sweep** when no
  generation is recorded — otherwise a just-updated install would delete the file
  it had open, reintroducing the same bug.
- **Defect 2, found while verifying defect 1 — the DB downloaded TWICE.** The
  simulator showed two generations a second apart: on a first launch the
  unconditional launch download AND the tick-1 foreground refresh both fire
  (nothing checked yet ⇒ resume also reads "stale"), pulling ~44 MB twice on
  every fresh install. Added an in-flight guard; the actor serialises the calls
  so the second is a no-op.
- **Verified on a clean install** (uninstall → reinstall → launch): unlink
  warnings **multiple → 0**; catalog generations **2 → 1**. Builds green on
  tvOS, iOS, macOS.
- **Lesson:** verifying a fix on-device found a second, larger defect the fix
  itself didn't cause. Build-verification would have caught neither.
- **Next:** tick 19 = DATA if archive.org is back (the 10:00 UTC probe should
  have run); otherwise hold coverage work and re-measure.

### Tick 19 — 2026-07-19 — DATA: hate propaganda excluded; synopsis question closed
- **archive.org recovered (200)** after ~5h. Dispatched a fresh probe run, then
  closed tick 14's open question.
- **Synopsis — 4th source evaluated, also NOT viable.** Of 25 popular
  empty-synopsis films, only **4** had a usable archive.org `description`, and of
  those: one a note about a defunct website, one a BBFC censorship comparison,
  one **explicit pornographic content**. Low coverage, wrong content type, and
  hazardous to pipe into the UI. **D6 is now blocked on all four sources.**
- **⚠️ The real find — content that isn't film at all.** That sampling surfaced
  uploads that are modern propaganda, not PD cinema. **4 now reversibly
  excluded**: one antisemitic video whose title advertises CSAM, and three
  Holocaust-denial ("holohoax") uploads. All were `contentType='feature-film'`
  with `isAdult=0` — fully browsable and searchable.
- **Word-boundary matching is load-bearing.** A naive substring test for "pedo"
  matches **TORPEDO** and would have excluded six legitimate films (*Torpedo
  Flotilla Visit to Manchester*, *Secret Agent X-9: Torpedo Rendezvous*, the
  Dutch submarine reels). Verified on the full 32k catalog: **4 excluded, all
  correct; 6 torpedo films untouched.**
- **Scope discipline:** markers are narrow phrases that are unambiguous in a
  title — deliberately NOT a general content classifier — and reversible via the
  existing Decision 027 `excluded` flag.
- **Next:** tick 20 = read the probe run, re-measure coverage, and re-assess the
  release wave.

### Tick 20 — 2026-07-19 — DATA: found why coverage stalled — CI starvation
- **Root cause, and it isn't the tool.** Every catalog workflow shares the
  `catalog-writers` concurrency group, and **GitHub keeps only ONE pending run
  per group — a newer arrival supersedes an older pending one.** `check-liveness`
  is long, so queuing behind the morning wave gets it cancelled *before it starts
  a single job*.
- **Evidence:** the 09:43Z dispatch was cancelled with **no jobs ever started**;
  scheduled history shows **2 of the last 4 runs cancelled the same way**
  (07-08 ✗, 07-01 ✗, 07-15 ✓, 06-24 ✓). Roughly half the runs lost, silently —
  which explains a catalog sitting at 31% liveness coverage for months while
  `check_liveness.py` itself was perfectly healthy.
- **Fix:** schedule **10:00 → 13:00 UTC**, clear of every scheduled writer
  (color-classify 00/08/16 · rights-audit 01:10 · validate-posters 02:15 ·
  cover-generation 05:00 · free-subtitles 06:00) *and* of the `publish-db` runs
  each dispatches on completion. `--max-minutes` **150 → 120** so the run plus
  its remediate/publish tail clears before the 16:00 color-classify.
- The full UTC map and the reasoning are in the workflow comment so the slot
  isn't innocently moved back into the morning later.
- **Retrospective:** ticks 2–12 treated coverage as purely a throughput problem
  and kept dispatching runs. Two of those dispatches happened to land in quiet
  windows and worked, which masked the pattern. The right diagnostic —
  *did the run actually start?* — only got asked when one visibly failed.
- **Next:** tick 21 = verify a run completes from the new slot, then re-measure.

### Tick 21 — 2026-07-19 — DATA: four more starved pipelines unblocked
- **Confirmed tick 20's fix first:** a run dispatched into a clear group
  **started a job** (`started_at` set) — where the cancelled one had none. The
  diagnostic that had been missing all along.
- **Then generalised the finding.** Cancellation rate, last 20 runs each:
  | starved | | healthy | |
  |---|---|---|---|
  | detect-trailers | **75%** | rights-audit | 0% |
  | check-liveness | 50% (fixed) | validate-posters | 0% |
  | match-unmatched | 33% | cast-images | 0% |
  | free-subtitles | 30% | tvdb-movies | 0% |
  | subtitles | 25% | wikidata-posters | 0% |
- **Pattern: long jobs in busy slots.** `detect-trailers` (Wed 06:00) collides
  **exactly** with `free-subtitles` (daily 06:00) — same group, same minute, so
  one is always pending and can be superseded before starting.
- **Moved the four starved weeklies** into the evening window, staggered an hour
  apart, clear of color-classify (00/08/16) and the 13:00 liveness run + budget:
  detect-trailers → Wed 18:00 · verify-matches → Tue 19:00 · subtitles →
  Thu 20:00 · match-unmatched → Mon 21:00. `free-subtitles` keeps 06:00 as the
  daily incumbent. Measured rates recorded in each workflow comment.
- **Why this matters beyond CI hygiene:** these are the pipelines that fix
  matches, find trailers, and add subtitles. A quarter to three-quarters of
  their work was being silently discarded — so several "the data isn't
  improving" symptoms were scheduling, not tooling.
- **Next:** tick 22 = read the probe run (started 11:25Z), re-measure coverage.

### Tick 22 — 2026-07-19 — DATA/APP: Android home-surface gate (parity)
- **Gap closed:** the "don't highlight titles that don't play" guarantee shipped
  on tvOS/iOS/macOS (ticks 10/12) but **not Android**, so a broken title could
  still lead a shelf there. The four community shelves now require
  `playable = 1`, mirroring the Apple change clause-for-clause.
- **Same guard as Apple:** `playable` postdates shipped builds, so a new APK on a
  still-cached older DB would throw on every one of these queries.
  `CatalogDatabase` probes `PRAGMA table_info(items)` once at construction —
  reusing the existing `queryRaw` idiom (as `probeItemCount` does, after my first
  attempt used a non-existent `driver` property and a delegate that wouldn't
  infer) — and drops the clause when absent.
- **Verified the probe's assumptions against the live DB** rather than assuming:
  `PRAGMA table_info` column 1 is the column NAME, and `playable` is present
  (cid 29). `assembleDebug` green.
- Browse/Search stay ungated on Android too — full catalog reachable; only
  showcase surfaces gated.
- **Web still ungated:** its flat `catalog-index.json` has no playability column,
  so it needs an additive schema bump first.
- **Next:** tick 23 = web index schema bump + hero gate, then read the probe run
  (started 11:25Z) and re-measure.

### Tick 23 — 2026-07-19 — DATA/APP: web hero gated — **all 5 platforms covered**
- **Last platform closed.** The web viewer's flat `catalog-index.json` carried no
  playability column, so unlike the apps it could still marquee a dead title.
- `build_catalog_index` gains **column 8 `playable` (schema 8, additive)** from
  `playbackVerified` — bytes, not metadata. `watch.js`'s hero prefers verified
  rows, falling back to the ungated pool when fewer than 4 qualify, so it can
  never go empty — whether coverage is still climbing OR the visitor has an
  older index with no column 8.
- **Verified with the real builder** over a 300-item live slice: schema 8, rows
  9 columns, col 8 ∈ {0,1}, 240/279 playable. Against the live DB the gated web
  hero pool is **2,329 candidates for 6 slots**.
- **Milestone: the owner's core requirement now holds on tvOS, iOS, macOS,
  Android and web.**
- **Next:** tick 24 = read the probe run and re-measure coverage; the release
  wave's only open criterion.

### Tick 24 — 2026-07-19 — DATA: measure — coverage 45% → 65%, runtime gate MET
- **Third probe run** (first from a clear slot):
  `alive 6910 · dead 165 · unplayable 4 · alive_repointed 127 ·
  runtime_filled 2392 · runtime_corrected 262 · skipped_budget 792`.
  **`unreachable` 254 → 2** — archive.org healthy again.
- **Published DB movement:**
  | metric | baseline | prev | now |
  |---|---|---|---|
  | shelf playability verified | 0 | 45% | **65%** (14,146/21,825) |
  | items byte-verified | 0 | 9,796 | **14,673** |
  | catalog missing runtime | 5,408 | 4,295 | **2,212** |
  | feature-film / short-film | 11,059 / 3,578 | — | **9,737 / 4,895** (tick 16 landed) |
- **✅ EXIT CRITERION MET:** shelf items missing runtime **462/21,825 = 2%**
  against the ≤3% gate (17% at baseline).
- **One criterion resolved by measurement, not work.** The "implausible runtime
  (1–59s, non-commercial)" gate reads 638 — but **zero of them have a
  file-verified runtime**; every one is an unverified externally-matched value.
  `apply_file_runtime` corrects them the moment the probe reaches them, so that
  gate is **downstream of coverage**, not independent work.
- **Remaining blocker is singular:** playability coverage 65% vs the 95% gate.
  At ~4,900 newly-verified items per completed run, that is roughly 2 more runs.
- **Next:** tick 25 = opt/verify; coverage now advances on the daily 13:00 cron
  without dispatches.
