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
| Hidden Gems shelf | ✅ | ✅ | ✅ | ✅ | ✅ | **shared computed `hiddenGem` column** (Decision 050) — all five query the pipeline's flag, none restates a threshold. Was silently EMPTY on all four apps 2026-06-29→08-07 (client constant vs a rescaled popularityScore); web had a different, weaker definition (popularity-tail shuffle). |
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
| TV series → season → episode | ✅ | ✅ | ✅ `seriesCards()` → `SeriesDetail` → episode play | ✅ `#/series/{slug}` | ✅ phone `SeriesDetailScreen`; **Google TV: `TvSeriesScreen`, a TV-native scene** (TV-DESIGN §4.9, 2026-09-04) — hero, eyebrow, meta, favorite/share, season chips selecting on focus, episode rows | `series/*.json` shared |
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
| "Also known as" alternate release title | ✅ under the hero title | ✅ under the title | ✅ under the title | ✅ under the title | ✅ phone + TV Detail | Decision 100 — `canonicalTitle` only, ligature+diacritic folded; 1,646 items. Web carries it as `extras.ct` in the detail shards |
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
| **SharePlay — Watch Together** | ✅ join + start session; **cannot start the CALL** (`GroupActivitySharingController` does not exist on tvOS, checked in the 27.0 SDK) so it shows an alert instead | ✅ join + start session + start the call (UIKit sheet) | ✅ join + start session + start the call (**added 2026-09-01**; the Mac could previously only JOIN, and joining opened nothing) | 🚫 no Apple GroupActivities equivalent | 🚫 same | Shared `WatchTogether` service; coordination is by **archiveID**, never URL, since every title plays through a private `aw-stream://` scheme and Decision 077 can swap copies mid-film. Binding rules in `docs/SHAREPLAY.md`; Decision 098. Verified end to end on real hardware 2026-09-01 |
| SharePlay — group waits for a stalled member | ✅ | ✅ | ✅ | n/a | n/a | `.stallRecovery` suspension driven centrally from `WatchTogether.attach`. Was declared and **called by nothing on any platform** until 2026-09-01 — every player had a coordinator that never suspended, so a buffering viewer drifted instead of the group waiting |
| Cast / AirPlay | n/a (Apple TV IS the receiver — tvOS does not send) | ✅ AirPlay route-swap | ✅ AirPlay route-swap (**added 2026-08-08**; macOS had the AVPlayerView route button but no swap, so it failed on every title) | ✅ Cast sender (receiver 58AF34C3) | ✅ Cast sender, google flavor only | Shared `AirPlayRouting` picks the receiver-fetchable URL (HLS first, so captions survive). AirPlay WORKS on iOS + macOS. Apple does not support video AirPlay through a custom resource loader and every local path is loader-backed, so the route swap is what makes it work — Decision 051. Fire TV excluded: Cast is GMS-dependent |

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
| Watch history (full ever-watched record, D078) | ✅ Library History | ✅ Library tab | ✅ Library shelves | ✅ Library grid | ✅ Library tab | durable everCompleted + playCount + firstWatchedAt; Apple synced via CloudKit |
| Cross-ecosystem history sync (Drive App Data, D028) | n/a (CloudKit) | n/a (CloudKit) | n/a (CloudKit) | ✅ LIVE | ✅ LIVE (google flavor only) | OAuth configured 2026-09-03; VERIFIED Pixel 8a ↔ browser both ways incl. deletions — docs/google-oauth-setup.md |
| Local persistence (offline-first) | ✅ SwiftData | ✅ SwiftData | ✅ SwiftData | ✅ IndexedDB | ✅ user.sqlite | |
| Per-ecosystem sync (own cloud) | ✅ CloudKit | ✅ CloudKit | ✅ CloudKit (SAME container; Settings → Account; `CloudKitSyncService`) | ✅ Drive App Data + ⏳ CloudKit JS | ✅ Drive App Data (Settings → Sync) | Apple islands converge on one iCloud private DB; the WEB is the only client that can hold both — Apple half needs a CloudKit token (docs/web-apple-sync.md) |
| Cross-ecosystem sync (all platforms) | 🚫 | 🚫 | 🚫 | ⏳ the meeting point | 🚫 | Out of scope as a BACKEND (D028). The web is the exception: signed into both clouds it merges Apple + Google state with one set of rules |
| Deletions carry tombstones | ✅ | ✅ | ✅ | ✅ | ✅ | without one, a removed favorite is resurrected by the next pull — Apple's #84, now closed on Android + web too |
| **Download a film for offline viewing** | 🚫 **platform cannot** | ✅ Detail ⬇ → copy-picker sheet · **22/22 on iPhone 12 + iPad Pro** | ✅ Detail Download menu · **verified on this Mac** | 🚫 | ⏳ Media3 `DownloadManager` | Decision 099. tvOS has NO durable storage — a purgeable `Caches` plus ~500 KB of `NSUserDefaults`, no Documents dir — so a download there is a promise the OS may delete between launches. Web: browser quota will not hold a feature film. Background `URLSession` → Application Support, `isExcludedFromBackup` |
| Downloads in Library (manage + remove) | 🚫 | ✅ Downloads section, swipe delete / pause / resume | ✅ Downloads rows + Remove | 🚫 | ⏳ | Downloads is the FIRST Library section and the tab opens there when offline |
| Play a downloaded film with no network | 🚫 | ✅ plain `AVPlayerItem(url: file://)` — decoded off disk on both devices | ✅ **proven with the network DENIED to the process** (negative control: archive.org unreachable) | 🚫 | ⏳ | iOS-DESIGN §8.7 / macOS-DESIGN §B9b — the resilient loader is skipped; nothing to be resilient about |
| Offline subtitles for a downloaded film | 🚫 | ✅ downloaded WebVTT via the caption overlay | ✅ same (`liveLine`) | 🚫 | ⏳ | `OfflineSubtitles`. An HLS master cannot carry it — its video rendition is a remote URL (D099) |
| Offline state banner | n/a (always connected) | ✅ "Offline — your downloads still play" + jump to Library (OCR-verified on iPhone + iPad) | 🔮 | ⏳ | ⏳ | `NWPathMonitor`. Browse/Search keep working from the local catalog DB; only streaming stops |
| Downloads are device-local (never synced) | n/a | ✅ | ✅ | n/a | ⏳ | iOS-DESIGN §9.7 — a favorite is an intention, a download is bytes on ONE device |

