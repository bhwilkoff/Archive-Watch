#if os(macOS)
import Foundation
import AVFoundation
import CoreImage

// Color-grade "Looks" for Creation Studio clips (parity with iOS Clip Studio's grades,
// Decision 033). Native Core Image CIFilter chains, no third-party. `.none` is a no-op.
//
// Per-clip grades CANNOT share the composition's videoComposition with the layer-instruction
// reframe/cross-dissolve compositor (a CI filter handler receives ONE already-composited frame,
// so it can't grade per-clip or per-track). So a graded clip is produced as a SEPARATE source
// file first (LookGrader), and the main CompositionBuilder composes the graded file exactly like
// any other clip — preview == export, and grades compose with transitions for free.
enum ClipLook: String, CaseIterable, Identifiable, Sendable, Codable {
    case none, silent, noir, faded, technicolor, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:        return "None"
        case .silent:      return "Silent"
        case .noir:        return "Noir"
        case .faded:       return "Faded"
        case .technicolor: return "Techni"
        case .mono:        return "B&W"
        }
    }
    /// CIFilter chain for this look. Identity for `.none`. (Same chain as iOS ClipExporter.)
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

enum LookGrader {
    /// A graded copy of a local window file (`sourceURL`) with `look`, cached on disk keyed by
    /// the source filename + look. Returns `sourceURL` unchanged for `.none`. Re-uses the cached
    /// graded file if present, so a Look re-renders only when it (or the underlying window) changes.
    static func gradedURL(for sourceURL: URL, look: ClipLook) async throws -> URL {
        guard look != .none else { return sourceURL }
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let out = ProjectMediaCache.directory.appendingPathComponent("grade-\(look.rawValue)-\(stem).mp4")
        if FileManager.default.fileExists(atPath: out.path) { return out }

        let asset = AVURLAsset(url: sourceURL)
        // CI filter pass: grade each frame. clamped/cropped keeps the extent stable for filters
        // (vignette/blur) that read outside the frame.
        // macOS 27 deprecates videoComposition(with:applyingCIFiltersWithHandler:) in favor of the
        // Configuration-based AVVideoComposition(applyingFiltersTo:applier:) (the same migration the
        // iOS CIFilter pipeline already made — CREATE-STUDIO-PLAN.md §5c / ClipExporter). Both produce
        // an equivalent grade-only videoComposition (no size change; crop back to source extent), fed
        // identically into the HighestQuality export below.
        // The macOS-27 Configuration API (AVVideoComposition(applyingFiltersTo:applier:) +
        // AVCIImageFilteringResult) exists ONLY in the macOS 27 SDK, so it must be guarded at COMPILE
        // time, not just runtime: a bare `if #available(macOS 27)` still fails to compile against the
        // GA macOS 26 SDK (the symbol is absent). `#if compiler(>=6.4)` = "building with Xcode 27's
        // Swift 6.4 toolchain (the 27 SDK)"; the GA Xcode 26 toolchain (Swift <6.4) compiles ONLY the
        // deprecated-but-functional macOS 26 API, so the app archives + submits on a RELEASE Xcode
        // (App Review rejects beta-toolchain builds — see docs/mac-app-store-submission.md).
        let vc: AVVideoComposition
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            vc = try await AVVideoComposition(applyingFiltersTo: asset, applier: { request in
                let graded = look.apply(to: request.sourceImage.clampedToExtent())
                    .cropped(to: request.sourceImage.extent)
                return AVCIImageFilteringResult(resultImage: graded)
            })
        } else {
            vc = try await AVVideoComposition.videoComposition(with: asset) { request in
                let graded = look.apply(to: request.sourceImage.clampedToExtent())
                    .cropped(to: request.sourceImage.extent)
                request.finish(with: graded, context: nil)
            }
        }
        #else
        vc = try await AVVideoComposition.videoComposition(with: asset) { request in
            let graded = look.apply(to: request.sourceImage.clampedToExtent())
                .cropped(to: request.sourceImage.extent)
            request.finish(with: graded, context: nil)
        }
        #endif
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw CreationStudioError.cannotCreateExportSession
        }
        session.videoComposition = vc
        try? FileManager.default.removeItem(at: out)
        try await session.export(to: out, as: .mp4)
        return out
    }
}
#endif
