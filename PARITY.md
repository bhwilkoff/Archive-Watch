# Archive Watch — Cross-Platform Feature Parity

> **Single source of truth** for what ships where. Updated in the SAME change set
> as any user-facing feature. Companion to `CLAUDE.md`, `SCRATCHPAD.md`,
> `DECISIONS.md`, and the full strategy in `docs/MULTIPLATFORM-PLAN.md`.
>
> Per-platform binding design docs (create when each platform's UI complexity
> warrants): `docs/tvOS-DESIGN.md` (exists), `docs/iOS-DESIGN.md`,
> `docs/WEB-DESIGN.md`, `docs/ANDROID-DESIGN.md`.

## Legend
- ✅ **Shipped** · 🚧 **In progress** · ⏳ **Planned (committed)** · 🔮 **Future (agreed, no date)** · 🚫 **Out of scope (with reason)** · n/a **platform-inapplicable**

> **Android Phase P4 v1 spine (2026-06-09): SHIPPED** — native Kotlin + Compose M3
> (`android/`, applicationId `com.archivewatch.app`): contract-compliant data
> layer (seed → .zz download/inflate/swap via BundledSQLiteDriver FTS5), Home /
> Browse / Search / Detail / SeriesDetail / Media3 player (resilient
> LoadErrorHandlingPolicy) / Library / Settings, deep links. assembleDebug green +
> emulator-verified (full 27k catalog on-device). Next wave: Channels, modes,
> widgets, Drive App Data sync — see docs/ANDROID-DESIGN.md §7.
>
> **Web P3 (2026-06-09): SHIPPED + LIVE** at archivewatch.org/
> — Decision 029 data plane, installable PWA, /item share-URL forwarder.
>
> **iOS Phase 1+2 (2026-06-09): COMPLETE.** The P1/P2 parity gaps closed in the
> 2026-06-09 autonomous wave: Home discovery (category/decade tiles → generic
> filtered grid, Hidden Gems, Director shelves, Public Domain Day shelf, Modes
> row), Surprise grid + Public Domain Day explorer, Channels touch guide
> (shared date-seeded ChannelScheduler, join-in-progress, commercial breaks,
> create/delete user channels), Cartoon Mode, playlists (add/create/delete),
> manual prev/next episode controls, hide-watched + per-category Settings
> toggles. iOS + tvOS both build green; on-device spot-checks owner-pending.
>
> **iOS Phase 1 (2026-06): COMPLETE.** The tvOS Xcode project was converted to a
> **universal app target** (iOS + tvOS from one target via `#if os` guards) plus a new
> iOS-only **WidgetKit** extension target; the iPhone build **runs on the iOS 26
> simulator**, verified screen-by-screen, and tvOS still builds green (in-review project
> not regressed). Shipped: full-screen launch + photographic Méliès icon; Home (paging
> hero carousel + item_shelves-resolved/de-duped shelves + Continue Watching + Surprise);
> Browse (Films grid + facets + paging; **TV** series→episode via SeriesStore; **Collections**
> list→grid); Detail; Player (AVKit + PiP + resilient streaming + resume + continuous
> play / episode binge); Search; Library; Settings (Home cog: mature filter, autoplay,
> attribution, donate, **Account & Sync**); **iPad** sidebar adaptivity; **App Intents +
> Siri**; **WidgetKit** widgets; **Sign in with Apple → CloudKit** (shares the Apple TV's
> private DB). **Owner-pending (device-only):** on-device cross-device CloudKit verify;
> Siri phrase + widget-gallery spot-check on hardware. **Next:** Phase 2 (Web PWA, then
> Android).

## Parity rule
**Same verb, native idiom.** The feature (the verb) is identical across platforms;
the *idiom* is whatever is native — `.searchable` on iOS, `SearchBar` on Android,
`<input type=search>`+URL on web, the focus-driven `.searchable` on tvOS. Update
this table in the same change set; cross-link the platform design doc.

---

## 1. Navigation shell

