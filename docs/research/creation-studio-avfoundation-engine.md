# Creation Studio — native macOS AVFoundation engine (research)

*Date: 2026-06-22. Target: macOS 15 (Sequoia) / macOS 26, Apple Silicon. Swift 6 /
SwiftUI. Apple frameworks only inside the app; shelling out to `ffmpeg`/CLI as a
subprocess is acceptable on Mac for heavy lifting.*

This brief covers the **engine** for a NEW native macOS app whose flagship is
**Creation Studio** — a full multi-clip timeline editor that composes clips drawn
from MANY different archive.org titles into ONE export. It is the macOS sibling of
the iOS "Clip Studio" single-clip engine (Decision 033), which already migrated to
the Configuration-based AVFoundation API. The hard constraint inherited from that
work: **the per-frame Core Image (CIFilter) handler and the CALayer overlay
(`AVVideoCompositionCoreAnimationTool`) cannot coexist in one `AVVideoComposition`
— a two-pass render is required.**

It maps onto Creation-Studio features **1 (multi-clip composition), 3 (timed
text/title overlays), 4 (audio mix + dub), 5 (export), and 10 (keyframing)**.

---

## 0. Vocabulary & the canonical 2024+ API surface

The legacy mutable classes (`AVMutableVideoComposition`,
`AVMutableVideoCompositionInstruction`, `AVMutableVideoCompositionLayerInstruction`,
the synchronous `AVVideoComposition(asset:applyingCIFiltersWithHandler:)`, and
`AVAssetExportSession.exportAsynchronously(completionHandler:)`) are **deprecated**
on the iOS 26 / macOS 26 SDKs. Use the **Configuration-based API** throughout —
same naming as the project's `docs/CREATE-STUDIO-PLAN.md` §5c:

| Concept | Modern type |
|---|---|
| Timeline container | `AVMutableComposition` (subclass of `AVComposition`, which is an `AVAsset`) |
| Per-track media slots | `AVMutableCompositionTrack` (one per `AVMediaType`) |
| Render recipe | `AVVideoComposition` via `AVVideoComposition.Configuration` (`renderSize`, `frameDuration`, `instructions`, `animationTool`, `colorPrimaries`, `perFrameHDRDisplayMetadataPolicy`) |
| Composition step | `AVVideoCompositionInstruction.Configuration` → `AVVideoCompositionInstruction(configuration:)` |
| Per-track op | `AVVideoCompositionLayerInstruction.Configuration(trackID:)` → `AVVideoCompositionLayerInstruction(configuration:)` (opacity, transform, crop + ramps) |
| Burned overlay | `AVVideoCompositionCoreAnimationTool.Configuration(postProcessingAsVideoLayer:containingLayer:)` → `init(configuration:)` |
| Per-frame Core Image | `async AVVideoComposition(applyingFiltersTo:applier:)`; applier is `(AVCIImageFilteringParameters) async throws -> AVCIImageFilteringResult` |
| Audio | `AVMutableAudioMix` + `AVMutableAudioMixInputParameters` |
| Export | `AVAssetExportSession` async `export(to:as:)` + `states(updateInterval:)` AsyncSequence |
| Custom render (Mac) | `AVVideoCompositing` protocol + `AVAssetReader`/`AVAssetWriter` for offline ProRes |

Always load asset properties async (`load(.tracks)`, `load(.duration)`,
`loadTracks(withMediaType:)`) — synchronous `asset.tracks` is deprecated and
blocks; remote `AVURLAsset`s make this mandatory.

---

## 1. Multi-clip composition (feature 1)

### The spine
`AVMutableComposition` is the timeline. It holds N `AVMutableCompositionTrack`s.
Each clip is added with:

```swift
let comp = AVMutableComposition()
let vTrack = comp.addMutableTrack(withMediaType: .video,
                                  preferredTrackID: kCMPersistentTrackID_Invalid)!
let srcV = try await sourceAsset.loadTracks(withMediaType: .video).first!
try vTrack.insertTimeRange(clipRange, of: srcV, at: timelineCursor)
```

`insertTimeRange(_:of:at:)` copies a *reference* to the source sample data into the
timeline at a cursor — it does NOT decode/copy bytes, so building a 50-clip timeline
is cheap. The source can be a **remote `AVURLAsset`** (archive.org progressive MP4),
so clips from different titles compose directly. (See §11 for the remote-streaming
caveat — for editing we recommend a local cache, not the play-as-you-go loader.)

### Why one composition plays directly in AVPlayer
`AVComposition` **is an `AVAsset`**. So:

