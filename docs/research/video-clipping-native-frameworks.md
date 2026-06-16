# Video Clipping / Fan-Edit / GIF Creation — Native Framework Research

**Status:** Research brief. Not implemented. Captured 2026-06-15.

**Scope:** A feature suite to let users clip, trim, stitch, caption,
reframe, color-grade, and GIF-ify the public-domain MP4s Archive Watch
streams. Built with **native platform frameworks only** — on Apple
platforms this is a hard rule (no third-party Swift packages; see
CLAUDE.md / Decision 028). Android is documented at parity-planning
altitude; implementation is iOS-first.

**Source media:** progressive H.264 / HEVC `.mp4` from archive.org
(public domain). We download the whole file (or a byte range) to a local
writable directory first, then operate on a local `AVAsset` / `File`.
There is no editing of a remote URL — every operation below assumes a
local file.

**OS-version posture:** the tvOS app targets tvOS 26 / Liquid Glass and
iOS/iPadOS targets iOS 26 in the universal build. We can lean on iOS 18+
and iOS 26 APIs but must `#available`-gate the iOS-26-only pieces
(SpeechAnalyzer, the new `AVMutableVideoComposition` initializers) with a
graceful fallback to the iOS 18 path. **Note: clipping/editing UI is an
iOS/iPadOS feature — tvOS has no editing affordance** (no text entry, no
direct-manipulation timeline). The shared AVFoundation *engine* code can
live in the shared Core; the UI is iPhone/iPad only.

---

## 0. The architectural spine (read first)

Almost everything on Apple platforms funnels through three objects:

- **`AVMutableComposition`** — the edit graph. Holds
  `AVMutableCompositionTrack`s (one per media type: `.video`, `.audio`,
  optionally `.text`/`.closedCaption`). You build the *timeline* here by
  inserting time ranges from source assets. This is where trim, stitch,
  and speed-ramp live.
- **`AVMutableVideoComposition`** — the *render recipe* for the video
  track: `renderSize`, `frameDuration`, per-time-range
  `instructions` (layer transforms/opacity), and the hook for overlays
  (Core Animation) or per-frame filters (Core Image). This is where
  reframing, overlays, watermarks, and color grading live.
- **`AVAssetExportSession`** — the renderer. Takes the composition +
  videoComposition + a preset, writes a file. This is the output stage.

A clip with no effects needs only an `AVMutableComposition` (or even just
a time range passed to the export session). The moment you add an overlay
or a filter, you also need an `AVMutableVideoComposition`.

> **Always load asset properties asynchronously.** On iOS 16+ the
> synchronous `asset.duration` / `asset.tracks` accessors are deprecated.
> Use `try await asset.load(.duration)`,
> `try await asset.loadTracks(withMediaType: .video)`,
> `try await track.load(.naturalSize, .preferredTransform)`. The
> compiler will not always warn, but the sync accessors stall on remote
> assets and are being removed.
> Docs: <https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously>

---

## 1. Trimming a clip from a longer video

**iOS — recommended approach**

Two viable paths:

**(a) Fast, lossless-ish passthrough trim** — best for "give me seconds
30–45 of this film as-is":

```swift
let asset = AVURLAsset(url: localFileURL)
let session = AVAssetExportSession(
    asset: asset,
    presetName: AVAssetExportPresetPassthrough
)!
session.outputURL = outURL
session.outputFileType = .mp4
session.timeRange = CMTimeRange(
    start: CMTime(seconds: 30, preferredTimescale: 600),
    duration: CMTime(seconds: 15, preferredTimescale: 600)
)
```

`AVAssetExportPresetPassthrough` copies the compressed samples without
re-encoding — fast, no quality loss — but it can only cut on
**keyframe (IDR) boundaries**, so the start may snap to the nearest
preceding keyframe. For frame-accurate trims you must re-encode (use a
quality preset, below).

**(b) Frame-accurate trim via composition** — required if the user needs
exact in/out points or you're going to add effects anyway:

```swift
let comp = AVMutableComposition()
let vTrack = comp.addMutableTrack(withMediaType: .video,
                                  preferredTrackID: kCMPersistentTrackID_Invalid)!
let aTrack = comp.addMutableTrack(withMediaType: .audio,
                                  preferredTrackID: kCMPersistentTrackID_Invalid)!
let srcV = try await asset.loadTracks(withMediaType: .video).first!
let srcA = try await asset.loadTracks(withMediaType: .audio).first
let range = CMTimeRange(start: inPoint, duration: clipDuration)
try vTrack.insertTimeRange(range, of: srcV, at: .zero)
if let srcA { try aTrack.insertTimeRange(range, of: srcA, at: .zero) }
vTrack.preferredTransform = try await srcV.load(.preferredTransform) // keep orientation
```

**Quality / preset choices** (`AVAssetExportSession`):
- `AVAssetExportPresetPassthrough` — no transcode, keyframe-bounded, no
  effects allowed.
- `AVAssetExportPresetHighestQuality` / `...HEVCHighestQuality` —
  re-encode at source-ish quality; HEVC variant is smaller for the same
  quality but slower to encode and needs HEVC-capable hardware (fine on
  all modern devices). For archival H.264 sources, exporting H.264 is the
  safe, universally-shareable default.