## 7. Settings + account

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Mature-content filter (default ON) | ✅ | ✅ | ✅ `hideAdultContent` toggle | n/a (pre-filtered) | ✅ | Decision 012 |
| Category visibility toggles | ✅ | ✅ | ⏳ | ⏳ | ⏳ | |
| Autoplay/playback options | ✅ | ✅ | ⏳ | ⏳ | 🚧 | |
| Downloads storage + Remove All | 🚫 | ✅ + cellular toggle (OFF by default) | ✅ (no cellular question on a Mac) | 🚫 | ⏳ | Decision 099 |
| TMDb attribution (required) | ✅ | ✅ | ✅ verbatim notice | ✅ | ✅ | Decision 007 |
| Donate to Internet Archive | ✅ | ✅ | ✅ | ✅ | ✅ | Decision 010 |
| Sign-in (sync gate, optional) | ✅ Apple | ✅ Apple | ✅ Sign in with Apple | ✅ Google (+ ⏳ Apple) | ✅ Google (phone AND TV) | only gates sync; status row shows account / last sync / last error / Sync now |
| Account deletion | ✅ | ✅ | ⏳ | 🔮 | 🔮 | review requirement |

## 8. Platform reach + integration

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Home-screen surface | ✅ **Top Shelf** (`.sectioned` poster rows, Continue-Watching-first with resume bar + Play-resumes; ~15 named editorial rows rotated on a 6h window from the published `topshelf.json` pools; tvOS-DESIGN §15, Decision 049) | ✅ **WidgetKit suite**: Continue Watching (S/M/L + Lock Screen, art + resume bar), Pick of the Day, Favorites, Surprise Me (+ Lock Screen) + iOS-18 **Surprise Me Control** (Control Center / Action button) | ✅ **WidgetKit** (S/M/L): Continue Watching, Pick of the Day, Favorites, Surprise Me (sandboxed appex embedded in the Mac app) | 🚫 (PWA shortcuts only) | ⏳ home-screen widgets (Glance) | art pre-cached into the App Group (`WidgetArtCache`); deep-links into the app; `docs/research/topshelf-and-widgets.md` |
| Voice / shortcuts | ✅ App Intents + Siri | ✅ App Intents + Siri | 🚧 (shared App Intents; Spotlight/Siri surface TBD) | n/a | ✅ App Shortcuts | "surprise me", "random film" |
| Spotlight / system search | n/a | 🔮 Core Spotlight | 🔮 Core Spotlight | n/a | 🔮 App Search | |
| Installable app | App Store (cloud-built) | App Store (cloud-built) | **App Store — UPLOADED 1.3.249/771** via the cloud workflow (`.github/workflows/appstore-build.yml`, GitHub `macos-26` runner = released macOS + Xcode 26.6 → clears ITMS-90301 beta-OS + ITMS-90111 floor; free for this public repo). Same `app.archivewatch.tvos` record (Decision 042); manual `.p12` signing; macOS-DESIGN §C2c. Local `submit-appstore.sh` only works on a released-macOS box. | ✅ PWA | Play Store | All 3 Apple platforms build cloud-side now |
| Handoff / continuity | 🔮 | 🔮 | 🔮 | n/a | n/a | NSUserActivity declared |