```swift
let item = AVPlayerItem(asset: comp)         // comp = the AVMutableComposition
item.videoComposition = videoComposition     // the render recipe (opacity/transform/CI)
item.audioMix = audioMix
player.replaceCurrentItem(with: item)
```

This is the editor's real-time preview — no export needed. The same
`videoComposition`/`audioMix` objects feed BOTH preview and export, so what the user
scrubs is what they render.

**Critical mutation rule:** never mutate the live `AVMutableComposition`/
`AVVideoComposition` while it is attached to a playing `AVPlayerItem`. Edit a copy,
then build a fresh `AVPlayerItem` and `replaceCurrentItem(with:)`. Mutating in place
causes undefined preview behavior. Plan the editor around **rebuild-and-swap** on
each edit (debounced), keeping the previous item until the new one is `.readyToPlay`
to avoid a preview flash.

### Track-count strategy & performance
- AVFoundation imposes **no hard track-count limit**, but real-time preview decode
  budget does. A practical pattern (used by iMovie-class editors): keep a **small
  fixed set of video tracks** (commonly 2, "A/B") and lay non-overlapping clips
  end-to-end on them, only needing a 2nd track where clips OVERLAP (transitions).
  Many sequential clips on 2 tracks decode far better than N parallel tracks.
- Audio can use more tracks freely (cheap to decode) — one per simultaneous source
  + dub tracks.
- For long timelines, set `AVPlayerItem` decode hints sparingly; rely on the 2-track
  A/B layout to bound concurrent decoders.
- Apple Silicon hardware H.264/HEVC decoders are plentiful but finite; overlapping
  >2–3 hi-res video decodes can stutter preview. Mitigate with proxy/preview-quality
  assets (Mac advantage: generate ProRes Proxy or 720p H.264 proxies for editing,
  relink to originals at export — §7).

---

## 2. Transitions between clips (feature, on the §1 spine)

### Native (no custom compositor): overlap + opacity/transform ramps
Cuts are free — abut two clips, no overlap, single layer instruction each. A
**cross-dissolve** needs the two clips to **overlap in time on two tracks**:

1. Place clip A on track 1, clip B on track 2, with B starting `transitionDur`
   before A ends (so their time ranges overlap by `transitionDur`).
2. In the overlap `AVVideoCompositionInstruction.Configuration`, give BOTH tracks a
   layer instruction; ramp A's **opacity 1→0** and B's **opacity 0→1** over the
   overlap via `setOpacityRamp(fromStartOpacity:toEndOpacity:timeRange:)` on the
   layer-instruction configuration.
3. `setTransformRamp(...)` does push/slide/scale transitions; `setCropRectangleRamp`
   does wipes.

Build the instruction list as: solo-A instruction → overlap (A+B) instruction →
solo-B instruction, ordered, gap-free, covering the whole timeline. The
**layer-instruction ORDER within an instruction is the z-order** (front-most last).

This covers **dissolve, fade-to/from-color (ramp against a color track), push,
slide, scale, simple wipe** — the great majority of editorial transitions — with
zero custom code and full real-time preview.

### When you need a custom compositor (`AVVideoCompositing`)
Opacity/transform ramps can't express **GPU blend transitions** — ripple, glitch,
luma-keyed wipes, page-curl, blur dissolves. Those require implementing the
`AVVideoCompositing` protocol: `startVideoCompositionRequest(_:)` hands you an
`AVAsynchronousVideoCompositionRequest` with each source frame's pixel buffer for a
given `compositionTime`; you blend them (Core Image or Metal) and call
`request.finish(withComposedVideoFrame:)`. Apple's `AVCustomEdit` sample is the
canonical reference (it implements GL/Metal transitions exactly this way). A custom
compositor REPLACES the standard one for the whole composition, so you re-implement
the pass-through cases too. **Recommendation:** ship native ramp transitions in v1;
add a Metal `AVVideoCompositing` only when the design calls for GPU blends.

---

## 3. Timed text / title overlays (feature 3)

### The mechanism
Overlays are CALayers composited by **`AVVideoCompositionCoreAnimationTool`**. Build a
layer tree: a video layer + sibling text/graphic `CALayer`/`CATextLayer`s, then:

```swift
let tool = AVVideoCompositionCoreAnimationTool(
  configuration: .init(postProcessingAsVideoLayer: videoLayer,
                       in: parentLayer))
config.animationTool = tool
```

### Timing overlays to specific timeline moments
Each overlay is shown/hidden/animated with Core Animation on the **video timeline**,
not wall-clock. Two non-negotiable rules:

1. **`beginTime` must use `AVCoreAnimationBeginTimeAtZero`, never `0.0`** — a
   `beginTime` of 0 is interpreted as `CACurrentMediaTime()` (host clock) and the
   animation never appears in the rendered movie.
