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

### DATA
| Metric | Baseline 2026-07-18 | Gate |
|---|---|---|
| Shelf items ever playability-verified | 9,842 / 21,860 (45%) | **≥95%**, re-verified within 90d |
| Items on Home/hero/community shelves NOT verified-playable | unbounded | **0** |
| Shelf items missing runtime | 3,751 (17%) | **≤3%** |
| Items with implausible runtime (1–59s, non-commercial) | 930 | **≤100** |
| Catalog items with empty synopsis | 4,763 (15%) | **≤5%** on shelf items |
| Catalog items with stub synopsis (<80 chars) | 3,940 (12%) | **≤10%** on shelf items |
| contentType audited against real signals | never | **audit shipped + applied** |

### APP
- Every ranked cold-resume defect (below) fixed on every platform that has it.
- A resumed-after-days app observably re-checks the catalog, re-queries its
  views, and re-syncs the account — verified, not assumed.
- No regression in playback: stall diagnostics clean on a real title.

---

## Scorecard — live catalog (32,106 items, 21,860 on shelves)

Measured 2026-07-18 against the published `catalog.sqlite`.

- **Playability is the biggest hole.** Only **31%** of the catalog (9,899) has
  *ever* been liveness-checked, and **55% of shelf items have never been
  verified to play at all**. Nothing gates an unverified item off Home. This
  is exactly the failure the owner saw.
- 290 items carry **no `downloadURL`** (none currently on a shelf).
- **Runtime**: 5,408 items (17%) have none; 930 more claim <60s.
- **Synopsis**: 27% empty or stub.
- **Titles are clean** — only 168 suspicious (Decision 043's cleanup held).
- **contentType** skew worth auditing: `documentary` has 9 items,
  `trailer` 10 — near-dead categories; 1,511 `tv-special` is the known
  orphan-episode residue (Decisions 035/036).

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
| D2 | Add `playable` (and `downloadURL`) as real `items` columns in `build_sqlite.py` so queries *can* gate. | ⏳ |
| D3 | Flip the gate: `playable=1` required on hero + all Home/community shelves + `randomPlayable()`. **Only after D1 coverage ≥95%** — flipping early empties Home. | ⏳ |
| D4 | ✅ Re-probe cadence: `livenessChecked` is a one-time marker today, so a URL that dies *after* its check is never re-probed. Add a 90-day TTL re-sweep. | ✅ tick 2 |
| D5 | Runtime truth — **nothing validates runtime against the file.** `remediate_catalog.py:352-357` says so outright. ffprobe the popularity head, write `trueRuntimeSeconds`, flag \|Δ\| > 20%. Closest existing proxy is `detect_trailers.py:46-60`. | ⏳ |
| D6 | Synopsis gap: 4,763 empty + 3,940 stubs. Existing enrichment covers the mechanism; this is a coverage push. | ⏳ |
| D7 | contentType audit — `documentary` (9 items) and `trailer` (10) are near-dead categories; 1,511 `tv-special` is orphan-episode residue (Decisions 035/036). | 🔮 |
| D8 | 290 items carry no `downloadURL` at all — drop or repair. | ⏳ |
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
| A2 | Same on Android — `AppContainer.kt:58-63` `start()` runs `catalog.refresh()` once from `onCreate:23-27`. No `ProcessLifecycleOwner`/`ON_RESUME` observer. | Very high | Android ⏳ |
| A3 | **`scenePhase` frozen inside the 60s sync loop.** `ContentView.swift:42-49` / `RootView_iOS.swift:76-83` read `scenePhase` *inside* a `.task {}` with no `id:` — the View struct is captured at appear time and never updates. If the view first appears while `.inactive` (common on cold launch), the periodic sync **never fires for the whole session**. One-line fix; silently disables sync today. | High | ✅ tvOS · ✅ iOS (tick 1) |
| A4 | No sync retry/backoff — `CloudKitSyncService.swift:120-122` swallows into `lastError` and waits for the next tick. Combined with A3, a user gets one foreground shot and no retry. **Likely the "account doesn't sync".** | Medium | all Apple ⏳ |
| A5 | Web viewer never re-fetches — `watch.js:123-124` `Data.load()` runs once from `boot()`; no `visibilitychange`/`pageshow`/`focus`/`online` listener. | High | web ⏳ |
| A6 | `featured.json` is bundle-only (`CatalogLoader.swift:12-20`) — curated shelves and `deprioritizedSeries` can't update without an App Store release. | Medium-high | all Apple ⏳ |
| A7 | No `AVAudioSession` interruption observer (`PlayerView_iOS.swift:93-94` activates once). Audio stays dead after a post-background interruption. | Medium | iOS ⏳ |
| A8 | Stale SW shell — `sw.js:53-56` cache-first with no revalidation, no `controllerchange` handler. A tab open for days never picks up a new build. | Low-medium | web ⏳ |

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
