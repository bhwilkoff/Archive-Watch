---
name: macos-creation-studio-engine
description: AVFoundation multi-clip editing/render engine patterns for Archive Watch's macOS Creation Studio — one-model-to-composition, the two-pass grade/overlay rule, cache-then-export of REMOTE archive.org proxy clips, and caption-validated word-level supercut timing. Invoke before building or changing any Creation Studio engine/render/export/supercut path.
---

# macOS Creation Studio — Editing & Render Engine

Binding spec: `docs/macOS-DESIGN.md` §3–§6. Evidence:
`docs/research/creation-studio-{avfoundation-engine,proxy-remote-editing,supercut-subtitle-search}.md`.
This is the engine analogue of `tvos-platform-patterns` — invoke it instead of
re-deriving the composition pipeline.

## The load-bearing rules

1. **One model → one composition → preview == export.** A `Timeline` (clips =
   `sourceAssetID` + `sourceRange` + `timelineRange` + per-clip overlays/audio/effects)
   compiles to ONE `(AVMutableComposition, AVVideoComposition.Configuration,
   AVMutableAudioMix)` triple that feeds both `AVPlayerItem` (scrub) and the exporter.
   `AVComposition` *is* an `AVAsset` — so the same triple plays and renders. The user must
   render exactly what they previewed.

2. **Rebuild-and-swap, never mutate live.** Each edit recompiles the triple and
   `replaceCurrentItem`s. Never mutate a composition attached to a playing player.

3. **The two-pass split is law.** Per-frame Core Image grade and the
   `AVVideoCompositionCoreAnimationTool` (CALayer) overlay tool CANNOT share one
   `AVVideoComposition` (inherited Decision-033 constraint). Order: grade → ProRes
   intermediate → overlay pass. An intermediate-render manager owns temp files + ordering +
   cleanup. Get it wrong → overlays vanish or grades tint the titles.

4. **Cache-then-export, NEVER stream-into-export.** `AVAssetExportSession` is unreliable on
   remote URLs (`-11800`/`-16974`). For each proxy clip: probe the moov (archive.org
   `.ia.mp4` is NOT guaranteed faststart), pre-fetch ONLY the in/out byte range via
   `ResilientStreamLoader` → local faststart MP4 (`ffmpeg -c copy`) → compose/export from
   local files. This is the #1 reliability risk and its resolution.

5. **Track discipline.** Video on a 2-track A/B scheme (overlap only at transitions); audio
   on N tracks with `AVMutableAudioMixInputParameters` volume ramps. Transitions = native
   opacity/transform/crop ramps on layer-instruction Configurations; a Metal
   `AVVideoCompositing` compositor ONLY when GPU blends are truly needed (it replaces the
   standard compositor for the whole composition — a large surface).

6. **Configuration-based AVFoundation API only** (matches the migrated iOS engine;
   CREATE-STUDIO-PLAN §5c). Confirm exact symbols against the live macOS 26 SDK with
   `swift-api-digester` before relying on them.

7. **Apple frameworks in-app; ffmpeg/CLI as subprocess** for range re-mux, ProRes
   intermediates, scene detection, forced alignment. The Mac advantage, not a workaround.

## Supercut (#9) word timing — the caption-validated rule

SRT/VTT is line-level; isolating one spoken word needs word timing. Use macOS-26
**SpeechTranscriber/SpeechAnalyzer** (on-device per-word `CMTimeRange`) but VALIDATE its
word stream against the held caption text (token diff: keep agreeing words, drop invented
ones). Caption = ground truth for *what*; recognizer = *when*. This is the Decision-039b
hallucination fix applied to timing. MFA forced alignment for the rough-audio tail. Never
ship raw recognizer output as truth.

## The learning gate (never violate)

#9 (supercut) and #6 (auto-tag) output an EDITABLE timeline of candidates — never a one-tap
finished cut. Unmatched supercut words become explicit editable gaps. Every export burns
the provenance credit + embeds source `archive.org/details/{id}`. Rights-gated
`isClippable` only.

## When NOT to use this

Single-clip phone editing is `all-ios-skills` + Decision 033 (Clip Studio), not this. This
skill is multi-clip, Mac-only, remote-source composition.