| Verb | tvOS | iOS | Web | Android | Notes (native idiom) |
|---|---|---|---|---|---|
| Top-level nav | ✅ `TabView(.sidebarAdaptable)` | ✅ `TabView(.sidebarAdaptable)` (bottom bar iPhone → sidebar iPad) | ✅ top nav + hash routes (`/watch/`) | ✅ `NavigationSuiteScaffold` + sealed routes | Settings moved off the bar to a Home cog (4 content tabs) |
| Per-tab back stack | ✅ `NavigationStack` ×tab | ✅ `NavigationStack` ×tab + swipe-back | ✅ hash history (browser back) | ✅ `BackHandler` route stack | |
| Deep-linkable surfaces | ✅ `archivewatch://` | ✅ scheme; Universal Links UNBLOCKED — AASA live at archivewatch.org/.well-known (owner: add Associated Domains capability, Decision 030) | ✅ archivewatch.org/item/{id} canonical + 404-forwarder | ✅ `archivewatch://item/{id}` | Web makes every surface a shareable URL |

## 2. Discover — Home

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Hero / featured banner | ✅ focus carousel | ✅ paged `TabView` carousel (touch swipe, 7s auto-advance) | ✅ Marquee scroll-snap carousel (container-query fluid, WEB-DESIGN §4.7) | ✅ 7s auto-advance hero | Same pool/logic; 10-foot sizing → touch sizing |
| Curated + dynamic shelves | ✅ | ✅ horizontal rows, item_shelves-resolved + cross-shelf dedup | ✅ scroll-snap rails (editorial shelves map in the index; deduped, day-rotated) | ✅ `LazyRow`s (item_shelves, dedup, min-6) | `featured.json` shared verbatim |
| Category tiles | ✅ | ✅ tile row → filtered grid | ✅ accent tiles → `#/browse?type=` | ✅ tile row → filtered grid | accent colors from `featured.json`; count-gated ≥30 everywhere |
| Decade tiles | ✅ | ✅ era tiles + counts | ✅ era tiles + counts (last Home row) | ✅ era tiles + counts (last Home row) | |
| Hidden Gems shelf | ✅ | ✅ | ✅ (popularity-tail designed art) | ✅ | shared query |
| Top Rated shelf (IMDb score) + rating sort in Browse | ✅ shelf + sort | ✅ shelf + sort | ⏳ (index lacks a rating column — additive schema bump, then trivial) | ✅ shelf + sort | votes floor ≥1,000; owner request 2026-06-12 |
| Director shelves | ✅ | ✅ | ⏳ (index lacks director data) | ✅ | shared query |
| Continue Watching | ✅ | ✅ | ✅ | ✅ | progress store (see §6) |
| Modes row | ✅ | ➖ removed 2026-06-10 (Channels = tab; Surprise/Cartoon/PD via Home shuffle → Surprise grid) | ⏳ | ⏳ | links to §5 |
| Public Domain Day section | ✅ | ✅ Home shelf + year-chip explorer | ✅ Home shelf | ✅ Home row | seasonal, shared |

## 3. Discover — Movies / TV / Collections / Search

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Movies grid + facets + sort | ✅ | ✅ `LazyVGrid` + scope picker + `Menu` facets | ✅ CSS grid + type chips + URL params | ✅ `LazyVerticalGrid` + `FilterChip` + dropdowns + real counts | shared `CatalogDB.browse`; Browse scope = Films/TV/Collections |
| Infinite scroll / paging | ✅ | ✅ `.onAppear` paging | ✅ IntersectionObserver | ✅ paging on scroll | |
| TV series → season → episode | ✅ | ✅ series grid → `SeriesDetailView` (SeriesStore) → episode play | ✅ `#/series/{slug}` (spine from Pages) → episode play + resume | ✅ TV scope → SeriesDetail → play | `series/*.json` shared |
| TV never appears in Movies | ✅ | ✅ | ✅ | ✅ | Decision 036: tv-series AND tv-special excluded from every film surface (Browse/Home/Random) — CatalogDB `notStandaloneTV` (Apple/Android) / `isFilm` (web) |
| TV Specials surface (standalone, not in a spine) | ✅ TV tab "TV Specials" button → grid | ✅ TV scope "TV Specials" row → `FilteredGridView` | ✅ "TV Specials" browse chip | ✅ TV scope "TV Specials" button → `FilteredGridScreen` | Decision 036; `tvSpecials()` query / `tv-special` browse filter |
| Orphan episodes fold into series spines | ✅ pipeline (`build_canonical_tv` orphan pool) | — | — | — | Decision 036; pipeline-side, benefits all clients via `series/*.json`; episode-wants auto-follow |
| Prev/next episode in player | ✅ | ✅ overlay capsule + binge auto-advance | ✅ season queue auto-advance on `ended` | ✅ Media3 queue (native next/prev + advance) | EpisodeQueue swaps next on end |
| Collections landing + blurbs | ✅ | ✅ `CollectionMetadata` list → `CollectionGridView` | ✅ `#/collections` (index collections map, schema 5) | ✅ Browse → Collections (item_collections query) | `collection_metadata.json` shared |
| Full-text search (FTS5) | ✅ | ✅ `.searchable` + type/decade filter menu | 🚧 client title search over index (FTS5 upgrade = WEB-DESIGN §2.4) | ✅ debounced FTS5 `SearchBar` | same FTS5 index in `catalog.sqlite` |
| Search result filters | ⏳ (Browse facets cover the verb) | ✅ type/decade `Menu` over FTS results | ⏳ | ✅ type/decade chips over FTS results (facets present in results only) | audit addition 2026-06-12 |

