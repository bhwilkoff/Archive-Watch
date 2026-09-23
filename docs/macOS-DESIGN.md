# macOS — Binding Design Doc (Archive Watch for Mac)

**Status: binding.** Quote the relevant rule before proposing any new window, scene,
view, sheet, engine path, index, or feature. Append-only amendments; never silently
contradict a rule — amend it with a dated note and a reason.

This doc covers the **whole macOS app**, in three parts:
- **Part A — Creation Studio** (§1–§13): the Mac-exclusive multi-clip editor + engine.
- **Part B — The parity face** (§B1–§B12): browse / play / library / search / channels —
  the native shell, the player, the hero, image loading, and the macOS-specific gotchas.
- **Part C — Shipping the Mac app** (§C1–§C7): the command-line App Store pathway + its traps.
- **Part D — Watch Together Studio** (§D0–§D6): the OBS-informed broadcast studio —
  what we take from OBS and what we deliberately do not.

Research/evidence: Part A → `docs/research/creation-studio-README.md` (+ its seven briefs).
Part B/C codify what was learned shipping the app — see the skills `macos-native-app-shell`,
`macos-creation-studio-engine`, `apple-app-store-cli-submission`, and the memory notes
`mac_app_store_build_pathway` / `macos_player_native` / `macos_hero_fullwidth`. This doc is
the *decisions*; the briefs/skills are the *evidence*.

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
NOTE: source-in-metadata embedding is FIXED (2026-06-23) — common-identifier `AVMetadataItem`s
don't write to `.mp4`, so we also emit the iTunes `ilst` keys (`.iTunesMetadataSongName` ©nam
/ `.iTunesMetadataUserComment` ©cmt); ffprobe confirms `title` + `comment` (the archive.org
source URLs) in the export. Embedded only when attribution is on (clean export = no trace).

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

## 12. Phase 3 progress log — Stock archive (#6)

**Stock-shot browser shell + clips.sqlite query layer: SHIPPED 2026-06-23 (app-side first; the
ML CI pipeline is a later session, owner decision).**
- `StockIndex.swift` — the real read query layer over `clips.sqlite` (SQLite C API, mirroring
  `CatalogDB`): a `shots` table (id, archiveID, sourceURL, start/endSeconds, tags, title) with
  a LIKE query over tags+title. The SCHEMA matches what the future PySceneDetect→Vision→
  MobileCLIP pipeline will emit, so swapping in the published index is just changing the file.
