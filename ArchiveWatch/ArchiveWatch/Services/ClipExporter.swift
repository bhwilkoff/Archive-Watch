#if os(iOS)
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Photos

// Clip Studio export engine (iOS/iPadOS only — see docs/CREATE-STUDIO-PLAN.md).
// Native frameworks only (Decision 028): AVFoundation for video, ImageIO for
// GIF, PhotoKit to save. No third-party packages.
//
// Editing operates on a LOCAL file (the research's robust path — a complete
// moov-bearing file gives predictable AVFoundation behavior, unlike the
// play-as-you-go ResilientStreamLoader range stream used for playback). The
// engine downloads the source to Caches first, then trims / reframes / overlays
// / encodes. Exports are serialized through this actor (one hardware video
// encoder; concurrent sessions contend + overheat).

enum ClipFormat: String, CaseIterable, Identifiable, Sendable {
    case video, gif
    var id: String { rawValue }
    var label: String { self == .video ? "Video" : "GIF" }
    /// UI cap on clip length per format (perf + "it's a clip, not a re-host").
    var maxDuration: Double { self == .video ? 60 : 6 }
    var fileExtension: String { self == .video ? "mp4" : "gif" }
}

enum ClipAspect: String, CaseIterable, Identifiable, Sendable {
    case original, vertical, square, wide
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Original"
        case .vertical: return "9:16"
        case .square:   return "1:1"
        case .wide:     return "16:9"
        }
    }
    /// SwiftUI aspectRatio for the preview frame. nil = use the source's.
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .vertical: return 9.0 / 16.0
        case .square:   return 1
        case .wide:     return 16.0 / 9.0
        }
    }
    /// Render canvas for a 1080-class video export. `.original` keeps the
    /// oriented source size.
    func videoRenderSize(source: CGSize) -> CGSize {
        switch self {
        case .original: return source
        case .vertical: return CGSize(width: 1080, height: 1920)
        case .square:   return CGSize(width: 1080, height: 1080)
        case .wide:     return CGSize(width: 1920, height: 1080)
        }
    }
    /// Smaller canvas for GIF (file size = frames × pixels; cap the long edge).
    func gifCanvas(source: CGSize) -> CGSize {
        let long: CGFloat = 480
        switch self {
        case .original:
            let s = source.width >= source.height
                ? CGSize(width: long, height: long * source.height / max(source.width, 1))
                : CGSize(width: long * source.width / max(source.height, 1), height: long)
            return CGSize(width: s.width.rounded(), height: s.height.rounded())
        case .vertical: return CGSize(width: 480, height: 854)
        case .square:   return CGSize(width: 480, height: 480)
        case .wide:     return CGSize(width: 480, height: 270)
        }
    }
}

struct ClipSpec: Sendable {
    var sourceURL: URL          // local file (post-download)
    var archiveID: String
    var title: String
    var sourceDetailsURL: String
    var creditLine: String
    var inSeconds: Double
    var durationSeconds: Double
    var aspect: ClipAspect
    var caption: String
    var format: ClipFormat
}

enum ClipExportError: LocalizedError {
    case noVideoTrack, cannotCreateExportSession, exportFailed, gifFailed, photoPermissionDenied
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:             return "This title has no video track to clip."
        case .cannotCreateExportSession: return "Couldn't start the export."
        case .exportFailed:             return "The clip couldn't be rendered."
        case .gifFailed:                return "The GIF couldn't be encoded."
        case .photoPermissionDenied:    return "Photos access is needed to save. Enable it in Settings."
        }
    }
}

