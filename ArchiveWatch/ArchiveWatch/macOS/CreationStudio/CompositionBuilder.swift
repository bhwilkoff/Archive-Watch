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
    }

    /// Compile resolved clips (in timeline order) into the (composition, videoComposition)
    /// pair. `creditLine == nil` means a clean export — no burned attribution (owner
    /// decision: attribution is optional). Shared by preview + export.
    static func build(resolved: [ResolvedClip], timeline: Timeline,
                      creditLine: String?) async throws -> BuiltComposition {
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video,
                                                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CreationStudioError.noVideoTrack
        }
        let aTrack = comp.addMutableTrack(withMediaType: .audio,
                                          preferredTrackID: kCMPersistentTrackID_Invalid)
        let renderSize = timeline.renderSize.cgSize

        var instructions: [AVVideoCompositionInstruction] = []
        var volumePoints: [(CMTime, Float)] = []      // per-clip audio level (#4)
        var cursor = CMTime.zero

        for r in resolved {
            let asset = r.asset
            guard let srcV = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let insertRange = r.insertRange
            guard insertRange.duration.isNumeric, insertRange.duration > .zero else { continue }

            try vTrack.insertTimeRange(insertRange, of: srcV, at: cursor)
            if let aTrack, let srcA = try await asset.loadTracks(withMediaType: .audio).first {
                try? aTrack.insertTimeRange(insertRange, of: srcA, at: cursor)
                volumePoints.append((cursor, Float(max(0, r.audioVolume))))   // volume from this clip's start
            }

            // Per-clip aspect-fit transform (orient → fit into the render canvas, letterboxed).
            let natural = try await srcV.load(.naturalSize)
            let preferred = try await srcV.load(.preferredTransform)
            let oriented = natural.applying(preferred)
            let orientedAbs = CGSize(width: abs(oriented.width), height: abs(oriented.height))

            var layerCfg = AVVideoCompositionLayerInstruction.Configuration(trackID: vTrack.trackID)
            layerCfg.setTransform(preferred.concatenating(aspectFit(orientedAbs, into: renderSize)),
                                  at: cursor)
            let layerInstr = AVVideoCompositionLayerInstruction(configuration: layerCfg)

            var instrCfg = AVVideoCompositionInstruction.Configuration()
            instrCfg.timeRange = CMTimeRange(start: cursor, duration: insertRange.duration)
            instrCfg.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)   // letterbox matte
            instrCfg.layerInstructions = [layerInstr]
            instructions.append(AVVideoCompositionInstruction(configuration: instrCfg))

            cursor = cursor + insertRange.duration
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
        if creditLine != nil || !timeline.textOverlays.isEmpty {
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

        // Audio mix — each clip's segment plays at its own volume (#4). Step the volume at
        // every clip boundary on the shared audio track (Rule 3c: N-track mixing with
        // AVMutableAudioMixInputParameters; per-clip volume needs only one track + steps).
        var audioMix: AVAudioMix?
        if let aTrack = comp.tracks(withMediaType: .audio).first,
           volumePoints.contains(where: { $0.1 != 1 }) {
            let params = AVMutableAudioMixInputParameters(track: aTrack)
            for (t, v) in volumePoints { params.setVolume(v, at: t) }
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            audioMix = mix
        }

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