2. **`isRemovedOnCompletion = false`** and explicit `fillMode = .both` — otherwise
   the overlay vanishes on replay/scrub.

Show a title from t=4s to t=9s: an opacity `CABasicAnimation`/`CAKeyframeAnimation`
fading in at `AVCoreAnimationBeginTimeAtZero + 4`, holding, fading out, with
`beginTime`/`duration` in composition seconds. **Per-clip vs whole-timeline:** the
animation tool operates on the WHOLE timeline's coordinate space — there's no
per-clip overlay scoping; you place every overlay on the absolute timeline and time
it to the clip's window. Lower-thirds, captions, credits crawls (CAKeyframe position
animation), watermark/provenance credit (Decision 033's always-on
`archivewatch.org · Public Domain` credit) all live here.

### Keyframing overlays
`CAKeyframeAnimation` (`values` + `keyTimes` + per-segment `timingFunctions`) drives
position/scale/rotation/opacity keyframes — this is the overlay-keyframing surface
(see §6 for the broader keyframing picture).

### ⚠️ The two-pass constraint (inherited, load-bearing)
`AVVideoCompositionCoreAnimationTool` (CALayer overlays) and the per-frame Core Image
applier (`AVVideoComposition(applyingFiltersTo:applier:)`) **cannot both live in one
`AVVideoComposition`** — setting an `animationTool` on a CI-filtering composition is
mutually exclusive with the CI applier. So **color grade + titles ⇒ two passes**:

- **Pass 1 (CI):** trim/reframe/color-grade via the CI applier into an intermediate
  render (ProRes 4444/422 on Mac — lossless intermediate, §7).
- **Pass 2 (overlays):** feed pass-1 output as a single-track composition with the
  `animationTool` to burn the timed CALayer overlays.

On Mac this is acceptable (ProRes intermediate is cheap, disk is ample). Order
matters: grade first so overlays aren't tinted. (Transitions via §2 ramps need NO
extra pass — they're standard layer instructions, compatible with the CI pass; only
the CALayer **overlay tool** triggers the split.)

---

## 4. Audio: mix, replace, and dub (feature 4)

### Multi-track mix with ramps
Add an `AVMutableCompositionTrack(.audio)` per source; mix them with
`AVMutableAudioMix`, one `AVMutableAudioMixInputParameters(track:)` per audio track:

```swift
let p = AVMutableAudioMixInputParameters(track: musicTrack)
p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: fadeIn)   // fade up
p.setVolume(0.3, at: voiceoverStart)                                     // duck under VO
audioMix.inputParameters = [p, voiceP, ...]
item.audioMix = audioMix   // applies in BOTH preview and export
```

`setVolumeRamp(fromStartVolume:toEndVolume:timeRange:)` interpolates linearly across
the range — fades, ducking, crossfades (ramp one source down while another ramps up).
Tracks WITHOUT an `inputParameters` entry mix at full volume by default.

### Replace vs mix original audio
- **Mix:** keep the source clip's audio track in the composition AND add the music
  track; both mix per their parameters.
- **Replace:** simply don't insert the source's audio track (insert only its video
  track range), then add a music/dub track. Full control per clip.

### Recording new audio to dub
Record with **`AVAudioRecorder`** (file-based, simplest — record to `.m4a`/`.caf`)
or **`AVAudioEngine`** (tap `inputNode`, write via `AVAudioFile`, real-time
monitoring/effects). On Mac use `AVCaptureDevice`/`AVAudioApplication` for mic
permission (`NSMicrophoneUsageDescription`). Importing audio files from disk =
`AVURLAsset` → insert its audio track into a new composition audio track.

### Sync
Audio and video sit in the same composition timeline, so insertion `at:` times keep
them sample-synced. Dub sync = position the recorded clip's `insertTimeRange(at:)` to
the intended timeline moment; let the user nudge by frame. AVFoundation handles A/V
clock sync at playback/export; you only control placement.

---

## 5. Export (feature 5)

### Modern async export
```swift
let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHEVCHighestQuality)!
session.videoComposition = videoComposition
session.audioMix = audioMix
// macOS 15+ async API:
for await state in session.states(updateInterval: 0.5) {
    switch state {
    case .pending, .waiting: break
    case .exporting(let progress): updateUI(progress.fractionCompleted)  // Progress object
    @unknown default: break
    }
}
try await session.export(to: outputURL, as: .mov)   // throws on failure/cancel
```

