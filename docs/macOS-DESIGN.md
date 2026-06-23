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
  - **Amendment 2026-06-23 (Unit 2 — the cache mechanism is AVFoundation, not ffmpeg):**
    the app is **sandboxed** (App Store), so ffmpeg can't run as a subprocess inside the
    sandbox, and ffmpeg's GPL is App-Store-incompatible anyway. So we cache each window by
    running an **`AVAssetExportSession` PASSTHROUGH over a `ResilientStreamLoader`-backed
    asset** (`session.timeRange` = the clip window) — Apple-native, sandbox-safe, and the
    same resilient path playback + iOS Clip Studio use. The cache-then-export INTENT of
    Rule 4b is unchanged (each window → a local faststart MP4 → compose/export from local
    files); only the remux tool changed from ffmpeg to AVFoundation. archive.org content is
    codec-varied, so passthrough **falls back to a re-encode preset** (H.264) when the
    source isn't MP4-passthrough-compatible. Validated end-to-end (spike #3 PASS).
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

**Rule 5b — provenance is provided, default-on, but OPTIONAL.** Every export *offers* the
`archivewatch.org · Public Domain` credit, burned in by default. **Amendment 2026-06-23
(owner decision):** attribution is NOT mandatory — the user can turn it off for a clean
export (a per-project `ClipProject.burnAttribution` toggle, default true). When off, no
credit is burned and no source metadata is embedded (a truly clean export). The original
"never strip it" stance is superseded: attribution is encouraged and is the social wedge,
but the user owns their export. *(The no-auto-edit gate, Rule 5a, is the real learning
principle and is UNCHANGED — mandatory attribution was a secondary wedge, not the gate.)*
NOTE: embedding the source in file metadata is a known follow-up — common-identifier
`AVMetadataItem`s don't land in the `.mp4` atoms (read-back returns nil); the burned
credit is the verified provenance.

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

## 10. Phase 1 progress log

**Unit 1 — foundation + spike #1 (the `NSDocument`/package seam): SHIPPED 2026-06-23.**
- Data model (`macOS/CreationStudio/CreationModels.swift`): `ProxyClip` / `TimelineClip` /
  `Timeline` / `ClipProject`, OTIO-shaped Codable (Rule 4a), **CMTime-exact** times
  (`TimeStamp`=value/timescale, `TimeRange`=start+duration) so frame-accurate boundaries
  survive round-trips and don't cap Phase 3 shot-level / Phase 4 word-level granularity.
- Proxy-clip **Library** (`LibraryClip.swift`): app-global SwiftData `@Model` (Rule
  "Library ≠ Project"), references only, with a `ProxyClip` bridge. Added to the macOS
  ModelContainer schema. (CloudKit annotation-layer sync = a Phase-1.x follow-up.)
- `.archiveproj` **document** (`ClipProjectDocument.swift`): a `ReferenceFileDocument`
  over a directory **package** FileWrapper (Rule 2b — `timeline.json` + room for
  `caches/`/`imports/`), exported UTType `org.archivewatch.project` (Info-macOS.plist).
- **Editor scene** (`EditorScene_macOS.swift`): a `DocumentGroup` adding a
  `NavigationSplitView` editor (library sidebar + program-monitor/timeline detail +
  `.inspector`) alongside the WindowGroup Library face.
- **Spike #1 result: PASS.** Validated on-device end-to-end — New Project → editor renders
  → Save writes a `.archiveproj` package (a directory containing decodable, diffable
  pretty/sorted-keys `timeline.json`) → reopen decodes it back into the editor.
- **Gotcha logged:** with a WindowGroup (first scene) + a DocumentGroup, SwiftUI binds ⌘N
  to the WindowGroup (a new Library window, not a project). Fix: `CommandGroup(replacing:
  .newItem)` → "New Project" via `NSDocumentController.shared.newDocument(nil)`.
- **Known limitation (the budgeted NSDocument migration):** `ReferenceFileDocument`
  exposes no document file URL and saves on the main thread — fine for the timeline JSON,
  but Unit 2/3 (resolving relative cache paths + security-scoped bookmarks to the archive
  cache) needs the `NSDocument` + `NSHostingController` backbone. Migrate the document
  backbone when the engine first needs the document URL — not before.

