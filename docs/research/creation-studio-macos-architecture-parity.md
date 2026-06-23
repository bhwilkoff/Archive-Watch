# Creation Studio — native macOS app architecture + cross-platform parity (research)

*Date: 2026-06-22. Target: macOS 15 (Sequoia) / macOS 26 (Tahoe), Apple Silicon.
Swift 6 / SwiftUI with targeted AppKit interop. Apple frameworks inside the app;
`ffmpeg`/CLI subprocesses allowed on Mac for heavy processing; no separate
backend (sync via the user's iCloud, Decision 028).*

**Scope of THIS brief.** The companion research already nails the *engine* and
the *editor mechanics* — don't re-derive them here:

- `docs/research/creation-studio-avfoundation-engine.md` — the AVFoundation
  compose/overlay/audio/export engine (features 1, 3, 4, 5, 10) on the modern
  Configuration-based API; the two-pass CIFilter+CALayer rule.
- `docs/research/creation-studio-proxy-remote-editing.md` — the non-destructive
  proxy-clip model (feature 2): reference-not-copy, OTIO-shaped Codable, the
  range-cache-then-export strategy, the remote `AVAssetExportSession` -11800 trap.
- `docs/research/creation-studio-nle-ux-teardown.md` — the timeline mechanics
  (CapCut-style magnetic main track + overlays), the stock-browser teardown, and
  the **SwiftUI-shell + AppKit-bridge** UI mapping (Part 3 §3.1–3.12).
- `docs/research/social-clip-creation.md` + `…/video-clipping-native-frameworks.md`
  + `docs/CREATE-STUDIO-PLAN.md` — the iOS Clip Studio basis + Decision 033.

This brief answers the **remaining, un-synthesized questions**:

1. The **whole-app architecture** — scene/window structure for a *browse app
   PLUS a document-based editor*, the document model (a `.archiveproj` package),
   menus/toolbar/sidebar/inspector/Quick Look, the macOS app lifecycle.
2. The **reuse-vs-rebuild split** that gives parity with the other Apple
   platforms (which shared Swift Core pieces the Mac consumes verbatim).
3. The **Mac-only thesis** — the canonical Creation Studio feature list and
   *why* each belongs structurally only on the Mac.
4. **Storage with no backend** across all four data stores.
5. The **learning-orientation gate** for the whole Creation Studio set, the
   structure for the binding `docs/macOS-DESIGN.md`, and the new project skills.

---

## 0. TL;DR recommendations

- **One app, two faces, three+ scene types.** A single macOS target with a
  **`WindowGroup` "Library/Browse" scene** (the parity face — the same browse/
  play/search/channels app the other platforms ship) **+ a `DocumentGroup`
  editor scene** bound to a **`.archiveproj` package document** (Creation Studio)
  **+ a single `Window` Render/Export Queue utility scene + `Settings`**. The
  proxy-clip *library* is app-global state (SwiftData + iCloud), NOT a document;
  a *project* is a document.
- **Reuse the shared Swift Core verbatim** (`CatalogDB`, `ResilientStreamLoader`,
  `Catalog`/`UserState` models, networking clients, `CloudKitSyncService`,
  `ChannelScheduler`, the F4 continuous-playback engine) so the Library face is
  ~parity-for-free; rebuild only the Mac-native UI shell. The Mac joins the same
  CloudKit container → favorites/playlists/progress sync with the Apple TV +
  iPhone for free (per-ecosystem sync island, Decision 028).
- **The Mac-only thesis is structural, not stylistic.** Creation Studio (multi-
  track NLE), full-filesystem export/import, long-running/background heavy
  processing, `ffmpeg`/CLI subprocesses, the cross-title stock miner, and the
  text→supercut assembler are things the touch/TV/web platforms *structurally*
  can't host (sandboxed FS, no subprocess, no multi-window pointer editor, jetsam
  memory limits, no menu bar). They are not "the iOS editor, bigger."
- **Document model:** `.archiveproj` = a **package** (`UTType` with
  `conformsTo: .package`, `isPackage`) holding a Codable timeline (OTIO-shaped) +
  caches/thumbnails inside the bundle. Use `ReferenceFileDocument` for a SwiftUI
  prototype but **budget an `NSDocument` backbone** (URL access, async/atomic
  save, security-scoped bookmarks) — de-risk with a spike (per the UX teardown).
- **No-backend storage holds** for all four stores: shared catalog SQLite on the
  GitHub Release (query-on-disk, reused Core), proxy-clip library + projects in
  SwiftData + iCloud (annotation layer only), the stock/subtitle indices derived
  from the same catalog DB (no new host). Cached media bytes are device-local,
  re-derivable, never synced.