## 4. Detail + Playback

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Detail (backdrop, metadata, cast) | ✅ | ✅ framed 2:3 poster hero + tappable cast/crew → person filmography | ✅ poster + curated synopsis + cast/crew bubbles (catalog shards) | ✅ backdrop + cast row + favorite | shared item record; iOS person browse = `CatalogDB.byPerson` |
| More Like This | ✅ | ✅ | ✅ (type + era ±15y, designed art) | ✅ | shared `related` query |
| Cast → person filmography | ✅ PersonChip → FTS names browse | ✅ tappable bubbles → byPerson grid | ⏳ (blocked on FTS upgrade, WEB-DESIGN §2.5) | ✅ tappable cast → FTS person grid | audit addition 2026-06-12 |
| Share titles / series | ✅ ShareSheet + QR | ✅ ShareLink (item + series) | ✅ share menu + open-in-app (item + series) | ✅ ACTION_SEND (item) | archivewatch.org/item|series URLs (Decision 030) |
| Open in Callsheet (cast/crew app) | n/a (Callsheet is iPhone/iPad only) | ✅ actions menu on Detail + SeriesDetail (+ per-episode); App Store fallback | n/a | n/a | Decision 038; `callsheet://open\|search` by tmdbID/title |
| Now Playing / lock-screen media controls | ✅ externalMetadata (tvOS Info panel) | ✅ AVKit (lock screen + Control Center) | ✅ MediaSession (metadata + play/pause/seek/next/prev) | ✅ Media3 MediaSession | audit addition 2026-06-12 |
| Title+description in player (with controls) | ✅ native Info tab + externalMetadata (owner-approved as-is) | ✅ native `externalMetadata` (AVKit chrome, synced — the Apple TV app's way) | ✅ `.player-overlay` mirrors control activity (pointer/touch + 3.2s) | ✅ Media3 `setControllerVisibilityListener` (exact) | Decision 037; owner request 2026-06-18 (mobile + web) |
| Video playback | ✅ AVPlayerVC | ✅ AVPlayerVC (reused) | ✅ HTML5 `<video>` in `<dialog>` | ✅ Media3 `PlayerView` | |
| Resilient streaming | ✅ `ResilientStreamLoader` | ✅ reuse Swift loader | ✅ range-native + reconnect/reseek wrapper | ✅ OkHttp source + patient `LoadErrorHandlingPolicy` | Archive idle-reset resilience per platform |
| Resume across launches | ✅ | ✅ `WatchProgress` (item + per-episode) | ✅ IndexedDB progress | ✅ user.sqlite (10s–95%) | progress store (§6) |
| Subtitles / audio / speed | ✅ | ✅ native AVKit | 🚧 speed selector ✅ (persisted); `<track>` subtitles ⏳ (rare on Archive files) | ✅ subtitle button + Media3 speed control | |
| Autoplay / continuous play | ✅ F4 engine | ✅ shared F4 engine (PlaybackQueue + AutoplayMode setting) | ⏳ port engine (JS) | ⏳ Media3 playlist | F4 queue logic shared via Core |
| Picture-in-Picture | ✅ AVKit PiP (`allowsPictureInPicturePlayback`) | ✅ AVKit PiP + auto-PiP from inline | ✅ (Chrome + Safari presentation-mode APIs) | ⏳ Activity PiP | tvOS PiP corner window since tvOS 14 |
| Background play (audio continues) | n/a (TV apps suspend) | ✅ `audio` background mode + detach-on-background | ✅ (browser keeps audio; MediaSession controls) | ⏳ MediaSessionService foreground service | iOS: AVKit detach/reattach technique, PiP-aware |
| Cast / AirPlay | ✅ AirPlay | ✅ AirPlay (AVKit) | ⏳ Remote Playback API | ⏳ Google Cast (needs Cast SDK + device-tested receiver — deliberate defer) | each platform's native cast |

## 4b. Create — Clip Studio (phone-differentiating; Decision 033)

> The native phone apps *create*, not just consume. iOS-first; engine is 100%
> native (AVFoundation/ImageIO/PhotoKit · Media3 Transformer). tvOS/web stay
> lean-back viewers. Plan: `docs/CREATE-STUDIO-PLAN.md`.

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Create entry point (rights-gated) | n/a (lean-back) | 🚧 scissors button on Detail (PD/CC only via `isClippable`) | 🚫 (viewer) | 🚧 `ContentCut` action on DetailScreen (rights-gated) | hidden, not disabled, when not clippable |
| Source = stream, not download | n/a | 🚧 `ResilientStreamLoader` remote asset | 🚫 | 🚧 ranged `MediaMetadataRetriever` + `OkHttpDataSource` (ExoPlayer preview + Transformer read remote) | never download the whole film (hours-long) — both platforms 2026-06-16 |
| Trim (frame-accurate, length-capped) | n/a | 🚧 CapCut-style timeline: `UIScrollView` scroll-to-scrub + fixed playhead + pinch-zoom + Set Start/End + band handles; controls-free `AVPlayerLayer` preview | 🚫 | 🚧 CapCut-style timeline: custom `View` scroll-to-scrub + fixed playhead + `ScaleGestureDetector` pinch-zoom + `OverScroller` momentum + Set Start/End + band handles; controls-free `PlayerView` | no native trimmer on either platform (5b); both rebuilt 2026-06-16 |
| Reframe (Original/1:1/9:16/16:9, letterbox) | n/a | 🚧 `AVMutableVideoComposition` renderSize + transform | 🚫 | 🚧 Media3 `Presentation.createForWidthAndHeight` | |
| Blurred-fill reframe background | n/a | 🚧 Core Image `CIGaussianBlur` (video) / CG blur (GIF) | 🚫 | 🔮 needs custom `GlEffect`/AGSL shader (Media3 1.9.4 has no scaled blur-fill) | iOS 2026-06-16 |
| Auto-captions (timed, burned-in) | n/a | 🚧 `SFSpeechRecognizer` on-device → timed cues, live preview + styled burn-in (MP4) | 🚫 | 🔮 no native file transcription (`SpeechRecognizer` is mic-only; no cloud/ML-Kit by rule) | iOS 2026-06-16; SpeechAnalyzer = future upgrade |
| Caption styling (font/size/color/bg) + drag-to-position + live preview | n/a | 🚧 `CaptionStyle` (4 fonts · S/M/L · white/yellow/black · shadow/box/plain · normalized position); WYSIWYG live preview, drag to place on video or in bars | 🚫 | 🚧 `CaptionStyle` (Typeface fonts [Round→sans, no rounded system family] · S/M/L · colors · bg); draggable Compose preview; `BitmapOverlay` burn-in | both platforms 2026-06-16 |
| Caption + provenance credit (burned-in) | n/a | 🚧 image-rendered caption at styled position (video CALayer / GIF Core Graphics); credit pinned bottom | 🚫 | 🚧 Canvas/Paint `Bitmap` at styled position via Media3 `OverlayEffect` + `BitmapOverlay`; credit pinned bottom | always-on archivewatch.org · PD credit + source in metadata |
| Export MP4 / GIF | n/a | 🚧 `AVAssetExportSession` / `AVAssetImageGenerator`+ImageIO | 🚫 | 🚧 Media3 `Transformer` (**MP4 only** — no native GIF encoder) | GIF is Android's weak native story |
| Save to Photos / share | n/a | 🚧 PhotoKit (add-only) + `ShareLink` | 🚫 | 🚧 `MediaStore.Video` + `ACTION_SEND`/FileProvider | |
| Color-grade Looks (Silent/Noir/Faded/Techni/B&W) | n/a | 🚧 CIFilter chains, two-pass video + per-frame GIF, live preview | 🚫 | 🚧 Media3 `RgbAdjustment`/`RgbFilter`/`HslAdjustment`/`Contrast` (export only — no live preview, no vignette) | v2 both platforms 2026-06-16 |
| Speed (0.5×/1×/2×) | n/a | 🚧 `scaleTimeRange` (A/V together) | 🚫 | 🚧 `SpeedChangeEffect` + `SonicAudioProcessor` (A/V synced) | v2 both platforms 2026-06-16 |
| Saved clips library | n/a | 🚧 `VideoClip` SwiftData + Library "Clips" section (share/revisit/delete) | 🚫 | 🚧 `user.sqlite` clips table + Library "Clips" tab (share/delete) | re-create from definition if render evicted |
| Editor live preview | n/a | 🚧 controls-free `AVPlayerLayer`, timeline is sole scrubber | 🚫 | 🚧 controls-free `PlayerView` streaming, timeline is sole scrubber | both platforms 2026-06-16 (Android was static first-frame) |
| v2 deferred: stitch / transitions / beat-sync | n/a | 🔮 (same composition spine) | 🚫 | 🔮 | additive — `docs/CREATE-STUDIO-PLAN.md` §4 |

## 5. Surprise + Immersive modes

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Surprise / random actions | ✅ | ✅ Surprise grid (11 tiles, re-roll on tap) | ✅ `#/surprise` re-roll grid (topnav) | ✅ Surprise grid (Home shuffle → re-roll) | shared random queries |
| Channels (EPG guide) | ✅ proportional grid | ✅ proportional touch EPG (pinned ruler, window paging) | ✅ sticky-rail/ruler CSS listing (`#/channels`, pools from `channel-pools.json`, JS scheduler) | ✅ Compose proportional guide (Channels tab, Kotlin scheduler) | date-seeded `ChannelScheduler` ported per platform; 6 AM local broadcast day everywhere |
| Create / user channels | ✅ synced | ✅ Form sheet + swipe-delete, synced | ✅ type/era form (no genre in the index; rail-tap deletes) | ✅ chip-picker dialog + long-press delete | Apple: AWSync `channels` blob; W+A local-only until Drive sync |
| Cartoon / Kids mode | ✅ | ✅ characters + themes + marathon | ✅ `#/cartoons` (character shelves + marathon from the color-emphasized pool) | ✅ character shelves + marathon queue | color/B&W flags shared |
| Commercial-break controls (on/off + length) | ✅ guide header pills + Settings | ✅ guide toolbar toggle (length cap tvOS-only) | ⏳ (weave always on) | ⏳ (weave always on) | audit addition 2026-06-12; #89 weave itself ships everywhere |
| Party Play (muted) | ✅ | 🔮 (iPad-leaning) | ⏳ | 🔮 (tablet-leaning) | ambient mode; phone de-emphasized |
| Cover-art screensaver | ✅ + idle trigger | 🔮 ambient (iPad) | ⏳ ambient (desktop) | 🔮 ambient (tablet) | idle auto-trigger is a 10-foot/lean-back idiom |
| VHS effect overlay | ✅ Metal | 🔮 Metal (reuse) | 🔮 WebGL/CSS | 🔮 AGSL `RenderEffect` | optional polish; per-platform shader |

## 6. Personalization + sync

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Favorites | ✅ | ✅ Detail heart + Library | ✅ heart + Library (IndexedDB) | ✅ | local store per platform |
| Playlists | ✅ | ✅ add/create sheet + swipe-delete | ✅ IndexedDB + dialog + `#/playlist/{id}` | ✅ user.sqlite + dialog + Library tab | |
| Watched / hide-watched | ✅ | ✅ Watched tab + hide-watched toggle | ⏳ (needs a web settings surface) | ✅ hide-watched Settings toggle (Home filter) | |
| Continue Watching progress | ✅ | ✅ | ✅ | ✅ | |
| Local persistence (offline-first) | ✅ SwiftData | ✅ SwiftData (reuse) | ✅ IndexedDB | ✅ user.sqlite + DataStore | |
| Per-ecosystem sync (own cloud) | ✅ CloudKit | ✅ CloudKit (query-free AWSync records; owner-verified iPhone↔Apple TV 2026-06-11 after Production schema deploy) | ⏳ Google Drive App Data (web↔web) | ⏳ Google Drive App Data (device↔device) | Decided: each island on the user's own free cloud, no backend (plan §6) |
| Cross-ecosystem sync (all 4) | 🚫 | 🚫 | 🚫 | 🚫 | Out of scope by owner choice — unneeded complexity |

## 7. Settings + account

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Mature-content filter (default ON) | ✅ | ✅ Settings toggle (cog → sheet) | n/a (index pre-filtered upstream) | ✅ Settings toggle | `isAdult` flag baked into catalog (Decision 012/adult pass) |
| Category visibility toggles | ✅ | ✅ | ⏳ | ⏳ | |
| Autoplay/playback options | ✅ | ✅ autoplay-next picker | ⏳ | 🚧 toggle shipped; engine wiring pending | |
| TMDb attribution (required) | ✅ | ✅ verbatim notice | ✅ verbatim notice (#/about) | ✅ verbatim notice | Decision 007 — verbatim notice all platforms |
| Donate to Internet Archive | ✅ | ✅ | ✅ | ✅ | Decision 010 |
| Sign-in (sync gate, optional) | ✅ Sign in w/ Apple | ✅ Sign in w/ Apple (Settings → Account & Sync) | ⏳ Sign in w/ Google (Drive App Data) | ⏳ Sign in w/ Google (Drive App Data) | only gates sync; browse/play always work offline-first |
| Account deletion | ✅ | ✅ (deleteAllCloudData + sign out) | 🔮 | 🔮 | App/Play review requirement |

## 8. Platform reach + integration

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Home-screen surface | ✅ Top Shelf | ✅ WidgetKit (small + medium; Continue Watching / Editor's Picks) | 🚫 (PWA shortcuts only) | ⏳ home-screen widgets | App Group snapshot; deep-links into the app |
| Voice / shortcuts | ✅ App Intents + Siri | ✅ App Intents + Siri (Surprise / Random Film / Browse) | n/a | ✅ App Shortcuts (Surprise / Channels deep links) | "surprise me", "random film" |
| Spotlight / system search | n/a | 🔮 Core Spotlight | n/a | 🔮 App Search | |
| Installable app | App Store | App Store | ✅ **PWA (installable; shell+catalog offline)** | Play Store | web = zero-install reach |
| Handoff / continuity | 🔮 | 🔮 | n/a | n/a | NSUserActivity already declared |

## 9. Shared backend / data plane (consumed by ALL clients — no per-platform copy)

| Service / asset | Purpose | Where | Consumed by |
|---|---|---|---|
| `catalog.sqlite.zz` (+ `seed.sqlite`) | full catalog + FTS5, query-on-disk | GitHub Release (rolling) | tvOS, iOS, Android (download+inflate); web (range-query in place) |
| `catalog.json` | editorial source of truth | GitHub Release | pipeline only |
| `catalog-index.json` | slim search index | GitHub Pages | web fallback / public tool |
| `featured.json` | shelves, categories, accent colors, adult deny-list | git + Pages | all clients |
| `series/*.json` | TVmaze canonical episode spines | git + Pages | all clients |
| `collection_metadata.json` | curated collections + blurbs | git | all clients |
| Archive.org | video streams + posters | archive.org | all clients (playback + images) |
| `archivewatch-covers` | generated frame covers | archive.org item | all clients (images) |
| Python pipeline (`tools/`) | discovery, enrichment, rights audit, covers, color, match-verify | CI / local | build-time only — **no per-platform reimplementation** |
| `excluded` (rights) + `isAdult` flags | copyright + mature filtering | baked into `catalog.sqlite` | every client filters for free |

---

## Maintenance protocol
1. Find the feature's row; add one under the right section if new.
2. Update each platform's symbol; note deltas in Notes.
3. Cross-link the governing platform design doc.
4. When a platform rejects a feature, record it as an Out-of-scope row in that
   platform's design doc and mark 🚫 here with the reason.