- `AVAssetExportPreset1920x1080` / `1280x720` / `960x540` — fixed-size
  re-encode; useful to cap output size for sharing.
- You **cannot** attach an `AVMutableVideoComposition` to a Passthrough
  preset — overlays/filters force a quality preset.

**Modern async export (iOS 18+)** — the new structured-concurrency API
replaces `exportAsynchronously(completionHandler:)`:

```swift
if #available(iOS 18, tvOS 18, *) {
    try await session.export(to: outURL, as: .mp4)         // throws on failure/cancel
    // progress via the states AsyncSequence:
    for await state in session.states(updateInterval: 0.25) {
        switch state {
        case .pending, .waiting:        break
        case .exporting(let progress):  update(progress.fractionCompleted)
        @unknown default:               break
        }
    }
} else {
    // iOS 17 fallback: set outputURL/outputFileType, then
    await session.export() // or exportAsynchronously(completionHandler:)
}
```

`export(to:as:)` and `states(updateInterval:)` are **iOS 18 / macOS 15**.
The `states` sequence is the modern replacement for polling
`session.progress` on a timer. The old `.status`/`.progress` polling path
still works and is the iOS 17 fallback.
Docs: <https://developer.apple.com/documentation/avfoundation/avassetexportsession>
· <https://developer.apple.com/documentation/avfoundation/avassetexportsession/state>

**Gotchas**
- A trim that re-encodes is **CPU/GPU + thermals**; keep clips short
  (the UI should cap clip length, e.g. ≤60s, both for performance and to
  keep the feature clearly "clip," not "re-host the film").
- Always carry `preferredTransform` or rotated source video exports
  sideways.
- Output `.mp4` (H.264/AAC) for maximum share compatibility; `.mov` only
  if you specifically need ProRes/alpha.

**Android (parity)** — Media3 `Transformer` with a clipped `MediaItem`:

```kotlin
val item = MediaItem.Builder()
    .setUri(localUri)
    .setClippingConfiguration(
        MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(30_000)
            .setEndPositionMs(45_000)
            .build())
    .build()
val edited = EditedMediaItem.Builder(item).build()
Transformer.Builder(context)
    .addListener(listener)
    .build()
    .start(edited, outputPath)
```

`Transformer` (1.5+ stable, 1.9 current as of Dec 2025) is the modern
replacement for hand-rolled `MediaCodec`/`MediaMuxer` or `mp4parser`.
Clipping near non-keyframe boundaries triggers a transcode automatically;
set `experimentalSetTrimOptimizationEnabled(true)` on the builder to
attempt a fast level-passthrough trim when the codec config allows.
Docs: <https://developer.android.com/media/media3/transformer/transformations>

---

## 2. Stitching multiple clips (montage / fan edit)

**iOS** — one `AVMutableComposition`, multiple `insertTimeRange` calls
appended end to end:

```swift
var cursor = CMTime.zero
for src in orderedSources {
    let a = AVURLAsset(url: src.url)
    let sv = try await a.loadTracks(withMediaType: .video).first!
    let sa = try await a.loadTracks(withMediaType: .audio).first
    let r  = CMTimeRange(start: src.inPoint, duration: src.duration)
    try vTrack.insertTimeRange(r, of: sv, at: cursor)
    if let sa { try aTrack.insertTimeRange(r, of: sa, at: cursor) }
    cursor = cursor + r.duration
}
```

**Gotchas**
- **Heterogeneous sources are the hard part.** Archive clips vary in
  resolution, frame rate, color primaries, and rotation. Inserting them
  back-to-back on one track works, but to render cleanly you need an
  `AVMutableVideoComposition` whose `renderSize` is fixed and a per-range
  `AVMutableVideoCompositionInstruction` with an
  `AVMutableVideoCompositionLayerInstruction` that applies a transform to
  fit/letterbox each differently-sized clip into the common canvas (see
  §4 reframing). Without this, mismatched sizes render with the first
  clip's geometry and the rest are cropped/offset.
- Set `videoComposition.frameDuration` to a single target fps (e.g.
  `CMTime(value: 1, timescale: 30)`); mixed-fps sources are resampled.
- **Transitions** (crossfades) require overlapping layer instructions
  with ramped opacity (`setOpacityRamp(fromStartOpacity:to:timeRange:)`)
  and a two-region instruction during the overlap. This is fiddly; ship
  hard cuts in v1, transitions later.

**Android (parity)** — an `EditedMediaItemSequence` of multiple
`EditedMediaItem`s inside a `Composition`. `Transformer` resolves the
common output format. Cross-sequence overlap/transitions are still
limited (tracked upstream); hard-cut concatenation is well supported.
Docs: <https://developer.android.com/media/media3/transformer/transformations>

---

## 3. Text / caption / title overlays and watermarks

There are two distinct mechanisms on iOS; pick by overlay type.

### 3a. Core Animation overlays — `AVVideoCompositionCoreAnimationTool`

Best for **static or keyframe-animated graphic overlays**: title cards,
lower-thirds, watermarks, an Archive Watch logo bug, animated text. You
build a `CALayer` tree (video layer + overlay layer), and AVFoundation
composites it during export.

