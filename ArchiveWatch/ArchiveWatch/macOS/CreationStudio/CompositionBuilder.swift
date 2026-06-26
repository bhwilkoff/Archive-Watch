#if os(macOS)
import Foundation
import AVFoundation
import QuartzCore
import AppKit

// Timeline → composition compiler (docs/macOS-DESIGN.md §3). Rule 3a: ONE model compiles
// to the (AVMutableComposition, AVVideoComposition) pair that feeds BOTH preview and
// export. Rule 3e: Configuration-based AVFoundation API only (the whole macOS app targets
// 26, so the symbols are unconditionally available — no @available gating). Mirrors the
// proven iOS ClipExporter pipeline, adapted for MULTI-CLIP and reading LOCAL cached files.
//
// Phase 1 = a magnetic single video track (sequential clips, no transitions yet → one
// track suffices; the A/B 2-track scheme + opacity ramps arrive with transitions, Rule
// 3c). Each clip gets its own instruction over its sub-range carrying its aspect-fit
// transform. The provenance credit (Rule 5b / the learning gate) is a CATextLayer burned
// across the whole timeline via the Core Animation tool. No CI grade in Phase 1, so a
// single pass suffices — the two-pass grade→overlay split (Rule 3d) lands with grades.

struct BuiltComposition {
    let composition: AVMutableComposition
    let videoComposition: AVVideoComposition
    let audioMix: AVAudioMix?
    let duration: CMTime
}

enum CompositionBuilder {
    /// One clip already resolved to a loaded asset + the source range to splice in. EXPORT
    /// resolves to local cached files ([0, fileDuration]); PREVIEW resolves to the remote
    /// resilient asset + the live in/out range — same recipe, different source backing, so
    /// "preview == export" holds (Rule 3a).
    struct ResolvedClip {
        let asset: AVURLAsset
        let insertRange: CMTimeRange
        var audioVolume: Double = 1.0
        var fadeIn: Double = 0           // seconds: fade up from black + audio in over the head
        var fadeOut: Double = 0          // seconds: fade to black + audio out over the tail
        var transitionIn: Double = 0     // seconds: transition from the previous clip into this one
        var transitionKind: TransitionKind = .dissolve
    }

    /// An imported/recorded audio clip: a local audio file on its own track (#4, N tracks).
    /// `maxDuration` caps how long it plays (nil = to program end); fadeIn/fadeOut ramp its ends.
    struct ResolvedMusic {
        let asset: AVURLAsset
        let volume: Double
        let startSeconds: Double
        var maxDuration: Double? = nil
        var fadeIn: Double = 0
        var fadeOut: Double = 0
    }

    /// Compile resolved clips (in timeline order) into the (composition, videoComposition)
    /// pair. `creditLine == nil` means a clean export — no burned attribution (owner
    /// decision: attribution is optional). Shared by preview + export.
    ///
    /// `bakeOverlays` burns the timed text + provenance credit via the Core Animation tool.
    /// EXPORT passes true; PREVIEW passes FALSE — AVVideoCompositionCoreAnimationTool is
    /// offline-render-only and AVPlayerItem.setVideoComposition rejects it (a hard crash:
    /// "AVVideoCompositionCoreAnimationTool is for offline rendering only"). The clip splices,
    /// reframe transforms, and audio mix are identical either way, so the preview frame still
    /// matches the export; the editor draws overlays live over the program monitor instead.
    static func build(resolved: [ResolvedClip], timeline: Timeline,
                      creditLine: String?, bakeOverlays: Bool = true,
                      beds: [ResolvedMusic] = []) async throws -> BuiltComposition {
        let comp = AVMutableComposition()
        // Two video + two audio tracks (A/B) so adjacent clips can OVERLAP for a cross-dissolve
        // (Rule 3c). Clips alternate tracks; a plain cut just abuts on alternating tracks. Fades
        // and dissolves are both opacity/volume ramps, so they live in the standard compositor
        // (no CI handler) — the preview shows them and preview == export holds.
        guard let vA = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vB = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CreationStudioError.noVideoTrack
        }
        let aA = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let aB = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let vTracks = [vA, vB], aTracks = [aA, aB]
        let renderSize = timeline.renderSize.cgSize

