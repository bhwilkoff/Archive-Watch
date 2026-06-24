# Creation Studio — multi-track re-architecture (research, diagnosis & plan)

Owner feedback 2026-06-24: Creation Studio is "nonfunctional… needs to function
with the full capabilities of macOS, not as if it is just an iPad app." This brief
roots-causes all 13 reported issues, synthesizes WWDC/macOS-26-27 API research
(two cited passes below), and lays out a phased rebuild into a genuine native
multi-track NLE. The save crash (#1) is already fixed; everything else is planned
here.

---

## The keystone finding

**Creation Studio is single-track by construction, and that one fact is the root
of issues #4, #10, #11 (and part of #3).** `Timeline` holds `clips: [TimelineClip]`
as ONE magnetic array; `textOverlays`, `musicBed`, and `voiceover` are separate
scalar/array properties, **not tracks**. There is no `Track` type anywhere.
`TimelineClip.track` is hard-coded to `0` at every call site and never read as a
lane. The timeline VIEW renders exactly one clip row. So overlays/music/voiceover
have nowhere to live on the timeline, can't be retimed independently, and audio is
invisible. **Introducing a real multi-track model is the keystone change** that
unblocks the title track (#4), audio tracks (#10), and overlapping/parallel video
(#11). Everything else is contained bugs on top.

---

## Diagnosis — the 13 issues, grouped by root cause

**A. Single-track model** (`CreationModels.swift` `Timeline`; `TimelineView_macOS`
one lane; `EditorModel.relayout` end-to-end on one array):
- **#4** text overlays have no timeline lane · **#10** music/voiceover have no lane ·
  **#11** no parallel/overlapping tracks. → Build a `Track` abstraction.

**B. Serial, retry-heavy clip caching** (`EditorModel.rebuildPreview` awaits each
clip serially; `ClipCache` does export-passthrough → full re-encode fallback ×3
with 1s backoff over a ±12s window):
- **#2** clips load only after a long wait (one slow clip blocks all behind it) ·
  **#9** opaque progress (single `isBuildingPreview` bool, 300ms-delayed, no count/
  ETA/failure reason) · **#13** one bad/degenerate cached asset poisons the single
  shared `AVPlayerItem`, so good clips won't play either. → Concurrent bounded
  caching + per-clip readiness + placeholders + build-from-ready-only.

**C. Library (SwiftData) vs timeline (document) split:**
- **#12** supercut adds straight to the timeline via `model.addClip(from:)` but
  never `ctx.insert(LibraryClip(...))`; the manual Add-Clip path does both. → Route
  all "add" through one helper that inserts into the Library too.

**D. `embedMedia` retrofitted onto the `ReferenceFileDocument` writer:**
- **#1 (FIXED)** mutating the borrowed `configuration.existingFile` + off-thread
  cache reads + duplicate `preferredFilename`. → Now builds a fresh wrapper.

**E. Thin placeholder browser/UI:**
- **#5** Add-Clip has NO facets/sort/color (data layer already supports
  `contentType/decade/genre/sort` + `isColor`/`isBlackAndWhite`/`runtimeSeconds`) ·
  **#6** stock cards show a malformed hyphenated tag token over the thumbnail +
  the same film repeated (synthesized placeholder windows, no dedup, bad
  tokenization) · **#8** supercut is opt-OUT (everything pre-checked) and Compose
  mode has no per-segment include/exclude. → Wire real facets; fix tag tokenize +
  dedup; make selection opt-in + per-segment.

**F. Under-scaled stock pipeline** (`build_stock_index.py` 60 films/run, single
runner, no sharding; in-app usually shows a synthesized SAMPLE):
- **#7** DB is tiny. → Shard across runners (whisper/cover precedent), raise limit,
  run more often; stop shipping the misleading sample as primary.

**G. Text-overlay drag math** (`TextOverlayPreview` gesture reads coordinates in the
auto-sized `Text`'s space, not the video rect; inspector only has a 3-value Y
preset, no X):
- **#3** overlays don't move by drag or by the position control. → Fix the
  coordinate space + add continuous X/Y (normalized 0…1) controls.

---

## Research findings (WWDC / macOS 26-27 — cited)

Full briefs: see the two research passes appended to this session. Load-bearing
facts:

### Multi-track AVFoundation engine
- **One model → one `(AVMutableComposition, AVVideoComposition, AVMutableAudioMix)`
  triple → BOTH preview (`AVPlayerItem`) and export (`AVAssetExportSession`).**
  Preview == export because the inputs are identical. ([Apple — Editing](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html))
- **N video + M audio composition tracks.** Overlapping video layers composite by
  the **array order of layer instructions** within each instruction (first = on
  top); per-layer transform/opacity/crop ramps drive PiP, fades, wipes. ([Apple — AVVideoComposition](https://developer.apple.com/documentation/avfoundation/avvideocomposition))
- **macOS 26 deprecates the mutable composition/instruction/layer-instruction
  classes** in favor of the **Configuration value types**
  (`AVVideoComposition.Configuration` + `…Instruction.Configuration` +
  `…LayerInstruction.Configuration`) — the same migration the iOS engine already
  did. ([dotnet/macios Xcode-26 diff](https://github.com/dotnet/macios/wiki/AVFoundation-iOS-xcode26.0-b4))
- **Per-track audio mix:** one `AVMutableAudioMixInputParameters` per audio track,
  with volume ramps → music-bed ducking under voiceover. ([Apple — AVMutableAudioMixInputParameters](https://developer.apple.com/documentation/avfoundation/avmutableaudiomixinputparameters))
- **Titles as a track:** live SwiftUI/AppKit overlay (or `AVSynchronizedLayer`) for
  EDITING; `AVVideoCompositionCoreAnimationTool` (CALayer, EXPORT-only) for burn-in.
  The two-pass grade→overlay constraint still binds (a CIFilter handler and the
  CoreAnimation tool can't share one video composition). ([Apple — CoreAnimationTool](https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool))

### Robust remote-asset loading (the #2/#13 fix)
- A remote/slow `AVURLAsset` whose properties aren't loaded **blocks** when the
  composition touches them — stalling preview of OTHER ready clips. Use async
  `load(.tracks,.duration)` / observe `AVPlayerItem.status`+`.error`; **never touch
  an unloaded property synchronously.** ([Apple — AVAsynchronousKeyValueLoading](https://developer.apple.com/documentation/avfoundation/avasynchronouskeyvalueloading))
- **Cache-then-edit (non-negotiable):** pre-fetch only the in/out byte range to a
  local faststart MP4 before composing; `AVAssetExportSession` reliably fails on
  remote inputs (`-11800`/`-16974`). Reuse `ResilientStreamLoader`.
- **Per-clip readiness + placeholders:** model each clip `pending → downloading(bytes)
  → ready(localURL) → failed(error)`; compose from ONLY ready clips, substitute a
  gap/placeholder for the rest; hot-swap when ready. One slow/failed clip then never
  blocks the timeline. Surface bytes + state + failure reason to the UI.

### Document / save crash-safety (the #1 fix + future)
- `ReferenceFileDocument` **saves on the main thread in practice** (beachballs on
  big saves) and trips Swift-6 races on the snapshot→fileWrapper boundary. **Never
  mutate `configuration.existingFile`**; never read `self`/the model/SwiftData in
  `fileWrapper()` — only the `Sendable` snapshot. Key package children on stable
  unique IDs (duplicate `preferredFilename` silently rewrites the key). ([Eclectic Light](https://eclecticlight.co/2024/05/16/swiftui-on-macos-documents/), [Apple — FileWrappers](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileWrappers/FileWrappers.html))
- For a package document with external media refs + atomic/coordinated save +
  security-scoped bookmarks, **migrate to `NSDocument`** (SwiftUI document protocols
  are "terribly limited" for this). ([Christian Tietze, 2025](https://christiantietze.de/posts/2025/07/swiftui-documentgroups-limited/))

### Multi-track timeline UI + audio + windowing (the "iPad app" fix)
- **AppKit `NSScrollView` + layer-backed `NSView`/`CALayer` document view** is the
  proven substrate: built-in `magnification` (pinch-zoom), GPU rendering of many
  clips/waveforms, precise per-element hit-testing — bridged via `NSViewRepresentable`.
  SwiftUI per-view-per-clip degrades. ([Apple — NSScrollView.magnification](https://developer.apple.com/documentation/appkit/nsscrollview/1403497-magnification))
- **Voiceover:** `AVAudioEngine` (input tap → file + live monitoring) beats
  `AVAudioRecorder`. macOS mic needs BOTH `NSMicrophoneUsageDescription` + a
  `requestAccess(for:.audio)` call AND the sandbox entitlement
  **`com.apple.security.device.microphone`** (+ `…device.audio-input`) — missing the
  entitlement makes TCC **silently deny** (the "record does nothing" symptom, #10).
  ([Apple — capture authorization](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/requesting_authorization_for_media_capture_on_macos), [Apple — audio-input entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.audio-input))
- **Native Mac idioms:** Library + Document + Render-Queue scenes (`WindowGroup` /
  `DocumentGroup` / `Window`); `.inspector` (not slide-overs); `.commands`
  (`CommandMenu`/`CommandGroup` + `.keyboardShortcut` — Razor/Add Edit/Markers); a
  unified customizable `.toolbar`. Their absence is most of the "iPad feel."

---

## The re-architecture (what to build)

### 1. Multi-track model (keystone)
A `Track` type with a `kind` (`.video`, `.title`, `.audio`) and an ordered
`[TimelineItem]`; `Timeline` becomes `tracks: [Track]` (default: one video track;
add title/audio tracks on demand). `TimelineClip` gains a real `trackID`.
`relayout` becomes per-track (clips no longer forced end-to-end across one lane;
parallel/overlapping items become representable). `CompositionBuilder` maps model
tracks → composition tracks (video layers z-ordered by track order; audio tracks
each get audio-mix params). Migration: decode old single-array projects into one
video track (additive/tolerant, like every prior schema bump).

### 2. Multi-track timeline UI
Render N lanes (video / titles / audio), each with draggable, independently-retimed
blocks. Start in SwiftUI for the lane stack; **budget the AppKit `NSScrollView`+
`CALayer` timeline** (magnification, waveforms, hit-testing) as the scale path
(de-risk spike). Text overlays + music + voiceover appear as blocks on their lanes
(fixes the "no track appears" half of #4/#10).

### 3. Loading overhaul (per-clip readiness)
Bounded-concurrency `TaskGroup` caching (2–3 at once, not serial); per-clip state
`pending/downloading(bytes,total)/ready/failed(reason)`; compose from ready clips
with placeholders for the rest; validate each cached window (duration>0, readable
video track) before insert so a degenerate asset can't poison the player item;
surface a clear status panel ("3 of 7 ready · caching 'Title' · 1 failed: reason").

### 4. Text-overlay drag + title track
Fix the gesture coordinate space (drag in the video-rect space; store normalized
0…1 position); add continuous X/Y controls; always render the selected overlay
while editing; show titles as blocks on the title track.

### 5. Audio (music + voiceover)
Mic permission + entitlements + `requestAccess` before recording; `AVAudioEngine`
capture with monitoring + level meter; music/voiceover render as audio-track blocks
with volume + ducking; robust bed insertion regardless of start position; surface
failures (no silent `try?`).

### 6. Add-Clip browser + stock shots
Facet bar mirroring Browse (type/decade/genre chips + sort) + a color
(Color/B&W/Any) segmented control + a length sort. Fix stock tag tokenization
(discrete tags, hyphenate within a tag only) + render a clean chip (not a raw token
over the thumbnail); `GROUP BY archiveID` (dedup) + relevance ordering. Stop
shipping the synthesized sample as primary.

### 7. Stock pipeline scale (#7)
Shard `build_stock_index.py` across a runner matrix; raise the per-run limit; run
more frequently; CLIP-tag in lockstep.

### 8. Supercut UX
Opt-IN selection with obvious per-row checkboxes in Find mode; per-segment
include/exclude in Compose mode; route assembled clips through the shared "add to
Library + timeline" helper so they appear in the sidebar (#12).

### 9. Document hardening (#1 done; next)
Migrate the backbone to `NSDocument` for atomic/coordinated/background saves +
URL/bookmark access (removes the beachball + the whole class of save races).

### Learning gate (unchanged)
The supercut and stock surfaces still yield an EDITABLE timeline of candidates,
never a one-tap auto-cut (Decision 042 Rule 5a). The selection/checkbox work
(#8) actually *strengthens* this — the human curates which clips land.

---

## Proposed phasing

- **Phase A — Stop the bleeding (contained, no model change).** ✅ Save crash (#1);
  then supercut→Library (#12), stock tag-token + dedup + the malformed-tag-over-
  thumbnail bug (#6), Add-Clip facets/sort/color (#5), supercut opt-in checkboxes
  (#8), and a clear loading/status panel (#9). High user-visible relief, low risk.
- **Phase B — Loading overhaul (#2/#13).** Concurrent bounded caching, per-clip
  readiness, build-from-ready + placeholders, asset validation. Makes playback
  trustworthy.
- **Phase C — Multi-track keystone (#4/#10/#11).** `Track` model + migration +
  multi-lane timeline UI + CompositionBuilder track mapping; text overlays + audio
  as real lanes; fix overlay drag (#3); wire mic permission/entitlements + working
  voiceover/music (#10).
- **Phase D — Native-Mac polish + scale.** AppKit `NSScrollView`/`CALayer` timeline
  (magnification, waveforms), `.commands` menu + shortcuts, `.inspector`,
  render-queue window; `NSDocument` migration; stock-pipeline sharding (#7).

Phase A is mostly mechanical and ships fast; B and C are the substance; D is the
"truly native Mac editor" finish. Recommend A→B→C→D, each build-verified.
