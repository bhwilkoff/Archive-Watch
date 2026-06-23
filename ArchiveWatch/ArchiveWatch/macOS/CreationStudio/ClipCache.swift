#if os(macOS)
import Foundation
import AVFoundation

// Cache-then-export, the Apple-native way (docs/macOS-DESIGN.md §4, Rule 4b — amended
// for a SANDBOXED App Store app: ffmpeg is GPL + can't run as a subprocess inside the
// sandbox, so we cache with AVFoundation instead). For each clip we pre-fetch ONLY its
// in/out window into a local faststart MP4 by running an AVAssetExportSession PASSTHROUGH
// (stream copy, no re-encode) over a `ResilientStreamLoader`-backed asset — the same
// resilient byte-range path playback uses (Decision 021/031/034), and the same technique
// the shipping iOS Clip Studio already exports through. The multi-clip composition then
// reads LOCAL files only (never N concurrent remote streams), which is the reliability
// win Rule 4b is about — `AVAssetExportSession` is unreliable composing straight off
// remote URLs (-11800/-16974).
//
// Phase-1 scope: the cache is keyed + reused; LRU eviction + open-project pinning
// (Rule 4d) is a follow-up. Caches live in Library/Caches — disposable, never synced.

enum CreationStudioError: LocalizedError {
    case cannotCreateExportSession
    case noVideoTrack
    case noClips

    var errorDescription: String? {
        switch self {
        case .cannotCreateExportSession: "Couldn't create the export session."
        case .noVideoTrack: "A source clip had no video track."
        case .noClips: "The timeline is empty."
        }
    }
}

enum ProjectMediaCache {
    /// Library/Caches/CreationStudio — disposable, re-derivable, never synced (Rule 4d).
    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CreationStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Stable local path for a clip window, keyed by source id + in/out ms so the same
    /// window is cached once and reused across re-exports.
    static func clipURL(for clip: TimelineClip) -> URL {
        let inMs = Int((clip.sourceRange.start.seconds * 1000).rounded())
        let outMs = Int((clip.sourceRange.endSeconds * 1000).rounded())
        let safeID = clip.catalogItemID.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("clip-\(safeID)-\(inMs)-\(outMs).mp4")
    }
}

enum ClipCacheService {
    /// Cache a clip's in/out window to a local faststart MP4 and return its URL. Reuses
    /// an existing cache file.
    ///
    /// Tries PASSTHROUGH first (fast stream-copy, Rule 4b's `ffmpeg -c copy` spirit — only
    /// the window's bytes are fetched). archive.org content is wildly varied, though, and
    /// passthrough only works when the source codec is MP4-compatible (H.264/AAC); for
    /// MPEG-2 / H.265 / odd containers it fails. So on failure we fall back to a re-encode
    /// preset (H.264) — slower but universal. The final composition re-encodes anyway, so
    /// the fallback costs time, not quality.
    static func cachedURL(for clip: TimelineClip) async throws -> URL {
        let out = ProjectMediaCache.clipURL(for: clip)
        if FileManager.default.fileExists(atPath: out.path) { return out }

        do {
            try await transcodeWindow(clip, preset: AVAssetExportPresetPassthrough, to: out)
        } catch {
            // Passthrough couldn't stream-copy this source — re-encode to H.264.
            try await transcodeWindow(clip, preset: AVAssetExportPresetHighestQuality, to: out)
        }
        return out
    }

    private static func transcodeWindow(_ clip: TimelineClip, preset: String, to out: URL) async throws {
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: clip.sourceURL)
        // AVURLAsset holds its resource-loader delegate weakly — keep the loader alive for
        // the whole export (the iOS engine's `withExtendedLifetime` pattern).
        defer { withExtendedLifetime(loader) {} }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CreationStudioError.cannotCreateExportSession
        }
        session.timeRange = clip.sourceRange.cmRange
        session.shouldOptimizeForNetworkUse = true        // moov-at-front (faststart)

        let staging = out.deletingLastPathComponent()
            .appendingPathComponent("staging-\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: staging)
        try await session.export(to: staging, as: .mp4)
        // Atomic-ish move into place so a partially-written file is never treated as cached.
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: staging, to: out)
    }
}
#endif
