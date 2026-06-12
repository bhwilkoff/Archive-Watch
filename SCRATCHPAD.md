# Project Scratchpad — Archive Watch

## Current State

> **NOTE (2026-05-31):** This scratchpad had drifted ~6 weeks behind the
> code. The sections below were rewritten to match the actual repo state
> after a full audit. The Milestone checklists further down still reflect
> the original M0–M4 plan and are being reconciled feature-by-feature.

- **Status**: tvOS app is **well past M0** and deep into M1–M3 territory.
  The Xcode project exists at `ArchiveWatch/ArchiveWatch.xcodeproj`, builds
  **clean** on the tvOS 26.5 simulator (Xcode 26, exit 0), and ships a
  **25,417-item bundled `catalog.json`** (≈74 MB; 25,000 playable, 99%
  with posters, 86% synopsis, 41% TMDb, 27% IMDb). Implemented and working:
  Home (hero carousel + category/decade tiles + dynamic shelves + Hidden
  Gems + Director shelves + Continue Watching + Favorites shelves), Movies
  (Browse grid + facet chips + sort), TV Shows (series cards →
  season/episode drill-in → prev/next episode player), Collections,
  Search, Surprise (3 random actions, Decision 014), Detail (hero +
  metadata + More Like This), AVKit player with SwiftData resume.
  Navigation is tvOS-26 native `TabView(.sidebarAdaptable)` + per-tab
  `NavigationStack`.
- **Active milestone**: feature-complete for v1.1; app is **1.1.0 (build 12)**.
  Remaining is the **owner-gated App Store submission** (TestFlight) + a few
  owner-blocked items — see the top Session Log entry + the
  `session-handoff-2026-06` memory for the live backlog.
- **Last session**: 2026-06-09 — autonomous all-platform buildout: iOS P1/P2
  parity closed + merged, Web PWA viewer live, Android v1 spine shipped
  (see Session Log).
