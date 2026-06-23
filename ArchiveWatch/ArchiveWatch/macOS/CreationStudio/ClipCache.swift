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

    /// Stable local path for a SOURCE window, keyed by source id + the cached span's start/end
    /// ms — so a generous window (clip ± handles) is cached once and reused while the user
    /// trims inside it (no re-cache per trim).
    static func windowURL(catalogItemID: String, startSeconds: Double, endSeconds: Double) -> URL {
        let inMs = Int((startSeconds * 1000).rounded()), outMs = Int((endSeconds * 1000).rounded())
        let safeID = catalogItemID.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("win-\(safeID)-\(inMs)-\(outMs).mp4")
    }
}

// Coalesces concurrent requests for the SAME window into one cache task — so two overlapping
// preview rebuilds (e.g. rapid edits) never download the same window twice.
@MainActor
enum CacheCoordinator {
    private static var inFlight: [String: Task<URL, Error>] = [:]

    static func window(catalogItemID: String, sourceURL: URL,
                       startSeconds: Double, endSeconds: Double) async throws -> URL {
        let key = ProjectMediaCache.windowURL(catalogItemID: catalogItemID,
                                              startSeconds: max(0, startSeconds),
                                              endSeconds: max(startSeconds + 0.1, endSeconds)).path
        if let existing = inFlight[key] { return try await existing.value }
        let task = Task { try await ClipCacheService.cachedWindow(
            catalogItemID: catalogItemID, sourceURL: sourceURL,
            startSeconds: startSeconds, endSeconds: endSeconds) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
}

enum ClipCacheService {
    /// Cache a clip's EXACT in/out window (export path — precise bounds, cached once).
    static func cachedURL(for clip: TimelineClip, attempts: Int = 3) async throws -> URL {
        try await cachedWindow(catalogItemID: clip.catalogItemID, sourceURL: clip.sourceURL,
                               startSeconds: clip.sourceRange.start.seconds,
                               endSeconds: clip.sourceRange.endSeconds, attempts: attempts)
    }

    /// Cache an arbitrary [start, end] source window to a local faststart MP4 and return its
    /// URL (reusing an existing file). The editor caches a GENEROUS window (clip ± handles) so
    /// trimming within it needs no re-cache — only the composition's insert range changes.
    ///
    /// Tries PASSTHROUGH first (fast stream-copy — only the window's bytes are fetched), then a
    /// universal H.264 re-encode for sources passthrough can't copy (MPEG-2 / H.265 / odd
    /// containers). Retries on transient failures: a fresh attempt builds a NEW
    /// ResilientStreamLoader that re-resolves a healthy archive.org node (Decision 034).
    static func cachedWindow(catalogItemID: String, sourceURL: URL,
                             startSeconds: Double, endSeconds: Double, attempts: Int = 3) async throws -> URL {
        let s = max(0, startSeconds), e = max(s + 0.1, endSeconds)
        let out = ProjectMediaCache.windowURL(catalogItemID: catalogItemID, startSeconds: s, endSeconds: e)
        if FileManager.default.fileExists(atPath: out.path) { return out }

        let range = CMTimeRange(start: CMTime(seconds: s, preferredTimescale: 600),
                                duration: CMTime(seconds: e - s, preferredTimescale: 600))
        var lastError: Error = CreationStudioError.cannotCreateExportSession
        for attempt in 0..<max(1, attempts) {
            let t0 = Date()
            do {
                var path = "passthrough"
                do {
                    try await transcode(sourceURL, range: range, preset: AVAssetExportPresetPassthrough, to: out)
                } catch {
                    path = "reencode"
                    try await transcode(sourceURL, range: range, preset: AVAssetExportPresetHighestQuality, to: out)
                }
                if ProcessInfo.processInfo.environment["AW_CS_DIAG"] != nil {
                    FileHandle.standardError.write(Data(
                        "AWCS CACHE \(catalogItemID) \(path) \(Int(s))–\(Int(e))s in \(Int(Date().timeIntervalSince(t0) * 1000))ms\n".utf8))
                }
                return out
            } catch {
                lastError = error
                if Task.isCancelled { throw error }
                if attempt < attempts - 1 { try? await Task.sleep(for: .seconds(1)) }   // brief backoff
            }
        }
        let er = lastError as NSError
        FileHandle.standardError.write(Data(
            "AWCS CACHE FAIL \(catalogItemID) after \(attempts) tries: [\(er.domain) \(er.code) \(er.localizedDescription)]\n".utf8))
        throw lastError
    }

    private static func transcode(_ sourceURL: URL, range: CMTimeRange, preset: String, to out: URL) async throws {
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: sourceURL)
        // AVURLAsset holds its resource-loader delegate weakly — keep the loader alive for
        // the whole export (the iOS engine's `withExtendedLifetime` pattern).
        defer { withExtendedLifetime(loader) {} }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CreationStudioError.cannotCreateExportSession
        }
        session.timeRange = range
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
