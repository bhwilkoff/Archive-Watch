# Archive Watch — Cross-Platform Feature Parity

> **Single source of truth** for what ships where. Updated in the SAME change set
> as any user-facing feature. Companion to `CLAUDE.md`, `SCRATCHPAD.md`,
> `DECISIONS.md`, and the full strategy in `docs/MULTIPLATFORM-PLAN.md`.
>
> Per-platform binding design docs (create when each platform's UI complexity
> warrants): `docs/tvOS-DESIGN.md` (exists), `docs/iOS-DESIGN.md`,
> `docs/macOS-DESIGN.md` (exists), `docs/WEB-DESIGN.md`, `docs/ANDROID-DESIGN.md`.

## Legend
- ✅ **Shipped** · 🚧 **In progress** · ⏳ **Planned (committed)** · 🔮 **Future (agreed, no date)** · 🚫 **Out of scope (with reason)** · n/a **platform-inapplicable**

> **macOS (Decision 042): parity face SHIPPED + Mac-EXCLUSIVE Creation Studio.**
> Native AppKit/SwiftUI app (`ArchiveWatch/ArchiveWatch/macOS/`, shares the
> `app.archivewatch.tvos` App Store record — Decision 042/owner 2026-06-24).
> `NavigationSplitView` shell over the SHARED Swift Core (`CatalogDB`,
> `ResilientStreamLoader` w/ node failover, models, `CloudKitSyncService` — same
> container as tvOS/iOS): Home (hero + shelves), Movies/TV/Collections/Search,
> Detail (More Like This, cast→person, Share, Callsheet, reviews), AVPlayerView
> playback (resilient MP4 + HLS captions + speed + resume), Channels, Surprise,
> Cartoon mode, Library (favorites/playlists/watched), Settings (Sign in with
> Apple → CloudKit, mature filter, attribution, donate). **Creation Studio** is the
> Mac-only multi-clip editor (§4c). **Widgets** ship on macOS (§8). All four
> targets build green vs the 26 SDKs; on-device spot-checks owner-pending.
>
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
> **iOS Phase 1+2 (2026-06-09): COMPLETE.** Home discovery, Surprise grid + PD Day
> explorer, Channels touch guide, Cartoon Mode, playlists, manual prev/next
> episode, hide-watched + per-category Settings toggles. iOS + tvOS build green;
> on-device spot-checks owner-pending. (iOS is a universal target with tvOS via
> `#if os` guards; a WidgetKit extension + Sign in with Apple → CloudKit share the
> Apple TV's private DB.)

## Parity rule
**Same verb, native idiom.** The feature (the verb) is identical across platforms;
the *idiom* is whatever is native — `.searchable` on iOS, `NavigationSplitView` +
AppKit on macOS, `SearchBar` on Android, `<input type=search>`+URL on web, the
focus-driven `.searchable` on tvOS. Update this table in the same change set;
cross-link the platform design doc. Apple platforms are grouped (tvOS · iOS ·
macOS) since they share the Swift Core.

---

## 1. Navigation shell

| Verb | tvOS | iOS | macOS | Web | Android | Notes (native idiom) |
|---|---|---|---|---|---|---|
| Top-level nav | ✅ `TabView(.sidebarAdaptable)` | ✅ `TabView(.sidebarAdaptable)` (bottom bar iPhone → sidebar iPad) | ✅ `NavigationSplitView` sidebar (Home/Movies/TV/Channels/Collections/Surprise/Search/Library + **Create**) | ✅ top nav + hash routes (`/watch/`) | ✅ `NavigationSuiteScaffold` + sealed routes | Settings = a Mac Settings scene / a Home cog elsewhere |
| Per-tab back stack | ✅ `NavigationStack` ×tab | ✅ `NavigationStack` ×tab + swipe-back | ✅ `NavigationStack` detail column (`AppRouter`) | ✅ hash history (browser back) | ✅ `BackHandler` route stack | |
| Deep-linkable surfaces | ✅ `archivewatch://` | ✅ scheme; Universal Links UNBLOCKED — AASA live at archivewatch.org/.well-known (owner: add Associated Domains capability, Decision 030) | ✅ `archivewatch://` + Universal Links (onOpenURL; associated-domains entitlement) | ✅ archivewatch.org/item/{id} canonical + 404-forwarder | ✅ `archivewatch://item/{id}` | Web makes every surface a shareable URL |

## 2. Discover — Home

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Hero / featured banner | ✅ focus carousel | ✅ paged carousel (7s auto-advance) | ✅ `HeroBanner` — full-width **16:9 aspect-locked, never cropped at any window size** (no height cap; macOS windows resize, see macOS-DESIGN §B4) | ✅ Marquee scroll-snap carousel | ✅ 7s auto-advance hero | Same pool/logic; sizing per idiom |
| Curated + dynamic shelves | ✅ | ✅ horizontal rows, deduped | ✅ shelves (Top Rated / Watching Now / Hidden Gems / Community Favorites / Most Discussed) | ✅ scroll-snap rails | ✅ `LazyRow`s | `featured.json` shared |
| Category tiles | ✅ | ✅ tile row → filtered grid | ✅ tile row → filtered grid | ✅ accent tiles | ✅ tile row → filtered grid | accent colors shared; count-gated ≥30 |
| Decade tiles | ✅ | ✅ era tiles + counts | ✅ era tiles + counts | ✅ era tiles | ✅ era tiles | |
| Hidden Gems shelf | ✅ | ✅ | ✅ | ✅ | ✅ | shared query |
| Top Rated shelf (IMDb) + rating sort in Browse | ✅ | ✅ | ✅ shelf + Browse sort (`CatalogDB.Sort`) | ⏳ (index lacks rating column) | ✅ | votes floor ≥1,000 |
| Community shelves (Watching Now / Favorites / Most Discussed) | ✅ | ✅ | ✅ | ✅ | ✅ | archive.org signals; vote-floored ≥1,000 |
| Detail community (stats + genuine reviews) | ✅ | ✅ | ✅ | ✅ | ✅ | reviews filtered in the pipeline (`comment_fit.py`), baked into the catalog |
| Director shelves | ✅ | ✅ | ✅ | ⏳ (index lacks director data) | ✅ | shared query |
| Continue Watching | ✅ | ✅ | ✅ progress + widget + Home shelf | ✅ | ✅ | progress store (§6) |
| Modes row | ✅ | ➖ removed (Channels tab; modes via Surprise grid) | ➖ (Cartoon via Modes; Channels/Surprise are sidebar) | ⏳ | ⏳ | links to §5 |
| Public Domain Day section | ✅ | ✅ Home shelf + year-chip explorer | ⏳ | ✅ Home shelf | ✅ Home row | seasonal, shared |

## 3. Discover — Movies / TV / Collections / Search

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Movies grid + facets + sort | ✅ | ✅ | ✅ `LazyVGrid` + decade/sort `Picker`s + real counts + paging | ✅ CSS grid + chips | ✅ grid + chips | shared `CatalogDB.browse` |
| Infinite scroll / paging | ✅ | ✅ | ✅ offset paging | ✅ IntersectionObserver | ✅ | |
| TV series → season → episode | ✅ | ✅ | ✅ `seriesCards()` → `SeriesDetail` → episode play | ✅ `#/series/{slug}` | ✅ | `series/*.json` shared |
| TV never appears in Movies | ✅ | ✅ | ✅ | ✅ | ✅ | Decision 036 (shared `CatalogDB`) |
| TV Specials surface | ✅ | ✅ | ✅ TVBrowseView | ✅ | ✅ | Decision 036 |
| Orphan episodes fold into spines | ✅ pipeline | — | — | — | — | Decision 036; pipeline-side, benefits all via `series/*.json` |
| Prev/next episode in player | ✅ | ✅ | 🚧 | ✅ | ✅ | EpisodeQueue / PlaybackQueue (macOS wiring pending) |
| Collections landing + blurbs | ✅ | ✅ | ✅ `CollectionsList` | ✅ `#/collections` | ✅ | `collection_metadata.json` shared |
| Full-text search (FTS5) | ✅ | ✅ | ✅ `SearchView` over FTS5 | 🚧 client title search (FTS5 upgrade pending) | ✅ debounced FTS5 | same FTS5 index |
| Search result filters | ⏳ | ✅ type/decade menu | ✅ type/decade menu | ⏳ | ✅ chips | |

## 4. Detail + Playback

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Detail (backdrop, metadata, cast) | ✅ | ✅ | ✅ poster + metadata + cast row | ✅ | ✅ | shared item record |
| More Like This | ✅ | ✅ | ✅ `store.related` | ✅ | ✅ | shared `related` query |
| Cast → person filmography | ✅ | ✅ | ✅ tappable cast (TMDb photos) → byPerson | ⏳ | ✅ | |
| Share titles / series | ✅ ShareSheet + QR | ✅ ShareLink | ✅ `ShareLink` (item + series) | ✅ share menu | ✅ ACTION_SEND | archivewatch.org URLs (Decision 030) |
| Open in Callsheet (cast/crew app) | n/a | ✅ (App Store fallback) | ✅ `NSWorkspace` open/probe + App Store fallback | n/a | n/a | Decision 038 (+macOS amendment 2026-06-23) |
| Now Playing / media controls | ✅ externalMetadata | ✅ AVKit (lock screen + Control Center) | ✅ AVPlayerView (system media keys) | ✅ MediaSession | ✅ Media3 MediaSession | |
| Title+description in player | ✅ native Info tab | ✅ native externalMetadata | ✅ window title bar "Title (Year)" — macOS AVPlayerItem has NO `externalMetadata`; do NOT use the composition metadata-override (it blanks video, macOS-DESIGN §B5) | ✅ overlay mirrors controls | ✅ Media3 visibility listener | Decision 037 |
| Video playback | ✅ AVPlayerVC | ✅ AVPlayerVC | ✅ AVPlayerView (AppKit) | ✅ `<video>` in `<dialog>` | ✅ Media3 | |
| Resilient streaming | ✅ `ResilientStreamLoader` | ✅ reuse | ✅ reuse (resume-on-reset + node failover) | ✅ range + reconnect | ✅ OkHttp + patient policy | Decision 021/031/034 |
| Resume across launches | ✅ | ✅ | ✅ `WatchProgress` | ✅ IndexedDB | ✅ user.sqlite | progress store (§6) |
| Subtitles / audio / speed | ✅ | ✅ native AVKit | ✅ HLS captions + speed control | 🚧 speed ✅; `<track>` subs ⏳ | ✅ subtitle button + speed | Decision 039 |
| Autoplay / continuous play | ✅ | ✅ | ⏳ | ⏳ | ⏳ | F4 queue shared via Core |
| Picture-in-Picture | ✅ AVKit | ✅ AVKit + auto-PiP | ⏳ (AVPlayerView PiP) | ✅ presentation-mode | ⏳ Activity PiP | |
| Background play | n/a | ✅ | n/a (desktop) | ✅ | ⏳ | |
| Cast / AirPlay | ✅ AirPlay | ✅ AirPlay | ✅ AirPlay (AVPlayerView) | ⏳ Remote Playback | ⏳ Google Cast | |

## 4b. Create — Clip Studio (phone-differentiating; Decision 033)

> The native PHONE apps create single clips. On macOS this is superseded by the
> multi-clip **Creation Studio** (§4c) — so macOS = n/a here, not a gap.

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Single-clip create (trim/reframe/caption/looks/speed/GIF/export) | n/a (lean-back) | 🚧 full v1+v2 suite (`docs/CREATE-STUDIO-PLAN.md`) | n/a → Creation Studio (§4c) | 🚫 (viewer) | 🚧 Media3 port (MP4 only) | engine 100% native each platform |

## 4c. Create — Creation Studio (Mac-EXCLUSIVE; Decision 042)

> The Mac assembles a FILM (multi-clip timeline across archive.org titles), not one
> clip. Belongs only on macOS (filesystem + document model + heavy compute +
> pointer/keyboard editor). Binding spec: `docs/macOS-DESIGN.md`. Engine = native
> AVFoundation (cache-then-export, two-pass grade→overlay). Learning gate: yields an
> EDITABLE timeline, never a one-tap auto-cut.

| Feature | macOS | Other platforms | Notes |
|---|---|---|---|
| `.archiveproj` document (proxy clips, non-destructive) | ✅ ReferenceFileDocument package; durable embedded media | n/a | Library ≠ Project |
| Multi-clip timeline (AppKit `NSView`+`CALayer`) | ✅ trim/split/zoom/markers/snapping/ripple | n/a | the one custom UI element |
| Transitions (cross-dissolve / wipe / push) | ✅ native opacity/transform/crop ramps | n/a | no Metal needed |
| Color Looks · speed · music bed · voiceover | ✅ | n/a | per-clip graded source files |
| Text → Supercut (caption-validated word timing) | ✅ find + compose (longest-match) + forced-aligned word index + loudness | n/a | flagship #9; macOS-26 SpeechAnalyzer |
| Stock-shot mining (scene-detect + CLIP tags) | ✅ `clips.sqlite` index (CI) | n/a | #6; CLIP-on-Linux, not Apple Vision |
| Export (MP4 / multi-format) + provenance credit | ✅ cache-then-export | n/a | source embedded in metadata |
| Publish (Internet Archive IAS3) | ✅ | n/a | #7; YouTube deferred on OAuth verification |

## 5. Surprise + Immersive modes

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Surprise / random actions | ✅ | ✅ | ✅ `SurpriseView` | ✅ `#/surprise` | ✅ | shared random queries |
| Channels (EPG guide) | ✅ | ✅ touch EPG | ✅ `ChannelsView` (shared `ChannelScheduler`) | ✅ CSS listing | ✅ Compose guide | date-seeded scheduler ported per platform |
| Create / user channels | ✅ synced | ✅ synced | ⏳ | ✅ local | ✅ local | |
| Cartoon / Kids mode | ✅ | ✅ | ✅ `Modes_macOS` | ✅ | ✅ | color/B&W flags shared |
| Commercial-break controls | ✅ | ✅ toggle | ⏳ | ⏳ | ⏳ | |
| Party Play (muted) | ✅ | 🔮 | 🔮 | ⏳ | 🔮 | ambient mode |
| Cover-art screensaver | ✅ + idle trigger | 🔮 | 🔮 | ⏳ | 🔮 | 10-foot/lean-back idiom |
| VHS effect overlay | ✅ Metal | 🔮 | 🔮 | 🔮 | 🔮 | optional polish |

## 6. Personalization + sync

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Favorites | ✅ | ✅ | ✅ Detail heart + Library | ✅ | ✅ | local store per platform |
| Playlists | ✅ | ✅ | ✅ `PlaylistSheet` + Library | ✅ | ✅ | |
| Watched / hide-watched | ✅ | ✅ | ✅ `hideWatchedOnHome` filter | ⏳ | ✅ | |
| Continue Watching progress | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Local persistence (offline-first) | ✅ SwiftData | ✅ SwiftData | ✅ SwiftData | ✅ IndexedDB | ✅ user.sqlite | |
| Per-ecosystem sync (own cloud) | ✅ CloudKit | ✅ CloudKit | ✅ CloudKit (SAME container; Settings → Account; `CloudKitSyncService`) | ⏳ Google Drive App Data | ⏳ Google Drive App Data | Apple islands converge on one iCloud private DB |
| Cross-ecosystem sync (all platforms) | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | Out of scope by owner choice |

## 7. Settings + account

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Mature-content filter (default ON) | ✅ | ✅ | ✅ `hideAdultContent` toggle | n/a (pre-filtered) | ✅ | Decision 012 |
| Category visibility toggles | ✅ | ✅ | ⏳ | ⏳ | ⏳ | |
| Autoplay/playback options | ✅ | ✅ | ⏳ | ⏳ | 🚧 | |
| TMDb attribution (required) | ✅ | ✅ | ✅ verbatim notice | ✅ | ✅ | Decision 007 |
| Donate to Internet Archive | ✅ | ✅ | ✅ | ✅ | ✅ | Decision 010 |
| Sign-in (sync gate, optional) | ✅ Apple | ✅ Apple | ✅ Sign in with Apple | ⏳ Google | ⏳ Google | only gates sync |
| Account deletion | ✅ | ✅ | ⏳ | 🔮 | 🔮 | review requirement |

## 8. Platform reach + integration

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Home-screen surface | ✅ **Top Shelf** (best-in-class `.details` editorial carousel: contextual heroes, backdrop art, Continue-Watching-first; Decision-015 redesign 2026-06-24) | ✅ **WidgetKit suite**: Continue Watching (S/M/L + Lock Screen, art + resume bar), Pick of the Day, Favorites, Surprise Me (+ Lock Screen) + iOS-18 **Surprise Me Control** (Control Center / Action button) | ✅ **WidgetKit** (S/M/L): Continue Watching, Pick of the Day, Favorites, Surprise Me (sandboxed appex embedded in the Mac app) | 🚫 (PWA shortcuts only) | ⏳ home-screen widgets (Glance) | art pre-cached into the App Group (`WidgetArtCache`); deep-links into the app; `docs/research/topshelf-and-widgets.md` |
| Voice / shortcuts | ✅ App Intents + Siri | ✅ App Intents + Siri | 🚧 (shared App Intents; Spotlight/Siri surface TBD) | n/a | ✅ App Shortcuts | "surprise me", "random film" |
| Spotlight / system search | n/a | 🔮 Core Spotlight | 🔮 Core Spotlight | n/a | 🔮 App Search | |
| Installable app | App Store | App Store | **App Store — SUBMITTED via CLI** (1.3.246/768, Xcode 26.6; same `app.archivewatch.tvos` record — Decision 042; manual REST signing, `tools/submit-appstore.sh`; `docs/mac-app-store-submission.md` + macOS-DESIGN §C) | ✅ PWA | Play Store | |
| Handoff / continuity | 🔮 | 🔮 | 🔮 | n/a | n/a | NSUserActivity declared |

## 9. Shared backend / data plane (consumed by ALL clients — no per-platform copy)

| Service / asset | Purpose | Where | Consumed by |
|---|---|---|---|
| `catalog.sqlite.zz` (+ `seed.sqlite`) | full catalog + FTS5, query-on-disk | GitHub Release (rolling) | tvOS, iOS, **macOS**, Android (download+inflate); web (range-query in place) |
| `catalog.json` | editorial source of truth | GitHub Release | pipeline only |
| `catalog-index.json` | slim search index | GitHub Pages | web fallback / public tool |
| `featured.json` | shelves, categories, accent colors, adult deny-list | git + Pages | all clients |
| `series/*.json` | TVmaze canonical episode spines | git + Pages | all clients |
| `collection_metadata.json` | curated collections + blurbs | git | all clients |
| `clips.sqlite` / `subtitle.sqlite` | Creation Studio stock-shot + word-timing indices | GitHub Release (CI) | **macOS** (Creation Studio) — Decision 042 |
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
5. Apple platforms (tvOS · iOS · macOS) share the Swift Core — a shared-Core
   change usually moves all three columns; verify each builds.