`export(to:as:)` + `states(updateInterval:)` replace the deprecated
`exportAsynchronously`/`progress`/`status`/`error` polling. Validate target
compatibility with `await session.estimatedOutputFileLengthRange` /
`supportedFileTypes`.

### Formats / presets / qualities
- **H.264:** `AVAssetExportPreset1920x1080`, `…3840x2160`, `…HighestQuality` —
  universal social/web delivery.
- **HEVC:** `AVAssetExportPresetHEVCHighestQuality`, `…3840x2160`,
  `…HighestQualityWithAlpha` — smaller files, HDR-capable.
- **ProRes (Mac advantage):** export-session presets are limited for ProRes; for
  full ProRes control (422 / 422 HQ / 4444 with alpha) use the **`AVAssetWriter`**
  path (§7) with codec keys `AVVideoCodecType.proRes422`, `.proRes422HQ`,
  `.proRes4444`, `.proRes422LT`, `.proRes422Proxy`. This is the editorial-master
  format and the right intermediate for the §3 two-pass render.
- Resolution/bitrate beyond presets ⇒ `AVAssetWriter` with explicit
  `AVVideoCompressionPropertiesKey` (`AverageBitRate`, `ProfileLevel`, `MaxKeyFrameInterval`).

### Long / background renders (Mac)
`AVAssetExportSession` runs async and survives in the background on Mac (no
iOS-style suspension). For very long renders, jobs that need pause/resume, custom
codecs, or a render queue, drive an **`AVAssetReader` (with
`AVAssetReaderVideoCompositionOutput`) → process → `AVAssetWriter`** pipeline (§7):
it gives frame-level control, multi-job queueing, and lets you shell out to `ffmpeg`
for container muxing / formats AVFoundation lacks (e.g. GIF, WebM, animated APNG).
GIF specifically: `AVAssetImageGenerator` frame grabs → `CGImageDestination`
(`com.compuserve.gif`), or `ffmpeg` subprocess for palette-optimized GIF.

---

## 6. Keyframing — the general model

Two complementary keyframing surfaces, by what's being keyframed:

1. **Overlay / transform keyframing → Core Animation.** `CAKeyframeAnimation`
   (`values`, `keyTimes`, `timingFunctions`) on the overlay CALayers via the
   animation tool (§3). Use for title moves, Ken-Burns on a still/overlay, opacity
   envelopes, watermark animation.
2. **Image/effect keyframing → per-frame Core Image.** In the CI applier, key the
   filter parameters off `request.compositionTime` (a `CMTime`): interpolate a LUT
   strength, blur radius, or color grade across the clip by computing the value for
   that frame's time. This is how a grade "animates" without a CALayer.
3. **Geometric (whole-clip) keyframing → layer-instruction ramps.** `setTransformRamp`
   / `setOpacityRamp` / `setCropRectangleRamp` (§2) are linear two-point keyframes on
   a track — cheapest, native, preview-accurate; use for pans/zooms/reframes that are
   start→end linear.

Author the model so each keyframeable property declares which surface it renders
through; the two-pass split (§3) only triggers when CALayer overlays AND a CI pass
are both present.

---

## 7. Mac-specific advantages over the iOS Clip Studio engine

| Capability | iOS Clip Studio | macOS Creation Studio |
|---|---|---|
| **ProRes** | impractical (size/thermals) | **first-class** — `AVAssetWriter` 422/422 HQ/4444; ideal §3 two-pass intermediate + editorial master |
| **Render length / background** | iOS suspends background work; short clips | long renders run unattended; render **queue** of multi-title jobs |
| **RAM / decoders** | constrained; 1–2 decodes | large RAM + many HW decoders → more overlap, **proxy + relink** editing workflow |
| **Multi-window** | single modal flow | multiple project windows, separate preview + timeline + inspector (AppKit/SwiftUI windows) |
| **CLI escape hatch** | none (App Store, no subprocess) | **shell out to `ffmpeg`** for GIF/WebM/format muxing & batch ops |
| **`AVAssetWriter` control** | overkill | full codec/bitrate/color/alpha control; multi-pass; ProRes proxy generation |
| **Color / HDR** | basic | `colorPrimaries`/`perFrameHDRDisplayMetadataPolicy`, ProRes 4444 alpha, wide-gamut masters |

The macOS engine should treat ProRes-intermediate + `AVAssetWriter` as the export
backbone (with `AVAssetExportSession` presets as the quick-delivery path), and lean
on the subprocess escape hatch for anything outside AVFoundation's container/codec
set.

---

## 8. Recommended engine architecture (summary)

- **`Timeline` model** (clips with sourceAssetID + sourceRange + timelineRange + per-clip
  effects/overlays/audio) is the source of truth; it is **compiled** on each edit into
  a fresh `(AVMutableComposition, AVVideoComposition, AVAudioMix)` triple.