- **Learning gate:** the whole set passes the four-question test **iff** every
  generator (the text→supercut #9 and the auto-tagged stock miner #6) produces an
  **editable timeline, never a one-tap finished cut** (Decision 033). Automate the
  mechanical (find, fetch, transcode, tag, reframe, attribute); preserve the
  meaningful (which clips, what order, where to cut, what to say).

---

## 1. App architecture — a browse app PLUS a document-based editor

### 1.1 The scene graph (the load-bearing structural choice)

SwiftUI on macOS lets an app compose **multiple distinct scene types** in one
`App.body` — `WindowGroup`, `DocumentGroup`, `Window`, `Settings`,
`MenuBarExtra` — each managing its own window lifecycle
([nilcoalescing — Scene types in a SwiftUI Mac app](https://nilcoalescing.com/blog/ScenesTypesInASwiftUIMacApp/),
[createwithswift — Understanding scenes for your macOS app](https://www.createwithswift.com/understanding-scenes-for-your-macos-app/),
[WWDC22 — Bring multiple windows to your SwiftUI app](https://developer.apple.com/videos/play/wwdc2022/10061/)).
This is exactly the seam Archive Watch needs — the "browse app" and the "editor"
are *different scene kinds*, not tabs in one window:

```swift
@main
struct ArchiveWatchMacApp: App {
    @State private var appModel = AppModel()        // shared Core: CatalogDB, sync…

    var body: some Scene {
        // 1) PARITY FACE — the browse/play/search/channels app (data-driven)
        WindowGroup("Archive Watch", id: "library") {
            LibraryRootView_macOS().environment(appModel)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { LibraryCommands() }              // View/Go/Playback menus

        // 2) CREATION STUDIO — the document-based NLE editor
        DocumentGroup(newDocument: { ClipProjectDocument() }) { config in
            CreationStudioView_macOS(document: config.document)
                .environment(appModel)               // shares the proxy-clip library + Core
        }
        .commands { EditorCommands() }               // Timeline/Clip/Export menus (editor-only)

        // 3) UTILITY — a single Render/Export Queue window (one instance)
        Window("Render Queue", id: "render-queue") {
            RenderQueueView_macOS().environment(appModel)
        }
        .keyboardShortcut("r", modifiers: [.command, .option])

        // 4) Settings + (optional) menu-bar status item for an active export
        Settings { SettingsView_macOS().environment(appModel) }
        // MenuBarExtra(...) optional: surface a running export's progress
    }
}
```

Why this shape:

- **`WindowGroup` for Library** — data-driven, supports tabbed windows (macOS
  groups multiple browse windows into tabs for free), and `openWindow(id:)` /
  `openWindow(value:)` to spawn a second browse window or open a Detail in its
  own window ([createwithswift — scenes](https://www.createwithswift.com/understanding-scenes-for-your-macos-app/)).
  A power-user can have *two browse windows side by side while editing* — a
  genuine Mac affordance the single-window phone/TV apps can't offer.
- **`DocumentGroup` for the editor** — each open project is its own window; New /
  Open / Open Recent / the document title bar / proxy icon / Versions / autosave
  all come from the document scene. A user can have **several projects open at
  once**, each its own window, dragging clips between them.
- **`Window` (single instance) for the Render Queue** — `Window` is for "a
  single, distinct window… a tool/utility panel accessible from multiple places
  but only one instance" ([nilcoalescing — scenes](https://nilcoalescing.com/blog/ScenesTypesInASwiftUIMacApp/)).
  Long exports run here, decoupled from any one project window so closing a
  project doesn't kill its render.
- **Scene bridging (macOS 26)** lets us drop to AppKit (`NSDocument`,
  `NSHostingController`) for the editor backbone while keeping SwiftUI scenes —
  "SwiftUI scenes can be requested from UIKit and AppKit lifecycle apps with
  scene bridging" ([WWDC25 — What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/256/)).
  So the recommended "DocumentGroup prototype → NSDocument backbone" migration
  (§1.3) does **not** force abandoning SwiftUI for the rest.

### 1.2 Two persistence tiers — the LIBRARY is not a document

A crucial modeling decision the teardown flags but doesn't resolve: **what is a
document and what is app-global state?**

| Concept | Lives where | Why |
|---|---|---|
| **Catalog** (the 30k archive.org titles) | shared SQLite on the GitHub Release, query-on-disk via the reused `CatalogDB` | read-only shared data plane (Decision 017); identical to every platform |
| **Proxy-clip LIBRARY** (saved scenes tagged on top of archive.org — feature 2) | **app-global SwiftData store + iCloud** (NOT a document) | persistent across all projects; a clip is reusable in many projects; syncs as the Apple island annotation layer (Decision 028) |
| **A PROJECT** (a multi-clip timeline) | **a `.archiveproj` document** (one window each) | the user's authored edit; New/Open/Save/Versions; multiple open at once |
| **Cached media bytes + generated thumbnails/waveforms** | `Library/Caches` (device-local) **or inside the project package** | re-derivable, never synced; LRU-evictable (proxy doc §5) |
| **User state** (favorites/playlists/progress for the Library face) | SwiftData + the SAME CloudKit container as tvOS/iOS | parity sync island |

This split mirrors **Final Cut's "Library/Event browser → Project timeline"**
reference model (the teardown's §4.4): archive.org is the camera-original, the
proxy-clip library is the event browser, a `.archiveproj` is a project. The
library is global so the same clip drops into any project; a project edit never
mutates the library clip (the proxy doc §4.1 reusability rule).

### 1.3 The document — a `.archiveproj` PACKAGE

A project must hold a Codable timeline **plus** generated artifacts (poster
frames, filmstrip thumbnails, optionally a self-contained proxy cache). That is a
**package** (a directory the Finder treats as one file), declared as a custom
`UTType`:

```swift
extension UTType {
    static let archiveProject = UTType(exportedAs: "org.archivewatch.project")
    // Info.plist Exported Type Identifier:
    //   conformsTo: com.apple.package  (NOT public.data)
    //   so the bundle is a navigable directory, Quick-Look-able, iCloud-friendly
}
```

- Declare it in the target's **Exported Type Identifiers** and instantiate with
  `UTType(exportedAs:)`, matching the Info.plist identifier exactly — the
  recommended pattern ([HWS — document-based app with FileDocument & DocumentGroup](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-document-based-app-using-filedocument-and-documentgroup),
  [createwithswift — Crafting document-based apps in SwiftUI](https://www.createwithswift.com/crafting-document-based-apps-in-swiftui/)).
- Conform to `.package` so the bundle holds the timeline JSON + a `caches/`
  subfolder of thumbnails + optional clip-window proxies, while still presenting
  as a single file the user can move/duplicate/AirDrop.
- **`ReferenceFileDocument`, not `FileDocument`.** The project is a *class /
  `@Observable` object graph mutated incrementally* (the timeline), with undo and
  snapshot save — exactly `ReferenceFileDocument`'s use case; `FileDocument`'s
  value semantics fight a live editor ([Apple — Building a document-based app with SwiftUI](https://developer.apple.com/documentation/swiftui/building-a-document-based-app-with-swiftui),
  [eclecticlight — SwiftUI on macOS: Documents](https://eclecticlight.co/2024/05/16/swiftui-on-macos-documents/)).
- **Known SwiftUI-document limits → budget the `NSDocument` backbone** (teardown
  §3.4): the SwiftUI document model gives **no direct document URL** (needed for
  relative media paths, render caches, and **security-scoped bookmarks** to the
  user's archive cache), and `ReferenceFileDocument` saves have been observed
  **on the main thread** (UI hang on a big project). Drop to
  `NSDocument`/`NSDocumentController` (host SwiftUI via `NSHostingController`)
  for reliable async/atomic save, the URL, autosave + Versions, and robust menu
  control. **De-risk with a spike before committing** — this is one of two
  places the architecture can go wrong late (the other is the AppKit timeline).

### 1.4 Menu bar, toolbar, sidebar, inspector, drag-drop, Quick Look

These map onto native primitives (the teardown's §3.3–3.9 has the deep cites;
summarized here as the app-shell layer):

- **Menu bar = `.commands`** per scene. `LibraryCommands` (View/Go/Playback) on
  the WindowGroup; `EditorCommands` (Timeline/Clip/Export) on the DocumentGroup,
  splicing `CommandGroup(after:/replacing:)` into `.undoRedo`/`.pasteboard`. Every
  editing verb is *also* a menu item with a `.keyboardShortcut` — the Mac
  discoverability layer that teaches shortcuts. **macOS 26 bonus:** the same
  `.commands` now drives the iPad swipe-down menu bar, so the menu definitions
  could later seed an iPad pro-editor ([WWDC25 — What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/256/)).
- **Toolbar = `.toolbar(id:)` + `.windowToolbarStyle(.unified)`** — customizable,
  drag-rearrange, "Customize Toolbar…", auto-saved. macOS 26 toolbars get the
  Liquid Glass scroll-edge treatment for free.
- **Sidebar = `NavigationSplitView` + `.listStyle(.sidebar)`** — three columns
  map onto **sources (collections / categories / boards) → browser grid →
  detail/inspector**; the same `NavigationSplitView` becomes a Liquid Glass
  sidebar on macOS 26 ([WWDC25](https://developer.apple.com/videos/play/wwdc2025/256/)).
- **Inspector = `.inspector(isPresented:)`** (macOS 14+) — the trailing
  properties column for selected-clip opacity/scale/position/volume; `Form` of
  `LabeledContent`; `InspectorCommands` for the Show/Hide menu item.
- **Drag-and-drop = `.draggable`/`.dropDestination` + a `Transferable`
  `ClipReference`** (archive id + in/out, custom UTType — no media bytes moved);
  the drop `location` gives track+time. An AppKit `NSDraggingDestination` lane is
  reserved only for the live, pointer-following drop indicator.
- **Quick Look for `.archiveproj`** — ship a **Quick Look Preview + Thumbnail
  extension** so Finder previews a project (poster-mosaic of its clips + a
  scrub of the assembled timeline) without opening the app. Set
  `QLSupportedContentTypes` to the project UTI, `QLIsDataBasedPreview`, and a
  `QLPreviewProvider`/`QLPreviewingController` — the modern app-extension path
  (qlgenerators are dead as of Sequoia) ([Apple — QLPreviewProvider](https://developer.apple.com/documentation/quicklook/qlpreviewprovider),
  [Apple — Creating Quick Look Thumbnails](https://developer.apple.com/documentation/quicklookthumbnailing/creating-quick-look-thumbnails-to-preview-files-in-your-app),
  [eclecticlight — How QuickLook creates thumbnails/previews](https://eclecticlight.co/2024/11/04/how-does-quicklook-create-thumbnails-and-previews-with-an-update-to-mints/)).
  This is a Finder-integration win **no other platform can have**.

### 1.5 The macOS app lifecycle (vs iOS/tvOS)

- **`@main App` + `NSApplicationDelegateAdaptor`** if AppKit hooks are needed
  (the `NSDocument` backbone, services, dock menu). Default to the SwiftUI
  lifecycle; adopt the adaptor only where the document backbone demands it.
- **Multi-window is the norm, not a special case** — closing the last window
  does NOT terminate a Mac app (unlike iOS). Long renders survive in the Render
  Queue window; the app stays alive in the menu bar.
- **Background/long-running processing is allowed and expected** — no
  `BGTaskScheduler` ceiling, no jetsam at iOS's aggression. A 40-minute supercut
  render or a 5,000-clip stock-index build runs as a normal process (optionally
  under `ProcessInfo.beginActivity(.userInitiated)` to defer App Nap / sleep).
- **Sandbox + entitlements:** App Sandbox with **user-selected read-write** +
  **security-scoped bookmarks** for export folders the user picks; the bundled
  `ffmpeg` runs as a child process **inside the sandbox** (allowed — it's our own
  helper, not an arbitrary download). `com.apple.security.files.user-selected.*`
  + `cs.allow-jit` are NOT needed; a child-process entitlement is the only
  sandbox nuance for the CLI helper.

---

## 2. Code reuse / parity — the shared Swift Core, verbatim

The Mac's **Library face is parity-for-(almost)-free** because the heavy,
non-UI Core was already extracted for the iOS app (`ios/Core`, ~60–70% reuse per
the MULTIPLATFORM-PLAN). The Mac reuses the *same Swift files*; only the UI shell
is Mac-native.

### 2.1 Reused VERBATIM (zero or near-zero new code)

| Core piece | File(s) today | What it gives the Mac |
|---|---|---|
| **Catalog query layer** | `Store/CatalogDB.swift` | Home/Browse/Search/Detail/Channels queries — identical results to tvOS/iOS |
| **Catalog refresh** | `CatalogRefreshService` (download `.zz` → inflate → swap) | the same shared catalog, on-disk, off the heap |
| **Resilient streaming** | `Networking/ResilientStreamLoader.swift` | archive.org playback with resume-on-reset + node failover (Decisions 021/031/034) — and the Creation Studio source-fetch path |
| **Models** | `Models/Catalog.swift`, `UserState.swift`, `Channels.swift`, `Taxonomy.swift` | the schema contract; no re-decode |
| **Networking clients** | `ArchiveClient`, `TMDbClient`, `WikidataClient`, `HTTPClient` | metadata fetch where needed |
| **Sync** | `CloudKitSyncService` (+ `AccountStore`) | the SAME CloudKit container → favorites/playlists/progress sync with Apple TV + iPhone |
| **Channels EPG** | `ChannelScheduler` (date-seeded, deterministic) | the same guide on the Mac (rebuild the *layout*, reuse the schedule) |
| **Continuous playback (F4)** | the queue/advance engine | binge/lineup playback bound to `AVQueuePlayer` |

The contract is the **catalog SQLite schema + the editorial JSON** (`docs/
CATALOG-CONTRACT.md`). The Mac implements against it like every other client; it
does **not** re-host or re-derive the pipeline.

### 2.2 REBUILT Mac-native (the UI shell + Mac affordances)

- The browse shell: `NavigationSplitView` sidebar + grid + Detail, **pointer +
  keyboard + menu-bar** (not the iOS `TabView`, not the tvOS focus engine).
- Player: `AVPlayerView` (AVKit) with macOS transport + **PiP** + AirPlay, fed by
  the reused `ResilientStreamLoader`.
- Channels guide layout, Search facets (toolbar/menu), Library, Settings — all
  re-authored as Mac windows/inspectors/commands.
- **New Mac affordances** the parity face gains: multi-window browse, Open in New
  Window, Services menu, Spotlight (Core Spotlight) indexing of the catalog,
  drag a poster to the Finder/another app, Quick Look a Detail.

> **Parity principle (Decision 028 / `PARITY.md`):** *same verb, native idiom.*
> The Mac browses/plays/searches/tunes-in like the other platforms (same Core,
> same results); it just does so with Mac chrome. Update `PARITY.md` rows in the
> same change set; add a **macOS column**.

### 2.3 What the Library face does NOT inherit

The tvOS/iOS *views* (focus carousels, touch sheets, the iOS Clip Studio touch
timeline) are **not** ported — they're the wrong idiom. The iOS Clip Studio
*engine* (`Services/ClipExporter.swift`, AVFoundation Configuration-based) ports
~1:1 into the Mac Creation Studio engine; its *interaction layer* is re-authored
for pointer+keyboard+menu (the teardown's whole thesis).

---

## 3. What's genuinely Mac-ONLY (the thesis)

Creation Studio is a **first-class Mac-native NLE over public-domain archive.org
video** with a built-in cross-title stock browser. These features are Mac-only
**structurally** — the constraint, not the taste, excludes the other platforms.

### 3.1 The canonical Creation Studio feature list

(Consolidating the numbering scattered across the engine + proxy docs; this is
the master list for `docs/macOS-DESIGN.md`.)

| # | Feature | Mac-only because… |
|---|---|---|
| **1** | **Multi-clip / multi-track timeline composition** | needs a dense, zoomable, hover-driven, keyboard-modeless pointer editor (AppKit `NSView`+`CALayer` timeline). Touch can't hit-test it; TV has no pointer; web has no `NSScrollView` magnification or frame-accurate composition. |
| **2** | **Proxy-clip library over REMOTE archive.org** (scenes tagged on top, no full download) | needs persistent cross-session range-caching + a multi-source library browser; the full-filesystem scratch cache + LRU economics are a desktop concern. |
| **3** | **Timed text / title overlays** (lower-thirds, keyframed) | part of the timeline editor (#1). |
| **4** | **Audio mix / replace / dub** (multi-track, ducking) | multi-track timeline + waveform rendering (`AVAssetReader` downsample) — desktop editing. |
| **5** | **Export** (MP4/ProRes; ffmpeg concat/transcode) | **subprocess `ffmpeg`**, **full-filesystem write to a user-picked folder**, **long-running render** — all three are unavailable on iOS/tvOS/web by construction. |
| **6** | **Auto-tagged STOCK MINER** (browse clips across MANY titles, archive-native facets) | builds + queries a **stock index** derived from the catalog + on-device tagging (Vision/scene-shot detection via CLI), feeding the timeline — the Adobe-Stock-panel paradigm, free + native, on a multi-window pointer browser. |
| **7** | **Project files + import/export interchange** (`.archiveproj`, `.otio`/FCPXML/EDL round-trip) | a **document-based** app with Finder, Open Recent, Quick Look, and OTIO interchange to Resolve/FCP/Premiere — a filesystem + document-model feature. |
| **8** | **Render/Export Queue** (batch, background) | long-running background processing in a dedicated utility window — no iOS background ceiling, no web worker memory limit. |
| **9** | **Text → SUPERCUT assembler** (search subtitles across titles → assemble matching moments) | needs the **subtitle index** + heavy cross-title search + a *generated EDITABLE timeline*; the generation is desktop compute, and the result must land in the #1 editor (never a finished cut). |
| **10** | **Keyframing** (opacity/transform/volume ramps) | part of the timeline editor (#1). |

### 3.2 Why these belong ONLY on the Mac — the four structural reasons

1. **Full filesystem + a document model.** Export to a chosen folder,
   import/round-trip `.otio`/FCPXML/EDL, `.archiveproj` packages, Open Recent,
   Quick Look, Versions. iOS is `Files`-sandboxed and document-shy; tvOS has no
   user filesystem; the web PWA has only OPFS/downloads. Features **5, 7, 8**
   require it.
2. **Subprocess CLI tools (`ffmpeg`, scene-detect).** The Mac may shell out
   (project constraint); iOS/tvOS cannot spawn processes, and the web can't run
   native binaries (wasm-ffmpeg is heavyweight + memory-bound). Robust transmux/
   concat/transcode (feature **5**) and shot-detection tagging (feature **6**) lean
   on this.
3. **Heavy + long-running + background compute.** A multi-clip render, a stock
   index build, or a cross-title subtitle search is minutes of CPU/GPU and large
   working memory. iOS/tvOS face jetsam (the same 3 GB pressure that drove
   Decision 017) + background-execution ceilings; the web is single-threaded-ish
   and memory-capped. Features **5, 6, 8, 9**.
4. **A pointer + keyboard + menu-bar editor + multi-window.** The NLE timeline
   (#1, #3, #4, #10) needs hover-skim, precise trim-handle hit-testing, modeless
   transport keys (Space/JKL/nudge), right-click, marquee multi-select, pinch/⌘-
   scroll zoom, and multiple project windows. Touch can't hit a 2px trim edge at
   speed; the TV has no pointer; the web lacks `NSScrollView` magnification and
   frame-accurate composition. This is why the iOS Clip Studio stays a *single*-
   clip touch tool and the Mac gets the *multi*-clip editor.

> **The phones create one clip; the Mac assembles a film.** iOS Clip Studio
> (Decision 033) is the single-clip social-share tool — trim/reframe/caption ONE
> moment. The Mac is the workbench where many clips from many titles become a
> supercut / fan-edit / montage. Both create; only the Mac can host the
> *assembly*. tvOS + web remain lean-back viewers (no editing affordance).

---

## 4. Storage with no backend (all four stores)

Per Decision 028 there is **no separate backend**; every store is either the
shared read-only data plane or the user's own iCloud.

| Store | Where it lives | Sync | Notes |
|---|---|---|---|
| **Shared catalog** (30k titles, FTS5) | `catalog.sqlite.zz` on the **GitHub Release**; download → inflate (Compression framework) → **query on disk** via reused `CatalogDB` | n/a (read-only, refreshed by CI) | Decisions 017/019; identical to tvOS/iOS |
| **Proxy-clip library** (feature 2) + **projects index** | **SwiftData** app-global store | **iCloud** (CloudKit private DB / SwiftData+CloudKit) — *annotation layer only* (URLs + in/out + tags), tiny, offline-first, LWW merge on `modifiedAt` | same Apple sync island as favorites; cached bytes NEVER synced |
| **`.archiveproj` projects** | a **package document** on disk (user's chosen location, incl. iCloud Drive) | iCloud Drive if the user saves there (document-level, free) | the timeline JSON + caches inside the bundle |
| **Stock index (#6) + subtitle index (#9)** | **derived from the same catalog SQLite** — additional tables/FTS the build (or a one-time on-device pass) populates; no new host | n/a | subtitles already ride the catalog `captions` field (Decision 039); the stock index is a query view + on-device shot-tag cache |
| **User state** (favorites/playlists/progress — Library face) | SwiftData | the **same CloudKit container** as tvOS/iOS | parity sync for free |
| **Cached media bytes, thumbnails, waveforms, render scratch** | `Library/Caches` (or inside the project package) | **never synced** | re-derivable from references; LRU-evicted (proxy doc §5); pin ranges for an open project |

Key invariants: **only references sync, never media**; **the stock + subtitle
indices add no new infrastructure** (they're views over the catalog DB the Mac
already downloads); **the catalog/pipeline is consumed, never re-hosted**
(shared-data-plane contract).

---

## 5. Learning-orientation, the binding design doc, and skills

### 5.1 The four-question test — the WHOLE Creation Studio set

Run against CLAUDE.md / `learning-orientation-design`:

1. **Deepens understanding?** **Yes.** Clipping and assembling forces
   frame-by-frame, subtitle-level engagement with archival film and surfaces its
   provenance (source title, year, archive origin). The cross-title stock miner
   (#6) and text-search supercut (#9) make a user *discover* connections across
   the public-domain corpus they'd never find passively. The opposite of a feed.
2. **Invites participation?** **Yes.** The user IS the editor — chooses the
   clips, the order, the words, the cut. Co-authorship of a film out of the
   commons.
3. **Supports agency?** **Yes — conditional on the no-auto-edit rule.** The
   editorial cut is the meaningful human act; automating it end-to-end would
   strip the learning. **Binding gate (Decision 033):**
   - **#9 text→supercut** must produce an **editable timeline of candidate
     moments**, ranked + assembled in cut order, that the user *reviews, reorders,
     trims, and approves* — **never a one-tap finished export**. Automate the
     mechanical (search subtitles across titles, fetch the windows, lay them on a
     track in time order, attribute each). Preserve the meaningful (which moments
     belong, what sequence tells the story, where each cut lands).
   - **#6 auto-tagged stock** auto-*tags* (shot type, has-faces, color/B&W,
     motion, decade) to make clips *findable* — it does **not** auto-*assemble*.
     Tagging is the mechanical labeling; selection + placement stay the user's.
   - Neither feature may ship a "make me a fan-edit" button. The generator's
     output is always an **opening position in the #1 editor**, not a deliverable.
4. **Clarity over cleverness?** **Yes, if scoped.** v1 = the tight CapCut-style
   magnetic timeline + the proxy library + reframe/caption/credit + export. The
   clever craft (beat-sync, blend modes, multi-pass LUTs, the supercut assembler)
   is **additive on the same composition spine** (engine doc), not crammed into
   v1. The stock miner and supercut are v2+ once the editor + library are solid.

**The distinctive wedge stays the provenance credit** (Decision 033 / CREATE-
STUDIO-PLAN §1): every export burns an `archivewatch.org · public domain` credit
and embeds the `archive.org/details/{id}` source in `AVMetadataItem`s — an
attribution requirement turned into a culturally-native, *teaching* feature.

### 5.2 Recommended structure for `docs/macOS-DESIGN.md` (binding)

Author it via `binding-design-doc-discipline` once the Mac app passes ~5 views.
Proposed sections:

1. **Scope + parity stance** — the Library face mirrors the shared verbs;
   Creation Studio is Mac-exclusive. (Quote Decision 028.)
2. **Scene + window architecture** — the rule that there are exactly these scene
   kinds (Library `WindowGroup`, Editor `DocumentGroup`, Render `Window`,
   Settings); any new top-level window needs a new rule here. The Library/Document
   persistence split (§1.2) is binding.
3. **Document model rules** — `.archiveproj` is a `.package` `UTType`;
   `ReferenceFileDocument`→`NSDocument` backbone; what goes in the bundle vs
   Caches vs iCloud; the "references sync, media doesn't" invariant.
4. **SwiftUI-shell + AppKit-bridge contract** — the teardown's §3.12 table is
   binding: SwiftUI for sidebar/inspector/toolbar/commands/context-menus/drop-
   contract/browser-grid-until-N; AppKit for the timeline, transport keys, live
   drop indicator, and the document backbone. New custom AppKit is justified only
   against this table (`native-platform-first`).
5. **Timeline interaction model** — the CapCut-style magnetic main track +
   overlays; the one coherent shortcut scheme (teardown §1.13, not a blend of
   FCP/Premiere); hover-does-the-work density (the Mac analogue of tvOS "focus
   does the work").
6. **Creation Studio feature set + roadmap** — the §3.1 table; v1 vs v2 split;
   the learning-orientation gate (§5.1) quoted as binding for #6 and #9.
7. **Universal feature states** (`universal-feature-states`) — loading/empty/
   error/offline for the browser grid, the timeline, the export queue, the
   stock/supercut search.
8. **Density + type** (`mobile-first-density-design` adapted to desktop) — the
   six-level hierarchy; compact Mac controls (~22–28pt); density from removing
   chrome.

### 5.3 New project skills to author

- **`macos-creation-studio-engine`** — the AVFoundation Configuration-based
  compose/overlay/audio/export spine + the **two-pass CIFilter+CALayer rule** +
  the `ffmpeg`-subprocess transmux/concat pattern + the remote-source
  range-cache-then-export strategy (consolidates the engine + proxy research so
  it isn't re-derived; cross-refs Decisions 021/031/033).
- **`macos-native-app-shell`** — the multi-scene structure (WindowGroup +
  DocumentGroup + Window + Settings), the `.package` document model + the
  `ReferenceFileDocument`→`NSDocument` decision tree, the SwiftUI-shell/AppKit-
  bridge split table, Quick Look extensions, and the macOS lifecycle/sandbox/
  security-scoped-bookmark gotchas. (The Mac analogue of `tvos-platform-patterns`
  / `web-platform-patterns`.)
- Reuse as-is: `learning-orientation-design`, `native-platform-first`,
  `binding-design-doc-discipline`, `feature-shipping-discipline`,
  `cross-platform-parity-discipline`, `architectural-decision-log`,
  `resilient-media-streaming`, `shared-data-plane-contract`,
  `per-ecosystem-sync-islands`, and the relevant `all-ios-skills:*` (SwiftUI,
  SwiftData, swiftui-uikit-interop, swift-concurrency, app-intents, vision-framework
  for #6 tagging).

### 5.4 Decisions to log (when the Mac app bootstraps)

- A new DECISIONS entry: *"macOS is the creation tier: a document-based NLE +
  parity Library face; Creation Studio is Mac-exclusive structurally (filesystem,
  subprocess, heavy/background compute, pointer/multi-window editor)."*
- A DECISIONS entry pinning the **scene + document architecture** (§1) and the
  **Library-is-not-a-document** split (§1.2).
- A DECISIONS entry binding the **no-auto-edit gate** for #6/#9 (extends 033 to
  the macOS supercut/stock features).

---

## 6. Risks + de-risking (carry forward)

- **Document backbone late-failure** (§1.3) — spike the `.archiveproj` save/URL/
  bookmark path on `ReferenceFileDocument` AND `NSDocument` before building the
  editor on either.
- **AppKit timeline performance** (teardown §3.1) — spike the `NSView`+`CALayer`
  scroll/zoom/hit-test timeline early; SwiftUI-view-per-clip stutters at low clip
  counts.
- **Remote `AVAssetExportSession` is unreliable** (proxy doc §3) — never export a
  composite of remote `AVURLAsset`s directly; range-cache the windows locally,
  then compose/`ffmpeg` from cache.
- **macOS SDK API churn** — confirm `@available` minor versions and the
  AVFoundation async-export + Configuration-API signatures against the live macOS
  26 SDK with `swift-api-digester` (the Decision 033 §5c probe); Apple doc/HIG
  pages are JS-rendered and unreliable to scrape.
- **Parity drift** — add a **macOS column to `PARITY.md`**; update it in the same
  change set (`cross-platform-parity-discipline`).

---

## Sources

- [nilcoalescing — Scenes types in a SwiftUI Mac app](https://nilcoalescing.com/blog/ScenesTypesInASwiftUIMacApp/)
- [createwithswift — Understanding scenes for your macOS app](https://www.createwithswift.com/understanding-scenes-for-your-macos-app/)
- [WWDC22 — Bring multiple windows to your SwiftUI app](https://developer.apple.com/videos/play/wwdc2022/10061/)
- [Apple — Building a document-based app with SwiftUI](https://developer.apple.com/documentation/swiftui/building-a-document-based-app-with-swiftui)
- [createwithswift — Crafting document-based apps in SwiftUI](https://www.createwithswift.com/crafting-document-based-apps-in-swiftui/)
- [HWS — Create a document-based app using FileDocument and DocumentGroup](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-document-based-app-using-filedocument-and-documentgroup)
- [eclecticlight — SwiftUI on macOS: Documents](https://eclecticlight.co/2024/05/16/swiftui-on-macos-documents/)
- [WWDC25 — What's new in SwiftUI (scene bridging, macOS 26 Liquid Glass, iPad menu bar)](https://developer.apple.com/videos/play/wwdc2025/256/)
- [Apple — What's New in SwiftUI](https://developer.apple.com/swiftui/whats-new/)
- [Apple — QLPreviewProvider](https://developer.apple.com/documentation/quicklook/qlpreviewprovider)
- [Apple — Creating Quick Look Thumbnails to Preview Files in Your App](https://developer.apple.com/documentation/quicklookthumbnailing/creating-quick-look-thumbnails-to-preview-files-in-your-app)
- [eclecticlight — How does QuickLook create Thumbnails and Previews?](https://eclecticlight.co/2024/11/04/how-does-quicklook-create-thumbnails-and-previews-with-an-update-to-mints/)
- [Apple — HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)

*Cross-references: `docs/research/creation-studio-avfoundation-engine.md`,
`creation-studio-proxy-remote-editing.md`, `creation-studio-nle-ux-teardown.md`;
`docs/CREATE-STUDIO-PLAN.md`; `docs/MULTIPLATFORM-PLAN.md`; `docs/CATALOG-CONTRACT.md`;
Decisions 017/019 (catalog delivery), 021/031/034 (streaming), 028 (multi-platform
+ sync islands), 033 (Clip Studio / no-auto-edit), 039 (subtitles).*