```swift
let videoLayer = CALayer()
let overlayLayer = CALayer()
let parent = CALayer()
parent.frame = CGRect(origin: .zero, size: renderSize)
videoLayer.frame = parent.frame
overlayLayer.frame = parent.frame
parent.addSublayer(videoLayer)
parent.addSublayer(overlayLayer)

let title = CATextLayer()
title.string = "ARCHIVE WATCH"
title.fontSize = 48
title.frame = CGRect(x: 40, y: 40, width: renderSize.width - 80, height: 80)
title.contentsScale = 2          // avoid blurry text
overlayLayer.addSublayer(title)

videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
    postProcessingAsVideoLayer: videoLayer,
    in: parent
)
```

**Gotchas**
- **Core Animation's coordinate system is bottom-left origin (UIKit is
  top-left).** Y is flipped. Get this wrong and the watermark renders
  upside-down or off-screen. Flip with a transform or compute from the
  bottom.
- `CATextLayer` renders blurry unless `contentsScale` is set (use 2–3).
- For *animated* overlays, set `layer.beginTime` to a tiny non-zero value
  (`AVCoreAnimationBeginTimeAtZero`) — a literal `0` begin time is treated
  as "now" and the animation won't play in the export.
- **`AVVideoCompositionCoreAnimationTool` works for *export* but not for
  real-time `AVPlayer` preview.** For live preview you set
  `playerItem.videoComposition` and use a Core Image / custom-compositor
  approach, or overlay native SwiftUI/UIKit views on top of the player
  and only bake the CALayer at export time. Practical pattern: preview
  overlays as SwiftUI views layered over `VideoPlayer`; bake identical
  geometry into CALayers at export.
- There is a long-standing class of `AVVideoCompositionCoreAnimationTool`
  bugs across iOS releases (the GitHub `CustomVideoCompositor` workaround
  exists for one). Test the exact export path on each OS we target.

### 3b. Core Image per-frame — `applyingCIFiltersWithHandler`

Best for **pixel effects that also need text**: burned-in subtitles via
a `CIImage` of rendered text, or combining grade + caption in one pass.

```swift
let vc = AVMutableVideoComposition(asset: asset) { request in
    let source = request.sourceImage.clampedToExtent()
    let withText = compositeCaption(over: source, at: request.compositionTime)
    request.finish(with: withText, context: nil)
}
```

This *does* drive live `AVPlayer` preview (set
`playerItem.videoComposition = vc`) — its advantage over the CALayer
tool. Render text to a `CIImage` (via `CITextImageGenerator` or by
drawing into a `CGContext` → `CIImage`) and composite with
`CISourceOverCompositing`.

> **iOS 26 deprecation note.** The no-argument `AVMutableVideoComposition()`
> initializer and some mutable-setup patterns are deprecated in iOS 26 in
> favor of the async `AVVideoComposition(propertiesOf:)` /
> `init(asset:applyingCIFiltersWithHandler:)` initializers. The *class*
> is not going away; the bare initializer is. Use the asset-based
> initializers and `#available`-gate if we see warnings on the iOS 26 SDK.
> Background: <https://developer.apple.com/documentation/avfoundation/avvideocomposition>

**Watermark recommendation for Archive Watch:** a small, semi-transparent
"made with Archive Watch · archivewatch.org" bug + an attribution line is
both on-brand and useful provenance for shared PD clips. Use the CALayer
tool (3a) for export — it's the cleanest for a fixed logo + text.

**Android (parity)** — `OverlayEffect` with `TextOverlay` (text) and
`BitmapOverlay` (logo/watermark), passed via `Effects` on the
`EditedMediaItem`. `OverlaySettings` controls position/anchor/alpha; this
covers both captions and watermark in one mechanism.
Docs: <https://developer.android.com/media/media3/transformer/transformations>
· TextOverlay: <https://androidx.de/androidx/media3/effect/TextOverlay.html>

---

## 4. Aspect-ratio reframing (square / vertical / letterbox / blurred-fill)

Reframing for social (1:1, 9:16, 16:9) is done by setting the
`AVMutableVideoComposition.renderSize` to the target canvas and applying a
**transform** to the source via the layer instruction.

```swift
let videoComposition = AVMutableVideoComposition()
videoComposition.renderSize = CGSize(width: 1080, height: 1080)   // square
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: clipDuration)
let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)

// scale-to-fit + center; combine with preferredTransform for orientation
let fit = aspectFitTransform(srcSize: naturalSize,
                             into: videoComposition.renderSize)
layer.setTransform(preferredTransform.concatenating(fit), at: .zero)
instruction.layerInstructions = [layer]
videoComposition.instructions = [instruction]
```

**Letterbox vs blurred-fill background**

- **Letterbox (bars):** just aspect-fit the source into the canvas; the
  canvas background defaults to black. Cheapest. Set
  `videoComposition.backgroundColor` (a `CGColor`) for a colored matte.
- **Blurred-fill (the "Instagram" look):** the empty canvas is filled
  with a *scaled-up, gaussian-blurred copy of the same frame*, with the
  centered un-blurred frame on top. This is **not** expressible with layer
  instructions alone — it needs Core Image. Use the
  `applyingCIFiltersWithHandler` path:
  1. Take `request.sourceImage`.
  2. Background = source scaled to *fill* the canvas (overscan) →
     `CIGaussianBlur` (radius ~30–50) → cropped to `renderSize`.
  3. Foreground = source scaled to *fit*, centered.
  4. `CISourceOverCompositing` foreground over blurred background →
     `request.finish(with:context:)`.

