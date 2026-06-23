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

## Owner step — create the Xcode target (GUI)

These files compile only inside an Xcode target. Until then, SourceKit shows
"Cannot find AppStore/Catalog/… in scope" on every file — these are the known
**phantom errors** (CLAUDE.md): the symbols live in the shared Core and resolve
once the files join a target that also compiles the Core. Steps:

1. **File ▸ New ▸ Target ▸ macOS ▸ App.** Name `ArchiveWatchMac`, SwiftUI,
   SwiftData, bundle id `app.archivewatch.macos`. Delete its auto-generated
   `ContentView.swift` + `…App.swift` (this folder replaces them).
2. **Add the `macOS/` group** to the new target (the 13 files above).
3. **Add the SHARED Core to the target** (Target Membership checkbox) — reuse,
   do NOT copy:
   - `Models/` (Catalog, UserState, Channels, ContentItem, Taxonomy, VideoClip, …)
   - `Networking/` (ResilientStreamLoader, ArchiveClient, HTTPClient, TMDbClient,
     ArtworkResolver, DerivativePicker, EnrichmentService, WikidataClient)
   - `Store/` (AppStore, CatalogDB, AccountStore) — NOTE: `AppStore`/`AccountStore`
     have iOS/tvOS variants; add the shared one and confirm there's no `#if`
     collision (the macOS app uses the shared `CatalogDB`/`AppStore` query surface).
   - `Services/` (CatalogLoader, CatalogRefreshService, CloudKitSyncService,
     SeriesStore, ImageLoader, CollectionMetadata, SplitMix, helpers)
   - Resources: bundle **`seed.sqlite`** and **`featured.json`** in the target.
4. **Set entitlements** to `macOS/ArchiveWatch-macOS.entitlements`; **Info.plist**
   to `macOS/Info-macOS.plist` (or merge its keys). Enable capabilities: iCloud
   (CloudKit, container `iCloud.app.archivewatch.tvos`), Sign in with Apple, App
   Groups (`group.app.archivewatch.tvos`), Associated Domains.
5. **Wire `AppVersion.xcconfig`** to the target (Decision 003 — never the identity
   panel).
6. Build for **My Mac** (macOS 15+). Fix any genuine cross-platform `#if os()`
   gaps the shared files surface (e.g. UIKit-only code in a shared file should be
   guarded; flag these — they belong in the platform folders, not the Core).

## Phase 0 scope / non-goals

In: browse, home shelves, detail, native player (resilient stream + resume),
search, library, settings, CloudKit sync, deep-link scheme.
**Not yet** (later phases per `docs/macOS-DESIGN.md`): the Creation Studio
`DocumentGroup` editor, TV series episode drill-in (`SeriesStore`), Channels,
Surprise grid, the proxy-clip library, the stock/subtitle indices. The sidebar +
single split-view is intentionally Mac-native, not the iOS tab bar.

## Known refinements (cheap follow-ups)

- Player title/info overlay (macOS `AVPlayerItem.externalMetadata` is iOS/tvOS-only;
  use a `contentOverlayView` or the window title — deferred).
- `NSCollectionView` migration for very large grids (Rule 7b) — `LazyVGrid` is fine
  for now.
- TV section currently lists series cards routing to `DetailView`; the
  season/episode drill-in is a later port of `SeriesStore`.