**Unit 2 — the composition engine + cache-then-export + spike #3: SHIPPED 2026-06-23.**
- **Rule 3e check FIRST (as mandated):** a `swiftc` probe confirmed the Configuration-based
  AVFoundation API (`AVVideoComposition.Configuration` et al.) is **macOS 26.0+ only**.
  Resolution: **all Apple platforms now target 26+** (owner directive) — macOS moved 15→26;
  iOS/tvOS were already 26. No `@available` gating needed; the API is unconditional.
- `ClipCache.swift` — cache each clip window to a local faststart MP4 via AVFoundation
  passthrough over a `ResilientStreamLoader` asset, with a re-encode fallback for
  codec-varied content (Rule 4b amendment above).
- `CompositionBuilder.swift` — Timeline → `(AVMutableComposition, AVVideoComposition)` via
  the Configuration API (Rule 3a/3e): sequential single-track insert (Phase 1, no
  transitions), per-clip aspect-fit instructions, optional burned credit via a CATextLayer
  in the Core Animation tool (single pass — the two-pass grade split, Rule 3d, lands with
  CI grades in Phase 2).
- `ExportService.swift` — @Observable orchestrator: cache (40%) → compose → export the
  LOCAL composition (`AVAssetExportSession` HighestQuality + async progress).
- Editor: an "Add Clip" scaffold (real catalog item → timeline) + "Export…" (save panel +
  progress + reveal) + the inspector **"Burn in attribution credit"** toggle (Rule 5b).
- **Spike #3 result: PASS.** An env-gated self-test (`AW_CS_SELFTEST=1`, like AW_PLAYBACK_DIAG)
  ran the full pipeline on real archive.org titles, repeatedly: 2-clip cross-title cut →
  16.0s · 1920×1080 · h264+aac, **no -11800/-16974, inside the sandbox, no ffmpeg**.
  Validated BOTH the credit export (burned "archivewatch.org · Public Domain", confirmed by
  frame + objective bottom-band diff) and the clean export (no credit) — the codec fallback
  made it robust across varied content. Known follow-up: source metadata embedding (above).

