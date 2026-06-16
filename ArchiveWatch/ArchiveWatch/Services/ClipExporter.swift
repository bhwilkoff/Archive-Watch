#if os(iOS)
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Photos
import Speech

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

// Color-grade "looks" — era-appropriate film treatments for repertory PD
// cinema (Decision 033 v2). Applied with native Core Image CIFilters; no
// third-party. `.none` is a no-op fast path.
enum ClipLook: String, CaseIterable, Identifiable, Sendable {
    case none, silent, noir, faded, technicolor, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:       return "None"
        case .silent:     return "Silent"
        case .noir:       return "Noir"
        case .faded:      return "Faded"
        case .technicolor:return "Techni"
        case .mono:       return "B&W"
        }
    }
    /// CIFilter chain for this look. Identity for `.none`.
    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:        return image
        case .silent:      return image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.85])
        case .noir:        return image.applyingFilter("CIPhotoEffectNoir")
        case .faded:       return image
                .applyingFilter("CIPhotoEffectFade")
                .applyingFilter("CIVignette", parameters: ["inputIntensity": 1.0, "inputRadius": 1.6])
        case .technicolor: return image
                .applyingFilter("CIPhotoEffectChrome")
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25])
        case .mono:        return image.applyingFilter("CIPhotoEffectMono")
        }
    }
}

// A timed auto-caption cue (start/end relative to the clip, 0-based seconds).
struct CaptionCue: Sendable, Hashable, Identifiable {
    var text: String
    var start: Double
    var end: Double
    var id: Double { start }
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
    var look: ClipLook = .none
    var speed: Double = 1        // 0.5 = slow-mo, 2 = fast; output duration = clip/speed
    var blurredFill: Bool = false   // reframe background: blurred-fill vs solid letterbox
    var captionCues: [CaptionCue] = []   // timed auto-captions (override the static caption when present)
}

enum ClipExportError: LocalizedError {
    case noVideoTrack, cannotCreateExportSession, exportFailed, gifFailed
    case photoPermissionDenied, speechDenied, speechUnavailable, noSpeechFound
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:             return "This title has no video track to clip."
        case .cannotCreateExportSession: return "Couldn't start the export."
        case .exportFailed:             return "The clip couldn't be rendered."
        case .gifFailed:                return "The GIF couldn't be encoded."
        case .photoPermissionDenied:    return "Photos access is needed to save. Enable it in Settings."
        case .speechDenied:             return "Speech recognition access is needed for auto-captions. Enable it in Settings."
        case .speechUnavailable:        return "Speech recognition isn't available right now."
        case .noSpeechFound:            return "No spoken words were found in this clip."
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

    /// Orchestrates the video export. A color grade / blurred-fill reframe
    /// (Core Image filter applier) and the caption+credit overlay (Core
    /// Animation tool) can't share one video composition, so when either Core
    /// Image feature is requested the clip is rendered in two passes: pass 1
    /// grades + reframes the clip range to the render canvas with Core Image;
    /// pass 2 burns the overlay + applies speed on that already-framed clip. A
    /// plain letterbox clip with no look skips pass 1 (single overlay pass).
    func exportVideo(_ spec: ClipSpec,
                     onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let needsCorePass = spec.look != .none || spec.blurredFill
        guard needsCorePass else {
            return try await renderComposition(spec, onProgress: onProgress)
        }
        let framed = try await applyGradeAndReframe(spec) { onProgress($0 * 0.5) }
        var s2 = spec
        s2.sourceURL = framed
        s2.look = .none
        s2.blurredFill = false
        s2.aspect = .original   // already framed to the canvas; pass 2 only overlays + speeds
        s2.inSeconds = 0
        let out = try await renderComposition(s2) { onProgress(0.5 + $0 * 0.5) }
        try? FileManager.default.removeItem(at: framed)
        return out
    }

