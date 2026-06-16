# Clip Studio — content-creation feature plan (iOS / Android)

**Status:** v1 in progress (iOS). Binding plan for the "Create" surface
across the native phone apps.

**One-line thesis:** phones *create*, they don't just consume. The native
iPhone/iPad and Android apps differentiate from the tvOS and web apps by
turning the public-domain archive into raw material — users clip, reframe,
caption, and export archive.org films as social-media-ready video and GIFs.
tvOS and web remain lean-back viewers; the phone is the workbench.

Research that backs this plan:
- `docs/research/social-clip-creation.md` — formats, specs, fan-edit craft.
- `docs/research/video-clipping-native-frameworks.md` — the native tool suite.

---

## 1. Why this belongs here (learning-orientation test)

Run against the four questions (CLAUDE.md / `learning-orientation-design`):

1. **Deepens understanding** — clipping forces frame-by-frame engagement
   with archival film and surfaces its provenance (source, year, archive
   origin). The opposite of a passive feed.
2. **Invites participation** — the user *is* the editor. They choose the
   moment, the framing, the words. Co-authorship, not reception.
3. **Supports agency** — **only if we do not ship a one-tap "auto fan-edit"
   button.** The editorial cut is the meaningful act; automating it would
   strip the learning. So: **automate the mechanical** (frame extraction,
   encoding, reframe math, attribution-credit generation) and **preserve
   the meaningful** (which moment, what caption, where to cut). The human
   stays in the loop.
4. **Clarity over cleverness** — v1 is a tight pipeline (trim → reframe →
   caption + credit → export → share). The clever craft tools (beat-sync,
   color LUTs, speed ramps, auto-captions) are deferred to v2 on the same
   composition spine, not crammed in now.

**The distinctive wedge** (from the social-clip research): *auto-generated
provenance / attribution credits*. Every export carries a burned-in
"archivewatch.org · public domain" credit and embeds the
`archive.org/details/{id}` source in file metadata. We turn an attribution
requirement into a culturally-native feature no competitor has — and one
that teaches viewers where the footage came from.

---

## 2. Rights gate (binding)

Clipping is **only offered for content we can confidently call free**.
Per Decision 027 the catalog already excludes copyrighted titles upstream,
but the Create entry point adds an in-app gate as defense in depth:

> `Catalog.Item.isClippable` == has a playable video URL **and**
> `rightsStatus` is `public_domain`, `creative_commons`, a `cc*` license,
> or `nil` (post-027 the visible catalog is PD/CC-only). A `rightsStatus`
> that names a copyright/rights-reserved state is **not** clippable.

If an item is not clippable, the Create affordance is hidden (not disabled
with an error) — we don't advertise a capability we then refuse.

---

## 3. v1 feature set (iOS first)

The Clip Studio, launched from a **scissors "Create" button** on the iOS
Detail view (and later the player), is a single full-screen editor:

| Capability | v1 behavior | Framework |
|---|---|---|
| **Trim** | Frame-accurate in/out over a thumbnail filmstrip. Video clips capped ≤60s; GIF ≤6s. | `AVMutableComposition` + `AVAssetExportSession` |
| **Reframe** | Original / 1:1 / 9:16 / 16:9, letterbox fill (solid matte). Blurred-fill is v2. | `AVMutableVideoComposition.renderSize` + layer transform |
| **Caption** | One user-typed burned-in caption, lower-third, title-safe. | `AVVideoCompositionCoreAnimationTool` (video) / Core Graphics (GIF) |
| **Provenance credit** | Always-on small "archivewatch.org · public domain" credit; source URL embedded in file metadata. | same overlay path + `AVMetadataItem` |
| **Export** | MP4 (H.264, shareable everywhere) **or** GIF (≤480px, 12fps, looping). | `AVAssetExportSession` / `AVAssetImageGenerator` + ImageIO |
| **Save / share** | Save to Photos (add-only permission) + system share sheet. | PhotoKit + `ShareLink` |

