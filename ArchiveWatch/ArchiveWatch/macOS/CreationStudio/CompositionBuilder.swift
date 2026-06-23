#if os(macOS)
import Foundation
import AVFoundation
import QuartzCore

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
        var cursor = CMTime.zero

        for r in resolved {
            let asset = r.asset
            guard let srcV = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let insertRange = r.insertRange
            guard insertRange.duration.isNumeric, insertRange.duration > .zero else { continue }

            try vTrack.insertTimeRange(insertRange, of: srcV, at: cursor)
            if let aTrack, let srcA = try await asset.loadTracks(withMediaType: .audio).first {
                try? aTrack.insertTimeRange(insertRange, of: srcA, at: cursor)
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

        // Burn the provenance credit ONLY when requested — a clean export skips the
        // Core Animation overlay pass entirely (owner decision; attribution optional).
        if let creditLine {
            let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: renderSize)
            let videoLayer = CALayer(); videoLayer.frame = parent.frame
            parent.addSublayer(videoLayer)
            addCredit(creditLine, to: parent, size: renderSize)
            let toolCfg = AVVideoCompositionCoreAnimationTool.Configuration(
                postProcessingAsVideoLayer: videoLayer, containingLayer: parent)
            cfg.animationTool = AVVideoCompositionCoreAnimationTool(configuration: toolCfg)
        }

        return BuiltComposition(composition: comp,
                                videoComposition: AVVideoComposition(configuration: cfg),
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
        // KNOWN FOLLOW-UP: common-identifier items don't reliably land in the .mp4 atom
        // set — a self-test read-back (both ffprobe and AVFoundation's .commonMetadata)
        // returns nil. The burned-in visible credit is the VERIFIED provenance; embedding
        // the source in file metadata needs the iTunes/QuickTime identifiers (©nam/©cmt /
        // mdta) or a .mov container. Tracked, not blocking — attribution is optional anyway.
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
        return [item(.commonIdentifierTitle, title), item(.commonIdentifierDescription, desc)]
    }
}
#endif