- `StockIndexBuilder` — synthesizes a SAMPLE clips.sqlite from the catalog (real archive.org
  URLs + tags from each title's genres/subjects; placeholder shot windows) until the CI
  pipeline lands. Validated: 360 shots built; `animation` tag → 39 hits.
- `ClipBrowserSheet` gains a "Titles | Stock Shots" mode; Stock shots are pre-cut, so a tap
  adds one straight to the timeline (no marking step). `StockCard` shows poster + duration + tag.
- DEFERRED to its own session: the heavy CI shot-mining pipeline (PySceneDetect → Vision
  classify → MobileCLIP embeddings → sqlite-vec semantic search) that produces the real index.

## 13. Editor polish progress log

**Per-clip fades (video + audio): SHIPPED 2026-06-24.** Satisfies Rule 7c's "fade handles"
and gives the first transition idiom (fade up from black, fade to black, and dip-to-black
between two clips) WITHOUT the A/B 2-track rework.
- Model: `TimelineClip.fadeInSeconds` / `fadeOutSeconds` (tolerant decode → 0 for old projects).
- Engine (`CompositionBuilder`): video opacity ramps via the Configuration API
  `layerCfg.addOpacityRamp(.init(timeRange:start:end:))` against the black letterbox matte (0→1
  head, 1→0 tail, clamped so they never overlap); audio via per-segment
  `AVMutableAudioMixInputParameters.setVolumeRamp` (0→vol head, vol→0 tail). Ramps live on the
  layer instruction / audio mix, so the LIVE PREVIEW shows them too — no Core Animation tool,
  preview == export holds (Rule 3a).
- UI: the inspector "Clip" section gains Fade in / Fade out sliders (0…half the clip), live.
- Verified end-to-end via the self-test brightness probe: a faded export reads luma 0.000 at
  t=0, 0.095 mid-clip, 0.000 at the tail.
- Also deferred: timeline fade handles/markers, snapping, ripple-delete (Rule 7c later phase).

**Cross-dissolve (A/B 2-track) + color Looks: SHIPPED 2026-06-24.** The two hardest engine
features, built together because they hit the same constraint (Rule 3d): a CI grade handler
gets ONE composited frame, so it can't do per-track crossfade — and layer instructions can't
do color. Resolution:
- **Color Looks** (`Looks_macOS.swift`, parity with iOS Clip Studio): `ClipLook` (none/silent/
  noir/faded/technicolor/B&W) as native CIFilter chains. A graded clip is produced as a
  SEPARATE source file (`LookGrader.gradedURL` — a one-time CI-filter export cached by
  window+look), and the compositor treats it like any other clip, so grades compose with
  transitions and preview == export for free. `TimelineClip.lookRaw`; resolve/export bake it.
- **Cross-dissolve** (`CompositionBuilder` rewrite): clips alternate on two video + two audio
  tracks so adjacent clips OVERLAP by `transitionInSeconds`; the timeline is segmented at every
  clip start/end into instructions, the later-starting clip placed FRONT with an opacity ramp
  0→1 so it dissolves in over the previous (audio cross-fades via per-track volume ramps). All
  ramp-based → standard compositor, so the live preview shows it (preview == export). Fades
  (the prior unit) fold into the same opacity/volume envelopes (lead-in = max(fadeIn, transition)).
- UI: inspector "Clip" section gains a **Look** picker and a **Dissolve** slider (shown past the
  first clip). Verified via the self-test: dissolve shrinks a 16s timeline to 14.0s, the overlap
  midpoint blends (luma 0.094, both visible), fades still black at the head/tail, and the silent
  Look reads sepia (R 0.196 > B 0.075).
- non-dissolve transitions (wipe/push) via a Metal compositor remain deferred.

**Timeline direct-manipulation: SHIPPED 2026-06-24.** The deferred Rule-7c interaction layer,
all on the AppKit `TimelineContentView`:
- **Fade handles** — a yellow ramp line + draggable dot at each clip's top corners; drag sets
  fadeIn/fadeOut visually (the inspector sliders still work). 
- **Cross-dissolve handles** — a purple diamond at each clip junction; drag left = more overlap
  (delta-based to avoid the circular geometry of an overlapping magnetic layout). `relayout()`
  now places clips WITH the transition overlap (mirroring CompositionBuilder), so the timeline
  total + playhead finally match the (shorter) composition when a dissolve is set — a latent
  bug from the cross-dissolve unit, fixed here.
- **Markers** — `M` toggles a marker at the playhead (teal flag on the ruler + full-height
  line); `,` / `.` jump to the prev/next marker or clip boundary; `Timeline.markers` (tolerant
  decode).
- **Snapping** — scrub/trim/move snap to clip edges, markers, the playhead, and 0 within 8px
  (`EditorModel.snap`).
- Context menu gained Clear Fades / Clear Dissolve. Ripple-delete is already the magnetic
  default (delete closes the gap via relayout). Verified by screenshot: fade dots, the purple
  dissolve diamond, the teal marker, and the dissolve-shrunk 0:14 total all render.

**Publish to the Internet Archive (#7, Phase 5): SHIPPED 2026-06-24.** Completes the
create→edit→SHARE loop — a finished edit uploads to a NEW archive.org community item via the
user's own IAS3 ("S3-like") keys. archive.org-first (Decision 042: YouTube from an unverified
OAuth app is forced Private/100-user-capped). 
- `PublishService` — pure request builders (identifier slug with diacritic-fold + charset
  guard; `LOW access:secret` auth; `x-archive-meta-*` headers: movies / opensource_movies /
  CC0 license / title / creator / description-with-source-URLs) + the two-step upload (create
  item, then stream the file with progress). Keys live in the login Keychain (`IAS3Keychain`),
  never UserDefaults/iCloud.
- UI: a "Publish" toolbar button → `PublishSheet` (title/description, source count, progress,
  result URL with Open/Copy); Settings gained a "Publishing" tab for the S3 keys.
- The clips' `archive.org/details/{id}` sources are stamped as provenance + the export is CC0.
- Verified offline (AW_CS_PUBTEST=1): identifier/URLs/auth/headers all correct. The actual
  upload needs the owner's keys + creates a public item, so it's owner-verified (can't run in CI).
- DEFERRED: YouTube upload (blocked on Google OAuth verification, Decision 042).

**Text → Supercut (#9, the flagship) v1: SHIPPED 2026-06-24.** Type a phrase, find every moment
across the public-domain catalog where it's SPOKEN, pick the takes, and assemble them into the
timeline as EDITABLE candidate clips (Rule 5a — the editorial cut stays human; this only
automates the search + gather, never a one-tap finished cut).
- `SubtitleIndex` (mirrors `StockIndex`): a `cues` table (archiveID, sourceURL, start/end, text,
  title) queried by phrase (LIKE for the sample; the CI index adds FTS5). `VTTParser` parses
  WebVTT/SRT. `SubtitleIndexBuilder.buildSampleIfNeeded` fetches the popular captioned titles'
  real VTTs on-device and parses them (same sample-now / CI-pipeline-later shape as StockIndex).
- `SupercutSheet` — a search field → candidate cues (text + film + timecode, each toggle-able) →
  "Add N Clips" assembles each cue's padded window into the timeline. Toolbar "Supercut" button.
- Verified headlessly (AW_CS_SUPERTEST=1): 29,408 cues indexed from 25 real captioned films;
  "kill" → "I killed him." (Spellbound @94:29), "love" → "Except that I love you." (Spellbound).
- **DEFERRED refinements:** (a) the full-corpus `subtitle.sqlite` built in CI over all /subs with
  FTS5 + a word-timing table, downloaded like `catalog.sqlite` (the sample covers popular
  captioned films now); (b) WORD-level isolation — macOS-26 SpeechTranscriber per-word timing
  validated against the caption text (Rule 6b), to cut a single word rather than its whole line.

**Music bed (#4 audio layers): SHIPPED 2026-06-24.** "Add Music…" imports an external audio file
(NSOpenPanel) — copied into the project media cache (no security-scoped bookmark needed) and
mixed under the whole timeline as a separate audio track with its own volume + a short end fade
(`CompositionBuilder.ResolvedMusic`; `Timeline.musicBed`, tolerant decode). Inspector "Music"
section: track name, volume slider, Remove. Resolved into both the live preview and the export.
Verified via the self-test: a composition with a music bed has 3 audio tracks (clips A/B + music)
and 3 mix inputs. Completes the audio-layers story (per-clip volume + fades + dissolve cross-fade
+ music). DEFERRED: voiceover RECORDING (AVAudioRecorder) and durable copy into the `.archiveproj`
package (the NSDocument/bookmark unit) — the cache copy is the v1.

**Non-dissolve transitions (wipe / push): SHIPPED 2026-06-24 — and WITHOUT a Metal compositor.**
The design first assumed wipe/push needed a custom Metal `AVVideoCompositing`, but they're just
ramps on the existing 2-track overlap, same as the dissolve's opacity ramp: **push** = a transform
ramp (incoming slides in from +renderWidth → 0; outgoing slides 0 → −renderWidth); **wipe** = a
crop-rectangle ramp (incoming revealed left→right via a growing crop). `TransitionKind`
(dissolve/wipe/push) on `TimelineClip`; the engine picks the ramp by kind in the segment builder
(`addTransformRamp`/`addCropRectangleRamp`, Configuration API). Inspector gains a "Style" picker
when a transition is set. Verified via the self-test (frame sampled off the composition at the
mid-overlap): push 0.208, wipe 0.170 brightness — both clips visible, so the ramp rendered. So the
Metal compositor is now only needed for true GPU blend effects, not these.

**Voiceover recording: SHIPPED 2026-06-24.** "Record Voiceover" captures mic narration
(AVAudioRecorder → m4a in the project cache, starting at the playhead) and adds it as a second
audio bed alongside the music. The engine's music param generalized from a single `music` to
`beds: [ResolvedMusic]`, so music + voiceover are both audio tracks under the timeline (each with
volume + end fade). Inspector gains a "Voiceover" section (Record/Stop, volume, Remove);
`NSMicrophoneUsageDescription` added. The engine path is the verified music-bed one; the mic
capture itself is device-verified (no mic/permission headlessly). Durable copy into the
`.archiveproj` package (NSDocument/bookmark) remains the deferred persistence upgrade — the cache
copy is v1.

**Stock-archive shot mining (#6) — real shots: SHIPPED 2026-06-24.** The synthesized placeholder
windows are replaced by REAL detected shots: `tools/build_stock_index.py` runs ffmpeg scene
detection (`scdet`) over each clippable film's stream, turns the cut points into shot windows
(1.2–20s, long takes chunked), and emits `clips.sqlite` (the same `shots` schema `StockIndex`
already queries) tagged with the catalog's genres/subjects. `stock-index.yml` (daily cron,
popularity-first, resumable) publishes `clips.sqlite.zz` (raw DEFLATE, catalog convention) to a
`stock-index` release; the app's `StockIndexBuilder.ensureIndex` downloads + inflates it (reusing
`CatalogRefreshService.inflate`), falling back to the on-device sample until the release exists.
Verified locally: 24 real shots from 3 films (cuts at 19.3s / 24.7s / 32.0s…). **DEFERRED
refinement:** Apple-Vision per-shot classification + MobileCLIP/`sqlite-vec` semantic search
(genre/subject tags work now; semantic "find shots of X" is the upgrade).

**Supercut full-corpus index: SHIPPED 2026-06-24.** `tools/build_subtitle_index.py` parses every
captioned film's WebVTT into `subtitle.sqlite` (the `cues` schema `SubtitleIndex` queries);
`subtitle-index.yml` (daily) publishes `subtitle.sqlite.zz` to a `subtitle-index` release; the app
downloads + inflates it (`SubtitleIndexBuilder.ensureIndex`, StockIndex pattern), falling back to
the on-device popular-films sample until published. Verified locally: 2,114 cues from 15 films.
So the supercut searches the WHOLE captioned catalog, not just the sample.

**Supercut WORD-timing (Rule 6b): SHIPPED 2026-06-24.** A "Tighten each clip to the spoken word"
toggle narrows each supercut candidate from its whole caption LINE to just the spoken phrase.
`WordTiming` runs macOS-26 `SpeechTranscriber`/`SpeechAnalyzer` on the cached line-window (extract
audio → m4a → per-word `audioTimeRange`), VALIDATED against the caption text (token diff: keep
recognizer words the caption contains, drop hallucinations — the Decision-039b fix applied to
*when*). `AssetInventory.assetInstallationRequest` installs the model on first use; if it's
unavailable the toggle gracefully no-ops (clips stay line-level). Verified via the self-test:
`recognized 16 words: witness@0.1 What@3.0 was@3.3 he@3.5 doing?@3.6 …` — real per-word timings.

**Stock semantic tags — NO Apple Vision required: SHIPPED 2026-06-24.** The design assumed "find
shots of a sunset" needed an Apple-Vision macOS CLI + a macOS runner. It doesn't: open-source
**CLIP zero-shot** (`tools/tag_stock_shots.py`, `open_clip` ViT-B-32) runs on a plain Linux GitHub
runner, reusing the frames the stock pipeline already detects — it grabs each shot's mid-frame
(ffmpeg) and classifies it against a curated ~200-term stock-footage vocabulary (scenes / weather /
people / actions / objects), appending the confident tags to the `tags` column `StockIndex` already
searches with LIKE. So the APP needs no change, no in-app model, no `sqlite-vec`. `stock-tags.yml`
(daily, same concurrency group as `stock-index.yml` so they never clobber `clips.sqlite`) drains
the corpus. Verified locally: a 1953 educational film's shots tagged `black-and-white-footage`
(correctly) merged with the genre tags. Open-vocabulary semantic search (store CLIP image
embeddings + a same-model text query) remains a possible future upgrade, but the curated-vocabulary
tags deliver the feature now, cross-platform.

**Supercut v2 — the Sentence Composer: SHIPPED 2026-06-24.** The inverse of v1 (find a phrase) and
the genuinely hard half: type a LINE and the catalog SPEAKS it word-by-word, using only clips that
contain those words. Research: `docs/research/creation-studio-sentence-supercut.md`. The quality
lever is **longest-match coverage** (`SentenceComposer`) — cover the line with the FEWEST clips by
preferring the longest contiguous run of words spoken in a single cue, so the result is smooth not
jumpy. The supercut sheet gains a "Find clips | Compose a sentence" mode switch; the compose plan
shows each matched run + its source film (or a flagged GAP for a missing word), and assembles in
order into the editable timeline. Word ranges are PROPORTIONAL by default (instant) and tighten to
exact boundaries with the on-device `WordTiming` toggle. Verified on the real cue index: **"I love
you" → 1 clip** (the whole phrase in one film, Spellbound); "this is the end of the world" → 2
clips ("this is the" + "end of the world"); "kill the lights" → 2 clips — minimal cuts, exactly as
designed.

**Supercut Phase B — forced-aligned WORD index: SHIPPED 2026-06-24.** Composition is now
frame-accurate AND instant (no per-clip on-device speech pass). `tools/build_word_index.py`
force-aligns each captioned film's KNOWN caption to its audio with the torchaudio MMS aligner
(wav2vec2) — on a plain Linux runner, NO Apple — writing a `words(archiveID, word, start, end)`
table into `subtitle.sqlite`. Forced ALIGNMENT ≠ transcription: it places words we already hold in
time, so it can't hallucinate (Decision-039b stays satisfied — that retired *transcription*).
`word-index.yml` (daily, same concurrency group as subtitle-index, resumable, retry-hardened
against archive.org node 503s) publishes the updated index. The app's `SubtitleIndex.wordRange`
reads the table and `SentenceComposer` prefers it over the proportional estimate — so the sentence
cuts are exact with zero compose-time speech. Verified locally: 6 films aligned → 9,662 precise
word timings (`your 0.75-1.00s`, `life 1.00-1.12s`, …). The on-device `WordTiming` toggle remains
as the fallback when a film hasn't been aligned yet.

**Supercut Phase C — per-word alternate takes + shuffle: SHIPPED 2026-06-24.** Each run in the
compose plan now carries the ranked ALTERNATE source films that say those words (shortest cue first
= the word most isolated); ‹ › swap which film speaks each run, and "Shuffle takes" randomizes them
all for a different cross-film vibe — the editorial control + variety that makes a word collage
feel crafted, not auto-generated (the learning gate). Verified: "I love you" → Spellbound ×6
alternates; "this is the end of the world" → ×6 and ×4 alternates per run. Each composed word-cut
also gets a tiny 0.03 s fade so the assembled sentence doesn't CLICK at the joins (each word starts/
ends mid-waveform) — the hard visual jump between films stays, only the audio onset is smoothed.
Gap RECOVERY: a word the corpus can't speak shows an inline "try another word…" field — type a
replacement (synonym / re-spelling) and it re-resolves on the spot, so more lines become composable
rather than stuck. The supercut is now a full system: find-phrase (v1) + compose-sentence (v2,
longest-match) + forced-aligned frame-accurate word index (Phase B) + alternate takes / shuffle /
anti-click joins / gap recovery / loudness normalization (Phase C). **Loudness:** an "Even out the
volume across clips" toggle measures each word window's RMS (`Loudness`, native AVAssetReader) and
sets its mix gain toward a shared target, so one film's word doesn't boom over the next. Verified:
two real clips measured rms 0.0102 vs 0.1471 (a ~14× spread) → normalized to gains 3.00 vs 0.82.
The only remaining optional polish is a "read it back" in-sheet preview (the editor already previews
the assembly after Add).

**Durable media: SHIPPED 2026-06-24.** Project-local media (imported music bed + recorded
voiceover) is now EMBEDDED into a `media/` subdirectory of the `.archiveproj` package on save and
extracted back to `ProjectMediaCache` on open — so the edit travels to another Mac and survives a
Caches purge. Achieved WITHOUT the full NSDocument/security-scoped-bookmark migration: the bytes
live inside the package (a `ReferenceFileDocument` directory wrapper that already preserves sibling
wrappers), so no document URL or bookmark is needed. The engine still resolves media by filename
from the cache (unchanged); the package is the durable source of truth, the cache the disposable
working copy. archive.org video stays a remote reference. The full NSDocument backbone remains a
future option only if the engine later needs the document's own URL for relative-path resolution —
durable media no longer requires it.

**Session note (2026-06-24):** the entire Creation Studio editor + flagship backlog is now shipped
— timeline direct-manipulation, Publish (#7), Supercut (#9) line + word level + full-corpus index,
music bed + voiceover (#4) with durable package-embedded media, cross-dissolve + wipe/push
transitions, color Looks, and real Stock shots (#6). The only remaining optional polish is a
"read it back" in-sheet supercut preview (the editor already previews the assembly after Add) and
non-dissolve transitions via a Metal compositor (the native opacity/transform/crop ramps cover
dissolve/wipe/push today).

**Document naming = the filename, single source of truth: FIXED 2026-06-24.** The editor used to
show TWO names — the native window-title-bar name ("Untitled") AND a separate editable
`TextField("Project title")` in the toolbar bound to a `ClipProject.title` field — which is
non-standard and confusing (macOS document apps name a document by its FILE). Removed the toolbar
title field and the `ClipProject.title` model field entirely; the document's name is now ONLY its
filename, shown in the title bar and renamed the native way (title-bar proxy-icon popover / File ▸
Rename / first ⌘S Save panel). Export + Publish seed their default names from the document's own
filename via `@Environment(\.documentConfiguration).fileURL` (macOS 14+), falling back to "Archive
Watch" / "My Archive Watch Edit" for a not-yet-saved project; the export's embedded-metadata title
is the chosen export filename. Legacy `.archiveproj` files with a `title` key still decode (the
synthesized CodingKeys simply no longer include it — additive/tolerant). This is the
`native-platform-first` rule: don't invent an app-specific title surface when the OS already owns
document naming.

**Test/screenshot hooks (`AW_CS_TEST`) + sidebar clip thumbnails: SHIPPED 2026-06-24.** The
DocumentGroup editor is driven into a populated state (`editor`) or the Add-Clip scrubber
(`markclip`) for CLI visual verification (SwiftUI's a11y tree isn't AppleScript-traversable).
The Library sidebar now shows each clip's real in-point frame from the archive.org thumbnail
strip (`ClipThumbnailView` + `ClipThumbnailCache`), poster→icon fallback — robust regardless
of store/poster state, honoring "clip previews use thumbnails, not freshly-generated frames."

**Selection-driven inspector + multi-track audio: SHIPPED 2026-06-25.** Two coupled changes that
move the editor toward a fully-featured multi-track NLE:
- **Inspector is now purely selection-driven** (Rule 7a — the FCP/`.inspector()` model): it edits
  ONLY the current selection and nothing else — a video clip → volume/fades/look/transition; a text
  overlay → the text editor; an audio clip → name/volume/start/fades; NOTHING selected → the
  PROJECT (canvas-aspect preset + frame rate + attribution). The old kitchen-sink panel (global
  Music/Voiceover/Project-stats/Canvas/Dates all shown at once) is gone. **No read-only data in the
  inspector** — every control mutates; canvas size + frame rate became editable pickers (were
  read-only labels), and the clips-count/duration/format/dates stat blocks were removed. Adding
  music/voiceover/clips/text are TOOLBAR actions (Add Music, Voiceover), not inspector state.
- **One `EditorModel.Selection` enum** (`.none/.clip/.overlay/.audio`) replaces the separate
  `selectedClipID`/`selectedOverlayID` optionals (kept as computed getters). `.none` selects the
  project itself; ⌫ deletes whatever is selected.
- **Multi-track audio (Rule 3c "audio on N tracks"):** `Timeline.musicBed`/`voiceover` (single
  optionals) → `audioClips: [AudioClip]` — UNLIMITED music + voiceover, each with its own
  volume/start/fade-in/fade-out and its own composition track. `AudioClip` carries `kind`
  (music/voiceover) + a cached `sourceDuration`. Old `.archiveproj` files migrate their single beds
  into the array on decode (tolerant/additive). `CompositionBuilder` already took `beds:
  [ResolvedMusic]`; it now honors a per-clip duration cap + fade in/out. Text overlays + video clips
  were already arrays — so ALL THREE element kinds (video / audio / annotation) support adding as
  many as you want, anywhere, overlapping is fine.
- **Timeline**: audio clips render in a DYNAMIC stack of lanes (greedy non-overlap packing —
  multiple clips stack into as many rows as needed), each block selectable + draggable to retime +
  right-click Delete; color by kind (green = music, orange = voiceover).

**Timeline multi-selection + full mouse model: SHIPPED 2026-06-25.** Audited the timeline against
the HIG / NLE mouse conventions and filled every gap so all element kinds (clips, titles, audio)
are selectable + manipulable by mouse:
- **Multi-selection** is a `Set<UUID>` (`EditorModel.selectedIDs`) spanning all element kinds; the
  `Selection` enum stays the PRIMARY (the inspector's focus). **⌘-click** toggles an element in/out,
  **⇧-click** extends, **⌘A** selects all, **Esc / click-empty** clears.
- **Rubber-band marquee**: click-drag in empty timeline space draws an accent rectangle and selects
  every clip/title/audio block it intersects (⌘/⇧ adds to the existing selection). The band draws
  live (no model churn) and commits on mouse-up. A plain click in empty space clears + seeks; the
  RULER band still scrubs the playhead on drag.
- **Multi-drag**: dragging any selected FREE element (title or audio) moves the WHOLE selection of
  free elements together by the same Δt (origins captured at mouse-down, one rebuild per move).
  Magnetic video clips reorder individually (Rule 7c magnetic track — they have no free time
  position). A plain click on a selected member collapses to just it (the standard click-vs-drag
  disambiguation).
- **Delete** (⌫ or right-click) removes the entire multi-selection in one undo step; right-click on
  a selected group offers "Delete N Items"; titles + audio gained their own right-click Delete (was
  clips-only). The inspector shows an "N items selected · Delete N" banner above the focused editor.

---

# PART B — The parity face (browse / play / library)

*Shipped 2026-06-23…29 (Decision 042). The browse/play/library/search/channels window on the
shared Swift Core — native-Mac idioms, NOT the iOS app resized (§1). Files: the non-CreationStudio
`macOS/*_macOS.swift`. Each rule below is enforced in code today; quote it before changing a surface.*

## §B1 — Scene graph & navigation

Three SwiftUI scenes, in order: `WindowGroup("Archive Watch")` (parity face, root = `RootView`,
`minWidth 960 × minHeight 600`) → `DocumentGroup` (`.archiveproj`, Creation Studio) → `Settings`.

- **Rule B1a — ⌘N opens a PROJECT, not a window.** WindowGroup-first + a DocumentGroup makes
  SwiftUI bind ⌘N to a new Library window; re-point it with `CommandGroup(replacing: .newItem)` →
  `NSDocumentController.shared.newDocument(nil)`. (Surprise Me = `CommandGroup(after: .newItem)`, ⌘⇧R.)
- **Rule B1b — navigation = a sidebar `Section` + ONE `NavigationPath`**, NOT the iOS per-tab stack.
  `AppRouter.section` (`Section` enum home/movies/tv/channels/collections/surprise/search/library/create
  — its raw values are what `AW_START_TAB` matches) + `router.path` feed a single `NavigationSplitView`
  detail column. `openDetail` drills a `tv-series` card into `SeriesRef` (season/episode), else the item.
- **Rule B1c — `ModelConfiguration(cloudKitDatabase: .none)`.** Sync is MANUAL via
  `CloudKitSyncService` (not SwiftData auto-mirroring); it fires on sign-in + `scenePhase == .active`.
  Schema: WatchProgress/Favorite/Playlist/UserChannel/Tombstone/VideoClip/LibraryClip. App `init`
  sets `URLCache.shared` to 64/400 MB (the ImagePipeline depends on it, §B6c).
- Deep links (`.onOpenURL` + `NSUserActivityTypeBrowsingWeb`): `archivewatch://item/{id}` · `/surprise`
  · `/random` · `https://archivewatch.org/item/{id}` → the detail column.

## §B2 — The player is the window root while playing (load-bearing)

- **Rule B2a — when a title plays, the player REPLACES the split view as the window root** (not an
  overlay on it). `RootView` is a `Group`: `nowPlaying → PlayerWindow`, else `nowPlayingEpisode →
  EpisodePlayer`, else `browse`. WHY: an overlay leaves the split view owning the window toolbar, so
  its sidebar toggle + the previous view's title bleed through over the player. As root, the player's
  own NavigationStack title + X button are the only chrome. Never reintroduce the player as an overlay/
  cover on the split view. (The screensaver is likewise a full-window overlay, not a sidebar-keeping push.)

## §B3 — Player engine (native AVKit, no hand-drawn controls)

- **Rule B3a — `AVPlayerView`, `controlsStyle = .floating`** (the macOS TV-app HUD: transport,
  scrubber, volume, PiP, AirPlay, full-screen). Speed is the **native HUD** (`v.speeds =
  AVPlaybackSpeed.systemDefaultSpeeds`) — do NOT bolt on a custom Speed menu. `allowsVideoFrameAnalysis
  = false` (no Live Text on film frames). `VideoPlayerNS` is the `NSViewRepresentable`.
- **Rule B3b — resilient MP4 via `ResilientStreamLoader.makeAsset(for:)`** (retain the loader for the
  asset's lifetime; `preferredForwardBufferDuration = 300`). HLS (`AVPlayerItem(url: subtitleHLS)`) only
  when the title has subtitles (native CC + seek).
- **Rule B3c — resume + periodic save.** `WatchProgress` keyed by `archiveID` (films AND episodes);
  seek if saved > 5 s, skip if complete. SAVE every 5 s via a periodic time observer (owner 2026-06-29 —
  macOS used to save only on close, losing a crashed session), relaxed gate `pos > 1` (duration
  backfilled), then `SyncNudge.nudge(ctx)`.
- **Rule B3d — live TV NEVER persists.** `ChannelPlayer`/`ChannelEngine` (lineup, join-in-progress at
  offset, woven PD commercials, `advance()` on end) writes no WatchProgress — channels never pollute
  Continue Watching. Episode binge: `.id(episode.archiveID)` recreates the surface per episode (own
  resume) + auto-advance on end.

## §B4 — The hero (full-width 16:9, never cropped)

- **Rule B4a — the hero box is full-width AND aspect-locked to 16:9 with NO height cap:**
  `.frame(maxWidth: .infinity).aspectRatio(16.0/9.0, contentMode: .fit)`. Height tracks width
  (= width × 9/16), so a 16:9 backdrop fills it exactly and is never cropped at any window width. Two
  traps, both caused repeated owner pushback: a FIXED height letterboxes/crops as the window widens; a
  `maxHeight` cap makes the aspect-fit box go narrower than the window (inset/centered → "doesn't extend
  across"). Full-width 16:9 needs neither. (Mac windows resize; iOS/tvOS use a fixed height because
  device width is fixed. See `macos_hero_fullwidth`.)
- **Rule B4b — backdrop as `.background`, not a child** (the fill-image trap, §B6a). Pool requires a
  real WIDE backdrop (`backdropURLParsed != nil` + `hasDesignedArtwork` + `artworkSource != "generated"`)
  — never crop a 2:3 poster or a frame-grab into the banner; if too few qualify, show fewer or hide.
- **Rule B4c — rotation via structured concurrency, not a Combine timer** (§B10). `HeroCarousel`
  cross-fades every 7 s via `.task(id: items.map(\.archiveID))`; hover pauses.

## §B5 — The player title rule (no externalMetadata on macOS)

- **Rule B5a — the on-screen title rides the WINDOW TITLE BAR** (`navigationTitle("Title (Year)")`),
  NOT player metadata. macOS `AVPlayerItem` has **no `externalMetadata`** (iOS/tvOS only — verified in
  the SDK). The only way to override the MP4's embedded title is to wrap the asset in an
  `AVMutableComposition`, which over our custom-scheme resilient asset renders BLANK video — tried +
  reverted TWICE. Do NOT retry the metadata-override. (See `macos_player_native`.)

## §B6 — Posters & images (three rules, one pipeline)

- **Rule B6a — the fill-image layout trap (3 places, one fix).** A fill-mode image reports oversized
  "cover" dimensions; a `maxWidth:.infinity` frame ADOPTS them → cards overlap / hero overflows. Fix: a
  SIZED shape owns layout, the image fills via `.overlay`/`.background`. Used in `PosterCard` (a 2:3
  `RoundedRectangle` + `.overlay { RemotePoster }`), the Detail/Series poster wells (240×360, `.fit`),
  and the hero (§B4b).
- **Rule B6b — never show the archive.org thumbnail (owner 2026-06-29).** `RemotePoster` loads the
  DESIGNED poster only (`hasDesignedArtwork ? posterURLParsed`); on miss it falls through to a
  typographic title card, NEVER the `services/img` frame grab. Same rule governs `Modes.screensaverPool`.
- **Rule B6c — all browse/play images go through `ImagePipeline`, never bare `AsyncImage`.** Bare
  AsyncImage re-decodes/re-downloads on every reveal and bursts unlimited connections (archive.org
  throttles → "posters load slowly"). The pipeline: an `NSCache` of DECODED `NSImage`s (countLimit 800)
  + a single `URLSession` capped at `httpMaximumConnectionsPerHost = 6` (reusing the 64/400 MB URLCache)
  + in-flight coalescing. `RemoteImage` is the drop-in. (Creation Studio has its OWN `StudioNet` pool —
  `creation_studio_connection_discipline`.)
- **Rule B6d — decode non-RGB images to sRGB before SwiftUI (the grayscale→white bug).**
  `Image(nsImage:)`'s Metal path renders a 1-component grayscale (or CMYK/16-bit) image as a SOLID WHITE
  box (a real grayscale TMDb JPEG, "Frozen Frolics", rendered white). `decodedRGBImage` redraws any
  non-8-bit-RGB image into sRGB RGBA once, in the pipeline, for every call site.

## §B7 — Detail / Series poster wells

Detail + SeriesDetail use the SAME 240×360 aspect-FIT 2:3 poster well — never a wide-banner crop of a
portrait poster (the old `backdrop`-in-a-16:9-banner clipped a random slice). Series slug: prefer
`seriesID`, else strip the `series:` prefix from `archiveID`; spine loads from `/series/{slug}.json`.
Cast bubbles: left-click → `openPerson` (browse their titles); right-click → Callsheet person link when
installed. One consolidated Share menu (Open in Creation Studio when `isClippable` · Callsheet ·
`ShareLink` to `archivewatch.org/item/{id}` · archive.org). "Open in Creation Studio" queues
`store.pendingClipItem` then opens a fresh project window (the editor's `.task` consumes it).

## §B8 — Channels EPG

- **Rule B8a — a FIXED-window proportional EPG** (fixed channel rail + pinned time ruler + runtime-sized
  program blocks), NOT a 2D frozen-column scroll. The window holds still (the proven tvOS/iOS layout);
  pointer chrome (Earlier/Later/Now) shifts it — the Mac substitute for tvOS focus-paging / the iOS swipe
  (§1 says don't port touch idioms). An offset-mirrored 2D approach rendered the rail unreliably; don't
  reintroduce it. The window clamps to the broadcast day (`dayAnchor` → +20 h); landing within 5 min of
  NOW snaps back to live. User-channel delete writes a `ch:<id>` Tombstone (§B9).

## §B9 — Sync touch-points

Removals propagate via `Tombstone` keys: `fav:<id>` (DetailView favorites), `ch:<id>` (user channels);
playlists use `touch()` recency-merge (#11b). All rely on the foreground/sign-in `CloudKitSyncService.sync`;
only `PlayerSurface` additionally calls `SyncNudge.nudge` (push progress promptly so devices converge).

## §B9b — Downloads are the ONE unsynced surface (Decision 099)

Library's Downloads section, the Detail Download menu and Settings' storage
row all read `DownloadedFilm`, which is registered in the container and
**excluded from CloudKit** — it names a file on THIS Mac, so §B9's tombstone
and nudge discipline does not apply and a bare removal is correct
(iOS-DESIGN §9.7). Downloads render as ROWS inside the Library ScrollView, not
a `ShelfRow`: a download has a state and a size, and a poster shelf can show
neither. `PlayerWindow.setup()` checks `OfflineLibrary.videoURL(for:)` FIRST
and plays a plain `AVPlayerItem(url: fileURL)` — no `ResilientStreamLoader`,
no captioned-HLS wrapper (§B3 still binds for every REMOTE asset). A
downloaded film's subtitles publish into the same `liveLine` the caption
engine writes, so the overlay, its styling and its teardown stay one thing.

## §B10 — Native-platform-first + structured concurrency

- Binding everywhere: AVPlayerView HUD (no hand-drawn controls), `.searchable` toolbar field, native
  `Form` sheets, `NSWorkspace.urlForApplication(toOpen:)` for Callsheet install detection (NO Info.plist
  queries-schemes on macOS — that's an iOS restriction), native HUD speeds. The document is named by its
  FILE — never an in-app title field (the 2026-06-24 fix). See `native-platform-first`,
  `feedback_native_apis_no_workarounds`.
- **Replace Combine `Timer.publish` with `.task`-based loops** in any view (hero, screensaver, search
  debounce): a Combine timer delivering into a `@MainActor` closure can trip a Swift-runtime executor
  fault and fire into a torn-down view. `.task(id:)` is auto-canceled/restarted by SwiftUI.

## §B11 — Launch / test hooks

`AW_START_TAB=<section rawValue>` lands on a sidebar section; `AW_START_ITEM=<archiveID>` opens that
title's Detail (waits for the full DB to swap in); `AW_CS_TEST=editor|markclip` drives the Creation
Studio editor. Inert unless set. Needed because SwiftUI's a11y tree isn't reliably AppleScript-traversable
— screenshots capture by REGION from AX window bounds (§C6).

## §B13 — Watch Together Studio on macOS (binding; Phase 2)

*Feature rules: `docs/WATCH-TOGETHER.md`. This section says only what is
macOS-SPECIFIC, and every rule below is a consequence of §B2a or §B3a rather
than a new idea.*

- **Rule B13a — the Studio is the PLAYER IN A PRODUCTION MODE, never a second
  window.** §B2a is load-bearing here: the player already replaces the split
  view as the window root, so going live adds overlays and a readout *to that
  root* and changes nothing about the scene graph. A separate Studio window
  would give the broadcast its own toolbar and its own title bar, which is
  exactly the bleed-through §B2a was written to stop — and it would let a host
  close the window their audience is watching through. This matches iOS-DESIGN
  §8.8 and tvOS-DESIGN §8.8; all three platforms run one `StudioEngine`.
- **Rule B13b — the film keeps AVPlayerView's floating HUD (§B3a) while live.**
  Do NOT hand-draw transport controls for the Studio. What the host is
  producing is a *program*, and the program's own controls (layout, faders,
  cards) belong in a separate panel; the film's transport stays native, which
  is also what keeps PiP, AirPlay and the native speeds working mid-broadcast.
- **Rule B13c — the program panel is a `Form` in a sheet, not an inspector
  rail.** §B8's EPG and §B7's wells own the wide surfaces; a rail would
  reflow the player. The panel follows §B10's native-`Form` rule and mirrors
  the iOS §4.5 controls sheet so a host who learned one knows the other.
- **Rule B13d — the health readout is ALWAYS visible while live and is never
  a HUD element.** It is a capsule pinned top-leading over the player, outside
  AVPlayerView's own chrome, because the HUD auto-hides and health may not
  (`docs/WATCH-TOGETHER.md` §4). A Mac host is often not looking at the
  window at all, so the readout also states the ONE current problem in words.
- **Rule B13g-2 — and it is ALSO a toolbar item, because a menu command
  nobody can find is not a surface.** AMENDED 2026-09-20, owner looking at the
  Mac: *"it seems to lack the ability to set a destination or any settings for
  livestreaming at all. It just starts playing the movie."*

  B13g's reasoning below still stands — §B13a forbids a second window and
  §B13b forbids hand-drawing into the player's chrome, which genuinely do rule
  out the two obvious places. What it did not weigh is DISCOVERY. The command
  existed, worked, had a keyboard shortcut, and was greyed out until a film
  played — and a host who started a film saw nothing at all, because the
  player surface carries no Studio affordance until §B13d's readout appears,
  which only happens once you are already live. Every other platform puts
  entering a broadcast on the surface: tvOS in the transport menu (§8.8), iOS
  on Detail (§8.9). macOS alone required knowing.

  A native `ToolbarItem` is neither forbidden thing — not a window, not
  hand-drawn chrome, but the affordance macOS itself provides on a window that
  already has a toolbar. The menu command and ⇧⌘L stay exactly as they are;
  this is the same command with somewhere to be seen.

  It is HIDDEN while live rather than disabled, because §B13d's readout
  already owns the live state and ending the show. Two controls for one state
  is how a host presses the wrong one.

- **Rule B13g — going live is a MENU COMMAND that opens the same form sheet
  as iOS §8.9.** APPROVED by the owner 2026-09-18 ("Yes proceed with your
  plan"), in answer to the proposal below. The two questions it left open —
  which menu the command belongs under, and whether it is enabled with no
  film playing — were not answered explicitly, so the implementation takes
  the most conservative reading and says so where it does.

  *Why this is proposed at all*: `docs/WATCH-TOGETHER.md` §9.ccc found that the
  Mac cannot broadcast to YouTube or Twitch at all — the credential path is
  constructed only in the iOS container, and macOS has no go-live affordance of
  any kind. The engine, composite, overlays, rights gate, health readout and
  publisher are all real here; the thing missing is the surface that starts a
  broadcast, and §B13 has rules for the Studio once LIVE and none for entering
  it.

  *Why a menu command rather than a button*: §B13a forbids a second window and
  §B13b forbids hand-drawing anything into the player's chrome, which between
  them rule out the two obvious places. A menu command is the surface macOS
  offers that is neither, the app already uses `CommandGroup` for New Window
  and Refresh, and it gives the action a keyboard shortcut and a discoverable
  home without touching the scene graph §B2a protects.

  *Why the same sheet as iOS*: §B13c already chose mirroring over invention for
  the program panel — "a host who learned one knows the other" — and the
  go-live sheet carries content that is not cosmetic: the rights refusal in a
  sentence (§2.3), the sign-in row, §3.4a's warning about automated matchers,
  and the title the audience sees. Rebuilding that from scratch for the Mac
  would be a second chance to get the rights copy wrong.

  *What still needs deciding, and is the reason this is a proposal*: whether
  the command lives under File, under a new Broadcast menu, or in the existing
  playback commands; and whether it is enabled when no film is playing (the
  iPhone reaches Go Live from a film's Detail, so the Mac's entry point has no
  exact counterpart). Both are the owner's calls, not 4am's.

- **Rule B13e — the camera needs an ENTITLEMENT here, unlike the phone.**
  `com.apple.security.device.camera` plus `NSCameraUsageDescription`. A
  sandboxed Mac app without the entitlement gets a TCC denial that looks
  exactly like "there is no camera" — the same class as the
  `device.microphone` note in §B12 ("the record does nothing bug"). Measured
  2026-09-17: the camera tile costs **+0.73 ms/frame**, but that number was
  taken with an UNSANDBOXED command-line harness, which is why it worked
  before the entitlement existed.
- **Rule B13f — macOS is the only Apple platform that can capture a window,
  and it still does not screen-capture the film.** `WATCH-TOGETHER` §3.3 is
  absolute: the film is composited from `AVPlayerItemVideoOutput`. Phase 2's
  ScreenCaptureKit ambition is for a *guest call* (a FaceTime window beside
  the film), never for the film itself.

## §B12 — Capabilities, identifiers, Info.plist

- **Shared with tvOS/iOS** (one ASC record, Decision 042): bundle id `app.archivewatch.tvos`, CloudKit
  `iCloud.app.archivewatch.tvos`, App Group `group.app.archivewatch.tvos`, Associated Domains
  `archivewatch.org` (applinks + webcredentials). UTType `org.archivewatch.project` (`.archiveproj`, a
  `com.apple.package`).
- **Sandbox** (App Store requirement): app-sandbox + network.client + files.user-selected.read-write +
  **device.microphone + device.audio-input** (a sandboxed app needs the mic entitlement or TCC silently
  denies → the "record does nothing" bug) + **device.camera** (Watch Together Studio's camera tile,
  §B13e — same silent-denial trap). Sign in with Apple = Default.
- `LSMinimumSystemVersion = 26.0` (the Configuration-based AVFoundation API is macOS-26+),
  `LSApplicationCategoryType = entertainment`, `ITSAppUsesNonExemptEncryption = false`,
  `NSMicrophoneUsageDescription` (voiceover; also the Studio's host mic) and `NSCameraUsageDescription`
  (the Studio's camera tile). The target was wired by a direct `project.pbxproj` edit
  (objectVersion 77); the Core is REUSED via `fileSystemSynchronizedGroups` pointing at the same
  `ArchiveWatch` folder with `#if os()` guards — never copied.

---

# PART C — Shipping the Mac app

*Full runbook: `docs/mac-app-store-submission.md`. Triggerable skill: `apple-app-store-cli-submission`.
Live state + cert ids: `mac_app_store_build_pathway`. All three Apple apps share ONE ASC record.*

## §C1 — The CLI submission pathway (manual REST signing)

One command: `DEVELOPER_DIR=<released-Xcode>/Contents/Developer tools/submit-appstore.sh <mac|ios|tvos|all>`
→ archive → ensure certs → an App Store profile per embedded bundle id → manual ExportOptions → export +
upload via the ASC API key. The OWNER then selects the build in ASC and Submits for Review (the script
only uploads).
- **Rule C1a — signing is MANUAL; cloud/automatic signing FAILS for this team key** ("Cloud signing
  permission error"), though the key CAN create certs/profiles via REST (`asc_certs.py` + `asc_profiles.py`).
  Don't revert to automatic.

## §C2 — Two post-upload rejections gate every LOCAL build

Both fire AFTER upload, on the build's metadata — check both before building locally.

- **§C2a — ITMS-90111 (Xcode/SDK floor, RECURRING).** The Xcode/SDK is older than Apple's current
  floor. Diagnose: `WebFetch https://developer.apple.com/news/releases` for the latest RELEASED/RC Xcode
  (a build number ending in a lowercase letter, e.g. `27A5194q`, is a BETA → rejected), compare to
  `xcodebuild -version`; owner installs it (`xcodes install <ver>`, Apple ID + 2FA — not headless),
  rebuild ALL THREE at a fresh build. First hit 2026-06-30 (26.0 → floor **26.6 / 17F113**).
- **§C2b — ITMS-90301 ("not accepting applications built with this version of the OS") = the build
  MACHINE is on a BETA macOS.** This is about the build machine's OS, NOT Xcode — a GA Xcode does not
  help. Apple rejects ANY App Store build made on a beta macOS. Check `sw_vers` (a `BuildVersion` ending
  in a lowercase letter, e.g. `26A5353q`, or an unreleased `ProductVersion`, is a beta) or
  `BuildMachineOSBuild` in the archive's app Info.plist. **There is no local fix on a beta box — do not
  rebuild and retry.** Build on a RELEASED macOS. Hit 2026-06-30: the dev Mac is on **macOS 27 beta
  (`26A5353q`)**, so local CLI builds clear §C2a but fail §C2b.
- **§C2c — BUILD IN THE CLOUD (the implemented fix for BOTH).** `.github/workflows/appstore-build.yml`
  builds + signs + uploads all three on a GitHub-hosted **`macos-26` runner** — a RELEASED macOS (26.4,
  `25E246`) with **Xcode 26.6 (17F113)** — which clears §C2a (current Xcode) AND §C2b (released build OS).
  It's **FREE for this public repo** (no Xcode Cloud compute, no SIP spoof). Run it:
  `gh workflow run appstore-build.yml -f platform=all` (or `mac`/`ios`/`tvos`). It imports the signing
  `.p12`s from repo secrets into a temp keychain (cloud signing fails for this team key, §C1a, so manual
  signing stays) and runs `tools/submit-appstore.sh` with `ASC_DIST_CERT_ID`. Bump AppVersion.xcconfig +
  push BEFORE dispatching (the runner builds the committed version). **Validated 2026-06-30:** all three
  uploaded at 1.3.249/771. Secrets seeded by `tools/ci_make_signing_p12.py` (mint a CI cert → `-legacy`
  `.p12`) + `gh secret set`; the dedicated CI Distribution cert is `87TU7L3TBQ`, installer `K8QX4BXZZL`.
  (Xcode Cloud — `ci_scripts/ci_post_clone.sh` — is the same idea on Apple's runners, but its free
  compute ran out; GitHub Actions is the free equivalent.) **TestFlight still accepts beta-OS builds**,
  so testing is never blocked.

## §C3 — PyJWT venv (self-healing)

`asc_certs.py`/`asc_profiles.py` sign the ASC JWT with PyJWT + cryptography; Homebrew python3 (PEP-668)
lacks them. The script auto-provisions `tools/.asc-venv` and runs the cert tools from it. Bypassing the
script means putting a jwt-capable python on PATH first.

## §C4 — Per-platform SDK + Metal downloads

A fresh Xcode needs `-downloadComponent MetalToolchain` (~700 MB; the app has a `.metal` shader —
auto-installed by the script) and may need `-downloadPlatform iOS`/`tvOS` if "Any … Device" shows
"not installed".

## §C5 — Compile guards & the tuple-sort gotcha

- **Rule C5a — guard 27-only symbols with `#if compiler(>=6.4)`, not just `#available`.** A runtime
  `#available` check STILL needs the symbol in the BUILD SDK → it won't COMPILE on the GA toolchain; the
  `#else` carries the macOS-26 API. Audit: `grep -rn 'available((macOS|iOS|tvOS) 27'`.
- **Rule C5b — no tuple-sort closures.** `.sorted { (a,b,c) > (a,b,c) }` → "unable to type-check in
  reasonable time" on the GA toolchain (tvOS-only files surface it). Compare field-by-field.

## §C6 — Screenshots

macOS: 16:10, EXACTLY 2880×1800 (or 1280×800 / 1440×900 / 2560×1600). Drive via the §B11 launch hooks;
capture by REGION from the AX window bounds (SwiftUI has no AXWindowNumber) then PIL-frame to the exact
size. `tools/mac-shotset.sh <app>` runs the full set; needs Screen Recording permission. Any build may
produce them (need not be the submitted binary).

## §C7 — Version bump & disk

Bump BOTH `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` (AppVersion.xcconfig) every build — App Review
burns a build number even on rejection; the next must be ahead + monotonic. The box runs ~97% full; a
fresh Xcode needs ~25–30 GB — free it (delete the obsolete Xcode app, clear DerivedData + `build/`)
before installing.

---

*Amend, don't contradict. New views/features quote the rule they satisfy or the amendment
they propose.*

## §B13h — the mix controls are a 0–10 level, and auto-duck is a control

The same rule as tvOS-DESIGN Rule 8.8c, because it is a statement about people
rather than about televisions. Owner, 2026-09-20: *"a scale of 0 to 10 rather
than ... decibles that most people won't understand."*

- **0–10, with 8 as unity** — the source's own level and the default, so a host
  who never opens the panel is already there. 0–8 cuts 5 dB a step to silence;
  8–10 boosts 3 dB a step to the mixer's +6 dB ceiling. `MixLevel` in
  `Studio/StudioAudio.swift` is the one conversion, shared with the television.
- **`Slider` stays.** It is the native control on this platform — it is
  `@available(tvOS, unavailable)`, which is the only reason the television
  draws its own. Only the SCALE and the readout changed, and the value is
  shown beside it because a host needs a number they can say out loud.
- **The meter reads on the fader's own scale**, not linearly. A linear 0–1
  meter draws 2% for speech at RMS 0.02, which is how a working microphone
  reads as a broken one.
- **Auto-duck is a toggle, not a sentence.** Both panels used to STATE that
  "the film drops 12 dB automatically while you are talking". A host who sets
  Film to 9 and then speaks hears it drop anyway and reasonably concludes the
  fader is broken. Manual has to mean manual.

### B13i — a BORROWED PHONE is never given a session preset

The host camera path (`StudioSession.attachCameraIfAvailable`) sets
`.hd1280x720` for a built-in camera and **surrenders format control for a
Continuity Camera**, and it sets the preset AFTER adding the input, never
before.

**Why**: assigning the preset before any input existed is what killed every
Continuity broadcast on tvOS (2026-09-19, reproduced twice). The failure does
not surface at the assignment — it surfaces later, when something forces the
device to renegotiate, as an ObjC exception no Swift `try` can catch:
`-[AVCaptureDevice _setActiveFormat:…sessionPreset:] Unsupported format
((null))`, signal 6. tvOS was fixed in `StudioContinuity`; **the shared path
macOS and iOS use was not**, and macOS reaches the same device class, because
an iPhone used as a Mac's camera IS a Continuity Camera. `canSetSessionPreset`
is not a usable gate: it answered TRUE for `.hd1280x720` on a Continuity
camera and the exception was thrown anyway.

**How to apply**: `.inputPriority` is the verb on iOS and tvOS and is
**unavailable on macOS**. The macOS equivalent of "stop dictating a format" is
to leave the preset at its default `.high`, which NEGOTIATES the best the
device offers rather than demanding an exact size, so there is no specific
format for it to fail to find. Same intent, different verb — do not reach for
`.inputPriority` here and assume it compiles.

A built-in camera keeps `.hd1280x720` deliberately: the tile is never
full-frame, so capturing 1080p to draw a corner box is work nobody sees. Only
the borrowed-phone case gives that up, and it costs nothing because the tile is
scaled to its layout slot downstream regardless.

### B13j — the host's PLACEMENT is ARMED, never set after going live

`StudioSession.armLayout(_:)` is set beside `armDestination`, and the engine
takes it when it is BUILT. No caller waits for `isLive` and then calls
`setLayout`.

**Why**: `arm` records INTENT — the engine is built later, when the player
appears — so a caller that sets the layout at arm time sets it on nothing, and
one that sets it afterwards must first wait for a state. Every caller getting
that timing right independently is exactly what did not happen. The macOS
GO-LIVE SHEET armed the destination and the film and **dropped
`request.layout` on the floor**, so every broadcast from the product path went
out as `corner` however the host had chosen; the macOS DOOR waited for `isLive`
and applied it, so bench runs looked correct the whole time. tvOS had the same
defect one layer down (`setLayout(.corner)` hardcoded).

**How to apply**: arm the layout, do not set it. And when adding a debug door,
make it drive the chain the PRODUCT drives — a door that waits and sets where
the product arms cannot find the product's bugs, which is precisely how this
one hid behind a passing bench run.

---

# PART D — WATCH TOGETHER STUDIO on macOS (binding)

*Opened 2026-09-21. Owner: "You should have a lot of controls on MacOS to
determine exactly how the stream looks and which inputs/outputs are being
managed. You had researched OBS, so you should be able to take anything you
need from that open source project to make sure this feature is fully built
out."*

## §D0 — What we take from OBS, and what we deliberately do not

OBS is the reference because it is the thing hosts already know, and because
its hard-won answers to real problems are worth copying rather than
rediscovering. But Archive Watch is not a general-purpose broadcaster, and
copying OBS wholesale would make a WORSE product for this job.

**TAKE:**

| from OBS | why |
|---|---|
| **A program preview** — see what the audience sees, before and during | the single largest gap today: a Mac host reads numbers and trusts them |
| **An input list with real device pickers** — which camera, which microphone, which app's audio | the owner's words: "which inputs/outputs are being managed". Today the Mac takes `AVCaptureDevice.default` and never says which |
| **A per-input mixer**: fader, mute, and a meter per source | two faders is not a mixer once there are three inputs |
| **Output settings**: resolution, frame rate, bitrate, and the encoder's identity | these exist in the engine and are chosen for the host with no way to see or change them |
| **Stats that name a fault**: dropped frames, queue depth, reconnects | already measured (§6.4); never surfaced on macOS beyond a one-line capsule |

**DO NOT TAKE:**

- **Scenes as a general graph.** OBS scenes exist because OBS knows nothing
  about your content. We know: there is a FILM, optionally a HOST, optionally
  GUESTS, and a CARD. Rule 8.8e's five placements already name every
  arrangement those four can make, and a host choosing "Side by side" is
  making one decision where OBS would make six.
- **Filters and effects.** Chroma key, color correction, LUTs. A watch-along
  is not a production; the film is the picture and the host is a tile.
- **Recording to disk alongside streaming.** Tempting and cheap, and it turns
  a viewing app into a thing that makes copies of films — a rights posture
  this project has spent a year being careful about (Decision 027). NOT built
  without an owner decision.
- **Transitions.** A stinger between "film" and "film with a face in the
  corner" is motion for its own sake.

## §D1 — The Studio is a WINDOW, not a panel

The Mac gets a real Studio window — `Window("Watch Together Studio")`, its own
scene, resizable, remembered. The panel that exists today is a popover over
the player and cannot hold a preview, an input list and a mixer at once.

**Why a window and not a sheet**: a host runs a broadcast for two hours,
alongside the player. A sheet is modal to one window and disappears when the
player goes full-screen, which is exactly when a host most needs the controls.
This is §B2a's reasoning (the player is the window root) applied one level out.

**Layout**, and the proportions are the rule: PROGRAM PREVIEW across the top
at the program's own aspect; beneath it three columns — **Inputs**,
**Mixer**, **Output** — in that order, left to right, because that is the
order a host thinks in: what is in the show, how loud is it, where is it
going.

## §D2 — Every input is NAMED, and its device is CHOSEN

The input list carries one row per source. Each row shows the source's NAME
(the device's own localised name, never "Camera"), a live state, and its
control.

| input | device choice | today |
|---|---|---|
| Film | the film being watched — not choosable, it IS the show | ✓ |
| Camera | every `AVCaptureDevice` of type video, by name, plus "None" | takes `.default` silently |
| Microphone | every audio device by name, plus "None" | takes `.default` silently |
| A call's audio | any running process with audio, by bundle id (SHAREPLAY §10) | not built |

**A device that vanishes says so in its row** and the show continues — Rule
8.8's "an absent camera is normal" extended to every input. The camera-stall
recovery (Decision 133's `CameraStallRecovery`) reports into the camera row.

## §D3 — The mixer has one channel per AUDIBLE input, and a meter on each

Film, microphone, and the call — three channels where there are three inputs,
on the shared 0–10 scale (Rule 8.8c, `MixLevel`), each with a mute and a meter
drawn on the fader's own scale. Auto-duck stays a single toggle: it is a
relationship between the film and the voice, not a property of one channel.

**A muted input is drawn muted and still shows its meter.** A host needs to
see that the microphone they muted is picking up sound before they unmute it.

## §D4 — Output settings are the host's, with the engine's own numbers beside them

Resolution, frame rate and bitrate are choosable; the encoder's identity
(hardware or software) and what the wire is actually carrying are shown beside
them and are never editable. §6.5's thermal step may move the bitrate at
runtime — when it does, the control shows the ASKED figure and the readout
shows the ACTUAL, and the difference is the point.

**Nothing here may be changed while live** except the bitrate: an RTMP ingest
will not accept a resolution or frame-rate change mid-publish (§6.5's
correction), so those controls are disabled with that sentence, not hidden.

## §D5 — The preview is the PROGRAM, and it is honest about what it is

The preview draws the same composited frame the encoder receives — not an
approximation, not the film with an overlay drawn in SwiftUI. It is fed from
the engine's own output so that "what I see" and "what they see" cannot
diverge, which is the whole failure this session spent a day chasing on other
platforms (Decision 133).

**Before going live the preview still runs.** A host should be able to frame
themselves, set levels and pick a placement with nothing being broadcast —
which is what OBS's preview is for, and what no Archive Watch platform offers
today.

## §D6 — Build order, and where it actually stands

Each step ships on its own and is verified on the wire, never by compiling.

| # | step | state |
|---|---|---|
| 1 | The window, the preview, the existing controls moved into it | **shipped** (v1.42.440), seen on the glass at 1080x860 |
| 2 | Device pickers for camera and microphone (§D2) | **shipped** (v1.42.444), §8.24 |
| 3 | Output settings (§D4) | **shipped** (v1.42.445), §8.25 |
| 4 | A call's audio via `AudioHardwareCreateProcessTap` (SHAREPLAY §10) | **code + §8.26 shipped** (v1.42.446); the TCC behavior of a SIGNED, SANDBOXED app is NOT yet measured |
| 5 | Per-input meters and mutes (§D3) | **shipped** with 3 and 4 |
| 6 | §D5's preview BEFORE going live | **shipped**; explicit "Start preview", never automatic |

**§D4 IS PROVEN ON THE WIRE (2026-09-21), which is the standard this project
holds itself to.** The host's choices were set to values that are none of the
old hardcoded defaults — **1280x720 at 24 fps, 3000 kbps** against the former
1920x1080/30/6000 — the macOS bench door published to a local `mediamtx`, and
the SERVER's own recording was read back:

    codec=h264 profile=High level=31  1280x720  r_frame_rate=24/1
    bit_rate=2481440   audio=aac 44100 Hz stereo

2.48 Mbps delivered against 3.0 asked is ~83%, consistent with the ~70-75%
this encoder has always delivered (§9). A single frame of that recording
carries the whole program: the film, the camera tile bottom-right, and the
lower third with title, year, director and the provenance line. So the
pickers, the settings and the composite all reach the encoder rather than
stopping in a preference — Decision 133's test, passed.

**And the run found an observability hole before it found anything else.**
The first three attempts published nothing and left NO trace: camera
attached, film attached, then silence. `StudioSession` caught a failed
`engine.start()`, set `refusal` and returned without logging — so a Studio
that failed to start was indistinguishable in the log from one that started
and published nothing. `[AWSTUDIOSTART]` now marks the attempt, the success
and the failure, and it named the cause on the next run in one line (the
harness URL lacked the `/app/streamKey` shape the publisher requires). Same
family as the `AWPUB` and `AWAUTH` gaps.

**What step 4 does not yet know.** §8.21 proved the tap as a command-line
tool under the terminal's grants. A process tap is gated by its own TCC
service (`NSAudioCaptureUsageDescription`, added to the macOS Info.plist),
which the microphone entitlement does not cover, and the app is sandboxed.
Decision 130's rule applies exactly: *a harness can prove the logic and say
nothing about where the logic RUNS.* `StudioSession.callProblem` carries the
refusal sentence so the answer appears on screen rather than as a silent
channel.

**`isLive` is not `isOnAir`, and §D5 is what made that matter.** `isLive` has
always meant "the engine is running", and on macOS the engine runs with no
destination whenever a film is armed. A rehearsal is precisely that state, so
every surface that says "live" asks `isOnAir` (`isLive && hasDestination`)
and every surface that means "there is a program" asks `isLive`. Two things
were wrong the moment the preview existed and are fixed: the Go Live toolbar
button hid itself during a rehearsal, and `attachIfArmed`'s `!isLive` guard
silently swallowed the arm for a real broadcast — so going live from a
rehearsal must END it first.

---

# PART D (continued) — the Studio the owner asked for, 2026-09-22

*The owner ran the shipped Studio for the first time and reported six things.
Four of them are not defects in the build: they are places where a rule
written earlier turns out to be wrong. This section amends those rules, and
says which sentence each one replaces, because §D1–§D6 above stay in the file
(append-only) and a reader must be able to tell which one binds.*

> Owner, 2026-09-22: *"There doesn't seem to be any way to 'add a movie' to
> the studio from the studio itself … the video player and all of its controls
> should be within the studio rather than in a separate window. You should
> still be able to create a separate video window of the playing video for if
> you want to project the movie on a separate screen, but by default
> everything for a stream should be accessible within the Watch Together
> studio."*

## §D7 — The Studio OWNS the show: the film is chosen in it, and the player lives in it

**This amends Rule B13a and the premise of §D1.** B13a said the Studio *is the
player in a production mode, never a second window*, and forbade a second
window on §B2a's reasoning. §D1 then gave the Studio a window anyway, for
reasons that still hold — but left the FILM in the other window, so the Studio
became a window of controls for a show it did not contain. A host opening it
with nothing playing was told to go and start a film somewhere else.

The binding shape now:

- **The Studio window carries a film chooser.** Search the catalog from
  inside the Studio, see only titles that the rights gate will actually let
  you broadcast (`StudioRights.canGoLive`), pick one, and it becomes the show.
  A host never leaves the Studio to assemble a broadcast.
- **The Studio window hosts the film's player**, with `AVPlayerView`'s native
  floating HUD (§B3a is unchanged — the transport is still never hand-drawn).
  This is the SOURCE pane of §D8.
- **A second window is a PROJECTION, and it is the host's choice.** "Open in a
  separate window" moves the film to the ordinary player window (§B2a's root)
  so it can be thrown at another display. It MOVES; it never copies. Two
  `AVPlayer`s on one film is the defect in §D11, not a feature.
- **One show at a time.** Arming a film in the Studio clears `nowPlaying`, and
  playing a film in the main window hands it to the Studio if the Studio holds
  one. The rule is that the app has exactly one film playing, wherever its
  picture happens to be drawn.

WHY the second window is now allowed where B13a forbade it: B13a's objection
was *toolbar and title-bar bleed-through*, which is a real §B2a consequence
for an OVERLAY on the split view. A `Window` scene has neither problem, and
§D1 already accepted that reasoning. What B13a got right — that a host must
not be able to close the window their audience is watching through — is kept
by §D12 below, which ends the show when its surface goes.

## §D8 — SOURCE and PROGRAM, side by side

**This extends §D5.** §D5 gave the Studio one picture, the composed program.
That is the picture that matters, and it is not the picture a host watches the
film on: a host who wants to follow the story has to read it out of a 648-point
preview with their own face in the corner.

The top of the Studio is therefore TWO panes, side by side, left to right:

| pane | what it is | why |
|---|---|---|
| **SOURCE** | the film itself, native transport, nothing composited | the host watches the film here, and scrubs it here |
| **PROGRAM** | the engine's own `CVPixelBuffer`, §D5 unchanged | what the audience sees, and it may never be a second render |

This is OBS's preview/program split, taken for the same reason §D0 takes
everything else from OBS: it is the arrangement hosts already know. Each pane
is labeled, and PROGRAM keeps §D5's badge that says whether it is going out.

**The split is a native `HSplitView`**, so a host can give either pane the
room. On a narrow window the panes stack — SOURCE above PROGRAM — rather than
shrinking both below legibility.

## §D9 — Going live is SET UP in the Studio, not in a sheet over the player

**This replaces Rule B13g.** B13g put the go-live form in a sheet presented by
the window root, and a 2026-09-20 amendment added a toolbar button to the
player because the menu command could not be found. Both were answers to
"where does a host press Go Live"; neither asked where a host DECIDES to go
live. The owner found the sheet by accident — *"I think I may have found it
hidden behind a button on the video player (rather than in the studio for some
reason)"* — which is the honest verdict on a form that lives over a different
window from the controls it configures.

Everything the sheet carried now lives in the Studio's **Output** column, in
this order, and it is a CHECKLIST a host reads top to bottom:

1. **The film** — what is being streamed, with its provenance line.
2. **The rights answer** — the refusal sentence, or nothing.
3. **Where it goes** — platform, the shared `StudioSignInRow`, the readiness
   answer, the title, privacy or category.
4. **How it looks** — placement, lower third, cards (§D10).
5. **The policy and §3.4a's warning.**
6. **Go Live**, disabled with the reason above it, never disabled in silence.

The menu command (⇧⌘L) and the player's toolbar button remain, and both now
**open the Studio window** rather than presenting a sheet. A shortcut that
lands a host in the place the work happens is still a shortcut.

## §D10 — A card may carry the host's own words

**This extends Rule 8.8f's card set.** The three fixed cards — Starting soon,
Intermission, Thanks for watching — cover the three moments a watch-along
always has. They do not cover the moment a host wants to say something else,
and the answer to that today is to say it out loud or not at all.

A fourth card is **the host's own text: up to four lines, each with a chosen
weight**, drawn by the same renderer, on the same ground, under the same
wordmark and rule. The weights are the SIX LEVELS the project already has
(CLAUDE.md's "three weights × two sizes"), named for what they do in a card —
Display, Heading, Body, Caption — so the card cannot grow a seventh.

**What it is not**: a text layer, a font picker, a color picker or a position
control. A card is a full-frame interruption with the app's own typography.
The host chooses the WORDS and their RANK; everything else is the design
system's, exactly as it is for the three fixed cards.

**An empty custom card is not shown.** A card that covers the film with a
black frame and nothing on it is a fault, not a choice.

## §D11 — A device change takes effect NOW

**This replaces §D2's "device changes take effect on the next broadcast".**
That sentence was written from a true fact — an `AVCaptureSession` is built
once when a show starts — and drew the wrong conclusion from it. The capture
session is not the encoder. Nothing about swapping which camera feeds the tile
reaches the RTMP ingest, because the tile is COMPOSITED: the wire never learns
that a different device produced the pixels. §D4's "not while live" rule is
about resolution and frame rate, and it does not extend here.

So: the camera and microphone pickers are live at all times. Changing one
tears down the capture session and builds a new one, and the row reports what
happened. A host whose webcam is pointing at the wall in the middle of a show
can fix it in the middle of the show.

**And the Studio ASKS for the camera and the microphone.** Until now every
macOS path said "the Studio REPORTS, never REQUESTS" — a rule that came from
tvOS, where a permission prompt on a television is a real intrusion. On a Mac
it meant `AVCaptureDevice.authorizationStatus` was `.notDetermined` forever,
nothing ever prompted, and the camera row said **"not attached"** for the life
of the product. That is not reporting; it is a dead end with a label on it.
The request is made when the host starts a preview or goes live — an explicit
act, never on opening a window — and each of the four states says its own
name:

| state | what the row says and offers |
|---|---|
| `.notDetermined` | "Archive Watch has not asked yet" · **Allow the camera** |
| `.denied` / `.restricted` | named, with **Open System Settings** |
| `.authorized`, no device | "no camera on this Mac" |
| `.authorized`, device | the device's own name, and its frame rate |

## §D12 — Closing the window ends the show, and closing the film stops the film

**This is new, and it is a correctness rule rather than a layout one.** The
owner: *"I was able to close a playing movie and then realize that I closed
out of the app (without actually quitting it) by using the Red 'stop light'
button … The movie continued to play and then when I opened the interface back
up, a new copy of the movie started playing … the movie seems to keep playing
in the background even if I do close the movie with the x … and there is no
way to stop the audio at all at that point."*

Three separate faults, one rule:

- **A player surface that goes away STOPS ITS PLAYER.** `onDisappear` must
  pause, drop the current item and release the player, and every singleton
  holding a strong reference to it (`WatchTogether.attachedPlayer`,
  `StudioSession.localPlayer`, the caption scout) must be told to let go.
  A view that vanishes while its `AVPlayer` plays on is an app with no
  transport controls for a sound it is making.
- **Closing a window ends what that window was doing.** The red button is a
  close, and on macOS a closed window is not a quit — so the film stops, any
  broadcast ends, and `nowPlaying` is cleared. Re-opening from the Dock lands
  on the browse root, which is what the host left, not a second copy of a film
  they thought they had closed.
- **A broadcast never outlives its Studio.** Closing the Studio window ends
  the show. This is B13a's one genuinely load-bearing objection to a second
  window, kept as a rule now that the window exists.

## §D13 — A button says what it does, at every window width

**This is a Part B rule, placed here because it was found in the Studio and it
is app-wide.** Owner: *"Button text should never be truncated or abbreviated
and it happens on the mac app all of the time when you shrink the window
size."* And, on being shown the first attempt: *"We don't want button wrapping.
We want actual designed buttons that say what they mean and perform like macOS
buttons should."*

Those two sentences rule out both of the easy answers.

- **Not truncation.** An `HStack` offered less width than its children want
  COMPRESSES them, and a `Button`'s `Text` compresses by truncating, so "Add
  to Playlist" reads "Add to Pl…" and the person is reading a guess at what
  the control does.
- **Not wrapping.** A flow layout keeps the words and loses the design: the
  Detail action row's seven large buttons reflowed into three ragged lines
  with "Share" stranded alone on the last one. That is not a layout anybody
  chose; it is the absence of one.
- **Not icon-only.** An icon with a tooltip is an abbreviation with extra
  steps.

**The rule**: a row of actions has a SMALL FIXED SET of primary buttons that
never move, and everything else collapses into one native **"More" menu**
whose items still carry their full names. Which arrangement is on screen is
chosen by `ViewThatFits(in: .horizontal)` over arrangements that were each
designed — it never reflows and never shrinks a label; it picks the richest
bar that fits and the rest is one menu away. Every control in such a row
carries `.fixedSize()`, and so does the row: without it the first arrangement
always "fits", by squeezing, and `ViewThatFits` never gets to choose.

This is what Music, TV and Finder do, and it is why a macOS app's controls
stay where you left them as a window resizes.

**Two corollaries, both found on the same narrow screen as the buttons:**

- **A bar action and its menu item are ONE declaration.** `DetailView_macOS`
  names each action once (`DetailAction`) and renders it either as a control
  or as a menu item. Two parallel lists is how "Add to Playlist" becomes "Add
  to a playlist" in one of them, and how an action gets fixed in one and not
  the other.
- **The rule reaches past buttons.** Any label that means something may not be
  abbreviated: the cast row was rendering "Rev. Arthur Di…" and "Roger Prynne
  a…" on the same screen where the buttons had just been fixed. Names and
  roles get two lines with `reservesSpace: true`, and the row is `.top`
  aligned so cells of different heights still line their portraits up.

---

# PART D (continued) — framing, the lower third, and what the mixer owes a host

*Opened 2026-09-22, same day as §D7–§D13, from the owner running the rebuilt
Studio. Five more reports; three of them are features and two are defects one
of which the owner found by using a control nobody had ever exercised.*

## §D14 — The camera can be FRAMED and PLACED, and the preset is where it starts

**This amends §4's "layouts are presets, never free-form in v1".** Owner:
*"I'd like to be able to move my camera around the preview window AND crop the
video (to only capture my face, etc.)."*

§4's rule bought something real — five named arrangements are five decisions
instead of OBS's six per scene, and Rule 8.8e's names are what let a
television, a phone and a Mac agree about what a show looks like. None of that
is given up. What §4 got wrong is treating the tile's SIZE and POSITION, and
the crop of the camera's own picture, as part of the arrangement. They are
not: they are how a host fits themselves into it, and a webcam that sees a
whole room when the host wanted a face is a framing problem that no preset can
solve.

So: **the preset still decides the arrangement. The host may then adjust the
framing, and the adjustment rides on top.**

| control | what it changes | range |
|---|---|---|
| **Zoom** | the crop taken from the CAMERA's own picture | 1×–3× |
| **Pan** | where in the camera's picture that crop sits | the crop's own travel |
| **Size** | the tile, as a multiple of the preset's | 0.5×–2× |
| **Position** | the tile, by dragging it in the STREAM preview | clamped inside the frame |

**Dragging happens in the STREAM preview, not on a pair of number fields.**
That is the whole reason the preview exists (§D5): the host is looking at what
the audience sees, and moving the tile there is direct manipulation of the
thing itself. Numbers would be a second description of a picture that is
already on screen.

**Zoom applies in every layout; size and position only where the camera is a
TILE.** In `host` the camera is the ground, so there is no tile to move — and
zoom is the control that matters most there, because a full-frame webcam is
exactly where "crop to my face" earns its keep. The controls that do not apply
are disabled with that sentence, never hidden.

**The CROP is not per-layout** — a host who framed their face does not want it
undone by trying "Side by side". The TILE is, and §D14a says why. *(This
paragraph is superseded by §D14a in every other respect; it is left as written
because these sections are append-only.)*

## §D14a — CORRECTION: framing is DIRECT MANIPULATION, not sliders

*Same day. Owner, on §D14's first implementation: "I think the crop is pretty
clumsy. Most people expect to crop the video frame (size and shape of the
actual video tile) rather than zoom and move. I like the ability to zoom the
video within the frame and move it around the frame, but it is clunky
implementation with four different sliders. Can you research/consult a macos
design pattern for cropping, zooming, and moving video around a preview screen
(surely, OBS has a way to do this as well that could be emulated or improved
upon)."*

**What §D14 got wrong.** It modelled the tile as the preset's rectangle
SCALED, which can only ever make that rectangle bigger or smaller. Cropping a
camera means changing its SHAPE, and a scale cannot. So the one thing the
owner asked for — "only capture my face" — was the one thing four sliders
could not do, and the zoom was standing in for it.

**OBS is the pattern, and it is the one hosts already know**
(obsproject.com/kb/sources-guide): drag a source INSIDE the canvas to move it,
drag a CORNER handle to resize it keeping proportions, drag a SIDE handle to
stretch it, and hold Option while dragging a handle to CROP — OBS turns the
cropped edges green. Precision lives in a separate Edit Transform dialog
(⌘E), not on the canvas.

**What we take, and the one place we improve on it.** We take the handles, the
drag-to-move, and the corner-versus-side split. We do NOT need OBS's separate
Option-drag crop mode, and that is not laziness: our tile is aspect-FILLED, so
reshaping the box IS the crop. A 16:9 webcam in a tall narrow box shows a tall
narrow slice of the host, which is exactly what "crop to my face" asks for.
One gesture where OBS has two, and no modifier key to discover.

The binding set, all of it in the STREAM preview:

| gesture | what it does |
|---|---|
| drag inside the box | move the tile |
| drag a corner | resize, proportions kept |
| **drag an edge** | **reshape — and that is the crop** |
| scroll inside the box | zoom the source within the tile |
| hold ⌥ and drag inside | pan that zoom |

**No sliders, and the numbers are SHOWN rather than typed.** OBS pairs its
canvas with Edit Transform for precision; a watch-along needs to know the crop
it is at far more than it needs to type one, so the Inputs column carries a
readout (`tile 35% x 72% · zoom 1.5x`) and a Reset, and no other control.

**Choosing a placement RESETS the tile and keeps the crop.** The first draft
of this rule said framing "is not per-layout" full stop, and that is right
about the crop and wrong about the tile: deciding where the tile goes is the
placement's entire job, so a custom rect surviving the change would make the
picker look broken. So switching placement clears `tile` and keeps `zoom` and
the pan — a host who framed their face keeps that face, and a host who asks
for "Side by side" gets it.

**The handles sit on the rect the ENGINE composited**, published in
`StudioHealth.cameraTile` — never on a re-derivation of the layout inside the
view. Two descriptions of one picture is the defect Decision 133 exists for,
and a handle drawn 40 px from the thing it moves is the visible form of it.

**Two implementation facts that cost a run each**, written down because both
look wrong until you know them:

- **`.offset` is a render transform, not layout.** The `NSView` behind an
  offset SwiftUI view stays where it was laid out, so a scroll-catcher backing
  the box reported the pane's top-left corner as its own frame. `.position`
  is the layout modifier, and it must come AFTER the size and BEFORE anything
  that needs the sized view backed.
- **AppKit will not deliver `scrollWheel` to a sibling.** It dispatches to
  `hitTest`'s view and then up ITS responder chain; a representable in
  `.background` is a sibling of SwiftUI's hosting view and is never on that
  chain. Moving it to `.overlay` only swaps the problem for a dead drag
  gesture. A local `NSEvent` monitor sees the event first and can still ask
  "is the pointer over me" by converting its own bounds to the screen.

## §D15 — The lower third's lines are the host's to choose

Owner: *"you should be able to choose the information that shows up on the
lower third."*

The lower third carries three lines — the film's **title**, its **year ·
director**, and the **provenance** ("Public domain — published 1920, before
1930"). Until now one toggle drew all three or none.

Each line is its own toggle. What a host may choose is WHICH OF THE
CATALOGUE'S OWN VERIFIED FACTS to show — never to retype them. §2.1's argument
is that the audience learns what the film IS, and a free-text title over a
public-domain film is how an audience learns something false.

**The provenance line keeps its 20-second expiry, and that expiry still
belongs to a real broadcast.** Owner, asked: *"I think it is fine to leave it
as only expiring on a 'live stream', but it should be able to be manipulated
as a part of the lower third."* So `expireProvenanceIfDue` stays gated on
`showState == .live` — a rehearsal is not an audience and has no 20 seconds to
count — and the toggle is the host's override in both directions: off means
never drawn, on means drawn until §4's rule takes it away.

## §D15a — The microphone may be GATED, and a closed gate says so

*Roadmap #4, built 2026-09-22. This extends §D3 and does not weaken §D0.*

A Watch Together host is in a room with the film playing out of speakers, and
their open microphone is picking it up — so the broadcast carries the film
TWICE: once from the tap at full quality, and once as a room-reverb copy a few
milliseconds late. That is a comb filter on the thing the audience came for,
and no fader fixes it, because turning the microphone down turns the HOST down
with it. The two are separable in LEVEL, not in frequency: a host speaking is
far louder at the microphone than speakers across a room.

**This is not §D0's "filters and effects".** That refusal is about chroma key,
color correction and LUTs — a production rack on a watch-along. A gate is one
input made usable, and the distinction is that without it the microphone
channel actively damages the program.

**Binding**:

- **OFF by default.** A host who has never had a gate must not discover their
  quiet asides being cut. Rule 8.8c's "manual means manual" applies here
  exactly as it does to the duck.
- **The meter stays RAW.** A meter showing the gated level sits at zero while
  the microphone is plainly working, which is how a host concludes their
  microphone is broken. The honest pair is two facts: *your microphone hears
  this much*, and *none of it is being sent*. So the gate's state is drawn
  beside the meter, never instead of it.
- **A gated microphone does not duck the film.** Without this, bleed the gate
  is busy rejecting still reads as "the host is talking" and pulls the
  soundtrack down 12 dB for the whole show — the gate would fix the echo and
  introduce something worse.
- **The rule is a value type** (`MicGate`), testable with no ring, no encoder
  and no clock — the shape `CameraStallRecovery` already uses. §8.38 asserts
  the three things that separate a gate that helps from one that hurts: it
  opens within ~23 ms so the first syllable survives, it reaches ACTUAL zero
  rather than settling on a quiet copy of the room, and it does not chatter on
  a level sitting at the threshold. That last one carries a control showing
  the same signal flipping 95 times without hysteresis.

## §D19 — NEXT: the one place the preview may diverge, and it says so out loud

*Roadmap #5, OBS's Studio Mode reduced to the one thing worth staging here.*

§D5 is emphatic that the preview IS the program — fed from the engine's own
buffer so "what I see" and "what they see" cannot diverge, which is the
failure Decision 133 is entirely about. **This rule deliberately introduces a
second picture that is NOT going out**, so it has to earn that and be
impossible to mistake.

**What it earns.** A host composing a card mid-show is writing words the
audience will read, and today they write them blind: the editor is four text
fields, and the only way to see the result is to put it on air. "Back in five
— the projectionist needs a minute" is a sentence you want to look at before
five hundred people do.

**Why only a CARD.** OBS stages whole scenes because OBS has scenes. We have
four things (§D0), and of them:

| | staged? | why |
|---|---|---|
| a CARD | **yes** | composing takes time, and a half-typed card on air is the failure |
| a PLACEMENT | no | one decision a show, and §D14a made framing a drag you watch live |
| the FILM | no | it is the show; there is no "next film" in a watch-along |
| the LOWER THIRD | no | it draws the catalog's own facts (§D15) — nothing to compose |

**Binding, and these are the guards that keep §D5 intact:**

- **NEXT is small, and labeled as not on air.** It is a thumbnail beside the
  controls, never a third pane the size of STREAM. A picture that big invites
  a host to watch the wrong one.
- **It is only drawn when something is staged.** No empty slot, no permanent
  second window, nothing to glance at by mistake.
- **TAKE is the only way it reaches the audience**, and taking it CLEARS the
  staging — so NEXT is never showing what is already out.
- **It renders through the SAME `StudioOverlayRenderer` the program uses**,
  at a smaller size. A second drawing path would be a second chance to differ
  from the thing it is previewing, which is the whole mistake §D5 forbids.

## §D16 — A film with no soundtrack SAYS SO, and a dead meter says why

Owner: *"I don't see any audio from the film coming through on the source or
preview."*

**Measured before it was explained.** Buster Keaton's *The Scarecrow* (1920)
through the product path: `AWMACAUDIO filmHasAudio=false sourceAudioTracks=0`.
The film has no audio track at all. Nothing was broken — and nothing on screen
said so, which is the defect.

This is not an edge case on this platform, it is the NORMAL case. The Studio's
rights gate is the `guaranteed` tier, which is "published before 1930", which
is silent cinema. A majority of what a Mac host can legally broadcast here has
either no soundtrack or a score that a particular transfer may not carry.

Two sentences the Studio owes a host, and §4's "health is never hidden" is the
rule both come from:

- **"This film has no soundtrack"**, on the Film channel and on the Film input
  row, whenever the asset reports no audio track. With the consequence
  attached, because the consequence is the point: *your voice is the only
  sound your audience will hear.*
- **"Levels appear once something is running"**, whenever the mixer is drawn
  with no engine behind it. Three faders with dead meters over a film that is
  visibly playing is a mixer that reads as broken, and a host has no way to
  know that the meters belong to the PROGRAM and the program has not started.

## §D17 — The panes are FILM and STREAM

Owner: *"'Program' doesn't make sense as a label. I think Stream or Preview
makes a lot more sense."*

"Program" is broadcast-gallery jargon, taken from OBS along with the split
itself (§D8). It names the right thing to someone who already runs a vision
mixer and nothing at all to anyone else, and this app's voice is plain words.

**FILM** (left) is the film, with its own transport. **STREAM** (right) is what
goes out. The badge continues to say whether it is actually being sent —
"going out", "nothing is being sent", "idle" — so "STREAM" naming the pane and
the badge naming its state are two different questions with two answers,
which is what stopped `isLive` and `isOnAir` being confused in §D6.

`StudioProgramMirror` and the engine's internal vocabulary keep the word
`program`: that is the composited frame, it is what the code has always called
it, and renaming a type to match a label is how a rename turns into a defect.

## §D18 — A channel that cannot be heard is NAMED, and a discarded status is a silent channel

Owner: *"I attempted to add 'a call' from the list and it appeared in the mixer
for a second and then disappeared. Are you sure we are capturing audio
correctly from those apps in the list?"*

**Two defects, and the first one is mine from the session that built it.**

1. **A race that removed the channel it had just added.** `stopCallAudio()`
   cleared the engine's ring inside an unstructured `Task {}`, and
   `startCallAudio` calls `stopCallAudio()` first. So the order was: enqueue
   "clear the ring", attach the new ring synchronously, return — and then the
   enqueued clear ran and took the channel away. The fader appeared for a tick
   and vanished, which is exactly what the owner saw. Both calls are
   synchronous now (`attachCallAudio` is `nonisolated`), so the order is the
   order they are written in.
2. **`AudioDeviceStart`'s status was discarded.** A tap that macOS refuses to
   start therefore reported success, and the Studio drew a channel that could
   never carry anything. That is precisely the "silent channel" §D2 forbids,
   in the one input whose TCC behavior SCRATCHPAD has listed as unmeasured
   since it was written.

**The rule**: every step of opening an input is checked, and an input that has
been open for **three seconds with zero frames** says so rather than showing a
still meter. A level of zero is a legitimate reading — a quiet room — but *no
samples at all* is not a level, it is an absence, and the two must not draw the
same.

## §D20 — Four columns: a graphic is not an input

The Studio's control row is **Inputs · Mixer · On screen · Output**, in that
order. "On screen" holds everything that decides what the audience SEES over
the film — the placement preset, the host's framing box, the lower-third
lines, the card, and the NEXT staging area. "Inputs" keeps only the sources:
the film, the camera, the microphone, a call.

**Why this is a rule and not a tidy-up.** The Studio shipped with three
columns, and graphics were filed under Inputs because they are configured
alongside the camera. On 2026-09-22 a screenshot of the running Studio —
taken to verify §D19 — showed what that costs: the Inputs column had run off
the bottom of the window at "Crop", with the lower-third toggles, the card
picker and the whole NEXT panel below the fold, while the Mixer column beside
it was **half empty**. A control was in the Studio and still could not be
found, which is a weaker form of the complaint that put the go-live checklist
here in the first place — *"I think I may have found it hidden behind a
button on the video player."*

A scroll bar is not an answer to that. It is reachable, not visible, and the
things below the fold are the ones a host reaches for DURING a show: an
intermission card is decided in the moment, not configured beforehand (§D19's
whole argument). The one control that must be one press away was the one
furthest down.

**And the split is meaningful, not merely a rebalance.** A camera is a
source; a lower third is a drawing. OBS draws exactly this line — Sources
against a separate Audio Mixer — and it is the line a host already thinks in:
*what am I sending in* versus *what does it look like*. Filing a text overlay
under "Inputs" is a claim that it is a kind of camera.

**How to apply.** A new Studio control goes in the column that answers its
question: does it choose a SOURCE (Inputs), set a LEVEL (Mixer), change what
the audience SEES (On screen), or decide where the show GOES (Output)? If a
control seems to belong in two, it is usually two controls. And when a column
reaches the bottom of the window on this Mac at the Studio's own minimum
size, that is a measurement, not an aesthetic complaint — take the screenshot
before deciding it is fine.

**Consequence.** The window's minimum width rises to 1120, because four
columns at 940 are narrower than the device pickers they hold. The panes
above (§D17) are unchanged: FILM and STREAM still split the top.

## §D21 — When the film stops reaching the program, the Studio says WHY

The Inputs row already shows the film's frame rate, and "no new frames" is a
true and useless sentence: it is the symptom. When the film produces nothing
for **three consecutive seconds** and has not simply ended, the Studio names
the cause underneath it, in one line, from what the PLAYER says —
`StudioFilmStall.reason(_:)`.

**Why.** On 2026-09-22 the Studio's program went black on two runs out of
eight while the FILM pane beside it played perfectly, and both runs were
silent about it: the logs of a healthy run and a black one were identical
line for line. The camera has had a stall detector with a named cause since
it drifted the same way (§D23's recovery). The film — the thing the audience
is actually there for — had none. A host would have watched their audience
receive a black frame with every readout on the screen reading normal.

**Why it asks the player rather than counting frames.** A counter can only say
that nothing arrived, and from there every cause looks identical: paused,
buffering, ended, a window rebuilt underneath the engine. That is §9.bbbbbb's
lesson from telling "ended" from "buffering", and the answer is the same one
— ask the object that knows.

**Why it is a pure function in its own file.** A five-branch sentence written
inline in the poll loop cannot be exercised without a running show and the
specific fault it describes, so in practice it never is, and the first time
anybody reads one of its sentences is the day something is already wrong.
Split out, §8.40 reaches every branch in milliseconds — including the ORDER,
which matters because the branches overlap: a player whose item has been
nilled also reports a rate of 0, so asking "is it paused" first would tell a
host they pressed pause when their window was rebuilt underneath them. Both
sentences are true; only one sends them to the right place.

**How to apply.** Add a cause by adding a fact to `Facts` and a branch in
order of how completely the thing is gone, and add its row to §8.40 — the
test asserts the reasons are DISTINCT, so a vague catch-all that swallows a
new case fails rather than passes. Do not make this sentence reassuring: the
fallback deliberately says the film is playing and no frames are arriving,
which is an admission that the Studio does not know.

**Still open**: the black-program fault itself is reproduced twice in eight
runs and has no signature. The identity diagnostics (`AWSURFACE register` /
`forget` / `engine attaching`, carrying the `AVPlayer`'s identity) and this
sentence are in place so the next occurrence names itself instead of being
argued about.

## §D22 — The host decides what the audience reads

Chat gets three controls in the Studio's **On screen** column, and they are
not optional extras: **whether it is shown**, **which side it sits on**, and
**what is filtered out of it**. `StudioChatFilter` decides what reaches the
program; `StudioControls.showChat` / `.chatSide` decide whether and where.

**Why this is a rule and not a nicety.** Until 2026-09-22 `overlay.showChat`
was assigned `true` in two places in the engine and by nothing else, the
column's side came only from the layout preset, and no message was ever
filtered. The owner, on seeing chat render for the first time: *"I don't see
any controls for the chat (turning it on or off, moving it on the screen,
filtering, etc.). Surely, that has to be a part of the feature, right?"*

It has to, and chat is the case where it matters most, because **chat is the
only text in this app written by strangers and the only text that is BURNED
INTO the video**. A platform's own chat overlay can be moderated after the
fact and a viewer can collapse it; a message we composite into H.264 is in
the recording forever, under the host's own account, on a broadcast whose
copyright risk §3.4a already asks them to accept. A host who cannot turn that
off, move it off someone's face, or drop the bot spam is not in control of
their own show.

**Why a SIDE and not a position.** The column has two hard neighbors — the
lower third beneath it and the camera tile — and `chatRect` already dodges
both per layout, including a sign error that once ran the column through the
host's face (§9, 2026-09-17). Free placement would re-open that by hand on
every preset. Left or right, with the layout choosing the default, keeps the
dodging computed and still answers "get it off my face".

**What filtering means here, and what it deliberately does not.** It drops
**commands** (a leading `!`, which on Twitch is mostly bots answering other
bots), **links**, and **named accounts** the host lists. It is NOT moderation
and must never be described as such: it cannot see what a platform's own
AutoMod already blocked, it does not judge language, and a host who needs a
person gone needs them gone from the platform, not from our overlay. The
filter is about clutter and about what gets burned in — say that, and do not
imply safety we cannot provide.

**How to apply.** The filter is a pure function over a line, in its own file,
for §D21's reason: a rule written inline in the pump can only be exercised by
a live broadcast with the specific traffic it describes, so in practice it
never is. §8.43 covers every rule and the interactions between them. Add a
rule by adding a case and a row; do not add one that needs to see a message's
history, because the pump hands the filter one line at a time and a stateful
filter there would be a second place for a leak.

## §D22a — No broadcast, no chat

The chat column is drawn only while the show is **actually on air**. A
rehearsal draws none, an idle Studio draws none, and the host's "Show chat"
toggle can only ever turn it off — turning it on does not conjure an audience.
`StudioEngine.pumpChat` checks `health.showState.isOnAir` every second, and
clears the column the moment a show comes off air.

**Why.** The owner, watching a rehearsal with chat in it: *"Shouldn't there be
no chat on a stream that isn't going anywhere and certainly isn't going to
twitch to get a chat from twitch?"*

Exactly so, and it is §D5's rule rather than a nicety: the preview must not
show the host something no viewer could see. A column over a show that is
going nowhere is precisely that, and it is the more dangerous direction — a
host rehearses to find out what their audience will get.

**How it happened, which is the part worth keeping.** `AW_STUDIO_CHAT` is a
debug door that joins a Twitch channel BY NAME, and reading Twitch needs no
credential. So a test of mine put a busy stranger's chat over the owner's
film, on a show with no destination, and the Studio drew it without objection
because nothing anywhere asked whether there was a broadcast. Two separate
wrongnesses — somebody else's audience, and no audience at all — and the
second one is the product's.

**And the same question exposed that Twitch chat had no product path.** All
three surfaces read the channel from `AW_STUDIO_CHAT` and nowhere else,
under a comment saying the channel would come from the host's account "once
sign-in exists". Sign-in had existed since 2026-09-18.
`StudioPlatformAuth.twitchAccount()` — the same read the readiness gate
already makes — returns the host's own login, and all three now use it.
YouTube could never have had this defect: its `liveChatId` comes back from
the `liveBroadcasts.insert` that CREATED the broadcast, so it cannot be
anyone else's.

**How to apply.** A chat source is attached to a SHOW, never to a surface.
When adding one, the channel must be derivable from the broadcast or the
signed-in account and from nothing else — if a surface has to be told which
channel to read, that is the defect, not the design. And say why the column is
empty (§D13's rule, Decision 128's shape): "your audience's chat appears once
you go live" is information; a permanently blank column is a fault report.

## §D23 — The call's picture is ONE window the host names, and the list is never recorded

Watch Together's third mode gets its guests' faces from
`SCContentFilter(desktopIndependentWindow:)`: the host picks the window their
call is already in, and that one window becomes a source. Sound still comes
from the process tap (§D18) and never from ScreenCaptureKit.

**MEASURED, on the product path, 2026-09-22**: a signed, sandboxed Archive
Watch got `start=true problem=none` and **82 frames in 4 seconds** on the
first attempt, with no prompt and no refusal. That closes the last of the
three TCC unknowns this feature carried, by the same method as the process tap
— run it in the app and print what macOS says, never reason from the docs.

**Sound is not captured here, and that is a rule rather than an omission.**
`SCStreamConfiguration.capturesAudio` is APP-level even behind a window
filter, so switching it on delivers the same audio the process tap already
has — the call would arrive twice, a moment apart, which is §D18's fault
exactly. Picture here, sound there.

**The Studio never captures its own window.** A Studio that captured the
Studio would composite its preview into the program, and the preview draws the
program: an infinite corridor, live, on somebody's channel. `windows()`
excludes our own bundle identifier before the list is built.

### The part the measurement taught, which is not about capture at all

Asking macOS what can be captured returns **the host's whole working day**.
The first run of this probe printed, into a log: a Slack DM naming a
colleague, a PDF from someone's Drive, two university admin pages. Nothing was
captured that the probe was not asked for — but it had been asked for
"Google Chrome" by substring and took the owner's real browser rather than the
isolated test instance beside it.

So, binding:

- **A window list is never logged, never written to disk, and never leaves the
  machine.** Diagnostics may count windows and name applications; a window
  TITLE is other people's business. Our own harness broke this rule first.
- **A window is chosen by the host, explicitly, every time.** The picker does
  not remember a choice across shows and does not pre-select one: a stale
  selection is how a host ends up broadcasting the window they had open last
  week rather than the call they are on.
- **Nothing selects a window on a substring or a "first match".** Our probe
  did, and captured the wrong browser. The host picks from a list, or the
  Studio refuses and says why.
- **The tile shows what is being sent, at all times**, like every other source
  in this Studio (§D5). A host must be able to see, without leaving the
  Studio, that they are sending the call and not their email.

### The sixth arrangement — BUILT 2026-09-22

`StudioLayout.guests`, "Film, you, and your guests": the film full-frame and a
right-hand column carrying the call directly above the host. The host's tile is
EXACTLY `corner`'s — same size, same position — so switching to this placement
moves nobody who was already framed, and the call arrives at the same width so
the two read as one column of people rather than two loose tiles.

The call's tile is DERIVED from the camera's rect, never computed beside it:
two derivations drift by a few pixels and stop reading as one thing. Its width
is fixed and its HEIGHT follows the captured window, because a host does not
choose the shape of their call app — and a window tall enough to run the
column off the frame is clamped away rather than allowed to overflow, since a
guest cropped by the frame edge looks like a fault.

**Proved through the product's own chain** — the menu's `startGuests`, not a
harness path — with `guestsAttached=true` read at the ENGINE and the tile seen
in the composited frame above the host's.

**Chat dodges BOTH tiles.** The first version guessed 16:9 for the call, with
a comment calling that "the safe direction". It is backwards: a wider window
makes a SHORTER tile, so the guess under-estimated a 4:3 call by 63 px and the
column landed on it. §8.42 caught it at the first non-16:9 shape it tried. The
real aspect is threaded through, and `nil` means no call is attached.

### What is not built yet

**A guest tile is not framable.** §D14's drag-and-crop box belongs to the
host's camera; the call's tile is placed by the layout and cannot be moved,
resized or cropped. That is probably right — the host frames THEMSELVES, and a
call window is already a grid somebody else's app arranged — but it is a
decision nobody has made deliberately, so it is written here rather than
implied by its absence.

**Amends Rule 8.8e.** That rule named five placements; there are six, and the
sixth is the first with a third picture in it. PARITY's "what Watch Together
MEANS" table carries the row.

## §D12a — A view being rebuilt is not a window being closed

`PlayerSurface.teardown()` releases its `AVPlayer` only when no live show is
reading it (`StudioSession.engineIsUsing(_:)`). When a show is live the player
outlives the surface and `StudioSession.end()` releases it instead — and only
when the surface is already gone, so a show that ends while the film is still
on screen leaves it playing.

**Why.** §D12 fixed the owner's report that a film kept playing with nothing
left to stop it, by having a departing surface stop its player. That is right
when a WINDOW closes. It is wrong when SwiftUI merely rebuilds the view: the
engine may be holding that exact `AVPlayer`, and `replaceCurrentItem(with:
nil)` leaves the compositor pulling from a player with no item. **The
programme goes black while the FILM pane, the camera, the meters and the
health line all stay correct** — which is why the logs of a black run and a
healthy one were identical, line for line.

It reproduced twice in eight runs on 2026-09-22 and then not at all in six
more. That is the signature of a timing-dependent rebuild, and it is the kind
of defect a source invariant catches and a run does not — §8.45 holds the
shape, and fails when the unconditional teardown is put back.

**How to apply.** Before releasing any resource a surface owns, ask whether
something longer-lived is using it. The two lifetimes here are a VIEW's and a
SHOW's, and they are not the same: a view is rebuilt for reasons that have
nothing to do with the broadcast. When the two disagree, the show wins and
whatever ends the show cleans up.

**And `forgetSurfacePlayer` had been printing the answer all along.** It logs
`engineHolds=YES` in exactly this case; it just did nothing with it. A
diagnostic that names a condition nobody acts on is half a fix.

## §D23a — Going live builds a second engine, and everything must survive it

A rehearsal ends before a broadcast begins, so pressing Go Live tears down one
`StudioEngine` and builds another. Every value a host set up during the
rehearsal must be re-applied to the new engine, in **one place** —
`StudioSession.attachIfArmed` — never remembered by each caller.

**Why it is a rule and not a note.** On 2026-09-22 the call's picture was not
in that list. A host who picked their Zoom window during the preview and
pressed Go Live would have dropped their guests **silently**: the picker still
named the window, ScreenCaptureKit was still capturing it, `guestProblem` was
still nil, and the tile was simply absent from the broadcast. `armedChat`, two
lines above it in the same function, had already had the identical fix a few
hours earlier — which is the whole argument for the list being mechanical.

**How to apply.** Add the value to `attachIfArmed`, and let §8.46 hold you to
it: every `armedX` on `StudioSession` must appear there or be named in the
test's exemption list **with the reason** it does not belong (there are two,
and both are real). A live object like the screen source has no `armedX` name
for the check to find, so it gets its own assertion.

**And the reverse question is not symmetric.** `end()` must NOT stop the
screen capture, because going live calls it — so capture is stopped where the
show unambiguously ends, which is the Studio window closing (§D12). A window
capture that outlived its Studio would be this app quietly reading somebody's
screen with nothing on screen to say so.

## §D24 — A guest tile is framed exactly as the host's own is

The call's tile gets §D14's direct manipulation in full: drag inside to move,
a corner to resize, an edge to reshape (which is the crop, because the tile is
aspect-filled), scroll to zoom the source, ⌥-drag to pan it. Same gestures,
same handles, same readout as the host's camera.

**Why this reverses §D23's "not built yet".** That section said a guest tile
was placed by the layout and argued the host frames only themselves, since a
call window "is already a grid somebody else's app arranged". The owner:
*"we need to be able to move and crop the 'guest window' in the same way you
can manipulate the camera for your own video."*

They are right, and the reasoning I had written is wrong in a way worth
naming: a call window is *more* in need of cropping than a webcam, not less.
Zoom and Meet put chrome around the grid — a toolbar, a participant strip, a
title bar — and a host who captures that window is broadcasting somebody's
furniture along with their guests. The camera's crop exists to remove a room;
the guest tile's crop exists to remove an interface, which is the more
predictable need of the two.

**How to apply.** `StudioCameraFraming` is already a normalized tile rect plus
zoom and pan and is not camera-specific; the guest tile takes a second
instance of the same value type rather than a parallel one. The selection
model in `StudioTileHandles_macOS` draws one box at a time, so the STREAM
preview needs a way to say WHICH tile is being framed — a picker above the
framing controls, not two sets of handles at once, which would make a drag
ambiguous wherever the tiles overlap.

**And the placement's own rect stays the anchor.** §D23 derives the guest tile
from the camera's so the two read as one column. Framing displaces the host's
tile from that anchor today and must do the same for the guest's: the
arrangement decides where a tile starts, the host decides where it ends up.

## §D25 — One call is one choice

Choosing the window a call is in also taps that call's audio. A host picks
"Zoom" once and gets their guests' faces and their guests' voices; they do not
pick Zoom twice in two different columns.

**Why.** Until 2026-09-23 the Studio had two independent pickers for one
thing: "A call" under Inputs (audio, via `AudioHardwareCreateProcessTap`) and
"Show your guests" (picture, via ScreenCaptureKit). A host who picked the
window got faces and **no voices**, and the mixer showed no call channel at
all — because that channel is gated on the audio tap, which nothing had
started. The owner, on seeing exactly that: *"the mixer should have audio from
the call to be able to determine the levels for the other people talking on
the call."*

Two pickers for one call is the same defect class as a control whose value
never lands (Decision 133): everything reads correct in isolation, and the
product does half of what the host asked for.

**How to apply.** `startGuests` resolves the window's owning application and
starts the audio tap for that process, and `stopGuests` stops both. The audio
picker stays, because the two are not always the same thing — a host may be on
a phone call while sharing a slide — but it is now the exception rather than
the price of admission. When the window's app cannot be tapped, the picture
still runs and `callProblem` says why (§D18): half a call is better than a
refusal, as long as the half that is missing is named.

## §D26 — The audience can reach the screen

A host can take a message out of the chat column and put it **on the
broadcast**, large, over the film, attributed to the person who wrote it. It
sits above the lower third, holds for twelve seconds, and clears itself.

**Why this rule exists, and why it is the most important one in Part D.** On
2026-09-23 the owner said the Studio *"doesn't fulfill the promise of live
streaming a public domain movie with your friends ... It must also be designed
well and create genuine opportunities for connection for all involved."*

Auditing against that sentence found something the feature list hides:
**everything the Studio can put on screen comes from the host.** Starting
soon, Intermission, Thanks for watching, the host's own words, the host's
face, the host's guests. Chat arrives and is *displayed* — a column of small
type the audience cannot tell is being read. Nothing an audience member does
can reach the program. A person watching has no evidence they were heard.

That is not a missing feature; it is the difference between a broadcast and a
room. "Watching together" is the product's own claim, and one-directional is
the opposite of together.

**Why a BANNER and not a card.** §D10 settles that a card covers the film
completely and the audience sees only the card. A shout-out must not do that:
the film is what everyone came for, and stopping it to show a comment makes
the comment an interruption rather than an acknowledgment. The banner sits
over the film with the film still running, which is exactly the relationship
the moment has.

**Why it clears itself.** A message left up becomes furniture, and the next
person's message has to wait for a host who is watching a film. Twelve seconds
is long enough to read a sentence aloud and respond to it, which is what a
host does with it.

**Why the ATTRIBUTION is not optional.** The point is that a particular person
was heard. A message on screen without a name is content; with a name it is an
acknowledgment, and the person watching knows it was theirs.

**How to apply.** One at a time — a queue would turn a human moment into a
ticker. It is drawn by the program's own `StudioOverlayRenderer` (§D19's
rule), so what the host previews is what the audience gets. And it is never
automatic: a host chooses to acknowledge someone, and an algorithm choosing
for them would be picking whose words matter.

### §D26a — The AUDIENCE pane, and why it is not the chat column

This rule first said the host "picks from the chat they can already see, so
there is no second list to keep." **That was wrong, and building it showed
why.** The chat a host can see is the one composited into the STREAM preview:
eight lines because eight is what fits beside a film, obedient to the host's
*Show chat* switch, and made of pixels nobody can click. It is what the
AUDIENCE sees. A host needs something else — more lines, kept whether or not
any are being shown to anybody, and clickable.

So the Studio has a third pane beside FILM and STREAM: **AUDIENCE**. It
carries forty recent lines, newest last, post-filter — a host may not elevate
a message they have already told the program to hide. Clicking **Show** (or
double-clicking the row) puts it on the broadcast; what is on air appears at
the top of the pane with **Take down** beside it, and disappears by itself
when the twelve seconds are up.

**It appears when a broadcast does**, and not before. Chat comes from YouTube
and Twitch, so during setup this pane would be an empty box explaining
itself — the noise the owner's caption rule is about. The chat controls in
*On screen* already say "Appears once you go live."

**CHAT YIELDS TO THE BANNER; the banner does not cover chat.** The lower
third sitting over the chat column is deliberate — a long message must never
hide the film's own title. Applying the same rule to a shout-out put it
straight through the last two lines the host had been reading, because a
banner is tall and arrives mid-conversation. The column moves up for the
twelve seconds one is up, and drops away entirely if what is left is too
short to read. Only on the left: the banner is anchored to the lower third's
5% inset, so a right-hand column never meets it.

**THE NAME IS DRAWN IN THE CASE ITS OWNER TYPED.** Every other uppercase run
in the overlay is a label we wrote — "PUBLIC DOMAIN — PUBLISHED 1923" is ours
to style. A viewer's handle is not, and `crazyspecz` rendered as `CRAZYSPECZ`
is the small version of getting somebody's name wrong on the one graphic that
exists to name them. This is the same rule as the catalog's: a string that is
somebody else's data is spelled the way they spell it.

**A message too long to draw is SHOWN and REFUSED, never truncated.** Twitch
allows 500 characters, which wraps to seven lines and covers the film. The
row stays in the reader — a host should see everything the audience said —
carries "too long to show", and offers no button. Cutting a stranger's
sentence in half and putting their name under the remainder is worse than
declining to show it. The ceiling is four lines
(`ShoutOut.maxCharacters`), and §8.48 checks that guess against the
renderer's own wrapping rather than letting the two drift.

**Two cache keys were wrong in the same morning, in the same way.** The lower
third's named the title, year and provenance and not the shout-out, so a
banner could never appear and, once up, could never expire. The chat
column's named its x and WIDTH and not its height, so the shortened column
was drawn at its old size and the banner went on covering `kt_projects`
however correctly the rect was computed. **A cache key that names some of its
inputs is a cache that is wrong about the rest** — and neither defect is
visible to a harness that builds a fresh renderer per call, which is what
§8.48 did until it was made to reuse one.

## §D27 — The host knows how many people are watching, and the broadcast is a conversation

The AUDIENCE pane's header carries **"N watching"**, from the platform's own
report (`videos.list` `liveStreamingDetails.concurrentViewers` on YouTube,
helix `streams.viewer_count` on Twitch), read every 30 seconds. It is absent
until the platform reports a live stream, never a zero we assumed. And every
YouTube broadcast is created at **`latencyPreference: low`**, with DVR, the
recording and embedding stated rather than left to defaults.

**Why.** Most of an audience never types. Before this, nothing anywhere in the
Studio, on any platform, knew who was watching: a host talking over a film
into silence could not tell a room of twelve from an empty one, and the
difference changes what a host says. Separately, YouTube's unstated default
latency is `normal`, 15-30 s behind the host, so a viewer's chat answered a
picture the host had seen half a minute earlier. A watch-along is a
conversation, and that delay is the gap between a remark and its reply. `low`
rather than `ultraLow`, because ultra-low gives up captions.

**How to apply.** The count is the HOST's. It is not composited onto the
broadcast: a small audience displayed to itself is a reason to leave, and
whether to show it is a choice nobody has asked for. The poller is started by
`armBroadcast` and stopped by `completeArmedBroadcast`, because those are the
two calls every platform's go-live and End already make (Decision 133). A
read that fails is "not reported", and the badge disappears rather than
guessing. The quota budget is 240 units for a two-hour film against 10,000 a
day.

**Both halves are done from what we already hold.** Everything above sits
inside the `auth/youtube` scope under Google verification and the three
Twitch scopes hosts have already granted. Anything that would widen a scope
(posting in chat, polls, announcements) is a separate decision, because a new
Google scope means a new demo video and a new review.

## §D28 — The STREAM header is the host's status bar

While on air the STREAM header reads **● LIVE 1:11 · 2.4 Mbps**, adding
**N dropped** and **reconnecting** only when true. The clock starts when the
server ACCEPTS the stream (`publisher.state == .publishing`), not when Go Live
is pressed, and a reconnect does not restart it. The rate is what left the Mac
in the last second, from the publisher's byte counter, never the configured
target. Before the server accepts, it reads "connecting".

**Why.** The header used to say "going out" and nothing else, while OBS's
status bar tells a host exactly these three things. How long they have been
live is the first thing a host needs mid-show (to pace an intermission, to
know when the film started for latecomers), and it was nowhere on screen; the
only live status sat half-way down the Output column. The ACTUAL rate matters
because the encoder delivers ~70-75% of what it is asked (WATCH-TOGETHER §9),
so a configured "6 Mbps" is a number the audience never receives.

**How to apply.** Nothing is added here that is not true right now; a
dropped-frame count of zero is not shown, because a zero is not information.

## §D29 — STREAM starts as the largest pane

The stage opens with STREAM widest (ideal 680 pt, layout priority 1), FILM
narrower (420 pt), AUDIENCE beside them. The host can still drag the dividers.

**Why.** §D8 gave FILM and STREAM equal ideal widths, and once §D26's
AUDIENCE pane appeared the split took its room from STREAM, so the picture the
audience actually gets was the smallest on screen: chat lines, the lower
third and the camera tile's handles were all being read and dragged at
thumbnail size. The film is FOLLOWED in its pane; the stream is INSPECTED.
**This does not amend §B13h's 0-10 fader**, which a first look at the mixer's
"8.0" was about to: that scale is the owner's own (2026-09-20).

## §D30 — A card is a chapter on the replay

On Twitch, each card change places a stream marker on the VOD: "Starting
soon", "The film begins" (when it comes down), "Intermission", "Back from
intermission", "Thanks for watching", or a custom card's first line. Only
while publishing; kinds are compared, never values, so the Starting-soon
countdown does not mark every second. YouTube gets none: its `cuepoints` are
ad breaks, not chapters.

**Why.** The owner asked for "genuine opportunities for connection for all
involved", and the people a live show does not reach are the ones who come
later. A two-hour watch-along with no chapters is a replay nobody navigates;
the moments a host already marks with a card are exactly the ones a latecomer
wants to find. It uses `channel:manage:broadcast`, which every Twitch host has
already granted, so it costs nobody a re-consent.

**How to apply.** The engine names no session type: it publishes moments to
`StudioMoments.sink` and `StudioSession` subscribes, because the §8 harnesses
compile the engine without the session. Every platform's cards pass through
`StudioEngine.setOverlay`, so macOS, iOS and tvOS all mark. A refusal (VOD
storage off, not live yet) is logged as `AWMARKER not placed` and never
retried. NOT yet placed against a real Twitch channel.

## §D31 — Scenes: every part customizable, and each scene chooses what it inherits

A **scene** is a named, saved setup of everything the audience sees and
hears. A host builds as many as they like, switches between them live, and
each one is **fully customizable**:

| Part | What it holds |
|---|---|
| Placement | the arrangement (film full-frame, you in the corner, side by side, guests up, …) |
| On screen | lower-third lines, chat on/off and side, the card |
| Tiles | the camera tile's box and crop, the guest tile's box and crop |
| Audio | film / microphone / call levels, mutes, the duck |

**Each scene carries two toggles — "Use the show's tiles" and "Use the
show's audio".** On (the default), that part follows the show-wide setting,
which is §D14a's rule exactly: the crop follows the person across every
scene that inherits it. Off, the scene keeps its own copy, seeded from the
show's values at the moment it is switched off, and editing it changes that
scene alone. Placement and On screen always belong to the scene; they are
what makes one scene different from another.

**Why.** Owner, 2026-09-23, asked whether a scene should move the camera tile
and carry the mix: *"Each scene should be fully customizable and you should
be able to say (with a setting/toggle) whether to keep the default audio/tiles
or build new ones for the scene."* It keeps §D14a for the host who wants their
framing fixed and gives OBS's per-scene freedom to the one who does not —
chosen per scene rather than once for the Studio.

**This amends §D14a** from a rule to a default: "the crop follows the person"
holds for every scene whose tiles are inherited.

**How to apply.**
- While a scene is selected, every control edits THAT scene. A control whose
  part is inherited edits the show-wide value, and says so with one word
  beside the section ("shared") — the only caption this rule adds, because
  otherwise a host changing the mic in one scene would not know they changed
  it in five.
- Switching: a row of scene buttons above STREAM, and ⌘1-⌘9 in the Broadcast
  menu (OBS's hotkeys). A short crossfade by default, a Cut option. A switch
  places a Twitch chapter marker (§D30) named for the scene.
- Scenes persist across shows; a host builds them once. Starter set: Starting
  soon, Film, Intermission, Discussion, Thanks — each an ordinary, editable
  scene.
- Going live starts in the selected scene. Rehearsal switches scenes exactly
  as a live show does (§D19: the preview never diverges silently).
- macOS first. iPhone later as a compact switcher. **Apple TV: none** — Rule
  8.8c keeps the television's live surface to "two channels, a rotation, and
  nothing else", and widening it is a separate owner decision.

## §D32 — The host can put the film itself in front of the audience

On a YouTube broadcast the AUDIENCE pane opens with **Share the film in
chat**: one line under the host's own name — "Now watching: The Man Who Laughs
— 1928 · Paul Leni. Public domain, free to watch: https://archive.org/details/…"
— and "shared 5 minutes ago" beside it afterwards, never a disabled button,
because the host may want to say it again for the people who arrived since.

**Why.** Everyone who arrives after the lower third has faded is watching a
film they cannot name, and the whole premise of this app is that the film is
theirs to find: free, public domain, one link away. Putting the link in chat
turns a stream into an invitation to go and watch, look further, keep going
after the show ends — which is the owner's "genuine opportunities for
connection for all involved" pointed at the archive rather than the host.

**How to apply.** Never automatic: a host decides when the room hears about
the film, exactly as they decide whose message is shown (§D26). YouTube's
limit is 200 characters and the LINK IS NEVER CUT (`StudioChatShare`, §8.52):
words give way first, then the title shortens. It costs 50 quota units a
post, inside `auth/youtube`. Twitch needs `user:write:chat`, a new scope every
host would have to re-consent to, so it is not offered there yet.