- **Confirmed gaps blocking a clean v1.0 submission** (this session's work):
  1. **No Settings/About surface at all** — and TMDb attribution is
     *required* by Decision 007 / TMDb terms. Also missing: adult-content
     toggle (Decision 012), donate-to-Archive link (Decision 010).
  2. **Adult-content filter not enforced** — `featured.json.adultCollections`
     exists but is never read in Swift; Decision 012's default-on filter
     is currently off.
  3. **App icon assets are empty** — `App Icon & Top Shelf Image.brandassets`
     has the imagestack scaffolding but **zero PNGs**. Hard archive/submit
     blocker. (Master SVGs exist at `assets/app-icon/`.)
  4. **No `PrivacyInfo.xcprivacy`** privacy manifest — App Store requirement.
  5. **Loading / error / empty states** thin — `AppStore.loadError` is set
     but never surfaced to the user.
- **Non-issues found during audit** (do NOT re-investigate):
  - Playback is **fine** — `downloadURL` is baked into the catalog at
    build time (`itemsPlayable: 25000`); `EnrichmentService` /
    `DerivativePicker` are intentionally unused at runtime.
  - Random/Surprise actions are built and wired (better than docs implied).
  - Collections tab already shows only curated `CollectionMetadata.all`
    IDs, so `fav-<username>` pseudo-collections don't leak into the UI.
- **Open questions** (still open):
  - Which still goes in the v1 app icon? Méliès moon master is rendered
    this session; owner to confirm or swap a photographic 1902 still.
  - Silent preview loop on Detail focus — ship without, or generate 10s
    clips server-side via GitHub Actions?
  - `.xcodeproj` lives at `ArchiveWatch/ArchiveWatch.xcodeproj`, two levels
    deep — Decision 002 wants it at repo root for Xcode Cloud. Fine for
    local builds + side-loading; revisit before wiring Xcode Cloud CI.
  - Bundled `catalog.json` is ≈74 MB (fav-* collaborative-filter
    collections inflate it). Acceptable for now; candidate for slimming.

---

## Scope Note

Archive Watch is a **tvOS-first** app (see Decision 006). The `index.html`
/ `css/` / `js/` scaffold is retained only as the future editorial
dashboard for curating `featured.json`. The Dual-Platform Feature Parity
Model does not apply here.

---

## When to add a binding design doc

The project has grown past ~5 views (Home, Browse, Detail, Player,
Settings, Search, TV series shelf, …). A `tvOS-DESIGN.md` binding
design doc would be earning its keep — quote the rule before
proposing any new view / sheet / overlay / shelf type. Invoke
`binding-design-doc-discipline` when adding it.

Until that doc exists, `docs/tvos-playbook.md` is the closest thing
this project has to a binding spec — consult it first for any tvOS
UI change. The playbook lives in user memory (see CLAUDE.md "How we
build" table) and should be the first stop before iterating on
focus / layout / animation bugs.

---

## Milestones

### M0 — Project Setup
- [x] Research docs (`docs/research/metadata-sources.md`, `docs/research/design-reference.md`, `docs/research/tvos-home-screen-integration.md`)
- [x] Architecture decisions logged (DECISIONS 006–015)
- [x] Networking + model scaffold in `ios/`
- [x] CLAUDE.md identity filled in
- [x] `featured.json` seed (curated picks + dynamic shelves + categories)
- [x] Editorial dashboard (replaces template `index.html`; doubles as live pipeline validator)
- [x] What's New curation ticker (`whats-new.html`) with seen-tracking + dashboard handoff via localStorage
- [x] `tools/validate-pipeline.sh` (CLI smoke test for the cascade)
- [x] App icon spec (`docs/design/app-icon.md`) + master SVG (`assets/app-icon/icon-1024.svg`) + Méliès moon (`assets/app-icon/melies-moon.svg`) + multi-size preview page (`assets/app-icon/preview.html`)
- [x] tvOS home-screen integration plan (Top Shelf + NSUserActivity + App Intents)
- [x] Categorization schema: `docs/taxonomy/collections.json` + Swift `CollectionRegistry` (expanded subject-to-genre map, collection weights, adult deny-list)
- [x] Seed catalog pipeline: browser generator (`build-catalog.html`), `catalog.json` schema, Swift `SeedCatalog.prime(into:)` first-launch loader wired into the app shell via `RootView`
- [ ] `catalog.json` generated from real Archive + TMDb data (owner runs build-catalog.html once Pages is live + TMDb token is in hand)
- [ ] Xcode tvOS project created at repo root as `ArchiveWatch`
- [ ] Swift files moved from `ios/` into Xcode group, `ios/` deleted
- [ ] `AppVersion.xcconfig` wired to tvOS target (Debug + Release)
- [ ] `Secrets.xcconfig` created (gitignored) with `TMDB_BEARER_TOKEN`
- [ ] Empty tvOS shell runs on Simulator
- [ ] GitHub Pages enabled (so the dashboard goes live)

### M1 — Watch a film end-to-end
> User launches the app, lands on Home, sees shelves of enriched titles
> with real posters, opens a detail page, plays the film through native
> AVPlayer transport controls with resume-on-reopen, and can hit
> "Surprise Me" to be sent to a random film.

- **Learning check** (via `learning-orientation-design` skill):
  [x] Deepens understanding [x] Invites participation [x] Supports agency
  [ ] Clarity over cleverness
- **Acceptance criteria**:
  - [ ] Home reads `featured.json` from GitHub Pages and renders curated + dynamic shelves
  - [ ] Every card shows a TMDb-sourced poster (not Archive thumb) for titles with IMDb IDs
  - [ ] Detail page shows synopsis, cast, year, runtime, source attribution
  - [ ] AVPlayerViewController plays the h.264 MP4 derivative end-to-end
  - [ ] Playback position persists across app launches (SwiftData)
  - [ ] Rate limit handling on 429 (Archive + TMDb) works under load
  - [ ] Three random actions wired: Random Movie, Random Category, Random Collection (Decision 014)
  - [ ] Adult-content filter on by default; toggle in Settings (Decision 012)
  - [ ] Per-category accent colors applied to shelf titles + focus glow (Decision 013)

### M2 — Search + Favorites + Siri reach
> User searches the Archive, filters by facets, favorites titles, and
> can launch random actions or save items via Siri.

- **Acceptance criteria**:
  - [ ] Siri Remote keyboard + dictation search
  - [ ] Facet chips (Type / Decade / Length)
  - [ ] Favorites tab with SwiftData persistence
  - [ ] Continue Watching shelf (second row on Home), timecode not percent
  - [ ] Deep link routing: `archivewatch://item/{id}`, `/play/{id}`, `/random/...` (Decision 015)
  - [ ] NSUserActivity declared on Detail screens — "Hey Siri, add this to my Up Next" works (Decision 015)
  - [ ] Three App Intents: SurpriseMe, RandomCategory, RandomCollection (Decisions 014 + 015)

### M3 — Browse + Taxonomy
> User browses by decade, genre, and collection; list/grid toggle
> persists; can correct a wrong TMDb match.

- **Acceptance criteria**:
  - [ ] Browse tab with facet panel
  - [ ] Inline-expanding collection cards (UHF pattern)
  - [ ] Grid/list toggle persists
  - [ ] "Wrong match? Re-link." escape hatch on Detail (Channels pattern)

### M4 — Polish + App Store submission
> Top Shelf extension, ambient dim, Shuffle Collection, and full App
> Store / TestFlight submission.

- **Acceptance criteria**:
  - [ ] Top Shelf extension target with `.sectioned` content (Continue Watching + Editor's Picks + What's New) — Decision 015
  - [ ] App Group container `group.com.bhwilkoff.archivewatch` with snapshot writers in main app
  - [ ] BGAppRefreshTask updates the What's New cache periodically
  - [ ] Ambient dim on focus-hold > 2s
  - [ ] Shuffle Collection action on each shelf
  - [ ] App icon shipped (master at `assets/app-icon/icon-1024.svg`; layered tvOS variants exported per `docs/design/app-icon.md`)
  - [ ] App Store screenshots + promotional copy
  - [ ] Attribution screen (TMDb logo + notice, Archive, Wikidata, Commons, LoC)
  - [ ] Privacy policy (trivial: "no data leaves your device except API calls to public services")
  - [ ] TestFlight → App Store

---

## Enrichment Pipeline Status

### Done
- [x] Research (`docs/research/metadata-sources.md`)
- [x] Architecture decision (DECISION 008)
- [x] `ArchiveClient` — scrape / metadata / download URL
- [x] `TMDbClient` — find-by-IMDb / movie detail / image URLs
- [x] `WikidataClient` — P724 SPARQL fallback
- [x] `DerivativePicker` — pure video-file selection logic
- [x] `ArtworkResolver` — cascading poster/backdrop resolution
- [x] `EnrichmentService` — orchestrator that produces a `ContentItem`
- [x] `ContentItem` SwiftData model + `Taxonomy` controlled vocabulary
- [x] `CollectionRegistry` — Archive collection → category + weight + adult filter, shared by Swift and JS via `docs/taxonomy/collections.json`
- [x] `SeedCatalog` — Swift loader that populates SwiftData from bundled `catalog.json` on first launch
- [x] Browser catalog generator (`build-catalog.html`) — produces `catalog.json` from live Archive + TMDb data, runs on any device

### Next for Enrichment
- [ ] `Secrets.xcconfig` with TMDb bearer token (M0)
- [ ] Smoke-test harness: 5 Archive IDs across decades, print full
      enrichment results to the console (M0)
- [ ] Background enrichment job (actor-gated, batched) for when titles
      arrive from scrape without IMDb IDs (M1)
- [ ] `featured.json` curated picks on GitHub Pages (M1)

---

## iOS App Status

### Completed
- Research, decisions, and networking/model scaffold in `ios/`

### Next for iOS (tvOS)
- Create Xcode project, wire scaffold, build empty shell

---

## Web App Status

### Completed
- Editorial dashboard (`index.html` + `js/app.js` + `js/api.js` + `css/styles.css`) — live `featured.json` editor with metadata preview that doubles as a pipeline validator
- What's New ticker (`whats-new.html` + `js/whats-new.js` + `css/whats-new.css`) — recent uploads from each major collection, tracks "seen" in localStorage, hands off picks to dashboard via `aw_pending` queue
- `featured.json` seed with 7 personal favorites + 9 dynamic popularity shelves + 8 categories + adult-content filter list + random-action config
- App icon master + Méliès moon SVG + multi-size preview at `assets/app-icon/preview.html`

### Next for Web
- Enable GitHub Pages on `main` (Owner action — Settings → Pages → branch: main, root)
- Once live, link the dashboard URL in README
- Open `build-catalog.html` once Pages is live to generate the real `catalog.json`
- (Future) Drag-and-drop reorder for shelves and items (currently up/down buttons)
- (Future) Node CLI equivalent of build-catalog for scheduled GitHub Actions refresh

---

## Open Questions

- Méliès moon icon shipped as vector master at `assets/app-icon/icon-1024.svg`; production version may swap the illustration for a high-res photographic still from the 1902 film (PD via LoC / Wikimedia Commons). Owner to decide post-launch.
- Silent preview clips on Detail focus — ship without, or generate server-side?
- Serif body type on tvOS — Fraunces in dashboard works; prototype the same on tvOS panel before committing
- Should the Top Shelf "What's New" section pull from the editorial-picks list or directly from the Archive recent-uploads feed? (See `docs/research/tvos-home-screen-integration.md` open questions.)

---

## Session Log

### 2026-06-15 (later) — Top Rated shelf + rating sort (tvOS/iOS/Android)
Owner (after noticing the IMDb star on Detail): "we should allow for
sorting by star rating as one of the filters on browse and it should be
its own shelf on the Home Screen." App 1.2.25 (b38) / Android vc3; all
three platforms build green.
- **Shared CatalogDB**: Sort gains `.rating` (NULLS LAST + votes
  tiebreak, demote-aware); new `topRated(limit:24, minVotes:1000)` —
  home-gated, designed-art, votes floor so tiny-sample 9.8s can't outrank
  classics. SQL-verified against the live DB: City Lights / M / Citizen
  Kane / Sherlock Jr. / The Gold Rush lead.
- **tvOS**: TopRatedShelf (above Hidden Gems on Home); Browse sort menu
  "Top Rated" (TVShowsView switch made exhaustive — series sort by rating
  then episode depth). **iOS**: Home shelf + Browse Picker option (cross-
  shelf dedup includes the new shelf). **Android**: BrowseSort.RATING
  (menu auto-includes), CatalogDatabase.topRated, Home row above Hidden
  Gems. **Web**: ⏳ — catalog-index has no rating column; additive schema
  bump then trivial (PARITY row notes it).


### 2026-06-15 — Title-first PD discovery: the inverted pipeline (Decision 032)
All four store submissions are IN REVIEW (tvOS approved; iOS, Play internal
track submitted). Owner: "use our multiple APIs ... to instead go the other
direction and identify all of the titles that we should be searching
archive.org for that are public domain or have otherwise lost their
copyright."
- **tools/discover_pd_wants.py** — three metadata-first feeds emit
  iaid-less WANTS into the existing discovery_candidates.json queue; the
  EXISTING ingest step hunts archive.org per want by title+year
  (archive_lib.resolve_title) and everything downstream (enrichment,
  Decision-026 match verify, Decision-027 rights audit) applies unchanged:
  W = Wikipedia's curated "List of films in the public domain in the United
  States" (row carries the lapse REASON → pdEvidence; NOTE: it's a LIST
  page — the category does not exist); T = TMDb /discover pre-PD-cutoff
  (rolling current_year−95), popularity-first, imdb id resolved only for
  survivors of dedup; A = Wikidata pre-cutoff films with imdb but NO P6216
  flag, SHARDED BY DECADE (one big query or deep OFFSET pages 504/truncate
  on WDQS).
- **First production run: 2,907 wants queued** (2,466 wikidata-age, 440
  tmdb, 1 wikipedia), 2,900 with an IMDb id attached. The single Wikipedia
  find is a gem — March of the Wooden Soldiers (1934 Laurel & Hardy, PD by
  notice defect); the other 125 curated US-PD films were ALREADY held
  (validates both the back catalog and the dedup).
- Wired into discover-content.yml (wants step before ingest;
  wants_tmdb_pages dispatch input). Report: shared/editorial/
  wants_report.csv per run. DECISIONS 032 logged.
- **First hunt (CI run 27373679696, same day): 223/600 wants matched on
  archive.org → +216 new films ingested** (137 matched items had no
  playable video; 547 resolver hits were items already held — the
  ingest-level archiveID/imdb dedup is the real guard). ~2,300 wants
  remain; the nightly run drains ~600.
- CI caveat: WDQS 504s EVERY decade shard from GitHub runners (datacenter
  IP throttling) — the wikidata-age feed effectively runs only from a
  residential IP (like discover_loc); Wikipedia + TMDb feeds run fine in
  CI. The locally-run age feed's 2,466 wants are committed in the queue.
- **Full local drain (same day, owner ask)**: top-up +2,297 wants
  (residential IP gets past the WDQS 504s), then resolver matched
  1,542/4,164 (37%) → **+1,487 films ingested, 0 errors — catalog 40,189
  items**. Remediated, rights-stamped, published; publish-db dispatched.
  End state: 1,694 ingested / 2,999 unresolved / 40 no-video / 31 dup.
- Next ideas (not built): --retry-unresolved sweep as new uploads appear;
  more curated feeds (national archives, AFI) as additional sources in the
  same tool.


### 2026-06-14 (later) — Android polish: channel icons, search filters, designed-art parity
Owner: "add the correct icons for channels interface on Android and
filtering on the search tab as well. Also, can you apply the same
poster/title filtering on Android that we do for iOS (only professional
posters, etc.)" All emulator-verified (release build).
- **Channels rail icons**: Material twins of the iOS preset SF Symbols
  (TheaterComedy/Mood/Search/Bolt/Nightlight/Landscape/Science/Movie/
  Brush/Newspaper/Public/Tv; user channels = Star), white on the accent
  chip.
- **Search filters**: type/decade FilterChips + dropdowns over FTS results
  (only facets PRESENT in the results are offered; active chip shows ✕ to
  clear) — iOS Search-filter parity.
- **Designed-art/browse parity (CatalogDatabase)**: POPULAR sort is now
  demoted-last + designed-art-first + popularity + episodesCount (the iOS
  CatalogDB order verbatim); browseWhere got the explicit tv-series branch
  (series cards, hasRealArtwork-gated) — the contradictory WHERE meant
  Android Home NEVER showed the Classic TV tile (count=0 → gated out);
  seriesCards orders demoted-last + designed-first; featured.json
  deprioritizedSeries now decodes into CatalogDatabase.demotedIDs (SNL
  no longer leads any TV list). Verified: Classic TV tile on Home opens a
  poster-gated series grid; SNL absent from the top.


### 2026-06-14 — tvOS APPROVED; iOS submitted; Google Play prep complete
tvOS 1.2.24 approved by App Review; owner submitted iOS/iPadOS same day
(listing Part 2 + 7+7 screenshots, commit c1785da). Then full Play Console
prep (owner: "walk me through the steps"):
- **docs/play-store-listing.md** — complete walkthrough (account → app →
  declarations → listing → Play App Signing → production) + paste-ready copy
  (short/full description, release notes), exact Data Safety answers
  (nothing collected), IARC guidance, the personal-account 12-tester/14-day
  gotcha, and the post-enrollment assetlinks step (add the Play signing cert
  SHA-256 — REQUIRED or App Links break in the Play build).
- **Assets** at ~/Desktop/ArchiveWatch-PlayStore-Assets/: signed AAB
  (1.2.24/vc1, upload-key verified = assetlinks print), icon-512, feature
  graphic, 8 Pixel 9 Pro screenshots (deep-link-driven; SystemUI demo mode).
- **ICON INCIDENT (twice)**: Play assets were first generated from
  assets/app-icon/icon-1024.svg — the OLD illustrated moon the owner has
  repeatedly said to delete. The photographic 1902 still
  (AppIcon.appiconset/icon-1024.png) is THE icon. The SVG masters +
  preview.html + tools/render-app-icon.sh are now DELETED from the repo;
  memory file app_icon_photographic_only.md written.
- **Android fixes found via screenshots** (all in the uploaded AAB):
  versionName 1.0.0→1.2.24; manifest now resolves archivewatch://surprise +
  /channels (only ://item was declared — external links failed);
  archivewatch.org/series/{slug} App Link routed to a dead movie Detail
  ("Not playable") instead of SeriesDetailScreen (AppRoot now strips the
  series: prefix → Route.Series); DetailScreen got the SeriesDetail-style
  8s-timeout error state (an id missing from the live DB — e.g. a copy the
  IMDb dedup dropped — used to spin FOREVER; screenshot ids must come from
  the LIVE DB, not the seed).
- Emulator lesson: boot ONE sim/emulator at a time (iOS 26 sims dual-boot
  wedged "Waiting on System App"; the user had to close them).


### 2026-06-13 (later) — Background play + PiP for iOS and Apple TV
Owner: "Can you enable background play and Picture in Picture for iOS and
Apple TV?" App 1.2.24 (b37); iOS + tvOS sims both build green.
- **Info.plist**: `audio` added to UIBackgroundModes (shared universal
  target — enables background audio on iOS and PiP on both).
- **tvOS** (`AVPlayerScreen.swift`): both player containers set
  `allowsPictureInPicturePlayback = true` — swipe up / TV button while
  playing → corner PiP window.
- **iOS** (`PlayerView_iOS.swift`): already had PiP + auto-PiP from
  inline; ADDED background play via the supported AVKit technique —
  Coordinator is now NSObject + AVPlayerViewControllerDelegate, detaches
  `vc.player` on didEnterBackground (audio keeps running on the .playback
  session) and reattaches on willEnterForeground; PiP-aware (skips the
  detach while PiP owns the video; PiP state tracked via delegate
  callbacks; restore handler completes true since the full-screen player
  stays in the hierarchy).
- PARITY: PiP tvOS cell n/a → ✅; new "Background play" row (tvOS n/a —
  TV apps suspend; Android ⏳ MediaSessionService).
- Owner spot-check on device: background a playing film (audio should
  continue + lock-screen controls), Home-swipe auto-PiP on iPhone, tvOS
  PiP via the TV button.


### 2026-06-13 — Autonomous full-queue parity wave (web + Android)
Owner: "Go ahead and do all of them autonomously." App 1.2.23 (b36);
Android assembleDebug green; web JS-checked + headless-verified
(collections, cartoons render).
- **Web**: MediaSession (lock-screen/media-key play/pause/seek/next/prev),
  PiP button (Chrome + Safari APIs), persisted playback-speed selector,
  series-page Share; Collections (#/collections via the index's NEW
  collections map — build_catalog_index schema 5, 26 curated collections);
  Cartoon Mode (#/cartoons: character shelves + Marathon from the cartoon
  channel pool); user channels (type/era form — index has no genre; IDB v3
  'channels' store; lazy URL resolution via detail shards; rail tap
  deletes). SW v10.
- **Android**: media3-session MediaSession + subtitle button; Collections
  (byCollection over item_collections + bundled collection_metadata.json);
  Cartoon Mode (Surprise → Cartoons); cast tap → PersonScreen (FTS); user
  channels (user.sqlite, chip-picker dialog, guide rows lead, long-press
  deletes); static App Shortcuts (Surprise/Channels deep links).
- **Deliberately deferred** (PARITY notes say why): Google Cast, Android
  Activity-PiP, Glance widgets, web subtitles; OWNER-blocked: Drive OAuth
  (sync W+A), Pages→Actions flip (web FTS → person browse/real search).


### 2026-06-12 (night) — Parity completeness audit + gap closures
App 1.2.22 (b35); all three app builds green. Owner: "audit all features to
ensure we have identified all of the items that should go in the parity
matrix."
- **Audit found 5 missing rows** (added): Share titles/series; Commercial-
  break controls; Search result filters; Cast → person filmography; Now
  Playing / lock-screen media controls (MediaSession gap on web+Android).
- **Audit found 4 wrong/stale cells** (corrected): user-channel "(synced)"
  claim was FALSE (AWSync never carried channels; ch: tombstones never
  applied) — now REAL: AWSync gains a `channels` blob (same record type, no
  new schema deploy needed) + ch: tombstone application + UserChannel
  merge, both Apple platforms; Android autoplay = toggle-only (🚧, engine
  wiring pending); web director shelves blocked on index data; web
  hide-watched blocked on a settings surface.
- **Gap closures shipped**: iOS Channels commercial-breaks toolbar toggle
  (AppStore_iOS setting; weave gated — was unconditional; per-ad length cap
  stays tvOS-only, noted); Android Home director shelves (topDirectors/
  byDirector were already in CatalogDatabase).
- Remaining ⏳ queue (by size): Cartoon Mode W+A; Collections W+A; user
  channels W+A; MediaSession W+A; subtitles/speed W+A; PiP/Cast; Android
  cast-tap person browse; widgets/App Shortcuts; OWNER-blocked: Drive OAuth
  (sync W+A), Pages→Actions flip (web FTS5 → person browse, real search).


### 2026-06-12 (later) — Channels everywhere: iOS true EPG grid + Android & Web ports
App 1.2.21 (b34). Owner: "both the channels port to the other platforms and
a rework of the channels view on iOS... the true grid that is essential for
it to feel like you are looking at a tv listing... native to their
respective platforms."
- **iOS rework** (iOS-DESIGN §2.5b): the now/next LIST replaced by a
  proportional EPG grid — pinned half-hour ruler (LazyVStack stickyHeaders),
  fixed channel rail (tap → full-day schedule), runtime-proportional blocks
  on a 120/180-min window (compact/regular), chevrons + deliberate
  horizontal swipe page the window ±90 min (clamped to the broadcast day),
  NOW snap-back + red now-line. Sim-verified (screenshot: real TV listing).
- **Android** (ANDROID-DESIGN §3.1 five tabs + §4.6): Kotlin
  ChannelScheduler port (FNV-1a + SplitMix64 + 6 AM local anchor + per-type
  runtime defaults — same constants), ChannelsScreen Compose guide (sticky
  ruler, custom Layout placing blocks by minute offset), Channels tab.
  Tuning rides the Media3 queue with commercials woven, startPositionMs
  join-in-progress, persistProgress=false (channels never pollute Continue
  Watching — PlaySpec gained both fields). assembleDebug green.
- **Web** (WEB-DESIGN §4.13): `tools/build_channel_pools.py` emits
  channel-pools.json (14 channels × ≤90 programs + 60 commercials, 219 KB —
  the index lacks runtime/genre; wired into publish-db's index step); the
  browser runs the JS Scheduler port (BigInt SplitMix64) so the day anchors
  to the viewer's LOCAL 6 AM; #/channels renders a sticky-rail/ruler CSS
  listing (rows width:max-content — the sticky-containing-box gotcha) with
  now-line + auto-scroll-to-now. Player gained startAt + persist:false.
  Headless-verified (screenshots).
- docs channel skipped on web (4 documentary items total — same data gap as
  the category tile). User-created channels on W+A remain next wave.


### 2026-06-12 — Cross-platform parity wave: Web + Android close the launch gaps
User: "continue working on our parity matrix across all platforms to make
sure we can launch on all platforms with the same features across the
board." Two waves, both verified (web headless screenshots; Android
assembleDebug green).
- **Web** (commit 947901f): Home discovery rows (category accent tiles
  count-gated ≥30, Hidden Gems from the popularity tail, PD Day shelf, era
  tiles LAST), #/surprise re-roll grid in the topnav, More Like This on
  Detail, IndexedDB playlists (schema v2; Detail dialog + Library +
  #/playlist/{id}), season-queue episode binge. SW shell v7. WEB-DESIGN
  §4.1 amended + new §4.9–4.12.
- **Android**: category/era tile rows + Home shuffle → Surprise grid
  (Route.Surprise/Filtered/Playlist + DiscoverScreens.kt), playlists
  (user.sqlite table + Detail dialog + Library tab + PlaylistScreen),
  hide-watched Settings toggle filtering Home, episode binge via native
  Media3 queue (per-item progress; next/prev buttons enabled).
  ANDROID-DESIGN §4.1 amended; §7 updated.
- **REMAINING launch gaps** (PARITY ⏳): Channels EPG on Web+Android
  (ChannelScheduler ports — biggest single item), Cartoon Mode (W+A),
  Collections (W+A), director shelves (W needs index data; A has query),
  user channels (W+A), web FTS5 (OWNER: Pages→Actions flip, WEB-DESIGN
  §2.5), Drive App Data sync W+A (OWNER: Google OAuth client), subtitles/
  speed + PiP/Cast (player wave), Android widgets/App Shortcuts.


### 2026-06-11 (night) — Playback optimization: streaming loader + node pinning (Decision 031)
App 1.2.20 (b33), both sims green. Owner: "nearly every video [has] at least
one or two pauses... sometimes a dozen or more."
- Diagnosed with NEW env-gated diagnostics (AW_PLAYBACK_DIAG=1 →
  AWSTREAM/AWSTALL/AWBUF logs; AW_AUTOPLAY=1 + AW_START_ITEM = unattended
  sim playback). Baseline (8 min, high-bitrate BluRay title): every 2MB
  chunk paid the archive.org/download 302 (~0.5-1.0s TTFB vs node-direct,
  curl-measured), bytes reached the player only at chunk COMPLETION (2.6s
  avg holes), mid-chunk timeout re-downloaded the whole chunk; effective
  8.7 Mbps; buffer never reached its 300s target.
- ResilientStreamLoader rewrite (Decision 021 invariants kept): per-task
  URLSessionDataDelegate streams every Data slice to AVFoundation as it
  arrives (byte-exact resume), post-redirect storage node PINNED from the
  first probe (dropped on failure — nodes rotate; 416 = clean EOF), 8MB
  chunks. AFTER, same title: 34.9 Mbps (4×), 0.9s/8MB turnaround, 100%
  requests on the node, buffer fills in seconds; startup metadata reads
  1.5s → 53ms. Second content type (65MB cartoon) verified: fully buffered
  in ~6s. Shared loader → tvOS gets it identically (tvOS build green;
  PlaybackDiag attached in tunePlaybackBuffering).
- Real-world stall conditions (living-room wifi, busy nodes) can't be
  reproduced on the dev box — owner should judge on-device; if stalls
  persist, run with AW_PLAYBACK_DIAG=1 and read AWSTREAM retry lines.

### 2026-06-11 (evening) — Classic TV poster gate + SNL editorial demotion
App 1.2.19 (b32), both sims green. Owner: poster-less items in Classic TV
("source them or not show them") + SNL rights caution ("searchable and at
the end of the list on browse... I'd rather not highlight it").
- **Classic TV category grid now requires hasRealArtwork** (190 of 218
  cards qualify; the 28 poster-less stay reachable via Browse→TV + Search).
  SOURCING follow-UP for the 28: TVDB didn't match them (obscure clusters:
  Beat the Clock, Grand Ole Opry…) — try TVmaze artwork or frame covers.
- **Editorial demotion mechanism**: featured.json `deprioritizedSeries`
  (seeded with series:saturday-night-live-1975) → Featured model →
  CatalogDB.demotedIDs (set on every DB swap, both stores) → ORDER BY
  prefix sorts demoted ids LAST in browse-popular + seriesCards (category
  grid, Browse→TV, tvOS TV Shows). Still searchable/playable — only never
  the marquee. SQL-verified: SNL is the final row; Four Star Playhouse etc.
  lead. Curate dashboard round-trips the new key (exportJSON serializes
  whole object).
App 1.2.18 (b31), both sims green. Owner: "the Classic TV category contains
no items and there are a few others with very few or poor quality titles."
- **Classic TV was empty on BOTH apps**: `CatalogDB.browseSQL/browseCount`
  unconditionally excluded `tv-series` THEN appended `contentType =
  'tv-series'` for the category filter — contradictory WHERE → 0 rows. Now
  an explicit tv-series request browses the 218 SERIES CARDS (routing to
  SeriesDetail already existed on both platforms).
- **Popular sort is designed-art-first** everywhere browse is used:
  `(hasRealArtwork AND artworkSource != 'generated') DESC, popularity DESC,
  episodesCount DESC` — series cards have NULL popularity, so episode depth
  breaks ties (SNL/Four Star Playhouse lead). SQL-verified against the DB.
- **Category tiles count-gated (≥30)** on iOS + tvOS — documentary (4 items
  total!) no longer shows a dead tile.
- **iOS Home: decade tiles moved to LAST row** (tvOS parity); iOS-DESIGN
  §5.1 amended + new §5.1b (robust-category rule).
- NOTED for the pipeline: top "newsreels" include misclassified modern items
  (e.g. council-meeting uploads tagged newsreel) — a contentType remediate
  rule, not an app fix.

### 2026-06-11 — CloudKit sync root-caused + rewritten; Detail width-overflow fixed
App 1.2.17 (build 30), iOS + tvOS sims green.
- **Why sync NEVER worked** (owner tested iPhone↔Apple TV, nothing synced):
  pulls used `CKQuery(NSPredicate(value: true))`, which requires a queryable
  index on `recordName` that CloudKit never auto-creates — every pull failed
  "recordName is not marked queryable" and the silent catch hid it. Pushes
  worked; devices never converged. REWRITTEN: four fixed-ID records, one type
  (`AWSync` / tombstones·favorites·playlists·progress, JSON payloads),
  fetched by record ID — no queries, no indexes; merge semantics unchanged
  (tombstones → union favs → LWW playlists/progress). Sync status is now
  @Observable + surfaced in Settings→Account (Last sync / error / Sync Now)
  on BOTH platforms — never silent again. Owner deployed the schema to
  Production and **VERIFIED CROSS-DEVICE SYNC WORKING iPhone↔Apple TV
  (2026-06-11)** — #11/#11b finally closed end-to-end. Runbook updated
  (Production deploy step; don't mix Dev/TestFlight builds when testing).
- **Detail view "often not rendering correctly"** (owner screenshot: text
  clipped off both edges): reproduced via AW_START_ITEM + diagnosed with
  temporary width probes — a fill-mode AsyncImage reports its COVER size and
  `frame(maxWidth:.infinity)` ADOPTS the oversized child; items WITH a 16:9
  backdrop blew the hero to 604pt on a 402pt screen (poster-only items were
  fine → intermittent). Fix: ambient/hero art moved to `.background` (can't
  influence layout) in DetailHero + Home HeroCarousel. Probes removed.
  PATTERN for the playbook: never put a fill-mode image in a
  maxWidth:.infinity frame; use .background + .clipped().
- AW_START_ITEM hook now retries on dbVersion (items beyond the seed open
  once the full DB swaps in).

### 2026-06-10 (late) — iPhone/iPad wave: Channels tab, contrast audit, tappable cast, live sync, framed posters, search filters
Owner's 7-item iOS punch list, all sim-verified (iPhone 17 Pro + iPad Pro 11"
26.5; tvOS re-verified green). App 1.2.16 (build 29). iOS-DESIGN §2.1 amended
(five tabs incl. Channels), PARITY rows updated.
- **Channels = top-level tab**; Home modes pill row REMOVED (Surprise/Cartoon/
  PD Day live behind the Home shuffle button → Surprise grid).
- **Contrast audit**: root cause = global AccentColor #0047FF under forced
  dark mode (bordered buttons/links drew dark-blue-on-dark). Fix: dark-
  appearance AccentColor variant (#4D7DFF) + Apple-style white SiwA button.
  Everything else already white/secondary/orange.
- **Cast/crew bubbles tappable** → BrowseFilterRoute(person:) →
  FilteredGridView via CatalogDB.byPerson (tvOS PersonChip parity; director
  leads the row with role captions).
- **Library sync**: iOS only synced at launch + after local edits — added the
  tvOS live triggers (foreground + 60s timer), sign-in gated. NOTE: most
  likely the owner never signed in on iPhone because the SiwA button was
  unreadable; on-device cross-device verify still owner-pending
  (cloudkit-setup runbook).
- **Detail poster framing**: hero rendered FILL-cropped (top of art cut off).
  Rebuilt DetailHero: explicit-height aspect-FIT 2:3 poster (rounded+shadow)
  over blurred ambient backdrop; 340pt iPhone / 460pt iPad; TMDb w185/342/500
  → w780 + OMDb _SX300 → _SX800 upsizing on Detail only.
- **Search filters**: type/decade Menu (Browse facet vocabulary) over FTS
  results, filled-icon active state + clear action; tv-series results route
  to SeriesDetail.
- **iOS screenshot hooks**: AW_START_TAB / AW_START_ITEM env vars now work on
  iOS (tvOS RootView twin) — drive Detail/tab screenshots via
  SIMCTL_CHILD_AW_START_ITEM=… simctl launch; cold start needs ~25s before
  the shot.
User found a South Park frame on the AitF page — it was the thumbnail of a
bliptv REVIEW VLOG about an AitF episode (the vlog opens with a South Park
clip; archive.org auto-thumbnailed it). New tool
`tools/audit_series_episodes.py` (report-first, Decision-026-style: the
Archive item's OWN title/collections are the authority; TVmaze resolves S/E
disputes) + `--apply`. Removed 23 confirmed-bad episodes across 9 spines:
review vlog (AitF), 14 GoAnimate "Caillou Gets Grounded" parodies (Caillou +
Bayou Classic — incl. genuinely awful content on a kids' show), Pingu ×2 in
The Snowman, One Step Beyond ep "The Avengers" in The Avengers, Green Acres
"Eb's Double Trouble" in Double Trouble, Mystic Knights in The Challenge,
The Chase UK (contestant "Alf") in ALF, Catch 21 (contestant "Angie") in
Angie. Root pattern: episode-title/contestant-name collides with another
show's name. Backfill ingest now also rejects vlogs/bliptv collections +
parody markers (`meta_ok`) and parody-titled candidates. CI: audit runs
--confirm --apply in discover-content after the backfill, CSV artifact
`episode-audit`. False-positive guards verified: "S3E28 The Avengers"-style
uploads, Degrassi franchise cross-refs, real episode titles containing
"review"/"reaction" all KEEP. south-park-1997 spine is dormant (card
excluded by rights audit, not in public index).
User-reported fixes, all on `main`, web changes live after Pages deploy.
- **Web images**: archive.org throttles poster bursts (transient 503s);
  `wireArt()` now retries the fallback chain ×2 with jittered backoff;
  typographic placeholder card (`card-ph`, Decision-013 accent) when art
  fails for good — and ALWAYS for poster-less `series:` ids, which were
  pulling the Archive's generic gray placeholder on Browse (71/218 series
  rows). About & Attribution rebuilt in the viewer card language with ✕ +
  Back affordances. SW shell → v6. WEB-DESIGN §6.3 updated.
- **Adult filter on web**: upstream-only by design (§8.3) — verified
  build_catalog_index drops excluded/isAdult/adult-collection items; no
  client toggle until the §2.4 data layer.
- **TV mismatch audit** (user found an Arabic Facebook video in All in the
  Family): backfill_tv_episodes accepted (a) transcript-dump titles that
  defeat word-overlap matching, (b) candidates whose S/E matches but whose
  title puts the show name AFTER the SxxEyy marker (Murphy Brown S08E12
  "All in the Family"). Added `candidate_ok()` guards (scrape-id prefixes,
  200-char title cap, show-before-marker rule) to BOTH search paths.
  Removed both bad eps from the AitF spine; TVmaze-verified + fixed 6
  misassigned episodes (WKRP, Death Valley Days, Rocky Jones, Vicar of
  Dibley ×2, Hill Street Blues). REMAINING (flagged, unverifiable without
  watching): ~15 "colorized SxEy" uploads (AHP ×7, Twilight Zone ×3,
  Doctor Who, Outer Limits, Out of the Unknown ×2, Avengers ×2) assigned
  to different episodes than their id claims — likely compilations or
  fuzzy-title mismaps; also sigmund S1E3-id→S1E2, space-patrol S1E1-id→
  S5E2. Degrassi Jr High vs Junior High = duplicate spines of one show
  (separate cleanup). Catalog-card episodesCount syncs on next CI pass.
All on `main`, pushed, LIVE at archivewatch.org. App version unchanged (1.2.15).
- **Share links → archivewatch.org everywhere**: tvOS ShareSheet QR (items
  /item/{id}, series /series/{slug}, loc: stays loc.gov), iOS Detail + new
  SeriesDetail toolbar ShareLink (slug percent-encoded), Android Detail share
  action (ACTION_SEND). Web Detail shows the share MENU (<dialog>): Open in
  app (archivewatch:// on Apple; intent:// w/ fallback on Android), Share
  link, archive.org. All three app platforms re-built green.
- **Owner follow-ups DONE**: Associated Domains entitlement in
  ArchiveWatch.entitlements (applinks+webcredentials; registers at next
  archive); Android App Links (autoVerify manifest filter + MainActivity
  routes /item + /series); **upload keystore ~/keystores/archivewatch-
  upload.jks, creds in ~/.gradle/gradle.properties — NEVER in git**; signed
  assembleRelease verified; assetlinks.json LIVE (upload+debug SHA256s; add
  Play App Signing print at enrollment); .nojekyll (Jekyll was dropping
  .well-known); docs/app-store-listing.md URLs → archivewatch.org (ASC paste
  = owner; no API key on this machine). HTTPS enforced (owner).
- **Web fixes (user reports)**: detail SHARDS details/{00..ff}.json
  (build_web_details.py, FNV-1a low byte, in publish-db daily) carry
  downloadURL/synopsis/director/cast(+TMDb profilePath)/genres/runtime/
  backdrop → Detail + playback are catalog-first (archive.org metadata API
  hangs 30s+ on some items; now a bounded fallback only). Cast/crew bubble
  row on Detail. Per-visit random hero/shelves. Rail scroll-padding inset
  fix. **Home = professional art only** (index schema 4 `pro` col); **TV
  shelves = series cards** (decade from shelf id → SeriesDetail). Editor's
  Picks (2/7 pro) + Newsreels (3) dropped off Home until ≥4 pro posters —
  flagged to owner; exemption for curated shelves is a one-liner if wanted.
- **Verification pattern that works**: execute the real watch.js in a Node
  DOM shim (headless Chrome --virtual-time-budget distorts timers/
  AbortSignal; --timeout dumps at load, pre-hydration). Pixel-measure
  layout via PIL on screenshots. Pages CDN caches 600s — cache-bust checks.
- **Resume next**: owner archive (registers Associated Domains → verify AASA
  via Apple CDN), ASC URL paste, decide Editor's Picks exemption vs art
  refresh, Android next wave (ANDROID-DESIGN §7), web FTS5/SQLite upgrade
  (WEB-DESIGN §2.5), iPad/device spot-checks.

### 2026-06-10 — archivewatch.org goes live: viewer at root, curator at /curate/
Owner purchased archivewatch.org + pointed Pages at it (CNAME committed).
Restructured per Decision 030: the consumer viewer moved /watch/ → site ROOT
(index.html + watch.js/.css + sw.js + manifest at /, SEO/OG meta added); the
editorial dashboard moved root → /curate/ (assets via ../, js/app.js fetches
featured/catalog-index root-absolute; its own manifest). 404.html forwards
/item/{id}, /series/{id}, and legacy /watch/* (GitHub 301s the old
bhwilkoff.github.io/Archive-Watch/* URLs to the apex, hash intact). App share
URLs + SeriesStore now use archivewatch.org. Universal Links UNBLOCKED: AASA
for L2G756LY8N.app.archivewatch.tvos (/item/*, /series/*) ships at
/.well-known/ — owner step remaining: add the Associated Domains capability
(applinks:archivewatch.org) in Xcode (kept out of entitlements to protect
in-flight signing). robots.txt added. Earlier same day: Marquee responsive
hero (container-query fluid, WEB-DESIGN §4.7), working TV series surface
(§4.8 — series: ids were hitting the archive.org metadata API and failing),
editorial shelves map in catalog-index (schema 3, Decision 029 amendment —
live scrape was returning identical unvetted lists), brand logo + footer
chrome. Owner ASC follow-up: update marketing/support URLs to
archivewatch.org.

### 2026-06-09 (later) — Autonomous all-platform buildout: iOS P1/P2 closed, Web PWA live, Android P4 shipped
User: "finish all phases of our buildout for the ArchiveWatch app across all
platforms that we have documented should receive full parity." All on `main`
(merged from `ios-universal`), every step build-verified; PARITY.md updated per
change set. App version 1.2.15 (build 28).
- **iOS/iPadOS — P1/P2 parity gaps CLOSED** (all sim-verified, tvOS re-verified
  green after each shared-file touch): Home discovery (category + decade tile
  rows → new generic `FilteredGridView`, Hidden Gems, Director shelves, Public
  Domain Day shelf, Modes capsule row), Surprise grid (11 re-rollable tiles;
  Home shuffle now opens it), Public Domain Day year-chip explorer, **Channels
  touch guide** (shared date-seeded ChannelScheduler; now/next rows, tune-in
  joins in progress, commercial breaks woven, full-day schedule view, Create
  Channel Form sheet + swipe-delete with tombstones; `Channel` presets moved to
  shared Models/Channels.swift), **Cartoon Mode** (kid-safe color-leaning pool,
  character + theme shelves, marathon via new lineup player), playlists
  (AddToPlaylistSheet + Detail button + swipe-delete), manual prev/next episode
  overlay (binge auto-advance reports back via onAdvance), hide-watched +
  per-category Settings toggles (HomeView now feeds completedArchiveIDs).
  Channel/lineup playback never persists WatchProgress. xcuserdata untracked
  (merge friction fix).
- **Web PWA (P3) — SHIPPED + LIVE**: `/watch/` viewer (vanilla, no build step,
  mobile-first, URL-driven hash state) — Home hero + shelves, Browse with
  chips/facets + infinite scroll, client search, Detail hydrated from the
  archive.org metadata API, `<dialog>` player with the Decision-021-analog
  reconnect wrapper + IndexedDB resume, Library, About (verbatim TMDb notice +
  donate), installable PWA + service worker, and `404.html` forwarding the
  canonical `/item/{id}` share URLs the apps already emit. **Decision 029**
  (data plane: index + metadata API now; chunked SQLite via Actions-Pages
  later) after live CORS/Range measurements (Pages = 206+CORS on GET; Release
  assets + archive.org download = 206 without CORS). `build_catalog_index.py`
  → schema 2 with designed-poster column (additive). Live at
  https://bhwilkoff.github.io/Archive-Watch/watch/ (verified 200s + forwarder).
- **Android (P4) — v1 spine SHIPPED** (`android/`, Kotlin + Compose M3,
  `app.archivewatch.android`, from TriAppTemplate simplified to manual DI +
  sealed-route nav): contract-compliant data layer (bundled seed → ETag .zz
  download → raw-DEFLATE inflate → ≥10MB floor + open-probe → atomic swap;
  BundledSQLiteDriver for guaranteed FTS5; build-time copy of seed/featured
  from the repo), Home/Browse/Search/Detail/SeriesDetail/Library/Settings,
  Media3 player with OkHttp + patient LoadErrorHandlingPolicy (Decision 021
  analog), archivewatch:// deep link, dark brand theme. assembleDebug GREEN +
  emulator-verified (Browse showed 27,029 titles from the downloaded full DB).
  Deferred next wave in docs/ANDROID-DESIGN.md §7 (Channels, modes, widgets,
  Drive App Data sync, Cast, playlists).
- **Docs/skills**: docs/CATALOG-CONTRACT.md (the Decision-028 shared-schema
  artifact; notes build_sqlite docstring drift), docs/iOS-DESIGN.md,
  docs/WEB-DESIGN.md, docs/ANDROID-DESIGN.md binding docs; project skill
  `web-catalog-data-layer` (verified CORS/Range matrix).
- **Owner-pending**: on-device spot-checks (iOS Channels/Cartoon tune-in, iPad
  landscape hero), CloudKit cross-device verify (existing), Pages→Actions flip
  when the web SQLite upgrade is wanted (WEB-DESIGN §2.4), Play Store record
  for Android (none yet), Google OAuth client for Drive sync (Android/Web wave
  2). Universal Links remain blocked: a project Pages site can't serve root
  `/.well-known` (needs a user site or custom domain).

### 2026-06-09 — Multi-platform plan + iOS Phase 1 kickoff
- **Plan + parity** (Decision 028): expanding tvOS → iOS → iPad → Web → Android per
  the TriAppTemplate (`docs/MULTIPLATFORM-PLAN.md`, `PARITY.md`). Feature-parity-not-
  design-consistency; shared `catalog.sqlite` data plane reused untouched; per-
  ecosystem sync on the user's OWN cloud (CloudKit for Apple; Google Drive App Data
  for Android + Web), NO separate backend.
- **iOS Phase 1 — foundation + core spine (in `ios/`, NOT yet an Xcode target):**
  - **Shared Core extracted + COMPILE-VERIFIED for iOS** (`ios/Core/` + `ios/Package.swift`
    → `xcodebuild -scheme ArchiveWatchCore -destination generic/platform=iOS` =
    BUILD SUCCEEDED). 15 files: Catalog/UserState models, CatalogDB, CatalogRefreshService,
    ResilientStreamLoader, ContinuousPlayback (decoupled via a `ContinuousPlaybackSource`
    protocol so Core doesn't import the app store), ChannelScheduler, CollectionMetadata,
    SeriesStore, CatalogLoader, ImageLoader, CloudKitSyncService, HTMLStripper, SplitMix,
    Color+Hex. Every "tvOS" reference in these was a comment/UA string, not an API —
    proving the ~60-70% reuse thesis.
  - **Native iPhone UI written** (`ios/App` + `ios/Views` + `ios/Components`): App entry +
    ModelContainer, AppStore (loads featured + seed→full DB swap; conforms
    ContinuousPlaybackSource), Router (bottom TabView), RootView, Home (hero+shelves+
    Continue Watching), Browse (grid+facet/sort menu+paging), Detail (Play/Favorite/
    Share/More-Like-This/cast), Player (AVPlayerViewController + PiP + ResilientStreamLoader
    + resume), Search (.searchable FTS5), Library (Favorites/Watched/Playlists), Settings
    (mature toggle+attribution+donate). Deep links (archivewatch:// + Universal Link twin).
  - **Config:** `ios/Info-iOS.plist`, `ios/ArchiveWatch-iOS.entitlements` (SAME CloudKit
    container `iCloud.app.archivewatch.tvos` → iPhone syncs with the Apple TV), README
    with the exact Xcode target-creation steps.
  - **One remaining step (owner, Xcode GUI):** create the iOS app target + add the
    `ios/{Core,App,Views,Components}` folders + bundle seed.sqlite/featured.json. See
    `ios/README.md`. The in-review tvOS Xcode project was deliberately NOT touched;
    Core is duplicated for now (unify to a package post-review).
  - Out of scope this phase: TV Shows drill-in, Collections, Surprise/Channels/modes,
    iPad NavigationSplitView, WidgetKit, sign-in/sync UI — queued next.

### 2026-06-08 (later) — Rights audit applied + CloudKit #84 (v1.2.12, build 25)
**State**: all on `main`, app builds clean tvOS 26.5 sim. The pre-submission
copyright/rights audit is DONE and APPLIED; CloudKit deletion/live sync shipped.

**Rights audit (Decision 027)** — `tools/audit_rights.py`, report-first + network
confirm. Buckets every item by PD confidence (US year tiers x colorMode x gov/CC
collections x the Archive item's OWN licenseurl). Confirm phase (CI, archive.org
blocked from local sandbox) fetched licenseurl+date for ~5,100 modern PD-labelled
items: **475 rescued** by a genuine CC0/CC dedication (kept), wrong-dated old films
re-anchored, **failed fetches left UNCONFIRMED (never wrongly hidden)**. Applied:
**6,168 items hidden** via a reversible `excluded` flag (4,596 modern copyrighted
films w/ no real license — Schindler's List, Fargo, Peanuts Movie…; 1,040 modern
brand ads ≥1995; 528 commercial slop/compilations; 4 modern no-year). **32,309
visible.** `build_sqlite` (full DB + bundled seed) and `build_catalog_index` skip
`excluded`; item stays in catalog.json (flip to restore). Owner policy: keep all
1964-77 (PD-by-defect era incl. Night of the Living Dead); commercials cutoff 1995.
Manifest `tools/rejected_audit.csv` (gitignored; CI artifact) carries per-item
Archive evidence + a `SUSPECT_old_video` flag — all 284 suspects reviewed, none
are wrong hides (genuinely-modern B&W films). CI: `rights-audit.yml` (confirm),
`apply` done locally then published + publish-db. **48 modern items remain
unverifiable** (archive.org didn't respond; 4 dark) — left VISIBLE pending a
decision/re-confirm (a couple are mislabeled-old PD like a 1933 Bosko cartoon
tagged 2018, which must not be wrongly hidden).

**CloudKit #84 (#11b)** — deletion propagation via `Tombstone` model (a removed
favorite no longer resurrects on pull; re-add newer than the tombstone clears it),
playlist merge by `modifiedAt` recency (removals propagate), and LIVE triggers
(foreground + post-edit debounce + 60s timer). Builds clean. On-device verify
across 2 Apple TVs is owner-pending (checklist in `cloudkit-setup.md`). APNs push
subscription deferred.

**#88 status**: reached TestFlight; no hidden engineering left. Real blocker is
**#87** (blank ASC icon / stretched iPhone SiwA icon — owner must resolve in ASC).
Then: paste listing from `docs/app-store-listing.md`, archive build 25, submit.

### 2026-06-08 — Pre-submission compaction handoff (v1.2.11, build 24)
**State**: all on `main` (HEAD `c1034dd`), builds clean tvOS 26.5 sim. Catalog
(~38,405 items) on the GitHub Release (Decisions 017/018). This session shipped a
large wave; next up is the **App Store submission push** + a **copyright/rights
audit** before submitting.

**Shipped this session** (each committed + version-bumped where app-facing):
- TheTVDB enrichment: professional posters + cast for TV (217 series) and movies
  (`enrich_tvdb_tv.py`/`enrich_tvdb_movies.py`, `tvdb_lib.py`, `tvdb-movies.yml`).
- Cast/crew profile images (`enrich_cast_images.py`, `cast-images.yml`).
- Cover pipeline WIRED: ~19,134 frame covers applied (apply_covers → publish).
- **Color/B&W flag** `colorMode` (Decision 025): `classify_color.py` (ffmpeg
  signalstats saturation, threshold 8; cover-frame fast-path), `color-classify.yml`
  (every 8h), ~97% classified. Wired into Catalog.Item (`isColor`/
  `isBlackAndWhite`), Cartoon Mode/Channel color-emphasis, remediate B&W
  wrong-match rule, and the match verifier.
- **Archive-anchored match verifier** (Decision 026): `verify_external_match.py`
  (Tier 1 Archive imdb → Tier 2 Archive date → Tier 3 color), `verify-matches.yml`.
- Home hero carousel: final design = single full-width swapping banner + an
  invisible left focus-"catcher" (Left = previous until leftmost → sidebar; Right
  wraps; Down → shelves; no neighbor slivers). Playbook §9.2.
- Button legibility audit → `BarButtonStyle` (Channels header + secondaries).
- CloudKit sync ENABLED (`CloudSync.entitlementConfigured = true`); runbook
  container id fixed to `iCloud.app.archivewatch.tvos`.
- Cartoon Mode excludes silent / B&W de-emphasized; Cartoon Channel ≤10% silent.
- Playlist tile fixed (matches PosterTile spacing 28 — no focus-overlap).

**FINAL SCOPE before submission** (start here after compaction — full detail in
the `submission_push_handoff` memory):
1. **Copyright/rights audit (main task):** 8,121 items are year ≥1978 (≥2010:
   2,767) yet 37,001/38,405 are `rightsStatus=public_domain` — modern,
   clearly-copyrighted titles are mislabeled PD (e.g. "The Stranger" 2025, "The
   Peanuts Movie" 2015). Build a report-first `tools/audit_rights.py` that buckets
   wrong-match-fixable (old video, modern metadata → fix via
   `verify_external_match.py`) vs. genuinely-modern-copyrighted (drop/hide).
   Signals: year ≥1978 AND not gov/PD-collection AND not CC AND a confident modern
   external match; cross-check Archive `date`/`external-identifier` + `colorMode`.
   `_PD_BY_AGE = 1929`; removal must be additive-safe (Decision 020).
2. Complete outstanding: #88 submission (ASC record, listing from
   `docs/app-store-listing.md`, screenshots, Push capability, archive, submit),
   #87 ASC/iPhone icon (UNSOLVED), #84/#11b CloudKit deletion+live sync, #86
   color no-frame tail (~783).
3. Full test pass on device.


Implemented the mac-based screenshot protocol that gives a real poster to every
catalog item no third-party source covers. Audit: **56% of the catalog (20,962
items) lacked designed art** — all 2,390 commercials + the long tail. Three
resumable stages (committed `dfce40e`, Decision **023**, runbook
`docs/runbooks/cover-generation.md`):
- `tools/batch_covers.py` (wraps `frame_cover.py`: ffmpeg + opencv face/sharpness
  scoring) — grabs the best real frame per item, popularity-first, concurrent,
  resumable via `manifest.jsonl`. Pure measurement, nothing hallucinated.
- `tools/upload_covers.py` — publishes covers to ONE archive.org item
  `archivewatch-covers` (IAS3 API; keys env-only, never committed); per-cover URL
  `https://archive.org/download/archivewatch-covers/<slug>.jpg`. Verified
  end-to-end (200 image/jpeg). Hosting = owner choice (archive.org, on-brand).
- `tools/apply_covers.py` — wires posterURL + artworkSource="generated" +
  hasRealArtwork into the catalog; additive + count-guarded (Decision 020).
- Fixed `frame_cover.py` to write proper-quality JPEG (was applying a PNG flag).
- **LIVE**: full ~20,900-item run is going under `caffeinate -i` (workers 16),
  nohup, resumable — a ~1.5-day unattended batch (~8/min, network-bound). Finish
  with: `upload_covers.py` → `catalog_release.py fetch`/`apply_covers.py`/`publish`
  → publish-db. `tools/covers_out/` is gitignored. See `cover_generation_protocol`
  memory for the live state + remaining steps.

### 2026-06-05 — Commercials, real Channels EPG, Browse pagination, public tool, App Store prep
App now **1.1.0 (build 12)**, all on `main`, builds clean (tvOS 26 sim). Big batch:
- **Commercials**: ingested ~2,390 PD/CC0 vintage commercials as a new
  `commercial` contentType (Duke AdViews excluded — no license). Kept OFF Home
  (`CatalogDB.notCommercial`); surface via the Commercials collection, Random
  Commercial (Surprise), and channel breaks. New `tools/discover_commercials.py` +
  `--prioritize-source` ingest flag; wired into discover-content.
- **Channels → a real EPG**: deterministic date-seeded schedule
  (`ChannelScheduler`) rendered as a **proportional guide** (3-hour window, blocks
  sized to runtime on a shared ruler, vertical-scroll-only for native tvOS focus),
  with vintage commercial breaks between programs, join-in-progress, rating chips.
  (Replaced an earlier uniform-column version that looked "regimented".)
- **Playback fix**: next video / next episode loaded + seeked but never played —
  both players now `play()` on `.readyToPlay`.
- **Browse (Movies)**: shows the REAL total (`CatalogDB.browseCount` → "30,615
  titles") instead of the 500 cap, + **infinite scroll** (300/page) with the JSON
  decode moved off-main for smooth fast scroll.
- **Home modes row (#82)**, **idle screensaver (#83**, opt-in, never over
  playback), **redesigned Create Channel + Add to Playlist** (native pills/cards).
- **Public web tool**: editorial dashboard → public **Suggest & Curate** with a
  full-catalog search index (`catalog-index.json`, refreshed by publish-db),
  mailto submissions/export, real branding + square favicon. README rewritten.
- **App Store prep**: `docs/app-store-listing.md` (full listing + TestFlight notes
  + Copyright `© 2026 Ben Wilkoff`); 10 screenshots (3840×2160) on
  `~/Desktop/ArchiveWatch-AppStore-Screenshots/`; screenshot env hooks
  (`AW_START_TAB`/`AW_START_ITEM`, no-ops in prod). `tools/frame_cover.py` built +
  validated for commercial covers (hosting/wiring remains).
- **Backlog to continue**: #88 App Store submission (owner: add Push capability,
  create ASC record, paste fields, upload screenshots, archive build 12, submit);
  #84 CloudKit on-device flip; #87 ASC icon (tvOS platform limit, see memory);
  #86 commercial-cover hosting; #82 cartoon wonderland shell; #92 in-program
  breaks. Curation loop PAUSED (resume only on explicit ask). Full handoff in the
  `session-handoff-2026-06` memory.

### 2026-06-04 — Metadata quality program + pipeline crash fixes
- **Metadata quality program** (`docs/architecture/metadata-audit.md`): tiered,
  popularity-weighted, sustainable. Tier 0 `tools/audit_metadata.py` (measure,
  wired into publish-db daily report); Tier 1 `remediate_catalog.py` text
  sanitization (clean synopses/titles every build — items-with-a-blocker 27%→~0%,
  avg score 75→83); Tier 2 = existing enrichment workflows; **Tier 3 = the agent
  loop IS the LLM** (`tools/metadata_review.py` select/apply, loop item **B6** in
  `docs/autonomous-curation-loop.md`) — owner runs the loop nightly for one full
  pass, then only new titles (tracked by `agentReviewHash`).
- **Decision-018 crash class fixed**: 4 tools (omdb_backfill, ingest_candidates,
  discover_loc, enrich_movies) were crashing in CI loading the removed committed
  seed catalog.json — silently freezing cast/director, halting ingestion (5.8k
  candidates piled up) + LoC discovery for days, masked by error-tolerant steps.
  Fixed to use the full catalog only. Also: `fetch_omdb` now tolerates non-JSON
  replies (OMDb key verified valid). omdb-backfill re-dispatched; **validation
  pending** (confirm omdb_cache schema 3 + identity, cast climbing).
- **Ops**: killed 2 stuck `until`-loop background shells (~2 days old). All 9
  crons green + intact; nothing overridden.
- Closed all session tasks. Sidebar "full height" (#1) = native tvOS behavior
  (won't-fix unless custom sidebar — separate decision).

### 2026-06-03 — Home cleanup, player-year fix, catalog clobber + recovery
- **App (shipped on main, builds clean tvOS 26.5 sim)**: Favorites is its own
  sidebar tab (above Surprise), not a Home shelf; player no longer shows the
  MP4's embedded creation year (1969/2035/2045) — suppressed via empty
  `externalMetadata` override on BOTH movie + episode players (see
  `docs/tvos-playbook.md` §8.6); Browse-by-Era "1,960s" comma fixed
  (`Text(verbatim:)`) + implausible decades clamped (1890-2029); curated Home
  shelves drop the year<=1977 rights gate (it starved NASA/post-1977 + classic
  TV) and order real-artwork first; stub shelves (<9 tiles) hidden.
- **Pipeline (remediate_catalog.py, runs in every writer)**: precise
  wrong-external-match fix (modern TMDb/OMDb poster+year on a vintage title →
  clear + fix year: CInderella→2015 Disney, Pink Panther); PD-animation
  compilation reels stripped of single-film posters; gov/PD-by-age rights
  inference; Méliès shelf query widened; build_sqlite date-seeded shelf rotation
  (#10). NOTE: a blunt "clear any shared poster" rule was BUILT then DROPPED
  after measuring it would wipe ~2,500 correct posters (foreign titles/AKAs/
  serials share posters legitimately) — precise wrong-match only.
- **INCIDENT + recovery (Decision 020)**: dispatched `rebuild-catalog`, which
  runs `build-catalog.mjs` and OVERWRITES the catalog with a fresh ~1.1k build —
  it clobbered the full ~30k catalog on the release. Recovered the 30,645-item
  pre-Decision-018 `catalog.json` from a dangling git commit (`5ef1795`, via the
  activity-API force_push SHA), remediated + republished. Now 30,374 items.
  Fixed the footgun: `tools/merge_catalogs.py` makes rebuild-catalog additive +
  enrichment-preserving + shrink-guarded (Decision 020); weekly cron kept.
  Re-applied lost enrichment by dispatching the idempotent workflows (Commons
  posters back to 1,873; Wikipedia synopses upgraded; OMDb cast drains daily).
  Runbook: `docs/runbooks/catalog-recovery.md`.
- **Docs**: Decision 020; runbook; tvOS-playbook §7.6 (locale comma) + §8.6
  (player metadata); this entry.

### 2026-05-31 — Full audit + v1.0 hardening pass
- **State found**: this scratchpad was ~6 weeks stale (claimed M0 blocked
  on "create the Xcode project"). Reality: app builds clean on tvOS 26.5,
  ~44 Swift files, six-tab shell, 25k-item catalog, TV-series support,
  Surprise actions — effectively M1–M3 in code. Corrected the playback
  scare (field is `downloadURL`, `itemsPlayable: 25000` — playback is
  fine). Build env note: default `xcode-select` points at
  CommandLineTools; use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Work done** (all builds exit 0 on the Apple TV 4K sim):
  1. Rewrote Current State to match reality.
  2. **Adult filter enforced (Decision 012)** — `AppStore.hideAdultContent`
     (default on, persisted) applied once in `rebuildDerived()` to a new
     `visibleItems` source; every direct `catalog.items` reader migrated
     (Home hero, Search, Surprise ×3, Collections, Detail "More Like This").
     `"fav-"` excluded from adult markers.
  3. **Settings/About tab** (new `SettingsView` + Router/RootView wiring):
     required verbatim TMDb notice (007), source credits, mature toggle
     (012), donate QR + archive.org/donate (010), version.
  4. **`PrivacyInfo.xcprivacy`** — no tracking/collection; UserDefaults CA92.1.
  5. **App icon + Top Shelf PNGs** generated from the master SVG via
     `tools/render-app-icon.sh` (qlmanage + sips — no rsvg/magick on this
     box); authored the `.brandassets` Contents.json. Flat single-layer
     for v1; layered parallax is later polish.
  6. Version 0.1.0 (1) → 0.2.0 (2).
- **Native tvOS 26 pass** (same session, after the user asked to confirm
  modern-tvOS / native-API usage): audit found the app was *already* well
  modernized — `FocusableStyles` uses native `.glassEffect` Liquid Glass +
  `@Environment(\.isFocused)` everywhere, plus native `.buttonStyle(.card)`,
  `.searchable`, `TabView(.sidebarAdaptable)`, `@FocusState`. Genuine
  changes made:
  - GlassPolish + episode-player transport → native `.glassEffect` (the
    last `.ultraThinMaterial` holdouts).
  - Settings rebuilt on native `Form`/`Section`/`Toggle` + nav title.
  - **Playback → `AVPlayerViewController`** (UIViewControllerRepresentable)
    with `externalMetadata` so the native Info panel / scrubber / Now
    Playing show title + synopsis + genre. Verified on-sim.
  - **App Intents + Siri** (Decision 015): Surprise Me / Random Film /
    Random Category via `AppShortcutsProvider` → `IntentInbox` → RootView.
  - **NSUserActivity** on Detail (Siri/Spotlight/Handoff).
- **State left**: all of the above committed on branch `v1-hardening`
  (6 commits), each verified to build clean on the tvOS 26.5 sim; app
  launches, Home + Settings + native player all confirmed on-sim. NOT
  pushed.
- **Second wave (same session) — finished the documented backlog**, all
  committed on `v1-hardening`, each built clean + (where visible)
  sim-verified:
  - **Manual `Info.plist`** (GENERATE_INFOPLIST_FILE = NO): archivewatch://
    URL scheme, `NSUserActivityTypes` (completes Up Next), BG task IDs +
    `UIBackgroundModes`. Deep links route via `ContentView.onOpenURL` →
    `IntentInbox` → RootView.
  - **Top Shelf snapshot writer** + invisible `TopShelfUpdater` (App
    Group, no-ops until the group exists) + **BGAppRefreshTask** (SwiftUI
    `.backgroundTask`, armed on background).
  - **Top Shelf extension target created by hand in `project.pbxproj`**
    (`ArchiveWatchTopShelf`, TVTopShelfContentProvider) + **App Group**
    `group.com.bhwilkoff.archivewatch` on both targets + entitlements.
    Verified: `xcodebuild -list` shows both targets; the `.appex` embeds
    in `PlugIns/` with NSExtensionPointIdentifier `com.apple.tv-top-shelf`;
    full build clean on sim. (Ruby `xcodeproj` gem unavailable + would
    risk the objectVersion-77 synchronized groups, so the pbxproj was
    edited directly.)
  - **Layered-parallax app icon** (Back orange / Middle film frame /
    Front moon) for App Icon + App Store imagestacks; Top Shelf flat.
    At rest identical to the flat icon; actool-validated.
  - **Catalogs slimmed** (`tools/slim-catalog.py`) by dropping `fav-*`
    pseudo-collections: bundled seed 12.6MB → 5.4MB (3,120 items) and the
    root refresh source 74.5MB → 40.9MB (25,417 items). (Earlier commit
    messages said "74.5→33.9" — that conflated the two files; these are
    the real per-file numbers.)
  - **Icon-layer dimension fix**: `qlmanage` renders square thumbnails,
    but tvOS imagestack layers must be landscape (400×240 / 800×480 /
    1280×768). A clean from-scratch build caught this (actool
    GenerateAssetSymbols failure) where incremental builds had masked it;
    fixed by center-cropping each layer to 5:3 (Pillow). Re-confirm the
    clean build in Xcode — the final from-scratch verification this
    session was blocked by a tooling/output issue. If it still fails,
    `git revert` the layered-icon commit to restore the flat icon.
- **State left**: M1/M2/M3 features + the M4 Top Shelf/Up Next/BG-refresh
  surfaces all landed on `v1-hardening` (~13 commits), built clean on the
  tvOS 26.5 sim. NOT pushed — owner to review, build in Xcode, and test on
  Apple TVs.
- **Only owner step remaining for full Top Shelf on-device**: enable the
  App Group capability for the App ID in the Apple Developer account (sim
  needs nothing). See `docs/top-shelf-setup.md`.
- **Next (future)**: confirm the layered-icon parallax + Top Shelf on real
  hardware; make the `tools/` catalog pipeline drop `fav-*` at the source;
  App Store screenshots + metadata for submission.

### 2026-04-17 — Archive Watch foundation
- **State found**: Empty dual-app template on `claude/archive-org-apple-tv-5bKXB`
- **Work done**:
  - Researched Archive.org API, TMDb, Wikidata, Wikimedia Commons, Library of Congress
  - Studied Apple TV / UHF / Channels for tvOS design patterns
  - Wrote `docs/research/metadata-sources.md` (enrichment pipeline, taxonomy, schema sketch)
  - Wrote `docs/research/design-reference.md` (visual + structural spec)
  - Logged Decisions 006–010 (tvOS-only, TMDb, identifier chain, no accounts, free release)
  - Filled CLAUDE.md project identity (Archive Watch, tvOS primary)
  - Rewrote SCRATCHPAD with M0–M4 milestones
  - Scaffolded `ios/Networking/` and `ios/Models/`: HTTPClient, ArchiveClient,
    TMDbClient, WikidataClient, DerivativePicker, ArtworkResolver,
    EnrichmentService, ContentItem, Taxonomy, response types
- **State left**: Ready for Xcode tvOS project creation (M0 final gate before M1 UI work).

### 2026-04-19 — Categorization schema + seed catalog pipeline
- **State found**: Editorial + icon + tvOS integration plan complete; owner asked to start the categorization schema and the cache database of popular videos for launch.
- **Work done**:
  - Authored `docs/taxonomy/collections.json` as the authoritative
    Archive-collection registry. 15 major collections with category
    mapping, display names, weights (for disambiguating overlapping
    collection membership), adult deny-list, and an extended
    subject-keyword → Genre map shared between Swift and JS.
  - Added `ios/Models/CollectionRegistry.swift` reading the bundled
    JSON, exposing `info(for:)`, `isAdult(_:)`, `containsAdult(_:)`,
    `genre(forSubject:)`, `dominantCollection(from:)`. Rewired
    `ContentTypeClassifier.classify(...)` to consult the registry
    first, fall back to the string-contains heuristics for
    unregistered collections.
  - Defined `catalog.json` (root) as the tvOS seed-catalog schema,
    initialised as an empty placeholder so the repo always compiles.
  - Built the browser catalog generator (`build-catalog.html` +
    `js/build-catalog.js` + `css/build-catalog.css`). Reads
    `featured.json`, resolves every dynamic shelf against Archive's
    scrape API, fetches per-item metadata, and — if you paste a TMDb
    v4 bearer token — enriches each result with poster/backdrop/
    credits/runtime. Concurrency-limited, stop-able mid-run. Outputs
    a downloadable `catalog.json`. Works from a phone.
  - Added `ios/Services/SeedCatalog.swift` — `@MainActor enum`
    `SeedCatalog.prime(into:)` that reads the bundled `catalog.json`
    and inserts non-existing items into the app's SwiftData store
    on first launch. Idempotent. Maps catalog fidelity to
    `EnrichmentTier` (fullyEnriched / identifierResolved /
    archiveOnly) so the live refresh knows which items to
    prioritize.
  - Wired the primer into `AppNameApp.body` via a tiny `RootView`
    wrapper that pulls `@Environment(\\.modelContext)` from the same
    `.modelContainer(for:)` the content views use.
- **State left**: Seed catalog schema + loader + generator are
  shipped, but `catalog.json` itself is still empty — needs a run
  of the browser generator (blocked on GitHub Pages going live).
  All other M0 boxes done.

### 2026-04-18 (later) — Méliès moon, What's New ticker, tvOS integration plan
- **State found**: Editorial pipeline + decisions in place; owner approved going forward with Méliès moon icon + What's New ticker, asked for tvOS home-screen integration research.
- **Work done**:
  - Researched tvOS home-screen integration surfaces (Top Shelf
    extension styles, NSUserActivity for "add to Up Next" via Siri,
    App Intents for voice-launched random actions, Apple TV App
    partner program). Wrote
    `docs/research/tvos-home-screen-integration.md` covering
    architecture, App Group plumbing, deep-link routes, milestone
    landing, and known gotchas.
  - Logged Decision 015: ship Top Shelf (`.sectioned`) + NSUserActivity
    + App Intents in M2 + M4; defer Apple TV App partner program to v2.
  - Designed and implemented the Méliès moon as a hand-illustrated
    SVG (`assets/app-icon/melies-moon.svg`) — anthropomorphic moon
    face with rocket lodged in right eye, scaled to read clearly
    from 64px to 1024px. Composed full app icon master
    (`assets/app-icon/icon-1024.svg`) with bold orange field,
    sprocketed black film frame (10 perforations top + bottom),
    charcoal photo gutter, and the moon centered inside.
  - Built `assets/app-icon/preview.html` — multi-size icon preview
    plus a Home Screen mock with Apple TV / Netflix / Disney+ / Plex
    neighbors so the brand signal can be evaluated at a glance.
  - Built the What's New ticker (`whats-new.html` +
    `js/whats-new.js` + `css/whats-new.css`) — collection-tabbed feed
    of the 8 major collections, sorted by `-publicdate`, with
    seen-tracking in localStorage, IMDb + Playable badge hydration
    per item, copy-to-clipboard, and "Send to Picks" which queues
    archiveIDs in `aw_pending`. Dashboard now shows a banner when
    pending items are waiting and offers a one-click "Add to
    Editor's Picks" merge.
- **State left**: Curation tooling fully assembled (dashboard +
  ticker + pipeline validator). Icon master ready for export. tvOS
  integration plan documented end-to-end. Still awaiting owner-at-desk
  steps: Xcode project, GitHub Pages enable, validator run.

### 2026-04-18 (earlier) — Editorial pipeline, validator, decisions, app icon spec
- **State found**: Owner away from desktop; needed productive non-Xcode work.
- **Work done**:
  - Tried to live-validate the cascade against the 7 personal favorites via `curl`
    and `WebFetch` — both blocked by sandbox policy on archive.org. Pivoted.
  - Drafted `featured.json` seed (8 categories with accent colors, 1 curated
    "Editor's Picks" shelf with the 7 favorites, 9 dynamic popularity shelves,
    `adultCollections` filter list, `randomActions` config).
  - Built the editorial dashboard (`index.html` + `js/app.js` + `js/api.js`
    + `css/styles.css`): loads `featured.json`, lets the curator add/remove/
    reorder/edit-note Archive IDs with live metadata preview from
    Archive.org. Each row surfaces an "IMDb ✓ / No IMDb" badge and a
    "Playable ✓ / Not playable" badge — same checks the Swift
    `EnrichmentService` will run, so the dashboard doubles as a pipeline
    validator that runs in any browser.
  - Wrote `tools/validate-pipeline.sh` — a Bash + curl + jq script that
    runs the same checks from the command line for the desktop
    smoke-test workflow. Optional `--tmdb` flag probes TMDb /find when
    `TMDB_BEARER_TOKEN` is set. `--json` for machine output.
  - Logged Decisions 011 (hybrid curation: editor's picks + dynamic
    popularity shelves), 012 (adult content filter on by default),
    013 (per-category accent palette), 014 (random actions in M1).
  - Drafted `docs/design/app-icon.md` — photographic film frame on
    bold category color; layered tvOS icon variants; recommended
    starting still: Méliès moon.
- **State left**: Editorial pipeline live (pending GitHub Pages enable).
  Validation harness ready for desktop. Scaffold + dashboard + decisions
  in sync. Next time at desk: create Xcode project, run validator,
  enable Pages.