        // A placed clip in TIMELINE coordinates (after overlap), with its transition/audio envelope.
        struct Placed {
            var trackIndex: Int
            var trackID: CMPersistentTrackID
            var start: CMTime
            var dur: CMTime
            var transform: CGAffineTransform
            var fadeIn: Double           // fade up from black (opacity), when there's no incoming transition
            var fadeOut: Double          // fade to black (opacity) at the tail
            var transIn: Double          // incoming transition from the previous clip (overlap)
            var transKind: TransitionKind
            var nextOverlap: Double      // the NEXT clip's transition that overlaps this clip's tail
            var nextKind: TransitionKind
            var leadIn: Double           // audio ramp-up = max(fadeIn, transIn)
            var vol: Float
            var audioTailOut: Double     // audio ramp-down = max(fadeOut, next clip's transition)
            var hasAudio: Bool
        }
        var placed: [Placed] = []
        var cursor = CMTime.zero
        let ts: Int32 = 600

        for (i, r) in resolved.enumerated() {
            guard let srcV = try await r.asset.loadTracks(withMediaType: .video).first else { continue }
            let insertRange = r.insertRange
            guard insertRange.duration.isNumeric, insertRange.duration > .zero else { continue }
            let ti = i % 2
            let vTrack = vTracks[ti]
            let durS = insertRange.duration.seconds
            // Overlap with the previous clip by transitionIn (0 for the first clip / a hard cut).
            let trans = i == 0 ? 0 : max(0, min(r.transitionIn, durS))
            let start = i == 0 ? .zero : CMTimeMaximum(.zero, cursor - CMTime(seconds: trans, preferredTimescale: ts))
            try vTrack.insertTimeRange(insertRange, of: srcV, at: start)

            var hasAudio = false
            if let aTrack = aTracks[ti], let srcA = try await r.asset.loadTracks(withMediaType: .audio).first {
                try? aTrack.insertTimeRange(insertRange, of: srcA, at: start)
                hasAudio = true
            }

            let natural = try await srcV.load(.naturalSize)
            let preferred = try await srcV.load(.preferredTransform)
            let oriented = natural.applying(preferred)
            let orientedAbs = CGSize(width: abs(oriented.width), height: abs(oriented.height))
            let transform = preferred.concatenating(aspectFit(orientedAbs, into: renderSize))

            let fadeIn = trans > 0 ? 0 : max(0, min(r.fadeIn, durS))     // fade XOR transition on the head
            let leadIn = min(max(r.fadeIn, trans), durS)
            placed.append(Placed(trackIndex: ti, trackID: vTrack.trackID, start: start, dur: insertRange.duration,
                                 transform: transform, fadeIn: fadeIn,
                                 fadeOut: max(0, min(r.fadeOut, durS - leadIn)),
                                 transIn: trans, transKind: r.transitionKind,
                                 nextOverlap: 0, nextKind: .dissolve,
                                 leadIn: leadIn, vol: Float(max(0, r.audioVolume)),
                                 audioTailOut: 0, hasAudio: hasAudio))
            cursor = start + insertRange.duration
        }
        guard !placed.isEmpty else { throw CreationStudioError.noClips }

        // Patch each clip's OUTGOING side from the following clip's transition (audio crossfade +
        // the push-out / cover during the next clip's transition).
        for i in placed.indices {
            let nextTrans = (i + 1 < resolved.count) ? max(0, resolved[i + 1].transitionIn) : 0
            placed[i].nextOverlap = max(0, min(nextTrans, placed[i].dur.seconds))
            placed[i].nextKind = (i + 1 < resolved.count) ? resolved[i + 1].transitionKind : .dissolve
            placed[i].audioTailOut = max(0, min(max(placed[i].fadeOut, nextTrans), placed[i].dur.seconds - placed[i].leadIn))
        }