**Source acquisition:** the editor downloads the full source MP4 to
`Caches` with visible progress, then edits the local file (the research's
robust recommendation — a complete local `moov`-bearing file gives
predictable AVFoundation behavior). Cached so repeat edits are instant.
*Known v1 cost:* downloading a feature to clip 15s is wasteful — **v2**
should range-download only the needed window keyed on the `moov` index.

**Persistence:** a `VideoClip` SwiftData model records each saved clip's
definition (source id, in/out, aspect, caption, format) + the cached output
path, so a "Clips" surface in Library can re-share / re-export. If the
cached file is evicted, re-export from the stored definition.

**Editing is iPhone/iPad only.** tvOS and web have no editing affordance
(no text entry / direct-manipulation timeline). The AVFoundation *engine*
lives in `Services/` guarded `#if os(iOS)`.

---

## 4. v2 — status (same composition spine — additive, do not rebuild)

**Shipped (iOS, 2026-06-16):**
- **Color-grade "Looks"** — Silent (sepia) / Noir / Faded / Technicolor / B&W,
  native CIFilter chains (`ClipLook`). Live grade preview on the player.
- **Speed** — 0.5× / 1× / 2× via `scaleTimeRange` (A/V scaled together).
- **Clips library** — a Clips section in iOS Library lists saved `VideoClip`s
  (share the cached render / revisit source / delete); definition is the source
  of truth if the render is evicted.
- **Blurred-fill reframe background** — the "Instagram" archival adaptation: a
  scaled-up `CIGaussianBlur` of the frame behind the centered fit, toggleable
  per non-Original aspect. Unified into the Core Image pass (grade + reframe in
  one handler → overlay pass); GIF gets it via a blurred Core Graphics bg.
- **Auto-captions** — `SFSpeechRecognizer` on-device transcription of the clip
  range → cues grouped ~7 words/≤2.2s → burned in as timed CALayer overlays
  (per-cue opacity keyframes, speed-mapped). MP4 only (GIF keeps the static
  caption). `SpeechAnalyzer` (iOS 26) is the future upgrade.

  > **The two passes:** a color grade / blurred-fill reframe (Core Image) and
  > the caption+credit overlay (CALayer animation tool) can't share one
  > `AVMutableVideoComposition`, so when either CI feature is on the video
  > renders in two passes (CI grade+reframe → overlay+speed). A plain letterbox
  > clip with no look stays single-pass.

**Still deferred (next wave, additive on the same spine):**
- **Multi-clip stitching** (montage) + **hard-cut → crossfade transitions** —
  a multi-source picker/sequence UI on `insertTimeRange` ×N. *The largest
  remaining piece — the "montage fan-edit."*
- **Beat detection + snap-to-beat trimming.**
- **Range-download optimization** — fetch only the clip window keyed on the
  `moov` index instead of the whole film (improves the wait before editing a
  feature).
- **Cross-device sync** of clip definitions (CloudKit / Drive App Data).
- **Android v2+**: GIF (WebP/vendored encoder), blurred-fill (custom GL effect),
  auto-captions, Media3 live preview.

---

## 5. Android parity (implementation after iOS)

Feature-parity, native idiom (Decision 028 / `PARITY.md`). Engine spine:
**Jetpack Media3 `Transformer`** — `ClippingConfiguration` (trim),
`Presentation` (reframe), `OverlayEffect` + `TextOverlay`/`BitmapOverlay`
(caption + credit), `MediaStore` + `ACTION_SEND` (save/share). **GIF is
Android's weak native story** (no native encoder) — ship MP4/WebP first and
treat true-GIF as best-effort (vendor a GIF89a encoder as source if needed).
Tracked as a `PARITY.md` row from day one with the deliberate-defer reason.

---

## 5b. Native-first audit (`native-platform-first`)

Every interaction was checked against a native primitive before any custom
code. Verified against current API/design docs (June 2026):