## 8b. Non-Apple TV platforms (Decision 047 · `docs/TV-DESIGN.md`)

Two new **clients**, not two new products. They are tracked in their own section
rather than as two more columns above because the existing tables are already
six wide, and because a TV client's parity question is *"which wave is this
surface in?"* — the per-surface waves are binding in TV-DESIGN §2.

| Client | Reuse vehicle | Ships to | Status |
|---|---|---|---|
| **Android TV** | the SAME `android/` app + AAB + `applicationId`, TV branched at runtime on `UiModeManager` | Google TV / Android TV **and** Amazon Fire TV | ✅ all surfaces D-pad-verified (12/12); compliance gates pass; Play TV form factor opted in — only the asset upload remains (owner) |
| **Web-TV** | the SAME root PWA + `tv.js`/`tv.css` layer | LG webOS, Samsung Tizen, VIDAA / Titan / Zeasn | 🚧 focus engine + packaging staged |
| **Google Cast** | hosted HTML receiver + web/Android senders | Chromecast, Google TV, Chromecast-built-in (incl. most **Vizio**) | ✅ **PUBLISHED** `58AF34C3`; both senders wired + declared in the console. ⏳ on-device verification (needs a Cast device) |
| **AirPlay** | **needed new code** — see below | Apple TV + AirPlay-2 TVs (Samsung, LG, Vizio, Sony, TCL, Roku TV) | ✅ built, ⏳ owner device QA |
| **Roku** | none — 0% reuse, BrightScript/SceneGraph rewrite | Roku (#1 US CTV) | 🔮 separate funded decision |
| **Vizio native** | — | — | 🚫 no self-serve program; BD-gated and ad-aligned post-Walmart. Reached via Cast/AirPlay instead. |

| Verb | Android TV | Web-TV | Notes (native idiom) |
|---|---|---|---|
| Top-level nav | ✅ focusable rail, expands on focus | ✅ topnav + spatial focus | a bottom tab bar is a touch affordance; it reads as an error at ten feet |
| Home (hero + shelves) | ✅ shares `rememberHomePayload` with phone | ✅ existing shelves + TV breakpoint | shelf order + cross-shelf dedup single-sourced so they cannot drift |
| Browse | ✅ TV-native: scope chips + 6-col D-pad grid, focus-driven paging | ✅ | grid uses FIXED columns so "first column" is knowable |
| Detail | ✅ TV-native: full-bleed hero, focus-first Play, More Like This | ✅ | |
| Search | ✅ TV-native: on-screen keyboard **+ no-typing browse doors** | ✅ | §3.6 — a keyboard-only Search is a dead end on a remote |
| Library | ✅ TV-native: focusable sections; **Clips tab omitted** | ✅ | Clip Studio is never on TV (§2) |
| Channels (EPG) | ✅ focusable programme blocks, tune-in by remote | ✅ | the EPG layout was already a ten-foot idiom; it needed focusability, not a rewrite |
| Surprise · Collections · Cartoon · filtered grids | ✅ operable via shared focusable tiles + shell focus claim | ✅ | |
| Playback | ✅ Media3 + D-pad centre/seek + media keys | ✅ `<video>` + remote key contract | TV-PC / TV-PP |
| Background media controls | 🚫 **gated off — TV-NP forbids it for video apps** | 🚫 n/a | phone keeps its MediaSession; TV pauses on switch-away |
| Picture-in-Picture | 🚫 gated off on TV (TV-NP wants a pause) | 🚫 n/a | |
| Cast (send to TV) | ⏳ needs `CastPlayer` wiring; flavor split ✅ done | ✅ sender shipped | Cast is GMS — `google` flavor only, never `amazon`/Fire |
| Subtitles | ✅ Media3 `SubtitleConfiguration` — **verified rendering on TV** | ✅ `<track>` via a same-origin **blob** — **verified 1,947 cues** | cross-origin `<track>` fails silently and `crossorigin` on `<video>` would break playback (no CORS on archive.org storage nodes) |
| Sign-in + sync | 🚫 first wave | 🚫 first wave | no CloudKit off Apple; Drive App Data deferred |
| Clip Studio / Creation Studio | 🚫 **never** | 🚫 **never** | a remote has no text entry or direct manipulation (Decisions 033 / 042) |
| Platform home-screen integration | 🔮 Google TV channels / Fire TV catalog | n/a | constrained by §1.4 — our editorial + the user's own Continue Watching, never an opaque model row |

**Verification (all runnable, all green):**

| Gate | Covers | Result |
|---|---|---|
| `tools/verify_tv_focus.sh` | Android TV surfaces by remote (incl. shared Settings/Library via the a11y tree) | 12/12 |
| `tools/tv_browser_tests.js` | web-TV in Chrome | 20/20 |
| `tools/test_tv_focus.mjs` | web-TV focus algorithm | 10/10 |
| `tools/test_tv_ua.mjs` | platform detection vs real UAs | 5/5 |
| `tools/audit_tv_g6.py` | 64-bit + 16 KB page sizes | PASS |
| `tools/audit_fire_tv_gms.py` | Fire TV zero-GMS (amazon flavor) | PASS |

**Submission packs drafted:** `docs/webos-submission.md` (UX scenario +
self-checklist — LG auto-rejects thin checklists), `docs/tizen-submission.md`
(Samsung manual-QA pass + the US-only tier decision).

**Compliance gates (Google TV app quality).** ✅ TV-ML leanback launcher · ✅ TV-MT
touchscreen not required · ✅ TV-LB/TV-BN 320×180 banner with app name · ✅ TV-PS
`minSdk` 29 ≤ 31 · ✅ **TV-G6 64-bit + 16 KB page sizes** (measured, all 12 native
libs — `tools/audit_tv_g6.py`) · ✅ TV-G1 AAB · ✅ **Fire TV zero-GMS**
(`tools/audit_fire_tv_gms.py`) · ⏳ TV-DP full D-pad reachability (needs the
remaining ten-foot passes + device QA).

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
