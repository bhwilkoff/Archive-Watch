# Archive Watch — macOS app (Phase 0 shell)

Native macOS browse/play/library/search built on the **shared Swift Core** (the
parity face of Decision 042). The Creation Studio editor (`DocumentGroup` /
`.archiveproj`) is a later phase — this proves the Core-reuse thesis first.

Binding spec: `docs/macOS-DESIGN.md`. Research: `docs/research/creation-studio-README.md`.

## What's here (`macOS/`)

| File | Role |
|---|---|
| `ArchiveWatchApp_macOS.swift` | `@main` App — `WindowGroup` + `Settings` scenes, ModelContainer, CloudKit sync wiring |
| `AppRouter_macOS.swift` | Mac-native nav model (sidebar section + one NavigationPath) |
| `RootView_macOS.swift` | `NavigationSplitView` shell + player sheet |
| `Cards_macOS.swift` | `PosterCard`, `GridView`, `ShelfRow` |
| `HomeView_macOS.swift` | Curated shelves + hero banner |
| `BrowseView_macOS.swift` | Paginated grid + decade/sort facets |
| `DetailView_macOS.swift` | Hero + metadata + play + cast + More Like This + reviews |
| `PlayerWindow_macOS.swift` | `AVPlayerView` (AppKit) over the shared `ResilientStreamLoader`; resume via `WatchProgress` |
| `SearchView_macOS.swift` | `.searchable` over the shared FTS5 index |
| `LibraryView_macOS.swift` | Continue Watching / Favorites / Playlists (SwiftData) |
| `SettingsView_macOS.swift` | Account, content filter, TMDb attribution, donate |
| `ArchiveWatch-macOS.entitlements` | App Sandbox + network + **same CloudKit container** + Sign in with Apple + app group + associated domains |
| `Info-macOS.plist` | `archivewatch://` scheme, user-activity types, min macOS 15 |

## Target status — created programmatically (no Xcode GUI needed)

The `ArchiveWatchMac` target now exists in `ArchiveWatch.xcodeproj` and **compiles
clean for macOS** (`-destination 'generic/platform=macOS'`), with the shipping
tvOS/iOS targets re-verified unbroken. It was wired by a direct, additive edit of
`project.pbxproj` (objectVersion 77) rather than the Xcode GUI:

- New `PBXNativeTarget` **ArchiveWatchMac** (`app.archivewatch.macos`, `SDKROOT =
  macosx`, `MACOSX_DEPLOYMENT_TARGET = 15.0`), Debug+Release configs, and a
  shared scheme (Xcode auto-generates it from the target).
- **Core is reused, not copied.** The target points its
  `fileSystemSynchronizedGroups` at the SAME `ArchiveWatch` folder as the
  universal target — so every Core file (`Models/`, `Networking/`, `Services/`,
  `Store/`) is shared automatically; per-platform `#if os()` guards select what
  compiles. `seed.sqlite` rides the synchronized group; `featured.json` +
  `collections.json` are in the target's Resources phase; `catalog.json` is
  excepted (mirrors the main target).
- Entitlements → `ArchiveWatch/macOS/ArchiveWatch-macOS.entitlements`;
  Info.plist → `ArchiveWatch/macOS/Info-macOS.plist`; version inherited from
  `AppVersion.xcconfig` at the project level (Decision 003 — no identity panel).

**Cross-platform gaps that were fixed** (the `#if os()` work the Core needed):
the macOS shell is modeled on the **iOS** app, so the iOS variants of `AppStore`,
`Color(hex:)`, and `SplitMix` (`iOS/*_iOS.swift`) were widened from `#if os(iOS)`
to `#if os(iOS) || os(macOS)` — they're SwiftUI/Foundation-only and UIKit-clean.
`Services/ImageLoader.swift` (UIImage, tvOS/iOS-only consumers) was wrapped in
`#if canImport(UIKit)`; `Services/BackgroundRefresh.swift` (BGTaskScheduler,
unavailable on macOS) was guarded to iOS/tvOS; `Store/AccountStore.swift` got a
macOS `presentationAnchor` (NSWindow). The tvOS `Store/AppStore.swift` is
untouched.

### The one remaining OWNER step — signing & capabilities (only to RUN/ship)

The target builds with signing **off**. To run on *My Mac* or archive, the bundle
id `app.archivewatch.macos` needs its capabilities registered in your Apple
Developer account (these can't be done from here — they touch your portal/iCloud):

- **iCloud / CloudKit** — container `iCloud.app.archivewatch.tvos` (the SAME
  container as tvOS/iOS, so the Mac syncs with them).
- **Sign in with Apple**, **App Groups** (`group.app.archivewatch.tvos`),
  **Associated Domains** (`applinks:archivewatch.org`).

With those enabled and automatic signing on, a local Debug "My Mac" build signs
itself. Everything else is already in the project.

## Phase 0 scope / non-goals

In: browse, home shelves, detail, native player (resilient stream + resume),
search, library, settings, CloudKit sync, deep-link scheme, TV series
season/episode drill-in (`SeriesStore`), Collections, Surprise, Public Domain
Day, and Channels (a proportional EPG guide — fixed rail + pinned ruler +
runtime-sized blocks, window paged by Earlier/Later/Now, tune-in lineup player
with woven commercials, create/right-click-delete user channels).
**Not yet** (later phases per `docs/macOS-DESIGN.md`): the Creation Studio
`DocumentGroup` editor, the proxy-clip library, the stock/subtitle indices. The
sidebar + single split-view is intentionally Mac-native, not the iOS tab bar.

## Known refinements (cheap follow-ups)

- Player title/info overlay (macOS `AVPlayerItem.externalMetadata` is iOS/tvOS-only;
  use a `contentOverlayView` or the window title — deferred).
- `NSCollectionView` migration for very large grids (Rule 7b) — `LazyVGrid` is fine
  for now.
- Channels uses a fixed-window EPG (window paged by Earlier/Later/Now), not a 2D
  frozen-rail/frozen-column scroll — the offset-mirrored 2D approach rendered the
  rail unreliably; the windowed model is the proven tvOS/iOS layout and renders
  correctly. A horizontally-scrollable full-day grid is a possible later refinement.