**Gotchas**
- Reframing always re-encodes (it changes geometry), so a quality preset
  is required — no Passthrough.
- Keep the Core Image work on a single shared `CIContext` (create once,
  reuse) — recreating per frame tanks performance.
- The blurred-fill path is per-frame GPU work; it roughly doubles export
  time vs a plain letterbox. Acceptable for short clips.

**Android (parity)** — `Presentation.createForWidthAndHeight(...)` or
`Presentation.createForAspectRatio(...)` as a video effect sets the output
frame; layout modes handle scale-to-fit vs scale-to-fill. Blurred-fill
needs a custom GL/shader effect (`GlEffect`/`RgbMatrix`-style) — defer.
Docs: <https://developer.android.com/media/media3/transformer/transformations>

---

## 5. Speed ramps / slow-mo

**iOS** — `AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)`
stretches/compresses a track range. Slow-mo = scale a short source range
to a longer duration; fast-forward = the reverse.

```swift
let sourceRange = CMTimeRange(start: .zero, duration: oneSecond)
vTrack.scaleTimeRange(sourceRange, toDuration: CMTime(seconds: 3, preferredTimescale: 600))
```

**Gotchas**
- Scaling video and audio independently desyncs them. Either scale both
  tracks by the same factor, or drop audio for ramped segments (pitch
  also shifts oddly when audio is time-scaled without a pitch algorithm).
- True slow-mo (smooth, not stuttery) requires high-fps source footage or
  optical-flow frame interpolation. AVFoundation's
  `AVVideoCompositionInstruction` does **not** do optical flow; you get
  frame duplication. Archive sources are typically 24/30fps, so deep
  slow-mo (4×+) will visibly stutter. For optical-flow interpolation you'd
  need a custom Metal/Core Image compositor (out of scope for v1).
- A "speed ramp" (gradually changing speed) needs *multiple* scaled
  sub-ranges; AVFoundation has no single ramp primitive.

**Android (parity)** — `SpeedChangeEffect`, or
`EditedMediaItem.Builder().setSpeed(...)` for a whole-item constant speed.
Docs: <https://developer.android.com/media/media3/transformer/transformations>

---

## 6. Color grading / filters (vintage / film looks)

**iOS** — Core Image via `applyingCIFiltersWithHandler` (§3b path),
chaining `CIFilter`s. This is the natural home for "give it a film look."

Useful built-in filters for vintage/repertory looks (apt for PD cinema):
- `CIPhotoEffectNoir`, `CIPhotoEffectTonal`, `CIPhotoEffectMono` — B&W
  looks (already era-appropriate for much of the catalog).
- `CIPhotoEffectInstant`, `CIPhotoEffectTransfer`, `CIPhotoEffectProcess`,
  `CIPhotoEffectFade`, `CIPhotoEffectChrome` — faded/period color casts.
- `CISepiaTone` — silent-era sepia (ties to the Silent Era accent in the
  design system).
- `CIColorControls` (saturation/brightness/contrast),
  `CIVignette`/`CIVignetteEffect` — manual grade + edge darkening.
- `CITemperatureAndTint`, `CIToneCurve`, `CIColorCurves` — precise grade.
- **LUT-based looks:** `CIColorCube` / `CIColorCubeWithColorSpace` lets
  you apply a 3D LUT (`.cube`) baked into a data blob — the cleanest way
  to ship a curated set of named "looks" without hand-tuning filter
  chains. Pre-bake LUTs as bundled resources.
- Film grain / dust: `CIRandomGenerator` → blend with
  `CIScreenBlendMode`, or a bundled grain texture composited per frame.

```swift
let vc = AVMutableVideoComposition(asset: asset) { request in
    let img = request.sourceImage
        .applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.7])
        .applyingFilter("CIVignette", parameters: ["inputIntensity": 1.2, "inputRadius": 1.6])
    request.finish(with: img, context: nil)
}
```

**Gotchas**
- Reuse one `CIContext` across frames; prefer a Metal-backed context
  (`CIContext(mtlDevice:)`).
- Clamp/crop extents (`.clampedToExtent()`) before blurs/convolutions or
  you get transparent edges.
- Grades apply during *export* and (live) during preview if set on the
  `playerItem.videoComposition`.

**Android (parity)** — Media3 `Effects` list: `RgbFilter`,
`RgbMatrix`/`Brightness`/`Contrast`/`HslAdjustment`,
`SingleColorLut`/`LanczosResample`, or a custom `GlShaderProgram` for LUTs.
Docs: <https://developer.android.com/media/media3/transformer/transformations>

---

## 7. GIF creation

There is **no AVFoundation "export to GIF."** The native recipe is:
extract frames with `AVAssetImageGenerator`, then encode with **ImageIO**
(`CGImageDestination`) using `UTType.gif`.

