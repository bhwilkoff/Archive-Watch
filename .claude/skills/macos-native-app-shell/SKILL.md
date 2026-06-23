---
name: macos-native-app-shell
description: Native macOS app-shell patterns for Archive Watch — multi-scene SwiftUI (WindowGroup browse + DocumentGroup .archiveproj editor + render-queue Window), the Library≠Project rule, the SwiftUI-shell/AppKit-bridge split (timeline NSView+CALayer, browser NSCollectionView), shared Swift Core reuse, and no-backend storage. Invoke before building the macOS app shell, windows, documents, or parity surfaces.
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

## Feature states & density

Every list/grid/browser honors `universal-feature-states`; show "X films searched so far"
for still-building indices (`*Checked == false` = unknown, not empty). Density from removing
chrome; the selection + inspector do the work. Six type levels max.
