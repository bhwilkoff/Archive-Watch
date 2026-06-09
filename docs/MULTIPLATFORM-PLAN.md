# Archive Watch — Multi-Platform Implementation Plan (iOS · Web · Android)

Status: **planning** (2026-06). Basis: the `TriAppTemplate`
(`/Users/bhwilkoff/Documents/GitHub/TriAppTemplate`). Companion to `PARITY.md`
(the live matrix) and the per-platform binding design docs to be created
(`docs/iOS-DESIGN.md`, `docs/WEB-DESIGN.md`, `docs/ANDROID-DESIGN.md`).

---

## 0. The animating principle

**Feature parity, not design consistency** (TriAppTemplate's thesis). The tvOS app
is *not* the definitive version to be shrunk onto other screens. Each platform gets
a **fully native** experience: iPhone feels like iOS, Android feels like Material,
the web feels like the web. The *verbs* are identical (browse, tune in, search,
save, surprise); the *idioms* are whatever is native to each platform.

Goal: make the Internet Archive's public-domain cinema **as widely accessible as
possible** — the web build is the zero-install reach play; iOS rides on the
already-shipped Apple ecosystem; Android opens the largest device base.

---

## 1. Why this is tractable: the app already has a clean seam

Archive Watch separates cleanly into two layers, and the expansion only rebuilds
the second:

**A. The shared data plane (already built, reused as-is — zero per-platform copies).**
- `catalog.sqlite.zz` (+ bundled `seed.sqlite`) on a GitHub Release — the full
  catalog with FTS5, designed for *query-on-disk* (Decision 017).
- `featured.json` (shelves/categories/accents), `series/*.json` (TVmaze spines),
  `collection_metadata.json` (curated blurbs) — hand-authored editorial source.
- archive.org for video + posters; `archivewatch-covers` for generated art.
- The entire Python pipeline (`tools/`): discovery, enrichment cascade, TV
  canonicalization, cover generation, color classification, match verification,
  **rights audit + adult flagging**. This is build-time/CI and **needs no change** —
  every client inherits a copyright-clean, mature-filtered catalog for free
  (`excluded` + `isAdult` columns baked into the SQLite).

**B. The platform layer (rebuilt natively per platform).**
- The query layer (`CatalogDB`), the UI (views/components/navigation), the player
  integration, local persistence, and platform reach (widgets, voice, deep links).

The contract between the two is **the catalog SQLite schema + the JSON editorial
files**. Lock that contract once (it already exists) and each platform implements
against it. See `docs/CATALOG-CONTRACT.md` (to author — extract the schema + JSON
shapes so all four clients implement identically).

---

## 2. The data layer, per platform (the load-bearing technical choice)

The catalog is ~30k items / ~96 MB uncompressed. Each platform reaches it differently:

| Platform | How it reads the catalog | Rationale |
|---|---|---|
| **tvOS** (shipped) | download `.zz` → inflate (Compression framework) → query on disk | Decision 017/019 |
| **iOS** | **reuse the tvOS Swift `CatalogDB` + `CatalogRefreshService` verbatim** | same SQLite, same inflate, ~zero new data code |
| **Android** | download `.zz` → inflate (`java.util.zip.Inflater(nowrap=true)` = raw DEFLATE) → query via SQLite/Room or SQLDelight (FTS5 is in Android's bundled SQLite via `requery/android-sqlite` if needed) | mirrors tvOS; on-disk query keeps a 30k catalog off the heap |
| **Web** | **`sql.js-httpvfs` / `sqlite-wasm-http`** — query the SQLite *in place* over HTTP **range requests** from GitHub Pages; only the needed pages (KB, not 96 MB) transfer; FTS5 works. `wa-sqlite` + **OPFS** caches pages for offline/PWA. Fallback: `catalog-index.json` for a lightweight search. | static-host friendly, no backend, no 96 MB download. Verified current (phiresky/sql.js-httpvfs, sqlite-wasm-http). |

Key consequence: **no client re-implements the pipeline or re-hosts the catalog.**
The publish-db CI already produces the one asset all four consume.

---

## 3. Streaming resilience, per platform

The tvOS `ResilientStreamLoader` (Decision 021) owns the HTTP connection to survive
Archive's idle-connection resets (resume-from-byte-offset instead of buffer flush).
Each platform gets its own analog:

- **iOS** — reuse the Swift `ResilientStreamLoader` (`AVAssetResourceLoaderDelegate`) verbatim.
- **Android** — Media3/ExoPlayer with an OkHttp `DataSource` + a `ResolvingDataSource`
  and a custom `LoadErrorHandlingPolicy` (retry/backoff, resume on reset). ExoPlayer's
  range handling is already strong; the policy adds Archive-specific resilience.
- **Web** — the browser's `<video>` already does ranged GETs; add a small
  `error`/`stalled`-listener reconnect wrapper that re-seeks to `currentTime` on a
  network drop. Escalate to MSE only if needed (likely not for progressive MP4).

Derivative selection stays at build time (highest quality); no client adds a
bitrate ceiling.

---

## 4. Per-platform plans

### 4.1 iOS (iPhone + iPad) — ship first

**Why first:** highest leverage. ~60–70% of the tvOS Swift is non-UI and reusable
(`CatalogDB`, `CatalogRefreshService`, `ResilientStreamLoader`, networking clients,
`Catalog.Item` + SwiftData models, the F4 continuous-playback engine, CloudKit sync,
App Intents). And because iOS can **reuse the same CloudKit private DB**, an iPhone
signs into the same iCloud account as the living-room Apple TV and **favorites /
playlists / watch-progress sync for free** — a marquee household feature on day one.

**Stack:** Swift 6, SwiftUI, **iOS 26 baseline**, SwiftData, CloudKit, AVKit,
URLSession. No third-party packages. Version via `AppVersion.xcconfig`.

**Native design (touch-first, NOT 10-foot):**
- Bottom `TabView` on iPhone; `NavigationSplitView` sidebar on iPad (size-class
  adaptive, one hierarchy).
- `Tab(role: .search)` / `.searchable` for Search; `Menu` + `searchScopes` for facets.
- `.sheet` / `.fullScreenCover` for Detail-actions, Create Channel, Settings.
- Hero/detail transition: `.matchedTransitionSource` + `.navigationTransition(.zoom)`.
- Liquid Glass tab bar/toolbar (iOS 26 native).
- `AVPlayerViewController` (reused) → free touch transport, **PiP**, AirPlay.
- Context menus (long-press) replace tvOS long-press menus.
- Drop the focus engine entirely; gain swipe-back, pull-to-refresh, haptics.
- **New affordances:** WidgetKit widgets (Continue Watching / Editor's Picks /
  What's New — the Top Shelf analog), Live Activities for "now playing" (future),
  Core Spotlight indexing (future), Handoff (NSUserActivity already declared).
- iPad emphasizes the lean-back modes (Party Play, screensaver) that suit a propped
  tablet; iPhone de-emphasizes them.

**Reused largely verbatim:** data plane, streaming, models, sync, intents.
**Rebuilt:** every View/Component, navigation shell, the EPG layout for touch.

### 4.2 Web (PWA) — ship second (widest reach, no review gate)

**Why second:** zero-install accessibility — the strongest answer to "as widely
accessible as possible." Ships continuously via GitHub Pages (no store review).

**Stack (TriApp web):** vanilla HTML/CSS/JS, no build step, mobile-first, GitHub
Pages. Data via `sql.js-httpvfs`/`sqlite-wasm-http` over range requests (+ OPFS
cache); HTML5 `<video>`; IndexedDB for favorites/playlists/progress. Installable
**PWA** (`manifest.json` exists) with offline shell.

**Native-web design (the web feels like the web):**
- **URL-driven state** — every surface is a shareable canonical URL; filters live
  in query params (`/movies?decade=1950&genre=noir`). This is a web *superpower*,
  not a port of in-memory mobile state.
- `<dialog showModal>` for modals; Popover API for menus; View Transitions API for
  cross-view animation; container queries for component responsiveness; `:has()` to
  kill JS toggles; Web Share API + clipboard fallback.
- Responsive grid (CSS grid), keyboard shortcuts (desktop), `<video>` native
  controls + `requestPictureInPicture()` + Remote Playback API (cast).
- Channels EPG as a CSS-grid time guide; modes as fullscreen.
- Reuses the existing editorial web tooling's conventions (`js/api.js` single
  data-access module; `:root` tokens; no inline styles; visible error states; the
  Safari flex-column body rule).

**Reach note:** the web build doubles as the canonical link target for shares from
every platform — every `archivewatch://item/x` has a `https://…/item/x` twin.

### 4.3 Android (phone + tablet) — ship third (most new code)

**Stack (TriApp android):** Kotlin + Jetpack Compose + **Material 3 Expressive**,
`minSdk 29` / `targetSdk 36`, Compose-only. Media3/ExoPlayer, Coil 3, Room +
DataStore, Hilt, Ktor (for JSON), Navigation 3. SQLite/Room reads the downloaded
catalog; Tink-encrypted DataStore for any secrets.

**Native design (Material, not a reskin of iOS):**
- `NavigationSuiteScaffold` — bottom bar (compact) → nav rail (medium) → drawer
  (expanded), driven by `currentWindowAdaptiveInfo()`.
- M3 components first: `SearchBar`, `ModalBottomSheet`, `FilterChip`/`InputChip`,
  `DropdownMenu`, `PullToRefreshBox`.
- `SharedTransitionLayout` + `sharedBounds` for hero→detail.
- **Predictive back** (let M3 animate the back-drag); **edge-to-edge** mandatory;
  Material You **dynamic color opt-in** (brand theme default).
- Media3 `PlayerView` → transport, track selection, **PiP**, **Google Cast**
  (Android's AirPlay analog).
- Stable `key`s on every `LazyVerticalGrid`/`LazyRow`.
- **New affordances:** home-screen widgets (Top Shelf analog), App Shortcuts +
  App Actions (App Intents analog), Quick Settings tile (maybe), adaptive icon.

**Reused:** the catalog contract + pipeline + JSON; the F4 queue logic + rights/
adult flags (re-expressed in Kotlin). **Rebuilt:** everything UI + the data/query/
player layer in Kotlin.

---

## 5. The hard ports (feature-by-feature notes)

- **Channels EPG** — `ChannelScheduler` is deterministic (date-seeded), so the
  schedule is reproducible across platforms from the same seed + catalog. Port the
  scheduler logic; rebuild the *guide layout* natively (touch guide on iOS,
  Compose lazy guide on Android, CSS-grid on web). Commercial-break injection +
  join-in-progress reuse the same logic.
- **Continuous playback (F4)** — a queue + advance-on-end engine. Port the logic;
  bind to each platform's player (AVQueuePlayer / Media3 playlist / JS `ended`).
- **Cartoon/Party/Screensaver modes** — selection pools are shared queries
  (color/B&W flags already in the catalog). UX rebuilt per platform; Party +
  screensaver are lean-back idioms → emphasized on iPad/tablet/desktop, optional on
  phones (see PARITY §5).
- **Adult filter + rights exclusion** — already baked into the SQLite as columns;
  every client filters with a `WHERE` clause. The *settings toggle* is rebuilt per
  platform; the *data* needs no per-platform work.
- **VHS effect** — per-platform shader (Metal reuse on iOS, AGSL `RenderEffect` on
  Android, WebGL/CSS on web). Optional polish, last.

---

## 6. The one genuinely-new cross-cutting decision: sync strategy

tvOS uses **CloudKit** (Apple-only). The choices:

- **Recommended phased path:**
  - **Phase A (v1 each platform):** iOS reuses CloudKit → syncs with the Apple TV
    automatically. Android + Web are **local-only** (Room/DataStore, IndexedDB).
    Browse/play/save all work; only cross-*ecosystem* sync is absent.
  - **Phase B (when warranted):** add a **neutral sync backend** (Cloudflare
    Worker + D1/KV, or Supabase) that all four platforms can use, with Sign in with
    Apple (iOS/web), Sign in with Google (Android/web), email everywhere. This gives
    true Android↔iOS↔Web parity. The TriAppTemplate's PARITY/auth rows already
    anticipate this shape.

**Open question for the owner:** accept the Apple-only sync asymmetry in v1 (faster,
zero new backend) and add the neutral backend later — **or** stand up the neutral
backend up front so Android/Web sync from day one? Recommendation: **Phase A first**
(ship value fast; the asymmetry is invisible to single-ecosystem users), Phase B
once there's an Android/web install base that wants it.

---

## 7. Repository structure (TriApp layout, applied to Archive Watch)

Archive Watch already has the web scaffold (`index.html`/`css`/`js`) and the tvOS
app. Adopt the TriApp sibling layout:

```
/                              ← repo root
├── ArchiveWatch.xcodeproj     ← (eventually) iOS+tvOS multiplatform target at root
├── ArchiveWatch/              ← Swift: shared core (CatalogDB, loaders, models,
│   ├── Core/                    networking, F4, sync) + per-platform UI groups
│   ├── tvOS/  iOS/              (tvOS views exist; add iOS views)
├── android/                   ← Kotlin + Compose (from TriAppTemplate)
├── index.html, css/, js/      ← web app (extend the editorial scaffold into the viewer)
├── catalog.* (Release), featured.json, series/, collection_metadata.json  ← shared data plane
├── tools/                     ← Python pipeline (unchanged)
├── PARITY.md, docs/*-DESIGN.md, docs/CATALOG-CONTRACT.md, docs/MULTIPLATFORM-PLAN.md
└── .well-known/               ← apple-app-site-association + assetlinks.json (Universal/App Links)
```

iOS + tvOS can share one Xcode project with per-platform UI and a shared Core
group (the cleanest reuse), or stay separate projects sharing a Swift package — to
be decided at iOS bootstrap. Android is a sibling module (different toolchain).

---

## 8. Recommended sequencing + milestones

| Phase | Platform | Scope | Why this order |
|---|---|---|---|
| **P1** | **iOS (iPhone)** | Core: Home, Movies, TV, Detail, Player, Search, Collections, Library, Surprise, Settings + CloudKit sync with the TV | Max code reuse + instant household sync; same dev stack as the shipped app |
| **P2** | **iPad adaptivity** | `NavigationSplitView`, size-class layouts, lean-back modes | small delta on P1 |
| **P3** | **Web PWA** | Core browse/play/search/collections/library(local) + shareable URLs | widest reach, no review gate; `sql.js-httpvfs` data layer |
| **P4** | **Android** | Full feature set, Material 3, Media3 | most new code; benefits from P1/P3 lessons |
| **P5** | **Reach + parity polish** | Widgets, deep/App Links, App Actions, Channels+modes everywhere, VHS shaders, (optional) neutral sync backend | cross-platform finish |

Each phase: bootstrap → core browse+play → personalization → modes → reach. Apply
`feature-shipping-discipline` per feature; update `PARITY.md` in the same change set
(the template's standing rule). Create each platform's binding design doc
(`binding-design-doc-discipline`) once that platform passes ~5 views.

---

## 9. Skills needed

**Already have (use as-is):**
- Cross-platform method: `learning-orientation-design`, `native-platform-first`,
  `mobile-first-density-design`, `universal-feature-states`,
  `binding-design-doc-discipline`, `feature-shipping-discipline`,
  `architectural-decision-log`.
- iOS depth: `all-ios-skills:*` / `swift-ios-skills` (SwiftUI, SwiftData,
  navigation, networking, Liquid Glass, App Intents, WidgetKit, app-store-review).
- Design: `KUI:*`, `ui-ux-pro-max`, `killer-ui`, `frontend-design` (web component work).
- Assets: `app-store-screenshots`.
- (tvOS reference) `tvos-platform-patterns`.

**Install for Android** (`TriAppTemplate/tools/install-android-skills.sh`, or
individually):
- `Kotlin/kotlin-agent-skills` (JetBrains official)
- `chrisbanes/skills` (Compose, Google Android engineer)
- `rcosteira79/android-skills` (architecture, M3, Coil 3, Room, Flows)
- `Drjacky/claude-android-ninja` (Compose M3, Nav 3, Hilt, Room, biometrics)
- `skydoves/android-testing-skills` + `skydoves/compose-performance-skills`
- `android/skills` (Google official: adaptive layouts, edge-to-edge, theming, Nav 3)
- `aldefy/compose-skill`
- Gap to watch: **Media3/ExoPlayer** depth — covered partially by android-ninja;
  may author a small `media3-resilient-streaming` project skill capturing the
  Archive-reset `LoadErrorHandlingPolicy` pattern.

**Web:** no umbrella framework skill (vanilla by design); `frontend-design` + `KUI`
cover component/design work. Author a small project skill `web-catalog-data-layer`
capturing the `sql.js-httpvfs` + OPFS + range-query pattern (so it's not re-derived).

**New project docs/skills to author:**
- `docs/CATALOG-CONTRACT.md` — the SQLite schema + JSON shapes all four clients
  implement against (the single most important shared artifact).
- `docs/iOS-DESIGN.md`, `docs/WEB-DESIGN.md`, `docs/ANDROID-DESIGN.md` — binding
  design docs (seed each from the cross-platform principles; diverge on idioms).
- `web-catalog-data-layer` + `media3-resilient-streaming` project skills (above).

---

## 10. Open decisions for the owner
1. **Sync strategy (§6):** Apple-only sync in v1 + neutral backend later (recommended),
   or neutral backend up front for day-one Android/Web sync?
2. **Sequencing (§8):** iOS → iPad → Web → Android (recommended), or pull Web earlier
   for fastest broad reach?
3. **iOS/tvOS project shape:** one multiplatform Xcode project sharing a Core group,
   or separate projects sharing a Swift package?
4. **Scope of modes on phones:** ship Party Play / screensaver on iPhone/Android
   phone, or reserve those lean-back modes for iPad/tablet/desktop-web/TV?

## 11. Risks + mitigations
- **Web video from archive.org** — CORS/redirects on `download/` URLs. Mitigation:
  posters/covers already proven fetchable; video via `<video src>` (no CORS needed
  for media element playback); test early, fall back to a tiny redirect Worker if a
  specific host blocks ranged media.
- **Web SQLite size/latency** — range-query latency on a 96 MB DB. Mitigation:
  indices are critical (already present); OPFS page cache; `catalog-index.json`
  fallback for first-paint search.
- **Android FTS5 availability** — bundled SQLite varies. Mitigation: bundle a known
  SQLite (requery/AndroidSQLite) or build the FTS index into the shipped DB (already
  is). 
- **Parity drift** — the classic failure. Mitigation: `PARITY.md` updated in the
  same change set; the template's standing rule.
- **Sync fragmentation** — see §6; phased, with the neutral backend as the
  convergence point.