- **One compiler** builds that triple for BOTH preview and export — preview =
  `AVPlayerItem(asset: comp)` with the composition/mix attached (rebuild-and-swap,
  debounced, never mutate-in-place); export = the SAME triple into async
  `export(to:as:)` or the `AVAssetWriter` ProRes pipeline.
- **2-track A/B video layout** for sequential clips + overlaps only where transitions
  occur; N audio tracks freely.
- **Transitions** = native opacity/transform/crop ramps (`*.Configuration`); a Metal
  `AVVideoCompositing` only for GPU-blend transitions later.
- **Two-pass render** whenever CALayer overlays (`AVVideoCompositionCoreAnimationTool`)
  coexist with a per-frame CI grade: CI/grade pass → ProRes intermediate → overlay
  pass. Transitions need no extra pass.
- **Edit on proxies, export from originals** for heavy 4K multi-title timelines.

## Top 3 hard problems

1. **The two-pass split is structural, not incidental.** Color grade + timed titles
   can't share one composition; the engine must own an intermediate-render manager
   (ProRes temp files, pass ordering, cleanup) and the model must know which features
   force the split. Get this wrong and overlays silently disappear or grades tint the
   titles.
2. **Real-time multi-title preview without stutter.** Composing remote/4K clips from
   many archive.org titles overruns the HW decoder budget; needs a rebuild-and-swap
   pipeline (never mutate live), the 2-track A/B discipline, and a proxy/relink path —
   all while keeping preview frame-accurate to what exports.
3. **Custom GPU transitions / effects = a full `AVVideoCompositing` compositor.** The
   moment design wants anything past linear opacity/transform ramps, you implement and
   maintain a Metal compositor that replaces the standard one (re-handling pass-through,
   timing, color, and the preview/export parity) — a large, sharp-edged surface.

---

## Sources

- [AVVideoComposition.Configuration — Apple Developer](https://developer.apple.com/documentation/avfoundation/avvideocomposition/configuration)
- [AVVideoComposition — Apple Developer](https://developer.apple.com/documentation/avfoundation/avvideocomposition)
- [AVMutableVideoCompositionLayerInstruction — Apple Developer](https://developer.apple.com/documentation/avfoundation/avmutablevideocompositionlayerinstruction)
- [AVVideoCompositionInstruction — Apple Developer](https://developer.apple.com/documentation/avfoundation/avvideocompositioninstruction)
- [AVVideoCompositionCoreAnimationTool — Apple Developer](https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool)
- [AVVideoCompositing — Apple Developer](https://developer.apple.com/documentation/avfoundation/avvideocompositing)
- [AVAssetExportSession — Apple Developer](https://developer.apple.com/documentation/avfoundation/avassetexportsession)
- [AVMutableAudioMixInputParameters / setVolumeRamp — Apple Developer](https://developer.apple.com/documentation/avfoundation/avmutableaudiomixinputparameters)
- [AVAudioMixInputParameters — Apple Developer](https://developer.apple.com/documentation/avfoundation/avaudiomixinputparameters)
- [AVPlayerItem.videoComposition — Apple Developer](https://developer.apple.com/documentation/avfoundation/avplayeritem/videocomposition)
- [AVVideoComposition.PerFrameHDRDisplayMetadataPolicy — Apple Developer](https://developer.apple.com/documentation/avfoundation/avvideocomposition/perframehdrdisplaymetadatapolicy-swift.struct)
- [Editing (AVFoundation Programming Guide) — Apple archive](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html)
- [AVCustomEdit sample (custom compositor / transitions) — Apple archive](https://developer.apple.com/library/archive/samplecode/AVCustomEdit/Listings/AVCustomEdit_APLCustomVideoCompositor_m.html)
- [Decode ProRes with AVFoundation and VideoToolbox — WWDC20 (10090)](https://developer.apple.com/videos/play/wwdc2020/10090/)
- [Optimize the Core Image pipeline for your video app — WWDC20 (10008)](https://developer.apple.com/videos/play/wwdc2020/10008/)
- [Edit and play back HDR video with AVFoundation — WWDC20 (10009)](https://developer.apple.com/videos/play/wwdc2020/10009/)
- [Frame-by-frame video editing pipeline with Swift — videowithswift.com](https://videowithswift.com/frame-by-frame-video-editing-pipeline-with-swift/)
- Project binding doc cross-check: `docs/CREATE-STUDIO-PLAN.md` §5c (Configuration-API naming); Decision 033 (iOS Clip Studio engine + two-pass constraint).