```swift
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true               // respect rotation
gen.requestedTimeToleranceBefore = .zero                 // frame-accurate
gen.requestedTimeToleranceAfter  = .zero
gen.maximumSize = CGSize(width: 480, height: 480)        // downscale = smaller GIF

let fps = 12.0                                            // 10–15 is the GIF sweet spot
let frameTimes: [CMTime] = stride(from: 0.0, to: clipSeconds, by: 1.0 / fps)
    .map { CMTime(seconds: $0, preferredTimescale: 600) }

let dest = CGImageDestinationCreateWithURL(
    gifURL as CFURL, UTType.gif.identifier as CFString, frameTimes.count, nil)!
let fileProps = [kCGImagePropertyGIFDictionary as String:
                    [kCGImagePropertyGIFLoopCount as String: 0]]      // 0 = loop forever
CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

let frameProps = [kCGImagePropertyGIFDictionary as String:
                    [kCGImagePropertyGIFDelayTime as String: 1.0 / fps]] as CFDictionary

// iOS 16+: async batch generation
for await result in gen.images(for: frameTimes) {
    if case let .success(_, image, _) = result {
        CGImageDestinationAddImage(dest, image, frameProps)
    }
}
CGImageDestinationFinalize(dest)
```

**APIs**
- `AVAssetImageGenerator.images(for:)` — iOS 16+ `AsyncSequence` of
  `Result`s; cleaner than the legacy
  `generateCGImagesAsynchronously(forTimes:completionHandler:)` callback
  (still available as the iOS 15 fallback).
- `CGImageDestination` + `UTType.gif.identifier` (replaces the deprecated
  `kUTTypeGIF`).
- `kCGImagePropertyGIFLoopCount = 0` → infinite loop.
- `kCGImagePropertyGIFDelayTime` (clamped, ~min 0.02s observed by
  browsers; many clamp <0.05s up to 0.1s) — for sub-clamp precision use
  `kCGImagePropertyGIFUnclampedDelayTime` *and* set the clamped one too.

**File-size control** (GIF gets huge fast):
- **Cap dimensions** via `maximumSize` (≤480px is plenty for a shareable
  GIF).
- **Cap fps** (10–15). Frames × resolution is the size driver.
- **Cap duration** (≤6s in the UI).
- **Palette/dithering:** GIF is 256-color indexed. ImageIO does an
  internal adaptive palette + dithering per frame; you get little direct
  control. If we ever need a *global* optimized palette / better
  dithering / inter-frame delta compression (true GIF optimization),
  ImageIO won't do it and there's no native API for it — that's the one
  place a third-party encoder would help, but it violates the
  no-3rd-party rule, so accept ImageIO's per-frame palette.
- **Consider offering MP4/HEVC instead of GIF** where the share target
  supports it (iMessage, social) — vastly smaller and higher quality. GIF
  is for true GIF surfaces (forums, Slack, Reddit). Offer both.

**Gotchas**
- Set `requestedTimeTolerance*` to `.zero` for accurate frames, but this
  is slower (must decode to exact PTS). Loosening tolerance speeds it up
  and snaps to keyframes.
- `maximumSize` downscales using the GPU — set it rather than scaling
  CGImages yourself.
- Whole GIF assembly holds N decoded frames' worth of work; stream
  `CGImageDestinationAddImage` as frames arrive (as above) rather than
  collecting all CGImages first, to bound memory.

**Android (parity)** — Media3/`MediaMetadataRetriever`/`MediaCodec` to
extract frames (`getFrameAtTime` / `getFramesAtIndex`), then encode with
**`android.graphics.AnimatedImageDrawable` has no encoder** — Android has
no native *GIF encoder*. Options: (a) hand-roll a GIF89a encoder (the
classic `AnimatedGifEncoder` / "android-gif-encoder" single-file class
can be vendored as source, not a dependency); (b) encode an animated
**WebP** instead via `MediaCodec`/`ImageEncoder` (smaller, better, but not
"GIF"); (c) export a short MP4 and let the share sheet handle it. For
parity-planning: GIF on Android is the weakest native story — plan to
ship MP4/WebP and treat true-GIF as best-effort.

---

## 8. Auto-captions

**iOS — transcription**

Two generations; choose by OS:

- **iOS 26+: `SpeechAnalyzer` + `SpeechTranscriber`** (the modern,
  on-device, long-form API). It's an `AsyncSequence`-based modular
  pipeline: attach a `SpeechTranscriber` module to a `SpeechAnalyzer`,
  feed audio, receive timed transcript results with token/segment
  timing — exactly what we need for *timed* caption overlays. Language
  models download via the system asset catalog (`AssetInventory`). Runs
  fully on device; markedly faster than the old API and faster than
  Whisper in published benchmarks.
  Docs: <https://developer.apple.com/documentation/speech/speechanalyzer>
  · <https://developer.apple.com/documentation/speech/speechtranscriber>
  · WWDC25 "Bring advanced speech-to-text to your app with SpeechAnalyzer".

- **iOS 15–25 fallback: `SFSpeechRecognizer`** with
  `SFSpeechURLRecognitionRequest(url:)` over the local audio file. Set
  `requiresOnDeviceRecognition = true` to keep it offline (and avoid the
  ~1 min server limit + privacy concerns). Results carry
  `segments[].timestamp` + `.duration` for caption timing.
  Docs: <https://developer.apple.com/documentation/speech/sfspeechrecognizer>

```swift
if #available(iOS 26, *) {
    let transcriber = SpeechTranscriber(locale: .current,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults],
                                        attributeOptions: [.audioTimeRange])
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    // feed an AVAudioFile stream; consume transcriber.results (timed)
} else {
    let recognizer = SFSpeechRecognizer(locale: .current)!
    let req = SFSpeechURLRecognitionRequest(url: localAudioURL)
    req.requiresOnDeviceRecognition = true
    // recognitionTask -> result.bestTranscription.segments (timestamped)
}
```

