---
name: macos-native-app-shell
description: Native macOS patterns for Archive Watch — the multi-scene shell (WindowGroup browse + DocumentGroup .archiveproj editor), Library≠Project, shared-Core reuse, AND the parity-face runtime gotchas (player-as-window-root, NO externalMetadata on macOS, full-width-16:9 hero, the fill-image layout trap, no-archive-thumbnail posters, the ImagePipeline + grayscale-decode fix, the fixed-window Channels EPG, structured-concurrency-not-Combine-timers, Callsheet via NSWorkspace). Invoke before building or changing ANY macOS shell, window, document, player, hero, image, or browse/play/library surface.
---

# macOS App Shell — native structure for Archive Watch

Binding spec: `docs/macOS-DESIGN.md` §1–§2, §7. Evidence:
`docs/research/creation-studio-{macos-architecture-parity,nle-ux-teardown}.md`.
The Mac is NOT the iOS app resized — build Mac-native idioms.

## Scene & window architecture

- `WindowGroup "Library"` — parity browse/play/library/search on the shared Core.
- `DocumentGroup` bound to `.archiveproj` — the Creation Studio editor.
- `Window "Render Queue"` — single-instance, long-running exports.
- `Settings` — accounts (CloudKit, archive.org IAS3 keys, YouTube OAuth), storage, quality.

**Rule — Library ≠ Project.** The proxy-clip LIBRARY is app-global persistent state
(SwiftData + iCloud), NOT a document. A PROJECT is the `.archiveproj` document (FCP
event-browser → project-timeline model). Never store the library inside a project; a
project carries timeline + proxy REFERENCES + project-local imports, never archive.org
bytes.

**Rule — `.archiveproj` is a reference package** (`UTType(exportedAs:)` `.package`).
Prototype on `ReferenceFileDocument`; budget an `NSDocument` backbone for URL access,
atomic/async save, and security-scoped bookmarks. De-risk this seam with a spike FIRST —
it's the weakest one.

## Reuse vs rebuild

**Reuse verbatim** the already-extracted Swift Core: `CatalogDB`, `CatalogRefreshService`,
`ResilientStreamLoader`, models, networking, `CloudKitSyncService` (same CloudKit container
→ favorites/playlists/progress sync with Apple TV + iPhone for free). **Rebuild only** the
Mac-native UI. Add to the Core only what all platforms could use.

## SwiftUI shell, AppKit where it must

- **SwiftUI:** `NavigationSplitView` sidebar, `.inspector()`, unified `.toolbar(id:)`,
  `.contextMenu(forSelectionType:)`, menu-bar `.commands`, `Transferable` drag-drop.
- **AppKit bridges (only where SwiftUI stutters):** the timeline = `NSView`+`CALayer` in
  `NSScrollView` (magnification + hit-testing; view-per-clip and Canvas both break down);
  the browser grid starts `LazyVGrid`, migrates to `NSCollectionView` (reuse/prefetch/
  reliable hover); modeless transport keys via an `NSEvent` local monitor.
- **Keyboard-first, one coherent scheme** wired to the menu bar (the reference NLEs collide
  on `B`/`N` — pick one, document it). Power-user Mac idiom.

## The Mac-only thesis (why these features live here)

Creation Studio requires four things touch/TV/web can't host: full filesystem + document
model, subprocess CLI tools, heavy/long-running/background compute, and a
pointer+keyboard+menu+multi-window editor. Keep parity surfaces native-Mac too (windows,
inspectors, menus) — don't port the phone's full-screen modal navigation.

## No-backend storage (three planes)

1. Shared read-only SQLite on a Release/Pages (catalog + stock `clips.sqlite` + subtitle
   `subtitle.sqlite`), query-on-disk natively + WASM-Range on web (Decision 029).
2. User annotation layer: proxy-clip library + projects in SwiftData + iCloud (references).
3. Device-local, never synced, re-derivable: caches, thumbnails, render scratch.

## Parity-face runtime rules (browse / play / library) — the gotchas that bit

Full detail: `docs/macOS-DESIGN.md` Part B (§B1–§B12). The sharp ones, each fixed in code
after real failure — don't relearn them:

- **Player is the window ROOT while playing** (§B2), NOT an overlay on the split view —
  otherwise the split view keeps the toolbar and the prior title bleeds through. `RootView` =
  `Group`: nowPlaying→PlayerWindow / episode→EpisodePlayer / else browse.
- **macOS `AVPlayerItem` has NO `externalMetadata`** (§B5) — show the title via the WINDOW
  TITLE BAR (`navigationTitle "Title (Year)"`). The `AVMutableComposition` metadata-override
  blanks video over the resilient custom-scheme asset; tried+reverted twice — never retry.
- **Hero = full-width + `.aspectRatio(16/9, .fit)`, NO `maxHeight` cap** (§B4). A fixed height
  crops as the window widens; a height cap insets/centers it ("doesn't extend across").
- **The fill-image layout trap** (§B6a): a sized shape owns layout, the image fills via
  `.overlay`/`.background` — in PosterCard, the Detail/Series 240×360 poster wells, and the hero.
- **Never the archive.org `services/img` thumbnail** (§B6b): designed art → typographic title
  card. **Never bare `AsyncImage`** — go through `ImagePipeline` (decoded-NSImage cache + 6/host
  cap + in-flight coalescing) (§B6c). **Decode non-RGB → sRGB** or grayscale renders white (§B6d).
- **Player resume saves every 5 s** (`pos > 1`, dur backfilled) + `SyncNudge`; **live TV never
  persists** WatchProgress (§B3c/d).
- **Channels EPG = a FIXED window** the pointer shifts (Earlier/Later/Now), not a 2D
  frozen-column scroll (§B8).
- **Replace Combine `Timer.publish` with `.task(id:)` loops** (hero, screensaver, debounce) — a
  timer into a `@MainActor` closure can trip a Swift-runtime executor fault (§B10).
- **Callsheet install-detection = `NSWorkspace.urlForApplication(toOpen:)`** — no Info.plist
  queries-schemes on macOS (that's iOS) (§B7).
- Shared identifiers (one ASC record): bundle `app.archivewatch.tvos`, iCloud
  `iCloud.app.archivewatch.tvos`, App Group `group.app.archivewatch.tvos`, UTType
  `org.archivewatch.project`. Sandbox needs `device.microphone` + `device.audio-input` or TCC
  silently denies the voiceover recorder (§B12).
- **Shipping is its own skill:** `apple-app-store-cli-submission` (manual signing, the
  ITMS-90111 Xcode-floor trap, PyJWT venv, screenshots) + `docs/macOS-DESIGN.md` Part C.

## Feature states & density

Every list/grid/browser honors `universal-feature-states`; show "X films searched so far"
for still-building indices (`*Checked == false` = unknown, not empty). Density from removing
chrome; the selection + inspector do the work. Six type levels max.