    /// Pass 1: Core Image grade + reframe (letterbox or blurred-fill) over the
    /// clip range, output at the render canvas size, re-timed to 0. iOS 26/27
    /// API: the modern `AVVideoComposition(applyingFiltersTo:applier:)` has no
    /// renderSize parameter, so the clip is trimmed into an `AVMutableComposition`
    /// whose `naturalSize` sets the CI render canvas; the applier reframes the
    /// source frame into `request.renderSize`.
    private func applyGradeAndReframe(_ spec: ClipSpec,
                                      onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: spec.sourceURL)
        guard let srcV = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipExportError.noVideoTrack
        }
        let natural = try await srcV.load(.naturalSize)
        let preferred = try await srcV.load(.preferredTransform)
        let oriented = natural.applying(preferred).aw_abs
        let renderSize = spec.aspect.videoRenderSize(source: oriented)
        let look = spec.look
        let blurred = spec.blurredFill

        let comp = AVMutableComposition()
        comp.naturalSize = renderSize
        guard let vTrack = comp.addMutableTrack(withMediaType: .video,
                                                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ClipExportError.exportFailed
        }
        vTrack.preferredTransform = preferred
        let range = CMTimeRange(start: CMTime(seconds: spec.inSeconds, preferredTimescale: 600),
                                duration: CMTime(seconds: spec.durationSeconds, preferredTimescale: 600))
        try vTrack.insertTimeRange(range, of: srcV, at: .zero)
        if let srcA = try await asset.loadTracks(withMediaType: .audio).first,
           let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? aTrack.insertTimeRange(range, of: srcA, at: .zero)
        }

        let vc = try await AVVideoComposition(applyingFiltersTo: comp, applier: { request in
            let graded = look.apply(to: request.sourceImage)
            let out = Self.reframe(graded, into: request.renderSize, blurredFill: blurred)
            return AVCIImageFilteringResult(resultImage: out)
        })
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipExportError.cannotCreateExportSession
        }
        session.videoComposition = vc
        let out = Self.clipsDir.appendingPathComponent("aw-grade-\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: out)
        try await Self.runExport(session, to: out, onProgress: onProgress)
        return out
    }

    /// Core Image reframe: fit the (graded) source into `target`, centered,
    /// over either a solid-black letterbox matte or a scaled-up gaussian-blur
    /// of the same frame (the "Instagram" blurred-fill look for archival 4:3).
    nonisolated static func reframe(_ image: CIImage, into target: CGSize, blurredFill: Bool) -> CIImage {
        let ext = image.extent
        guard ext.width > 0, ext.height > 0, ext.width.isFinite, ext.height.isFinite else { return image }
        let normalized = image.transformed(by: CGAffineTransform(translationX: -ext.origin.x, y: -ext.origin.y))
        let w = ext.width, h = ext.height
        let fitScale = min(target.width / w, target.height / h)
        let fw = w * fitScale, fh = h * fitScale
        let fg = normalized
            .transformed(by: CGAffineTransform(scaleX: fitScale, y: fitScale))
            .transformed(by: CGAffineTransform(translationX: (target.width - fw) / 2, y: (target.height - fh) / 2))
        let bgBase: CIImage
        if blurredFill {
            let fillScale = max(target.width / w, target.height / h)
            let bw = w * fillScale, bh = h * fillScale
            bgBase = normalized
                .transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
                .transformed(by: CGAffineTransform(translationX: (target.width - bw) / 2, y: (target.height - bh) / 2))
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 36])
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.08])
        } else {
            bgBase = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
        }
        let bg = bgBase.cropped(to: CGRect(origin: .zero, size: target))
        return fg.composited(over: bg).cropped(to: CGRect(origin: .zero, size: target))
    }

    /// Pass 2 (and the only pass when `.none`): trim + reframe + speed +
    /// burned caption/credit. `spec.look` is expected to be `.none` here.
    private func renderComposition(_ spec: ClipSpec,
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
        var aTrack: AVMutableCompositionTrack?
        if let srcA {
            aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try? aTrack?.insertTimeRange(range, of: srcA, at: .zero)
        }

        // Speed: time-scale both tracks together (keeps A/V in sync).
        var outputDuration = range.duration
        if spec.speed != 1, spec.speed > 0 {
            outputDuration = CMTime(seconds: spec.durationSeconds / spec.speed, preferredTimescale: 600)
            let full = CMTimeRange(start: .zero, duration: range.duration)
            vTrack.scaleTimeRange(full, toDuration: outputDuration)
            aTrack?.scaleTimeRange(full, toDuration: outputDuration)
        }

        let renderSize = spec.aspect.videoRenderSize(source: oriented)

        // iOS 26/27 Configuration-based video composition (replaces the
        // deprecated AVMutableVideoComposition + AVMutable*Instruction).
        var layerCfg = AVVideoCompositionLayerInstruction.Configuration(trackID: vTrack.trackID)
        let fit = Self.aspectFit(oriented, into: renderSize)
        layerCfg.setTransform(preferred.concatenating(fit), at: .zero)
        let layerInstr = AVVideoCompositionLayerInstruction(configuration: layerCfg)

        var instrCfg = AVVideoCompositionInstruction.Configuration()
        instrCfg.timeRange = CMTimeRange(start: .zero, duration: outputDuration)
        instrCfg.backgroundColor = UIColor.black.cgColor    // letterbox matte
        instrCfg.layerInstructions = [layerInstr]
        let instruction = AVVideoCompositionInstruction(configuration: instrCfg)

        // Overlays (always burn the provenance credit; timed auto-captions when
        // present, else the static caption). Cue times are clip-relative, so
        // map them onto the speed-scaled output timeline.
        let total = outputDuration.seconds
        let displayCues = spec.captionCues.map {
            CaptionCue(text: $0.text, start: $0.start / spec.speed, end: $0.end / spec.speed)
        }
        let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer(); videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)
        Self.addOverlays(to: parent, size: renderSize, caption: spec.caption, credit: spec.creditLine,
                         cues: displayCues, totalDuration: total)
        let toolCfg = AVVideoCompositionCoreAnimationTool.Configuration(
            postProcessingAsVideoLayer: videoLayer, containingLayer: parent)

        var cfg = AVVideoComposition.Configuration()
        cfg.renderSize = renderSize
        cfg.frameDuration = CMTime(value: 1, timescale: 30)
        cfg.instructions = [instruction]
        cfg.animationTool = AVVideoCompositionCoreAnimationTool(configuration: toolCfg)
        let vc = AVVideoComposition(configuration: cfg)

        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipExportError.cannotCreateExportSession
        }
        session.videoComposition = vc
        session.metadata = Self.provenanceMetadata(spec)

        let out = Self.clipsDir.appendingPathComponent("ArchiveWatch-\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: out)
        try await Self.runExport(session, to: out, onProgress: onProgress)
        return out
    }

    private static func runExport(_ session: AVAssetExportSession, to url: URL,
                                  onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let progressTask = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let p) = state { onProgress(p.fractionCompleted) }
            }
        }
        defer { progressTask.cancel() }
        try await session.export(to: url, as: .mp4)
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
        // Speed stretches/compresses which source span the fixed output frames
        // sample (GIF has no audio, so this is just resampling).
        let times = (0..<count).map {
            CMTime(seconds: spec.inSeconds + (Double($0) / fps) * spec.speed, preferredTimescale: 600)
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
                let composed = Self.composeGIFFrame(image, canvas: canvas, look: spec.look,
                                                     blurredFill: spec.blurredFill,
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

    // MARK: Auto-captions (on-device speech → timed cues)

    /// Transcribe the clip's audio into timed caption cues. Extracts the
    /// clip-range audio to m4a first (SFSpeech wants an audio file), then runs
    /// on-device recognition when supported (offline, no length limit). Returns
    /// cues grouped to ~7 words / ≤2.2s. iOS-26 `SpeechAnalyzer` is the future
    /// upgrade; `SFSpeechRecognizer` is the lower-risk path used here.
    func transcribe(sourceURL: URL, inSeconds: Double, duration: Double) async throws -> [CaptionCue] {
        let auth = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard auth == .authorized else { throw ClipExportError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { throw ClipExportError.speechUnavailable }

        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ClipExportError.cannotCreateExportSession
        }
        let audioURL = Self.clipsDir.appendingPathComponent("aw-audio-\(UUID().uuidString.prefix(8)).m4a")
        try? FileManager.default.removeItem(at: audioURL)
        session.timeRange = CMTimeRange(start: CMTime(seconds: inSeconds, preferredTimescale: 600),
                                        duration: CMTime(seconds: duration, preferredTimescale: 600))
        try await session.export(to: audioURL, as: .m4a)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let segments: [SFTranscriptionSegment] = try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error { cont.resume(throwing: error); return }
                if let result, result.isFinal { cont.resume(returning: result.bestTranscription.segments) }
            }
        }
        let cues = Self.groupIntoCues(segments)
        guard !cues.isEmpty else { throw ClipExportError.noSpeechFound }
        return cues
    }

    /// Group word segments into readable caption cues (~7 words or ≤2.2s).
    nonisolated static func groupIntoCues(_ segments: [SFTranscriptionSegment]) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        var words: [String] = []
        var start = 0.0, end = 0.0
        func flush() {
            guard !words.isEmpty else { return }
            cues.append(CaptionCue(text: words.joined(separator: " "), start: start, end: max(end, start + 0.6)))
            words.removeAll()
        }
        for seg in segments {
            if words.isEmpty { start = seg.timestamp }
            words.append(seg.substring)
            end = seg.timestamp + seg.duration
            if (end - start) >= 2.2 || words.count >= 7 { flush() }
        }
        flush()
        return cues
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
    nonisolated static func addOverlays(to parent: CALayer, size: CGSize,
                                        caption: String, credit: String,
                                        cues: [CaptionCue] = [], totalDuration: Double = 0) {
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

        let capFrame = CGRect(x: size.width * 0.06, y: size.height * 0.085,
                              width: size.width * 0.88, height: size.height * 0.24)

        // Timed auto-captions take precedence: one layer per cue, shown only
        // during its window via an opacity keyframe animation over the clip.
        if !cues.isEmpty, totalDuration > 0 {
            for cue in cues {
                let layer = makeTextLayer(cue.text,
                                          fontSize: max(28, size.width * 0.046),
                                          weight: .bold, color: .white, alignment: .center)
                layer.contentsScale = scale
                layer.isWrapped = true
                layer.frame = capFrame
                layer.opacity = 0
                let s = min(max(cue.start / totalDuration, 0), 1)
                let e = min(max(cue.end / totalDuration, s), 1)
                let anim = CAKeyframeAnimation(keyPath: "opacity")
                anim.values = [0, 0, 1, 1, 0, 0]
                anim.keyTimes = [0, max(0, s - 0.0001), s, e, min(1, e + 0.0001), 1].map { NSNumber(value: $0) }
                anim.duration = totalDuration
                anim.beginTime = AVCoreAnimationBeginTimeAtZero   // literal 0 = "now" (won't render)
                anim.isRemovedOnCompletion = false
                anim.fillMode = .both
                layer.add(anim, forKey: "opacity")
                parent.addSublayer(layer)
            }
            return
        }

        guard !caption.isEmpty else { return }
        let capLayer = makeTextLayer(caption,
                                     fontSize: max(30, size.width * 0.050),
                                     weight: .bold,
                                     color: .white,
                                     alignment: .center)
        capLayer.contentsScale = scale
        capLayer.isWrapped = true
        capLayer.frame = capFrame
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
    /// Shared Core Image context for GIF look application (created once;
    /// recreating per frame tanks performance).
    nonisolated static let sharedCIContext = CIContext()

    nonisolated static func applyLook(_ look: ClipLook, to cg: CGImage) -> CGImage {
        guard look != .none else { return cg }
        let source = CIImage(cgImage: cg)
        let graded = look.apply(to: source)
        return sharedCIContext.createCGImage(graded, from: source.extent) ?? cg
    }

    /// Gaussian-blur a CGImage via Core Image (for the GIF blurred-fill bg).
    nonisolated static func blurred(_ cg: CGImage, radius: Double = 12) -> CGImage {
        let src = CIImage(cgImage: cg)
        let out = src.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: src.extent)
        return sharedCIContext.createCGImage(out, from: src.extent) ?? cg
    }

    nonisolated static func composeGIFFrame(_ cg: CGImage, canvas: CGSize, look: ClipLook,
                                            blurredFill: Bool, caption: String, credit: String) -> CGImage {
        let frame = applyLook(look, to: cg)
        let imgSize = CGSize(width: frame.width, height: frame.height)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: fmt)
        let ui = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            if blurredFill {
                // Scaled-up, blurred copy filling the canvas behind the frame.
                let bg = UIImage(cgImage: blurred(frame))
                let fill = aspectFillRect(imgSize, into: canvas)
                bg.draw(in: fill, blendMode: .normal, alpha: 1)
                UIColor.black.withAlphaComponent(0.08).setFill()
                ctx.fill(CGRect(origin: .zero, size: canvas))
            }
            let rect = aspectFitRect(imgSize, into: canvas)
            UIImage(cgImage: frame).draw(in: rect)

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

    nonisolated static func aspectFillRect(_ src: CGSize, into dst: CGSize) -> CGRect {
        guard src.width > 0, src.height > 0 else { return CGRect(origin: .zero, size: dst) }
        let scale = max(dst.width / src.width, dst.height / src.height)
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