**Permission:** `NSSpeechRecognitionUsageDescription` in Info.plist;
request `SFSpeechRecognizer.requestAuthorization`. (SpeechAnalyzer uses
the same Speech-framework authorization.)

**Rendering captions as timed overlays:** take the timed segments, group
into caption cues (~3–6 words / ≤2s each), and render either:
- as burned-in text via the §3a CALayer tool (animate
  `opacity`/`string` per cue using `CAKeyframeAnimation`/`beginTime`), or
- as a side-loaded **WebVTT** track muxed into the export (cleaner,
  toggleable, accessibility-correct) — generate VTT from the timed
  segments and add an `AVMutableCompositionTrack(mediaType: .text)` or
  expose via media selection (see the existing
  `docs/research/video-viewer-enhancements.md` subtitle notes).

For a *fan-edit caption* (meme-style burned-in text the user types), skip
transcription — it's just §3a text overlay.

**On-screen OCR (e.g. capturing burned-in title cards / intertitles):**
the **Vision** framework — `RecognizeTextRequest` (iOS 18+ Swift API) or
`VNRecognizeTextRequest` (legacy) run on a `CGImage` pulled via
`AVAssetImageGenerator`. Useful for auto-titling silent-film intertitles.
Docs: <https://developer.apple.com/documentation/vision>

**Android (parity)** — on-device `SpeechRecognizer` with
`EXTRA_PREFER_OFFLINE`, or **ML Kit** (on-device, but a dependency — so for
the strict-native posture, prefer the platform `SpeechRecognizer`).
Android's `SpeechRecognizer` is tuned for live mic input, not file
transcription, so file-based auto-caption is weaker than iOS; plan to gate
the feature or use a foreground-service mic-less decode workaround. OCR
parity: ML Kit Text Recognition / `TextRecognizer`.

---

## 9. Saving + sharing