| Surface | Native primitive used | Custom? |
|---|---|---|
| Trim/reframe/caption/GIF **engine** | AVFoundation, ImageIO, PhotoKit (iOS); Media3 `Transformer` (Android) | No — 100% native |
| Clip preview | AVKit `VideoPlayer` | No |
| Format / aspect choice | SwiftUI `Picker(.segmented)` | No |
| Caption entry | SwiftUI `TextField` | No |
| Save to library | PhotoKit `PHAssetCreationRequest` (add-only) | No |
| Share | SwiftUI `ShareLink` | No |
| Modal / nav / progress / errors | `.sheet`, `NavigationStack`, `.toolbar`, `ProgressView`, `.alert` | No |
| **Trim timeline (filmstrip + handles)** | — none exists — | **Yes (justified)** |

**The one custom piece — the trim timeline — and why it's justified:**
- `UIVideoEditorController` (still shipping, not deprecated) is the *only*
  Apple-provided trimming UI, and it is **trim + quality preset only** — it
  cannot reframe to 9:16, burn a caption, encode a GIF, or preview those.
  It is UIKit-modal and can't compose into the rest of the editor.
- There is **no native SwiftUI/UIKit timeline-trimmer component**. Apple's
  own editor sample code (AVSimpleEditor / AVCustomEdit) builds the timeline
  custom on AVFoundation; the documented community pattern is the same.
- Android is identical: Media3 ships the engine + an experimental
  `CompositionPlayer` preview, but only a **demo** editor UI, not a reusable
  component.

**Decision:** build the trim timeline custom (it's the platform-endorsed
path for an editor richer than trim-only), keep that custom layer *thin* (it
only positions two handles over native `AVAssetImageGenerator` thumbnails and
seeks a native `AVPlayer`; all rendering is native), and re-evaluate on each
major OS release in case Apple/Google ship a reusable trimmer. Logged as
Decision 033.

*Alternative on the table for the owner:* use `UIVideoEditorController` for
the trim sub-step (strictly native trim bar), then layer reframe/caption/GIF
after. Rejected as the default because it fragments the flow into two modals
and can't preview the reframe/caption — but it is a one-screen swap if a
strictly-native trim is preferred.

## 5c. iOS 26/27 video-composition API (binding)

The app targets iOS 26 (SDK 27). The legacy `AVMutableVideoComposition` +
`AVMutable*Instruction` + the synchronous CIFilter init are all deprecated.
**Use the Configuration-based API — do not reintroduce the deprecated types:**
- Video composition: `AVVideoComposition.Configuration` (set `renderSize`,
  `frameDuration`, `instructions`, `animationTool`) → `AVVideoComposition(configuration:)`.
- Instructions: `AVVideoCompositionInstruction.Configuration` →
  `AVVideoCompositionInstruction(configuration:)`; layer:
  `AVVideoCompositionLayerInstruction.Configuration(trackID:)` →
  `AVVideoCompositionLayerInstruction(configuration:)`.
- Core Animation overlay: `AVVideoCompositionCoreAnimationTool.Configuration(
  postProcessingAsVideoLayer:containingLayer:)` → `init(configuration:)`.
- Core Image filtering: `async AVVideoComposition(applyingFiltersTo:applier:)`
  where the applier is `(AVCIImageFilteringParameters) async throws ->
  AVCIImageFilteringResult` (use `request.sourceImage` / `request.renderSize`;
  return `AVCIImageFilteringResult(resultImage:)`).
- **Custom render size for a CI pass**: the CI applier init has no renderSize
  param, so trim into an `AVMutableComposition` and set its `naturalSize` to the
  target — that becomes the CI `renderSize`. (This is the blurred-fill/reframe
  path; verify the source-frame framing on device.)

## 6. New views / surfaces this introduces (for the design doc)

- **ClipStudioView** (iOS) — full-screen editor sheet from Detail.
- **Create button** — scissors icon in the Detail action row, rights-gated.
- (v1.1) **Clips** — a Library section listing saved `VideoClip`s.

These get binding entries in `docs/iOS-DESIGN.md` (and `ANDROID-DESIGN.md`
when Android lands). The editor is a *sheet*, not a nav push — it's a modal
task with its own Cancel/Done lifecycle.