actor ClipExporter {
    static let shared = ClipExporter()

    private static var clipsDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var sourcesDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clip-sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func renderURL(filename: String) -> URL { clipsDir.appendingPathComponent(filename) }

    // MARK: Source acquisition

    /// Download the full source MP4 to Caches (the editor needs a complete
    /// local file). Cached, so re-editing the same film is instant.
    /// v2: range-download just the clip window keyed on the moov index.
    func prepareSource(remote: URL, archiveID: String,
                       onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let safe = archiveID.replacingOccurrences(of: "/", with: "_")
        let dest = Self.sourcesDir.appendingPathComponent("\(safe).mp4")
        if FileManager.default.fileExists(atPath: dest.path) { onProgress(1); return dest }
        return try await ProgressDownloader(dest: dest, onProgress: onProgress).run(remote)
    }

    // MARK: Video export (trim + reframe + caption + credit)

    func exportVideo(_ spec: ClipSpec,
                     onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: spec.sourceURL)
        guard let srcV = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipExportError.noVideoTrack
        }
        let srcA = try await asset.loadTracks(withMediaType: .audio).first
        let natural = try await srcV.load(.naturalSize)
        let preferred = try await srcV.load(.preferredTransform)
        let oriented = natural.applying(preferred).aw_abs

        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video,
                                                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ClipExportError.exportFailed
        }
        let range = CMTimeRange(start: CMTime(seconds: spec.inSeconds, preferredTimescale: 600),
                                duration: CMTime(seconds: spec.durationSeconds, preferredTimescale: 600))
        try vTrack.insertTimeRange(range, of: srcV, at: .zero)
        if let srcA, let aTrack = comp.addMutableTrack(withMediaType: .audio,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? aTrack.insertTimeRange(range, of: srcA, at: .zero)
        }

        let renderSize = spec.aspect.videoRenderSize(source: oriented)
        let vc = AVMutableVideoComposition()
        vc.renderSize = renderSize
        vc.frameDuration = CMTime(value: 1, timescale: 30)

        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: range.duration)
        instr.backgroundColor = UIColor.black.cgColor    // letterbox matte
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        let fit = Self.aspectFit(oriented, into: renderSize)
        layer.setTransform(preferred.concatenating(fit), at: .zero)
        instr.layerInstructions = [layer]
        vc.instructions = [instr]

        // Overlays (always burn the provenance credit; caption when present).
        let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer(); videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)
        Self.addOverlays(to: parent, size: renderSize, caption: spec.caption, credit: spec.creditLine)
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)

        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipExportError.cannotCreateExportSession
        }
        session.videoComposition = vc
        session.metadata = Self.provenanceMetadata(spec)

        let out = Self.clipsDir.appendingPathComponent("ArchiveWatch-\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: out)

        let progressTask = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let p) = state { onProgress(p.fractionCompleted) }
            }
        }
        defer { progressTask.cancel() }
        try await session.export(to: out, as: .mp4)
        return out
    }

    // MARK: GIF export (frames → ImageIO, reframe + caption + credit baked in)

    func exportGIF(_ spec: ClipSpec,
                   onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: spec.sourceURL)
        guard let srcV = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipExportError.noVideoTrack
        }
        let natural = try await srcV.load(.naturalSize)
        let preferred = try await srcV.load(.preferredTransform)
        let oriented = natural.applying(preferred).aw_abs
        let canvas = spec.aspect.gifCanvas(source: oriented)

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = CGSize(width: canvas.width * 2, height: canvas.height * 2)

        let fps = 12.0
        let count = max(1, Int(spec.durationSeconds * fps))
        let times = (0..<count).map {
            CMTime(seconds: spec.inSeconds + Double($0) / fps, preferredTimescale: 600)
        }

        let out = Self.clipsDir.appendingPathComponent("ArchiveWatch-\(UUID().uuidString.prefix(8)).gif")
        try? FileManager.default.removeItem(at: out)
        guard let dest = CGImageDestinationCreateWithURL(
            out as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw ClipExportError.gifFailed
        }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let frameProps = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]
        ] as CFDictionary

        var done = 0
        for await result in gen.images(for: times) {
            if case let .success(_, image, _) = result {
                let composed = Self.composeGIFFrame(image, canvas: canvas,
                                                     caption: spec.caption, credit: spec.creditLine)
                CGImageDestinationAddImage(dest, composed, frameProps)
            }
            done += 1
            onProgress(Double(done) / Double(count))
            try Task.checkCancellation()
        }
        guard CGImageDestinationFinalize(dest) else { throw ClipExportError.gifFailed }
        return out
    }

    // MARK: Save to Photos

    func saveToPhotos(_ url: URL, format: ClipFormat) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ClipExportError.photoPermissionDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            // GIFs save as animated photos; MP4 as video.
            req.addResource(with: format == .gif ? .photo : .video, fileURL: url, options: nil)
        }
    }

    // MARK: Helpers (nonisolated — pure)

    /// Scale-to-fit + center transform mapping the oriented source into the
    /// render canvas (letterbox). Identity-safe for unrotated archive video.
    nonisolated static func aspectFit(_ src: CGSize, into dst: CGSize) -> CGAffineTransform {
        guard src.width > 0, src.height > 0 else { return .identity }
        let scale = min(dst.width / src.width, dst.height / src.height)
        let w = src.width * scale, h = src.height * scale
        let tx = (dst.width - w) / 2, ty = (dst.height - h) / 2
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    /// CALayer overlays for the video export. NOTE the Core Animation
    /// coordinate system is bottom-left origin (y grows upward) — credit sits
    /// near the bottom, caption in the lower-third title-safe band.
    nonisolated static func addOverlays(to parent: CALayer, size: CGSize, caption: String, credit: String) {
        let scale: CGFloat = 3
        // Provenance credit — small, bottom-centered, always present.
        let creditLayer = makeTextLayer(credit,
                                         fontSize: max(16, size.width * 0.020),
                                         weight: .medium,
                                         color: UIColor.white.withAlphaComponent(0.85),
                                         alignment: .center)
        creditLayer.contentsScale = scale
        creditLayer.frame = CGRect(x: 0, y: size.height * 0.022,
                                   width: size.width, height: max(22, size.width * 0.03))
        parent.addSublayer(creditLayer)

        guard !caption.isEmpty else { return }
        let capLayer = makeTextLayer(caption,
                                     fontSize: max(30, size.width * 0.050),
                                     weight: .bold,
                                     color: .white,
                                     alignment: .center)
        capLayer.contentsScale = scale
        capLayer.isWrapped = true
        let h = size.height * 0.24
        capLayer.frame = CGRect(x: size.width * 0.06, y: size.height * 0.085,
                                width: size.width * 0.88, height: h)
        parent.addSublayer(capLayer)
    }

    nonisolated static func makeTextLayer(_ string: String, fontSize: CGFloat,
                                          weight: UIFont.Weight, color: UIColor,
                                          alignment: CATextLayerAlignmentMode) -> CATextLayer {
        let l = CATextLayer()
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        l.string = string
        l.font = font
        l.fontSize = fontSize
        l.foregroundColor = color.cgColor
        l.alignmentMode = alignment
        l.truncationMode = .end
        l.shadowColor = UIColor.black.cgColor
        l.shadowOpacity = 0.9
        l.shadowRadius = 4
        l.shadowOffset = CGSize(width: 0, height: -1)
        return l
    }

    /// Compose one GIF frame: draw the oriented source frame aspect-fit into
    /// the canvas (black matte), then the caption + credit in UIKit coords
    /// (top-left origin). Self-contained Core Graphics so GIF gets the same
    /// reframe + provenance the video export gets.
    nonisolated static func composeGIFFrame(_ cg: CGImage, canvas: CGSize,
                                            caption: String, credit: String) -> CGImage {
        let imgSize = CGSize(width: cg.width, height: cg.height)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: fmt)
        let ui = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            let rect = aspectFitRect(imgSize, into: canvas)
            UIImage(cgImage: cg).draw(in: rect)

            let creditFont = UIFont.systemFont(ofSize: max(11, canvas.width * 0.026), weight: .medium)
            drawText(credit, font: creditFont, color: UIColor.white.withAlphaComponent(0.85),
                     canvas: canvas, fromBottom: canvas.height * 0.03, height: creditFont.lineHeight + 2)

            if !caption.isEmpty {
                let capFont = UIFont.systemFont(ofSize: max(16, canvas.width * 0.060), weight: .bold)
                drawText(caption, font: capFont, color: .white,
                         canvas: canvas, fromBottom: canvas.height * 0.12, height: capFont.lineHeight * 2.2)
            }
        }
        return ui.cgImage ?? cg
    }

    nonisolated static func aspectFitRect(_ src: CGSize, into dst: CGSize) -> CGRect {
        guard src.width > 0, src.height > 0 else { return CGRect(origin: .zero, size: dst) }
        let scale = min(dst.width / src.width, dst.height / src.height)
        let w = src.width * scale, h = src.height * scale
        return CGRect(x: (dst.width - w) / 2, y: (dst.height - h) / 2, width: w, height: h)
    }

    /// Draw centered, shadowed text in UIKit (top-left) coords, anchored a
    /// distance up from the bottom edge.
    nonisolated static func drawText(_ string: String, font: UIFont, color: UIColor,
                                     canvas: CGSize, fromBottom: CGFloat, height: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: style, .shadow: shadow
        ]
        let inset: CGFloat = canvas.width * 0.05
        let rect = CGRect(x: inset, y: canvas.height - fromBottom - height,
                          width: canvas.width - inset * 2, height: height)
        (string as NSString).draw(in: rect, withAttributes: attrs)
    }

    nonisolated static func provenanceMetadata(_ spec: ClipSpec) -> [AVMetadataItem] {
        func item(_ key: AVMetadataKey, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.keySpace = .common
            m.key = key as NSString
            m.value = value as NSString
            return m
        }
        let desc = "Public-domain source: \(spec.sourceDetailsURL) · Clipped with Archive Watch (archivewatch.org)"
        return [item(.commonKeyTitle, spec.title), item(.commonKeyDescription, desc)]
    }
}

// URLSession download with progress, bridged to async/await. The download
// task streams to a temp file (bounded memory) and reports byte progress;
// the temp file is moved to `dest` synchronously in the finish callback
// (the system deletes it the moment the callback returns).
private final class ProgressDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let dest: URL
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?

    init(dest: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.dest = dest
        self.onProgress = onProgress
    }

    func run(_ url: URL) async throws -> URL {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = session
        return try await withCheckedThrowingContinuation { c in
            self.continuation = c
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume(returning: dest)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }   // success handled in didFinishDownloadingTo
        continuation?.resume(throwing: error)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}

private extension CGSize {
    /// Absolute-valued size — a preferredTransform can flip signs.
    var aw_abs: CGSize { CGSize(width: Swift.abs(width), height: Swift.abs(height)) }
}
#endif