**iOS**
- **Save to Photos:** PhotoKit —
  `PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: outURL, options: nil) }`.
  For a GIF, add it as `.photo` from the GIF file (Photos stores GIFs as
  animated images).
  Permission: **`NSPhotoLibraryAddUsageDescription`** (add-only — the
  lighter grant; we don't need read access just to save).
  Request via `PHPhotoLibrary.requestAuthorization(for: .addOnly)`.
  Docs: <https://developer.apple.com/documentation/photokit>
- **Share sheet:** SwiftUI `ShareLink(item:)` (pass the file URL) is the
  modern path; `UIActivityViewController` for finer control (excluded
  activity types, custom items). Both hand the file to AirDrop, Messages,
  social apps, "Save to Files," etc.
- **Provenance:** consider embedding a metadata comment ("Public-domain
  source: archive.org/details/{id} · clipped with Archive Watch") via
  `AVMutableMetadataItem`s on the export, and including the source link in
  the share payload — good citizenship for PD redistribution and aligned
  with the app's attribution ethos (Decision 007/010).

**Android (parity)** — write to **`MediaStore`** (scoped storage; no
`WRITE_EXTERNAL_STORAGE` needed on API 29+): insert into
`MediaStore.Video.Media` (or `.Images` for GIF) and stream the file in.
Share via `Intent(ACTION_SEND)` with a `FileProvider` content URI +
`FLAG_GRANT_READ_URI_PERMISSION`.

---

## 10. Trim UI: `UIVideoEditorController` vs custom

**Recommendation: build custom.** `UIVideoEditorController` is a relic —
UIKit-only, fixed coarse trim UI, no SwiftUI integration, no multi-clip,
no overlays, and effectively unmaintained (it predates everything else in
this doc). It is technically still present but is the wrong foundation for
a feature this rich, and is unavailable on tvOS. Don't build on it.

**Custom trim UI** (iPhone/iPad):
1. **Filmstrip:** `AVAssetImageGenerator` to pull ~10–20 evenly-spaced
   thumbnails across the clip (use `images(for:)`, `maximumSize` small,
   loose time tolerance for speed). Lay them in a horizontal strip.
2. **Scrubber + handles:** two draggable trim handles over the filmstrip
   define in/out; a playhead overlay. Drive an `AVPlayer` `seek(to:)` on
   handle drag (use `seek(to:toleranceBefore:.zero,toleranceAfter:.zero)`
   for frame-accurate scrub preview, but throttle — exact seeks are
   expensive; use loose tolerance while dragging, exact on release).
3. **Live preview:** `VideoPlayer` (AVKit) or a custom
   `AVPlayerLayer`; set `playerItem.videoComposition` to preview
   filters/reframing live (CALayer overlays don't preview — layer SwiftUI
   views over the player for those).
4. Compose entirely in SwiftUI; this also gives free iPad support and a
   single codebase with the rest of the app.

**Frameworks to lean on:** AVKit `VideoPlayer`, `AVPlayer`/`AVPlayerItem`,
`AVAssetImageGenerator`, SwiftUI gestures. No third party needed.

**Android (parity)** — Media3 `CompositionPlayer` (experimental preview as
of 1.9, Dec 2025) for previewing edits, a custom Compose timeline +
thumbnails from `MediaMetadataRetriever`.

---

## 11. Export progress, cancellation, background, memory

**Progress / cancellation (iOS)**
- iOS 18+: consume `session.states(updateInterval:)` for progress; the
  `export(to:as:)` task is cancellable via Swift `Task` cancellation
  (`task.cancel()` → throws `CancellationError`). There's also
  `session.cancelExport()`.
- ⚠️ **Known footgun:** calling `cancelExport()` from the wrong context
  while the session is mid-export has caused UI freezes/deadlocks in
  shipping apps. Cancel via Task cancellation on the structured-concurrency
  path, or ensure `cancelExport()` is dispatched off the export's own
  queue. (See the Medium write-up + the structured-concurrency gist in
  Sources.)

**Background export**
- AVFoundation export does **not** automatically continue in the
  background. Wrap it in a `beginBackgroundTask(withName:)` /
  `endBackgroundTask` pair to get the ~30s grace window — enough for a
  short clip but **not** a long montage. For anything longer, keep the app
  foregrounded (show progress) or chunk the work. There is no
  `BGProcessingTask`-based offline transcode path that's reliable for
  AVAssetExportSession; treat export as a foreground operation with a
  background-task safety net.
- On tvOS the question is moot (no editing UI there).

**Memory**
- Export itself is streaming and bounded — the risk is **our** code:
  - Don't accumulate all GIF/thumbnail `CGImage`s in an array; stream them
    to the destination as generated (§7).
  - Reuse one Metal-backed `CIContext` for all filtered frames; don't
    create per frame.
  - `AVAssetImageGenerator` with a large `maximumSize` × many frames is a
    memory spike — downscale and bound concurrency.
  - This app already runs on a 3 GB Apple TV shared with 4K AVPlayer
    (Decision 017) — but editing is iOS-only, so device memory is less
    constrained; still, cap clip length / GIF dimensions in the UI.
- One export at a time. Serialize exports (an actor/queue) — concurrent
  `AVAssetExportSession`s contend for the video encoder and thermals.

**Android (parity)** — `Transformer` reports progress via
`Transformer.Listener` / `getProgress(ProgressHolder)`, cancels via
`transformer.cancel()`, and (unlike AVFoundation) can be driven from a
foreground service for background-safe long exports.

---

## 12. Downloading the source before editing (writable-directory constraint)

Editing operates on a **local file**, never a remote URL. The flow:

1. **Download** the chosen MP4 (or a byte range covering the clip window —
   but range-trimming a remote MP4 requires the `moov` atom; for
   progressive archive.org files the whole file is usually simplest)
   via `URLSession` **download task** (`downloadTask(with:)` →
   delegate/async), which streams straight to a temp file on disk rather
   than into memory.
2. **Move it to a writable directory.** The download task's temp URL is
   deleted when the handler returns — move it immediately:

```swift
let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
let dest = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("clip-source-\(id).mp4")
try? FileManager.default.removeItem(at: dest)
try FileManager.default.moveItem(at: tempURL, to: dest)
```

**Writable-directory constraint (cross-platform lesson from this repo):**
- The app **bundle is read-only.** Write only to **`Caches`** (evictable
  under disk pressure — fine for transient source + output) or
  **Documents** (backed up; use for user-saved exports if not going
  straight to Photos), or the **App Group container**.
- On **tvOS** this is sharper: the *only* writable locations are `Caches`
  and the App Group container (Documents is unreliable) — the simulator
  won't warn you. (See `docs/tvos-playbook.md` / `tvos-platform-patterns`
  writable-directory trap.) Editing is iOS-only so this is less binding,
  but keep the shared-Core download code Caches-based for tvOS safety.
- Clean up source + intermediate files after export
  (the existing `ResilientStreamLoader` already streams playback; the
  editor needs a *separate* full-file download since it needs random
  access to a complete local `moov`-bearing file, not a streamed range).

**Reuse opportunity:** the app already downloads/streams via
`ResilientStreamLoader` (Decision 021/031) and resolves the best H.264
derivative via `DerivativePicker`. The editor's downloader should reuse
the same derivative-URL resolution (`downloadURL` baked in the catalog)
but use a plain `URLSession.download` to a complete local file — it needs
the whole file on disk, not a play-as-you-go range stream.

**Android (parity)** — `DownloadManager` or OkHttp to app-specific
external/internal storage (`context.cacheDir` / `getExternalFilesDir`),
then feed the local `Uri` to `Transformer`. Scoped storage means
app-specific dirs need no permission.

---

## Summary capability → framework matrix

| Capability | iOS (native) | Android (native, parity) | OS gate |
|---|---|---|---|
| Trim | `AVMutableComposition` + `AVAssetExportSession` (`export(to:as:)` iOS 18) | Media3 `Transformer` + `ClippingConfiguration` | export(to:as:)/states = iOS 18 |
| Stitch | `AVMutableComposition.insertTimeRange` ×N | `EditedMediaItemSequence` / `Composition` | — |
| Text/watermark overlay | `AVVideoCompositionCoreAnimationTool` (CALayer) or CIFilter handler | `OverlayEffect` + `TextOverlay`/`BitmapOverlay` | bare `AVMutableVideoComposition()` init deprecated iOS 26 — use asset-based init |
| Reframe / letterbox | `videoComposition.renderSize` + layer transform | `Presentation` | — |
| Blurred-fill bg | CIFilter handler (`CIGaussianBlur` + composite) | custom `GlEffect` (defer) | — |
| Speed ramp / slow-mo | `track.scaleTimeRange(_:toDuration:)` | `SpeedChangeEffect`/`setSpeed` | — |
| Color grade / film look | Core Image `CIFilter` chain / `CIColorCube` LUT | Media3 `RgbMatrix`/`SingleColorLut` | — |
| GIF | `AVAssetImageGenerator.images(for:)` + ImageIO `CGImageDestination` (`UTType.gif`) | no native encoder — vendor GIF89a source or ship WebP/MP4 | `images(for:)` = iOS 16 |
| Auto-captions | `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26) → `SFSpeechRecognizer` fallback | `SpeechRecognizer` (offline) — weaker for files | SpeechAnalyzer = iOS 26 |
| OCR on frames | Vision `RecognizeTextRequest` | ML Kit Text Recognition | new Vision Swift API = iOS 18 |
| Save / share | PhotoKit + `ShareLink`/`UIActivityViewController` | `MediaStore` + `ACTION_SEND` + `FileProvider` | `NSPhotoLibraryAddUsageDescription` |
| Trim UI | custom SwiftUI + `AVAssetImageGenerator` filmstrip (NOT `UIVideoEditorController`) | custom Compose + `CompositionPlayer` (exp.) | CompositionPlayer = Media3 1.9 |
| Progress/cancel | `states(updateInterval:)` / Task cancel | `Transformer.Listener` / `cancel()` | iOS 18 for states |
| Download source | `URLSession.download` → move to `Caches` | `DownloadManager`/OkHttp → app dir | tvOS: Caches/App Group only |

---

## Recommended v1 scope (learning-orientation lens)

A clipping/fan-edit feature *invites participation and creative
engagement* with the public-domain archive — strongly aligned with
"makes someone more human" (CLAUDE.md). To keep it from becoming a passive
gimmick, the v1 cut should be:

1. **Trim** (frame-accurate, ≤60s cap) — the core verb.
2. **Reframe** to square / 9:16 / 16:9 with letterbox (blurred-fill v2).
3. **Burned-in caption** the user types (§3a) + the Archive Watch +
   source-link watermark for provenance.
4. **GIF export** (≤6s, ≤480px, 12fps) **and** MP4 export.
5. **Save to Photos + share sheet**, with PD source attribution embedded.

Defer to v2: multi-clip stitching, transitions, speed ramps, color-grade
LUT picker, and auto-captions (SpeechAnalyzer) — each is additive on the
same `AVMutableComposition`/`AVMutableVideoComposition` spine.

Editing is **iPhone/iPad only**; tvOS surfaces shared clips for *viewing*
but has no editing UI.

---

## Sources

- AVAssetExportSession: <https://developer.apple.com/documentation/avfoundation/avassetexportsession>
- AVAssetExportSession.State (iOS 18 progress states): <https://developer.apple.com/documentation/avfoundation/avassetexportsession/state>
- Structured-concurrency export safety (gist): <https://gist.github.com/samsonjs/2f006c5f62f53c9aef820bc050e37809>
- cancelExport freeze write-up: <https://medium.com/@mi9nxi/avassetexportsession-cancelexport-to-exportasynchronously-freezes-ui-8aadf72c43f5>
- Loading media asynchronously: <https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously>
- AVVideoComposition (CIFilter handler + iOS 26 init deprecation): <https://developer.apple.com/documentation/avfoundation/avvideocomposition>
- init(asset:applyingCIFiltersWithHandler:): <https://developer.apple.com/documentation/avfoundation/avvideocomposition/init(asset:applyingcifilterswithhandler:)>
- Custom compositor workaround (CALayer tool bug history): <https://github.com/claygarrett/CustomVideoCompositor>
- Make an animated GIF in Swift (ImageIO): <https://img.ly/blog/how-to-make-an-animated-gif-using-swift/>
- SpeechAnalyzer: <https://developer.apple.com/documentation/speech/speechanalyzer>
- SpeechTranscriber: <https://developer.apple.com/documentation/speech/speechtranscriber>
- On-device SpeechAnalyzer overview: <https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer>
- SFSpeechRecognizer: <https://developer.apple.com/documentation/speech/sfspeechrecognizer>
- Vision framework: <https://developer.apple.com/documentation/vision>
- PhotoKit: <https://developer.apple.com/documentation/photokit>
- Media3 Transformer: <https://developer.android.com/media/media3/transformer>
- Media3 Transformations (clip/effects/overlay/presentation/speed): <https://developer.android.com/media/media3/transformer/transformations>
- Media3 editing-app guide: <https://developer.android.com/media/implement/editing-app>
- Media3 1.9.0 (CompositionPlayer preview, Dec 2025): <https://android-developers.googleblog.com/2025/12/media3-190-whats-new.html>
- Media3 1.5.0 (Jan 2025): <https://android-developers.googleblog.com/2025/01/media3-150-whats-new.html>
- Media3 1.6.0 (Mar 2025): <https://android-developers.googleblog.com/2025/03/media3-1-6-0-is-now-available.html>
- Media3 common processing ops: <https://android-developers.googleblog.com/2025/03/media-processing-performance-jetpack-media3-transformer.html>
- Media3 TextOverlay: <https://androidx.de/androidx/media3/effect/TextOverlay.html>
