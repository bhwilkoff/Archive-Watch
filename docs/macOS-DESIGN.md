# macOS Creation Studio — Binding Design Doc

**Status: binding.** Quote the relevant rule before proposing any new window, scene,
view, sheet, engine path, index, or Creation-Studio feature. Append-only amendments;
never silently contradict a rule — amend it with a dated note and a reason.

Research backing every claim here: `docs/research/creation-studio-README.md` (+ its seven
briefs). This doc is the *decisions*; the briefs are the *evidence*.

---

## 1. Scope & thesis

Archive Watch on macOS is **two things in one native app**:
1. **Parity face** — browse / play / library / search / channels, mirroring the other
   platforms, built on the shared Swift Core (no new data plane).
2. **Creation Studio** — a Mac-EXCLUSIVE multi-clip timeline video editor that composes
   clips across different archive.org titles into one exported film.

**The Mac-only thesis (binding):** Creation Studio belongs only on macOS because its
features structurally require four things the touch/TV/web platforms cannot host — a full
filesystem + document model, subprocess CLI tools, heavy/long-running/background compute,
and a pointer+keyboard+menu+multi-window editor. **The Mac app is NOT the iOS app resized.**
Phones create ONE clip (iOS Clip Studio, Decision 033); the Mac assembles a film. Do not
port touch idioms (full-screen modal editors, drag-handle-only trim, one-pane navigation) —
build Mac-native (windows, inspectors, menu commands, keyboard-first editing).

---

## 2. App & scene architecture

One macOS target, multiple SwiftUI scenes:
- `WindowGroup "Library"` — the parity browse/play/library face.
- `DocumentGroup` bound to the `.archiveproj` document — the Creation Studio editor.
- `Window "Render Queue"` — single-instance, long-running exports.
- `Settings` — accounts (CloudKit, archive.org keys, YouTube), storage, quality defaults.

**Rule 2a — Library ≠ Project.** The proxy-clip **library** is app-global persistent state
(SwiftData + iCloud), NOT a document. A **project** is the document (`.archiveproj`). This
mirrors FCP's event-browser → project-timeline model. Never store the library inside a
project; never make a project carry copied media.

**Rule 2b — `.archiveproj` is a reference package.** A `UTType(exportedAs:)` `.package`
containing the timeline model + proxy-clip references + project-local overlays/audio
imports — **never** archive.org video bytes. Prototype on `ReferenceFileDocument`; budget
an `NSDocument` backbone for URL access, atomic/async save, and security-scoped bookmarks
(de-risk spike before Phase 1 ships).

**Rule 2c — reuse the Core, rebuild only the shell.** Reuse verbatim: `CatalogDB`,
`CatalogRefreshService`, `ResilientStreamLoader`, models, networking, `CloudKitSyncService`
(same CloudKit container → favorites/playlists/progress sync with the other Apple
platforms). Rebuild only the Mac-native UI. New code goes in the Core only if all
platforms could use it.

---

## 3. The editing engine (binding rules)

From `creation-studio-avfoundation-engine.md`:

- **Rule 3a — one model, one composition, preview == export.** A `Timeline` model compiles
  to a single `(AVMutableComposition, AVVideoComposition.Configuration, AVMutableAudioMix)`
  triple that feeds BOTH `AVPlayerItem` (preview) and the exporter. The user must render
  exactly what they scrubbed.
- **Rule 3b — rebuild-and-swap, never mutate live.** Each edit recompiles the triple and
  `replaceCurrentItem`s. Do not mutate a composition that's attached to a playing player.
- **Rule 3c — video on a 2-track A/B scheme** (overlap only at transitions); **audio on N
  tracks** with `AVMutableAudioMixInputParameters` volume ramps.
- **Rule 3d — the two-pass split is law.** Per-frame Core Image grade and CALayer overlay
  tool cannot share one `AVVideoComposition`. Grade → ProRes intermediate → overlay pass.
  An intermediate-render manager owns temp files + ordering + cleanup.
- **Rule 3e — Configuration-based AVFoundation API only** (matches the iOS engine post-
  migration; CREATE-STUDIO-PLAN §5c). Confirm exact `@available`/signatures against the
  live macOS 26 SDK with `swift-api-digester` before relying on any symbol.
- **Rule 3f — Apple frameworks in-app; ffmpeg/CLI as subprocess** for range re-mux, ProRes
  intermediates, and anything AVFoundation can't do cleanly. This is the Mac advantage,
  not a workaround.

---

## 4. Proxy clips & remote sources (binding rules)

From `creation-studio-proxy-remote-editing.md`:

- **Rule 4a — references, never copies.** `ProxyClip` = `catalogItemID` + `sourceURL` +
  `availableRange` + `sourceRange` + `label`/`tags`/`posterFrameTime`. OTIO-shaped Codable;
  emit `.otio` for interchange but do NOT vendor the OTIO library (no-third-party-package).
- **Rule 4b — cache-then-export, NEVER stream-into-export.** `AVAssetExportSession` is
  unreliable on remote URLs. Pre-fetch only each clip's moov-snapped in/out byte range via
  `ResilientStreamLoader` → local faststart MP4 (`ffmpeg -c copy`) → compose/export from
  local files. (Single biggest reliability risk; this is its resolution.)