        // Segment the timeline at every clip start/end. In each segment the active clips become
        // ONE instruction; the later-starting clip goes in FRONT (index 0) so a dissolve reveals
        // it over the previous. Opacity ramps are set in full and clamped by AVFoundation to the
        // instruction's range.
        //
        // The instructions MUST form a strictly contiguous, gap-free, in-order cover of
        // [0, total] using EXACT shared CMTime boundaries (never seconds round-trips). The preview
        // (AVPlayerItem, no animation tool) tolerates gaps by rendering black, but
        // AVAssetExportSession WITH the Core Animation overlay tool validates the composition
        // strictly and rejects ANY gap/overlap/zero-width sliver with AVErrorInvalidVideoComposition
        // (-11841) — which is why export failed while preview played. So: build deduped boundary
        // CMTimes (incl. 0 and the true end `cursor`), and emit an instruction for EVERY consecutive
        // pair — including a background-only one for any sliver with no active clip.
        var boundary: [CMTime] = [.zero, cursor]
        for p in placed { boundary.append(p.start); boundary.append(p.start + p.dur) }
        boundary.sort { $0.seconds < $1.seconds }
        var cuts: [CMTime] = []
        for b in boundary {
            if b.seconds < -0.0005 || b.seconds > cursor.seconds + 0.0005 { continue }
            if let last = cuts.last, abs(b.seconds - last.seconds) < 0.0005 { continue }   // dedupe
            cuts.append(b)
        }
        var instructions: [AVVideoCompositionInstruction] = []
        for k in 0..<max(0, cuts.count - 1) {
            let b0 = cuts[k], b1 = cuts[k + 1]                           // exact, shared boundaries
            let t0 = b0.seconds, t1 = b1.seconds
            guard t1 - t0 > 0.0005 else { continue }                    // (won't fire after dedupe)
            let mid = (t0 + t1) / 2
            let active = placed.filter { $0.start.seconds <= mid && ($0.start + $0.dur).seconds >= mid }
                               .sorted { $0.start.seconds < $1.start.seconds }
            var layerInstrs: [AVVideoCompositionLayerInstruction] = []
            for p in active.reversed() {                                  // later start first → frontmost
                var cfg = AVVideoCompositionLayerInstruction.Configuration(trackID: p.trackID)
                cfg.setTransform(p.transform, at: b0)
                let W = renderSize.width
                func range(_ s: Double, _ d: Double) -> CMTimeRange {
                    CMTimeRange(start: CMTime(seconds: s, preferredTimescale: ts),
                                duration: CMTime(seconds: d, preferredTimescale: ts))
                }
                // INCOMING transition (this clip arrives over [start, start+transIn]).
                if p.transIn > 0 {
                    let r0 = p.start.seconds
                    switch p.transKind {
                    case .dissolve:
                        cfg.addOpacityRamp(.init(timeRange: range(r0, p.transIn), start: 0, end: 1))
                    case .push:   // slide in from the right
                        cfg.addTransformRamp(.init(timeRange: range(r0, p.transIn),
                            start: p.transform.concatenating(.init(translationX: W, y: 0)), end: p.transform))
                    case .wipe:   // reveal left→right via a growing crop
                        cfg.addCropRectangleRamp(.init(timeRange: range(r0, p.transIn),
                            start: CGRect(x: 0, y: 0, width: 0, height: renderSize.height),
                            end: CGRect(origin: .zero, size: renderSize)))
                    }
                } else if p.fadeIn > 0 {
                    cfg.addOpacityRamp(.init(timeRange: range(p.start.seconds, p.fadeIn), start: 0, end: 1))
                }
                // OUTGOING side — only a PUSH moves the outgoing clip (dissolve/wipe leave it behind).
                if p.nextOverlap > 0, p.nextKind == .push {
                    let os = (p.start + p.dur).seconds - p.nextOverlap
                    cfg.addTransformRamp(.init(timeRange: range(os, p.nextOverlap),
                        start: p.transform, end: p.transform.concatenating(.init(translationX: -W, y: 0))))
                }
                // Fade to black at the tail (opacity).
                if p.fadeOut > 0 {
                    cfg.addOpacityRamp(.init(timeRange: range((p.start + p.dur).seconds - p.fadeOut, p.fadeOut),
                                             start: 1, end: 0))
                }
                layerInstrs.append(AVVideoCompositionLayerInstruction(configuration: cfg))
            }
            var ic = AVVideoCompositionInstruction.Configuration()
            ic.timeRange = CMTimeRange(start: b0, end: b1)               // exact → contiguous cover
            ic.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)   // letterbox matte
            ic.layerInstructions = layerInstrs                          // may be empty (background sliver)
            instructions.append(AVVideoCompositionInstruction(configuration: ic))
        }
        guard !instructions.isEmpty else { throw CreationStudioError.noClips }

        var cfg = AVVideoComposition.Configuration()
        cfg.renderSize = renderSize
        cfg.frameDuration = CMTime(value: 1, timescale: Int32(max(1, timeline.frameRate.rounded())))
        cfg.instructions = instructions

        // Core Animation overlay pass — burned timed text overlays (#3) + the optional
        // provenance credit. Skipped entirely for a clean export with no overlays. (Single
        // pass: no CI grade yet, so the two-pass grade→overlay split, Rule 3d, isn't needed
        // until color grades arrive.)
        let totalDuration = cursor.seconds
        if bakeOverlays, creditLine != nil || !timeline.textOverlays.isEmpty {
            let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: renderSize)
            let videoLayer = CALayer(); videoLayer.frame = parent.frame
            parent.addSublayer(videoLayer)
            for ov in timeline.textOverlays {
                addTextOverlay(ov, to: parent, size: renderSize, total: totalDuration)
            }
            if let creditLine { addCredit(creditLine, to: parent, size: renderSize) }
            let toolCfg = AVVideoCompositionCoreAnimationTool.Configuration(
                postProcessingAsVideoLayer: videoLayer, containingLayer: parent)
            cfg.animationTool = AVVideoCompositionCoreAnimationTool(configuration: toolCfg)
        }

        // Audio mix — per clip: base volume (#4) + ramp up (fade-in / dissolve-in) + ramp down
        // (fade-out / dissolve-out into the next clip), one AVMutableAudioMixInputParameters per
        // audio track (A/B), so a cross-dissolve cross-fades the audio too.
        var audioMix: AVAudioMix?
        var anyRamp = false
        var paramsList: [AVMutableAudioMixInputParameters] = []
        for (ti, aTrack) in aTracks.enumerated() {
            guard let aTrack else { continue }
            let onTrack = placed.filter { $0.trackIndex == ti && $0.hasAudio }
            guard !onTrack.isEmpty else { continue }
            let params = AVMutableAudioMixInputParameters(track: aTrack)
            // AVMutableAudioMix CRASHES ("the timeRange of a ramp must not overlap…") if two volume
            // ramps on one track overlap. That happens when a cross-dissolve makes a short clip's two
            // neighbors — which share this A/B track — overlap in time, so their fade ramps collide.
            // Collect every ramp, sort by start, and clamp each to begin no earlier than the previous
            // one ended (touching is fine; only overlap throws). Distorts a fade slightly in that rare
            // overlap case — far better than a crash.
            struct Ramp { var start: Double; var end: Double; let from: Float; let to: Float }
            var ramps: [Ramp] = []
            for p in onTrack {
                let durS = p.dur.seconds
                let vIn = min(max(p.leadIn, 0), durS)
                let vOut = min(max(p.audioTailOut, 0), durS - vIn)
                params.setVolume(p.vol, at: p.start)
                if p.vol != 1 { anyRamp = true }
                let s = p.start.seconds, e = (p.start + p.dur).seconds
                if vIn > 0 { ramps.append(Ramp(start: s, end: s + vIn, from: 0, to: p.vol)) }
                if vOut > 0 { ramps.append(Ramp(start: e - vOut, end: e, from: p.vol, to: 0)) }
            }
            ramps.sort { $0.start < $1.start }
            var lastEnd = -Double.greatestFiniteMagnitude
            for var r in ramps {
                if r.start < lastEnd { r.start = lastEnd }          // clamp to the previous ramp's end
                guard r.end - r.start > 0.001 else { continue }     // collapsed by the clamp → drop
                params.setVolumeRamp(fromStartVolume: r.from, toEndVolume: r.to,
                                     timeRange: CMTimeRange(start: CMTime(seconds: r.start, preferredTimescale: ts),
                                                            duration: CMTime(seconds: r.end - r.start, preferredTimescale: ts)))
                lastEnd = r.end
                anyRamp = true
            }
            paramsList.append(params)
        }

        // Audio clips (#4 audio layers) — N music + voiceover, each its OWN track. Each plays from
        // its start for its own length (capped at the program end), honoring its fade in/out; if it
        // has no explicit fade-out, a gentle tail keeps it from cutting abruptly.
        for bed in beds where cursor.seconds > bed.startSeconds + 0.05 {
            guard let mTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let srcA = try? await bed.asset.loadTracks(withMediaType: .audio).first else { continue }
            let toProgramEnd = cursor.seconds - bed.startSeconds
            let avail = (try? await bed.asset.load(.duration).seconds) ?? toProgramEnd
            let cap = bed.maxDuration ?? toProgramEnd
            let dur = CMTime(seconds: max(0.1, min(toProgramEnd, avail, cap)), preferredTimescale: ts)
            let at = CMTime(seconds: max(0, bed.startSeconds), preferredTimescale: ts)
            try? mTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: srcA, at: at)
            let mp = AVMutableAudioMixInputParameters(track: mTrack)
            let vol = Float(max(0, bed.volume))
            mp.setVolume(vol, at: at)
            // Fade IN from silence over the head, if requested.
            var fadeInEnd = 0.0
            if bed.fadeIn > 0.01 {
                let f = min(bed.fadeIn, dur.seconds)
                mp.setVolumeRamp(fromStartVolume: 0, toEndVolume: vol,
                                 timeRange: CMTimeRange(start: at, duration: CMTime(seconds: f, preferredTimescale: ts)))
                fadeInEnd = f
            }
            // Fade OUT over the tail — explicit if set, else a gentle default so the clip doesn't snap
            // off. Clamp so it can't overlap the fade-in on a short bed (overlapping ramps crash).
            let fadeOut = min(bed.fadeOut > 0.01 ? min(bed.fadeOut, dur.seconds) : min(1.5, dur.seconds / 2),
                              max(0, dur.seconds - fadeInEnd))
            if fadeOut > 0 {
                mp.setVolumeRamp(fromStartVolume: vol, toEndVolume: 0,
                                 timeRange: CMTimeRange(start: at + dur - CMTime(seconds: fadeOut, preferredTimescale: ts),
                                                        duration: CMTime(seconds: fadeOut, preferredTimescale: ts)))
            }
            paramsList.append(mp); anyRamp = true
        }
        if anyRamp { let mix = AVMutableAudioMix(); mix.inputParameters = paramsList; audioMix = mix }

        return BuiltComposition(composition: comp,
                                videoComposition: AVVideoComposition(configuration: cfg),
                                audioMix: audioMix,
                                duration: cursor)
    }

    /// Aspect-fit `src` into `dst`, centered (letterboxed). Mirrors the iOS engine.
    static func aspectFit(_ src: CGSize, into dst: CGSize) -> CGAffineTransform {
        guard src.width > 0, src.height > 0 else { return .identity }
        let scale = min(dst.width / src.width, dst.height / src.height)
        let w = src.width * scale, h = src.height * scale
        let tx = (dst.width - w) / 2, ty = (dst.height - h) / 2
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    /// A timed text overlay: a CATextLayer shown only during its window via an opacity
    /// keyframe over the whole composition (the proven iOS timed-caption pattern — note the
    /// AVCoreAnimationBeginTimeAtZero + fillMode/isRemovedOnCompletion gotchas).
    private static func addTextOverlay(_ ov: TextOverlay, to parent: CALayer,
                                       size: CGSize, total: Double) {
        guard total > 0, !ov.text.isEmpty,
              let img = renderTextImage(ov, canvasSize: size) else { return }
        // Render to a CGImage in a plain CALayer (an ANIMATED CATextLayer does not render in
        // the Core Animation tool; an image layer does — the proven iOS timed-cue path).
        let layer = CALayer()
        layer.contents = img
        layer.contentsGravity = .resizeAspect
        let w = CGFloat(img.width) / 2, h = CGFloat(img.height) / 2   // image is @2x
        let cx = ov.positionX * size.width
        let cyBottom = size.height - ov.positionY * size.height       // y from TOP; CA origin bottom-left
        layer.frame = CGRect(x: cx - w / 2, y: cyBottom - h / 2, width: w, height: h)

        let s = min(max(ov.timelineRange.start.seconds / total, 0), 1)
        let e = min(max(ov.timelineRange.endSeconds / total, s), 1)
        layer.opacity = 0
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 0, 1, 1, 0, 0]
        anim.keyTimes = [0, max(0, s - 0.0001), s, e, min(1, e + 0.0001), 1].map { NSNumber(value: $0) }
        anim.duration = total
        anim.beginTime = AVCoreAnimationBeginTimeAtZero          // literal 0 = "now" (won't render)
        anim.isRemovedOnCompletion = false
        anim.fillMode = .both
        layer.add(anim, forKey: "opacity")
        parent.addSublayer(layer)
    }

    /// Render an overlay's text to a @2x CGImage via Core Graphics (NSAttributedString) —
    /// crisp, and reliable inside the Core Animation tool.
    private static func renderTextImage(_ ov: TextOverlay, canvasSize: CGSize) -> CGImage? {
        let scale: CGFloat = 2
        let fontSize = max(8, canvasSize.width * ov.fontScale) * scale
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping
        let nsColor = NSColor(cgColor: cgColor(hex: ov.colorHex)) ?? .white
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor, .paragraphStyle: para]
        if ov.hasBackground {
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(0.9)
            sh.shadowBlurRadius = fontSize * 0.14
            sh.shadowOffset = CGSize(width: 0, height: -fontSize * 0.04)
            attrs[.shadow] = sh
        }
        let str = NSAttributedString(string: ov.text, attributes: attrs)
        let maxW = canvasSize.width * 0.86 * scale
        let bounds = str.boundingRect(with: CGSize(width: maxW, height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading])
        let pad = fontSize * 0.4
        let w = Int(ceil(bounds.width) + pad * 2), h = Int(ceil(bounds.height) + pad * 2)
        guard w > 1, h > 1,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        str.draw(with: CGRect(x: pad, y: pad, width: CGFloat(w) - pad * 2, height: CGFloat(h) - pad * 2),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Parse "#RRGGBB" / "#RGB" → CGColor (no SwiftUI dependency in the engine).
    static func cgColor(hex: String) -> CGColor {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return CGColor(gray: 1, alpha: 1) }
        return CGColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// The burned "archivewatch.org · Public Domain" credit, pinned bottom-center
    /// (CALayer origin is bottom-left). A CATextLayer keeps it cross-platform — no
    /// UIKit/AppKit image rendering needed for a single text line.
    private static func addCredit(_ text: String, to parent: CALayer, size: CGSize) {
        let credit = CATextLayer()
        credit.string = text
        credit.fontSize = max(16, size.width * 0.018)
        credit.foregroundColor = CGColor(gray: 1, alpha: 0.85)
        credit.alignmentMode = .center
        credit.truncationMode = .end
        credit.contentsScale = 2
        credit.frame = CGRect(x: 0, y: size.height * 0.022,
                              width: size.width, height: max(22, size.width * 0.03))
        parent.addSublayer(credit)
    }

    /// Provenance metadata embedded in the exported file (Rule 5b): title + the
    /// archive.org source page(s) of every clip in the cut.
    static func provenanceMetadata(title: String, catalogItemIDs: [String]) -> [AVMetadataItem] {
        // Common-identifier items don't land in the .mp4 atom set (read-back nil); the
        // iTunes `ilst` keys (©nam / ©cmt) DO — and they cover .mov too. Provide both so the
        // archive.org source is embedded regardless of container.
        func item(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m
        }
        let sources = Array(Set(catalogItemIDs)).sorted()
            .map { "https://archive.org/details/\($0)" }.joined(separator: " · ")
        let desc = "Public-domain source(s): \(sources) · Created with Archive Watch (archivewatch.org)"
        return [
            item(.commonIdentifierTitle, title),
            item(.commonIdentifierDescription, desc),
            item(.iTunesMetadataSongName, title),       // ©nam — ffprobe "title" in .mp4
            item(.iTunesMetadataUserComment, desc),     // ©cmt — ffprobe "comment"
        ]
    }
}
#endif
