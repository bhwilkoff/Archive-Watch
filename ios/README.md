# Archive Watch — iOS app (Phase 1)

Native iPhone/iPad app for Archive Watch, built on the **shared Core** (`ios/Core/`),
in native iOS-26 idioms (NOT the tvOS UI reskinned). See `docs/MULTIPLATFORM-PLAN.md`
and Decision 028.

## What's here (all written; Core is compile-verified for iOS)
```
ios/
├── Package.swift          ← ArchiveWatchCore compile-verification harness (builds for iOS ✅)
├── Core/                  ← SHARED, platform-neutral core (copied from the tvOS app, verified clean)
│   Catalog, UserState, CatalogDB, CatalogRefreshService, ResilientStreamLoader,
│   ContinuousPlayback (decoupled via ContinuousPlaybackSource), ChannelScheduler,
│   CollectionMetadata, SeriesStore, CatalogLoader, ImageLoader, CloudKitSyncService,
│   HTMLStripper, SplitMix, Color+Hex
├── App/                   ← ArchiveWatchApp (@main), AppStore, Router, Design
├── Views/                 ← RootView, Home, Browse, Detail, Player, Search, Library, Settings
├── Components/            ← PosterTile, PosterImage
├── ArchiveWatch-iOS.entitlements   ← CloudKit (SAME container as tvOS), SiwA, App Group
└── Info-iOS.plist
```

The Core is verified: `cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme ArchiveWatchCore -destination 'generic/platform=iOS' build` → **BUILD SUCCEEDED**.
The UI is written against the Core's real APIs but isn't compiled until the app
target exists (the one step below). SourceKit "cannot find … in scope" warnings in
these files are expected until then (cross-file resolution with no target).

## Create the iOS app target (the one Xcode-GUI step, ~10 min)
1. **Xcode → File → New → Target → iOS → App.** Product Name `ArchiveWatch`
   (no spaces). Interface SwiftUI, Language Swift. Save into this repo.
   - Bundle id: `app.archivewatch.ios` (separate App Store product from tvOS).
   - Deployment target: **iOS 26.0**.
2. **Delete** the template-generated `ContentView.swift` / `App.swift` (we provide them).
3. **Add files to the target** — drag these FOLDERS in as groups (Xcode 16 file-
   system synchronized groups work great here): `ios/Core`, `ios/App`, `ios/Views`,
   `ios/Components`. **Do NOT add `ios/` itself** (that would sweep in `Package.swift`).
4. **Build settings:**
   - Set `Info.plist` to `ios/Info-iOS.plist` (or merge its keys into the generated one).
   - Code Signing Entitlements → `ios/ArchiveWatch-iOS.entitlements`.
   - Reference the shared `AppVersion.xcconfig` for both configs (Decision 003).
5. **Capabilities** (Signing & Capabilities): **iCloud → CloudKit**, container
   `iCloud.app.archivewatch.tvos` (the SAME one the tvOS app uses → they sync);
   **Sign in with Apple**; **Push Notifications**; **App Groups**
   `group.app.archivewatch.tvos`. (These match the tvOS App ID — add them to the
   iOS App ID in the Apple Developer portal too.)
6. **Bundle these resources** into the app target (Copy Bundle Resources):
   - `ArchiveWatch/ArchiveWatch/seed.sqlite` (first-paint catalog — the SAME built seed)
   - `featured.json`, `shared/editorial/collection_metadata.json`
   - `series/` (if you want offline series spines; otherwise they fetch from Pages)
   - the app icon set.
7. **Build & run** on an iPhone simulator. Home should paint from the seed, then
   swap to the downloaded full DB.

## How the reuse works (Decision 028)
- `ios/Core/*` is the platform-neutral layer copied from the tvOS app and verified
  to compile for iOS unchanged (every "tvOS" reference there was a comment, not an
  API). It is the same SQLite query layer, the same `ResilientStreamLoader`
  (Decision 021), the same CloudKit sync (Decision 022), the same F4 queue.
- The UI in `App/` + `Views/` is **new and native** (bottom `TabView`,
  `.searchable`, `.fullScreenCover` player with PiP, `ContentUnavailableView`
  states) — it does not import tvOS focus/sidebar idioms.
- **Sync with the Apple TV is free**: same CloudKit container + the reused
  `CloudKitSyncService`, so an iPhone on the same iCloud account sees the TV's
  favorites/playlists/progress.

## Shipped this phase (PARITY.md → 🚧/⏳)
Home (hero + shelves + Continue Watching), Browse (grid + facet/sort menu + paging),
Detail (metadata + Play + Favorite + Share + More Like This + cast), Player (AVKit +
PiP + resilient streaming + resume), Search (FTS5), Library (Favorites/Watched/
Playlists), Settings (mature toggle + attribution + donate). Deep-link routing.

## Next within Phase 1 / Phase 2
TV Shows (series→episode), Collections, Surprise + Channels/modes, iPad
`NavigationSplitView` adaptivity, WidgetKit widgets, the sign-in/sync UI wiring,
and the later safe refactor of the tvOS app onto the shared `ArchiveWatchCore`
package (currently the Core is duplicated to avoid touching the in-review tvOS app).