- **Rule 4c — probe the moov before any byte math.** archive.org `.ia.mp4` is not
  guaranteed faststart; locate moov first.
- **Rule 4d — cache is disposable, references are truth.** Cache only ranges in use, LRU
  eviction, pin ranges for open projects; caches live in `Library/Caches`, never synced.

---

## 5. Feature set & the learning gate

The 10 backlog features, each tied to a brief, phased in `creation-studio-README.md`.

**Rule 5a — the no-auto-edit gate (from Decision 033).** Features #9 (text→supercut) and #6
(auto-tagged stock) MUST produce an **editable timeline of candidates**, never a one-tap
finished export. Automate the mechanical (search, forced-align, assemble, tag, attribute,
transcode); preserve the meaningful (which takes, order, cuts, narrative). Unmatched
supercut words become explicit editable gaps, never silent drops.

**Rule 5b — provenance is mandatory.** Every export burns the `archivewatch.org · Public
Domain` provenance credit and embeds each source `archive.org/details/{id}` in metadata
(carried from Decision 033). Never strip it.

**Rule 5c — clipping is rights-gated.** Only `isClippable` items (playable + PD/CC/absent
rightsStatus) enter the library or a timeline. Defense in depth over the catalog's
exclusion flags.

---

## 6. Data planes (no backend — binding)

Three planes, never a server (Decision 028):
1. **Shared, read-only** (SQLite on a GitHub Release / Pages, query-on-disk natively +
   WASM-Range on web, Decision 029): the catalog; `clips.sqlite` (stock: shots + Vision
   tags + MobileCLIP embeddings via `sqlite-vec`); `subtitle.sqlite` (FTS5 cues + a word-
   timing table). Built by CI pipelines (cover/whisper pattern), additive, popularity-first.
2. **User annotation layer** (SwiftData + iCloud): the proxy-clip library + projects —
   references only, last-writer-wins, same ethos as `CloudKitSyncService`.
3. **Device-local, never synced, re-derivable**: media/range caches, thumbnails, render
   scratch.

**Rule 6a — `sqlite-vec` + MobileCLIP are permitted** as "Apple frameworks + a SQLite
extension + a Core ML model," NOT third-party Swift packages (see DECISIONS). Heavy
tooling (ffmpeg, PySceneDetect, MFA) is subprocess/CI only.

**Rule 6b — word timing is caption-validated.** SpeechTranscriber/SpeechAnalyzer (macOS 26,
on-device per-word timing) validated against the held caption text (token diff: keep
agreeing words, drop invented) — the Decision-039b fix applied to *when*, not *what*. MFA
for the rough-audio tail. Never ship raw recognizer output as ground truth.

---

## 7. UI contract (SwiftUI shell, AppKit where it must)

From `creation-studio-nle-ux-teardown.md`:

- **Rule 7a — SwiftUI shell:** `NavigationSplitView` sidebar, `.inspector()`, unified
  `.toolbar(id:)`, `.contextMenu(forSelectionType:)`, menu-bar `.commands`, `Transferable`
  drag-drop.
- **Rule 7b — AppKit bridges (only where SwiftUI stutters):** the timeline is an
  `NSView`+`CALayer` in `NSScrollView` (magnification + hit-testing); the browser grid
  starts `LazyVGrid`, migrates to `NSCollectionView` (reuse/prefetch/reliable hover);
  modeless transport keys via an `NSEvent` local monitor.
- **Rule 7c — v1 timeline = CapCut-approachable.** Magnetic main track + 1–2 overlay/audio
  tracks; drag-trim (auto-ripples) as the only trim model; split (`⌘B`), ripple-delete,
  snapping, markers (`M`), hover-skim, ⌘-scroll/pinch zoom, always-on thumbnails+waveforms,
  per-overlay opacity/scale/position, fade handles. **Defer** ripple/roll/slip/slide tools,
  three-point editing, J/L cuts, full keyframe lanes until a later phase.
- **Rule 7d — keyboard-first, one coherent scheme** wired to the menu bar for
  discoverability (the reference editors collide on `B`/`N`; pick one and document it).
- **Rule 7e — browser = Storyblocks UX minus licensing:** curated Collections cards +
  Category/era facets, hover = muted autoplay preview + inline Add/Favorite/More-Like-This,
  Filters with active-count badge (orientation/duration/resolution/category/era),
  folders/boards as the "add to project" primitive. No watermark, no paywall.

---

## 8. Universal feature states & density

- **Rule 8a** — every list/grid/shelf/browser honors the `universal-feature-states`
  contract (loading / empty / error / populated), especially "X films searched so far" for
  the still-building subtitle/stock indices — treat `*Checked == false` as *unknown*, not
  *empty*.
- **Rule 8b** — density comes from removing chrome; on the Mac the focused/selected element
  and the inspector do the work. Six type levels max (project type hierarchy).

---

## 9. De-risk spikes (before Phase 1 commits)

1. SwiftUI/`NSDocument` save + URL + security-scoped-bookmark seam (weakest seam).
2. AppKit timeline scroll/zoom/hit-test prototype.
3. Cache-then-export round trip on one real archive.org title (Rule 4b end-to-end).

---

*Amend, don't contradict. New views/features quote the rule they satisfy or the amendment
they propose.*