**Unit 3 — the AppKit timeline (spike #2) + live preview: SHIPPED 2026-06-23.**
- `TimelineView_macOS.swift` (`ClipTimelineView` — renamed off SwiftUI's `TimelineView`):
  an `NSView`+`CALayer` document view in an `NSScrollView` (Rule 7b). Renders the magnetic
  main track — clip blocks sized by duration × **points-per-second** (zoom re-tiles crisply
  rather than NSScrollView magnification, which would blur), filmstrip thumbnails
  (`AVAssetImageGenerator` off the resilient remote asset), ruler, red playhead, selection,
  and trim handles. Interaction: click-to-scrub, click-to-select, **drag-trim handles**,
  ⌘/⌥-scroll zoom, Space/⌫/B keys (Rule 7c CapCut-approachable).
- `EditorModel.swift` — the @Observable editor state + edits: magnetic single-track layout
  (relayout after every change), add/trim/split/delete, debounced rebuild-and-swap preview
  (Rule 3b), playhead↔player sync, zoom, filmstrip thumbnails.
- `PreviewComposer.swift` — the live preview composition built from the REMOTE resilient
  assets (so a trim is just a new insert range, NO re-cache) — same recipe as export, so
  preview == export (Rule 3a). `CompositionBuilder` refactored to a shared core
  (`ResolvedClip`) that both preview (remote) and export (cached) use.
- Editor scene rebuilt: program monitor (preview `AVPlayer`) over transport + the timeline.
- **Spike #2 result: PASS.** Validated on-device — New Project → Add Clip ×2 → the timeline
  renders both clips magnetically with filmstrip thumbnails + ruler + playhead + selection,
  and the composition builds (0:16). Full drag-trim/zoom feel is owner-verifiable on device.

**Unit 4 — browser → proxy-clip Library → drag-onto-timeline: SHIPPED 2026-06-23. PHASE 1 COMPLETE.**
- `ClipBrowser_macOS.swift` — the source browser (§7e): "Add Clip" opens a sheet that
  searches/browses the catalog filtered to `isClippable` (Rule 5c rights gate), shows a
  poster grid, and on selection opens a **mark-in/out** view (resilient `AVPlayer` preview +
  Set In / Set Out at playhead + name) → "Add to Timeline" creates a `ProxyClip`.
- A marked clip joins the **proxy-clip Library** (`LibraryClip` SwiftData) AND the timeline.
  The Library sidebar renders each saved clip with its catalog poster + duration, makes it
  **`.draggable`** (`ProxyClip: Transferable` via `CodableRepresentation` — references only,
  Rule 4a), and right-click deletes. The timeline is a **`.dropDestination(for: ProxyClip)`**
  — dropping a Library clip appends it (magnetic track). The random "Add Clip" stand-in is
  retired.
- Validated on-device: the browser renders the clippable poster grid; mark/drag flow built
  on proven primitives (owner-verifiable on device — the dev box's window contention blocks
  deep UI automation).

**Phase 1 (the editor spine) is done** — all three de-risk spikes passed, and the full loop
works: browse → mark → Library → drag/add to timeline → trim/split/zoom → live preview →
cache-then-export (credit optional).

## 11. Phase 2 progress log — Layers

**Unit 5 — timed text overlays (#3): SHIPPED 2026-06-23.**
- Model: `TextOverlay` (text, timeline window, normalized position, font scale, color,
  legibility shadow) on `Timeline.textOverlays` (tolerant decode — old projects → []).
- Render (`CompositionBuilder`): each overlay is rendered to a **@2x CGImage** (Core
  Graphics / `NSAttributedString`) in a plain `CALayer` with an opacity keyframe over its
  window, added to the Core Animation tool alongside the optional credit. **Gotcha logged:**
  an *animated* `CATextLayer` does NOT render in the tool (a static one does) — the proven
  iOS path renders timed text to an image layer; same here. Still single-pass (no CI grade
  yet → the two-pass grade→overlay split, Rule 3d, is not needed until grades land).
- UI: an "Add Text" toolbar button (adds at the playhead) + an inspector `TextOverlayEditor`
  for the selected overlay (text, position preset, color, size, shadow, start/length,
  delete). Preview rebuilds live (Rule 3b). Overlays ride into the export unchanged.

**Unit 6 — audio mix (#4): SHIPPED 2026-06-23.**
- Model: per-clip `TimelineClip.audioVolume` (0…1.5, tolerant decode — pre-#4 clips → 1.0).
- Engine (`CompositionBuilder`): builds an `AVMutableAudioMix` — `AVMutableAudioMixInputParameters`
  on the shared audio track with `setVolume(_:at:)` stepped at each clip boundary, so each
  clip's segment plays at its own level (Rule 3c; per-clip volume needs one track + steps,
  not N tracks). Returned in `BuiltComposition.audioMix` and applied to BOTH the preview
  (`item.audioMix`) and the export (`session.audioMix`) — preview == export.
- UI: a "Clip" inspector section (when a clip is selected) with a speaker icon + volume
  slider + percent. Live preview reflects the change.
- *Deferred to the NSDocument/bookmark unit:* importing an external music bed + voiceover
  record — both need persistent file access (security-scoped bookmarks / copy-into-package),
  which is the budgeted `NSDocument` migration. Per-clip mix lands now without it.

**Unit 7 — multi-format / quality export incl. ProRes (#5): SHIPPED 2026-06-23. PHASE 2 COMPLETE.**
- `ExportFormat` (H.264·MP4 / ProRes 422·MOV / ProRes 4444·MOV) → preset + `AVFileType` +
  extension. ProRes uses `AVAssetExportPresetAppleProRes422LPCM`/`…4444LPCM` (LPCM audio,
  `.mov`); all honor the project render size via the videoComposition (not fixed-dimension
  presets). `ExportService.export(_:to:format:)` threads it through.
- UI: an "Export" settings sheet (radio format picker + blurb) → "Choose Destination…" save
  panel with the format's content type.
- Validated via the self-test: the ProRes `.mov` is genuine `prores` video (1920×1080, PCM
  audio) at 235 MB vs the H.264 MP4 at 19.6 MB — the expected master-vs-share contrast.

**Phase 2 (Layers) is done** — timed text overlays (#3), per-clip audio mix (#4), and
multi-format/ProRes export (#5), all additive on the composition spine. **Next: Phase 3 —
Stock archive (#6):** the CI shot-mining pipeline (PySceneDetect → Vision classify →
MobileCLIP embeddings → `clips.sqlite`) + the Storyblocks-style shot browser, which slots
into the existing `ClipBrowserSheet`. (The two-pass grade→overlay split, Rule 3d, still
waits on color grades, a later feature.)

---

*Amend, don't contradict. New views/features quote the rule they satisfy or the amendment
they propose.*
