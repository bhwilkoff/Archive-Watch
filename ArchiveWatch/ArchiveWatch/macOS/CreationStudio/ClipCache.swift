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
    static func windowURL(catalogItemID: String, sourceURL: URL,
                          startSeconds: Double, endSeconds: Double) -> URL {
        let inMs = Int((startSeconds * 1000).rounded()), outMs = Int((endSeconds * 1000).rounded())
        let safeID = catalogItemID.replacingOccurrences(of: "/", with: "_")
        // Key on the SOURCE too: the preview caches a small proxy derivative while export caches the
        // full-quality source — same item + window, DIFFERENT files. Without this the low-res proxy
        // window would be reused for export.
        return directory.appendingPathComponent("win-\(safeID)-\(sourceTag(sourceURL))-\(inMs)-\(outMs).mp4")
    }

    /// Stable (cross-launch) short hash of a source URL — FNV-1a, so the cache survives relaunches
    /// (Swift's Hashable is per-process salted and would needlessly re-cache every session).
    private static func sourceTag(_ url: URL) -> String {
        var h: UInt64 = 1469598103934665603
        for b in url.absoluteString.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h & 0xFFFFFFFF, radix: 16)
    }

    /// Cap the re-encoded-window cache at ~1.5 GB (LRU) and sweep orphaned staging files. The cache
    /// was UNBOUNDED (a documented Phase-1 gap) and had grown to multiple GB, filling the disk — which
    /// corrupts the system URL cache (Cache.db) and can fault mmap'd SQLite reads as EXC_BAD_ACCESS.
    /// Only manages `win-*` (re-encoded windows, re-derivable) and `staging-*` (interrupted writes);
    /// NEVER touches the indices (clips/subtitle.sqlite) or user media (music-/voiceover-). Pure
    /// filesystem work — safe to call off the main thread. Deleting a `win-*` a player still has open
    /// is harmless on APFS (the fd stays valid); LRU keeps the active project's recent windows last.
    static let maxBytes: Int64 = 1_500_000_000
    /// Files touched within this window are considered IN USE (an in-flight re-encode's staging file,
    /// or a win-* an AVAsset/image-generator is actively reading) and are NEVER deleted — yanking a
    /// file out from under AVFoundation is unsafe. The cache may sit slightly over cap during a busy
    /// session; the next sweep, once activity settles, brings it down.
    static let inUseGrace: TimeInterval = 180
    static func sweep(now: Date = Date()) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        func recent(_ v: URLResourceValues?) -> Bool {
            let t = max(v?.contentAccessDate ?? .distantPast, v?.contentModificationDate ?? .distantPast)
            return now.timeIntervalSince(t) < inUseGrace
        }
        var windows: [(url: URL, size: Int64, atime: Date)] = []
        for url in items {
            let name = url.lastPathComponent
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey])
            if name.hasPrefix("staging-") {                  // interrupted re-encode — but not a LIVE one
                if !recent(v) { try? fm.removeItem(at: url) }
                continue
            }
            guard name.hasPrefix("win-") else { continue }   // managed cache only (never indices/user media)
            if recent(v) { continue }                        // in active use — protect it
            windows.append((url, Int64(v?.fileSize ?? 0),
                            v?.contentAccessDate ?? v?.contentModificationDate ?? .distantPast))
        }
        var total = windows.reduce(Int64(0)) { $0 + $1.size }
        guard total > maxBytes else { return }
        for w in windows.sorted(by: { $0.atime < $1.atime }) where total > maxBytes {   // oldest first
            try? fm.removeItem(at: w.url)
            total -= w.size
        }
    }
}

// Resolves a SMALL proxy derivative for the PREVIEW path (export keeps the full-quality source).
// archive.org auto-derives a tiny H.264 `<name>_512kb.mp4` (~240p) for most items; byte-ranging
// THAT instead of the full uploader MP4 transfers ~10× less, which is the dominant cost of
// preparing clips. The file list comes from the metadata API (one small cached request per item).
@MainActor
enum ProxySource {
    private static var resolved: [String: URL] = [:]              // archiveID → proxy (or fallback)
    private static var inFlight: [String: Task<URL, Never>] = [:]

    /// The smallest playable H.264 derivative for `archiveID`, else `fallback` (the full source).
    /// Cached + coalesced so 20 clips from a few films issue at most one metadata fetch each.
    static func proxyURL(archiveID: String, fallback: URL) async -> URL {
        if let u = resolved[archiveID] { return u }
        if let t = inFlight[archiveID] { return await t.value }
        let t = Task { () -> URL in (await resolve(archiveID)) ?? fallback }
        inFlight[archiveID] = t
        let url = await t.value
        inFlight[archiveID] = nil
        resolved[archiveID] = url
        return url
    }

    private static func resolve(_ id: String) async -> URL? {
        guard let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let metaURL = URL(string: "https://archive.org/metadata/\(enc)"),   // full meta: server+dir+files
              let data = await StudioNet.data(from: metaURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return nil }
        var best: (name: String, size: Int)?
        for f in files {
            guard let name = f["name"] as? String else { continue }
            let lower = name.lowercased()
            guard lower.hasSuffix(".mp4") else { continue }
            let fmt = (f["format"] as? String ?? "").lowercased()
            // Only the SMALL auto-derivatives — never the (possibly huge) uploader/original mp4.
            guard fmt.contains("512kb") || fmt == "h.264" || lower.hasSuffix(".ia.mp4") else { continue }
            let size = Int(f["size"] as? String ?? "") ?? .max
            if best == nil || size < best!.size { best = (name, size) }
        }
        guard let pick = best?.name,
              let nameEnc = pick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        // NODE-DIRECT URL (server + dir) — skips the /download 302 through archive.org's rate-limited
        // MAIN host (the throttle that makes parallel clip prep -1004/-1011 + slow). Verified: the node
        // serves 200 + byte-ranges directly. Falls back to /download if metadata lacks server/dir.
        if let server = json["server"] as? String, let dir = json["dir"] as? String,
           let u = URL(string: "https://\(server)\(dir)/\(nameEnc)") {
            return u
        }
        return URL(string: "https://archive.org/download/\(enc)/\(nameEnc)")
    }
}

// Coalesces concurrent requests for the SAME window into one cache task — so two overlapping
// preview rebuilds (e.g. rapid edits) never download the same window twice.
@MainActor
enum CacheCoordinator {
    private static var inFlight: [String: Task<URL, Error>] = [:]

    static func window(catalogItemID: String, sourceURL: URL,
                       startSeconds: Double, endSeconds: Double) async throws -> URL {
        let key = ProjectMediaCache.windowURL(catalogItemID: catalogItemID, sourceURL: sourceURL,
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

/// Caps concurrent re-encodes GLOBALLY (across the preview pass, the verify pass, and export) so the
/// pipeline never oversubscribes the network + CPU. Too many parallel ResilientStreamLoader streams +
/// H.264 encodes were starving each other and timing out ("The operation couldn't be completed" after
/// a long wait), especially on a fanless Mac. FIFO so no caller is starved.
actor ReencodeLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ limit: Int) { self.limit = max(1, limit) }
    func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { active = max(0, active - 1) }
        else { waiters.removeFirst().resume() }        // hand the slot straight to the next waiter
    }
}

enum ClipCacheService {
    /// Global cap on simultaneous window re-encodes. Kept LOW (2): each re-encode runs its own
    /// ResilientStreamLoader (its own URLSession + connections to archive.org), and archive.org
    /// RATE-LIMITS / refuses a client IP that opens too many simultaneous connections (error 61 /
    /// -1004) — which then breaks the whole app, not just the studio. 2 concurrent downloads plus the
    /// image loads stays under that ceiling. Shared by every caller, so total in-flight never exceeds this.
    // Higher than the old 2: each clip is now a fast PASSTHROUGH COPY of a SMALL proxy derivative
    // (far less CPU + far fewer bytes), so the pipeline can run more in parallel without storming
    // archive.org. Still bounded so the per-IP main-host limit (the -1004 storm) isn't tripped.
    // 8 ≥ the preview's 6-wide maxConcurrent so the global limiter never bottlenecks preview; each
    // op is now a light passthrough copy from a small node-direct derivative, not a full transcode.
    static let reencodeLimiter = ReencodeLimiter(Int(ProcessInfo.processInfo.environment["AW_CS_LIM"] ?? "") ?? 8)
    /// Per-attempt re-encode deadline. A healthy node finishes a window in seconds; 90s still tolerates
    /// a slow-but-progressing connection while failing a true stall far sooner than the old 150s.
    static let attemptTimeout = 90.0

    /// A definitively UNRECOVERABLE failure — the source genuinely can't be processed, so retrying is
    /// pointless. Deliberately NARROW: the player streams these same sources fine through the resilient
    /// loader, so most re-encode errors (the generic AVErrorUnknown -11800 "The operation couldn't be
    /// completed", read interruptions, timeouts) are TRANSIENT — a less-tolerant AVAssetReader hiccuped
    /// mid-read, and a retry succeeds. Only a missing video track or an unrecognized format / absent
    /// codec is truly permanent. Everything else is treated as transient (the caller gives up only
    /// after it fails REPEATEDLY — count-based — rather than trusting one error code).
    static func isPermanent(_ error: Error) -> Bool {
        // ONLY a source with literally no usable video track is truly unprocessable. EVERYTHING else —
        // "cannot decode", format errors, timeouts, network — is treated as TRANSIENT and retried: the
        // AVAssetReader re-encode is stricter/flakier than playback (especially under concurrent load),
        // so a decode error on a video that actually plays in the preview is transient, not permanent.
        // (Marking decode errors permanent is what stuck a false "cannot decode" overlay on a good clip.)
        if let e = error as? CreationStudioError, case .noVideoTrack = e { return true }
        return false
    }

    /// Cache a clip's EXACT in/out window (export path — precise bounds, cached once).
    static func cachedURL(for clip: TimelineClip, attempts: Int = 2) async throws -> URL {
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
                             startSeconds: Double, endSeconds: Double, attempts: Int = 2) async throws -> URL {
        let s = max(0, startSeconds), e = max(s + 0.1, endSeconds)
        let out = ProjectMediaCache.windowURL(catalogItemID: catalogItemID, sourceURL: sourceURL, startSeconds: s, endSeconds: e)
        if FileManager.default.fileExists(atPath: out.path) { return out }

        let range = CMTimeRange(start: CMTime(seconds: s, preferredTimescale: 600),
                                duration: CMTime(seconds: e - s, preferredTimescale: 600))
        var lastError: Error = CreationStudioError.cannotCreateExportSession
        for attempt in 0..<max(1, attempts) {
            let t0 = Date()
            // Gate the heavy work on the GLOBAL limiter so total concurrent encodes stay bounded
            // (oversubscription was the cause of the cascading timeouts). The slot is held only for
            // the encode, freed between retries / on failure.
            await reencodeLimiter.acquire()
            do {
                // Read the window THROUGH the ResilientStreamLoader (byte-range + node failover +
                // resume-on-reset) and re-encode it to a local file. This is the ONLY path that
                // survives archive.org's idle connection resets on a deep window of a long film —
                // AVAssetExportSession has no resourceLoader and fails "Operation Stopped" (-11838)
                // exactly there, which is why both export AND the cache-backed preview were broken.
                try await withTimeout(attemptTimeout) {
                    try await cacheOneWindow(sourceURL: sourceURL, range: range, to: out)
                }
                await reencodeLimiter.release()
                if ProcessInfo.processInfo.environment["AW_CS_DIAG"] != nil {
                    FileHandle.standardError.write(Data(
                        "AWCS CACHE \(catalogItemID) reencode \(Int(s))–\(Int(e))s in \(Int(Date().timeIntervalSince(t0) * 1000))ms\n".utf8))
                }
                return out
            } catch {
                await reencodeLimiter.release()
                lastError = error
                if Task.isCancelled { throw error }
                if isPermanent(error) { break }                 // a codec/format failure won't change on retry
                if attempt < attempts - 1 { try? await Task.sleep(for: .seconds(1)) }   // brief backoff
            }
        }
        let er = lastError as NSError
        FileHandle.standardError.write(Data(
            "AWCS CACHE FAIL \(catalogItemID) after \(attempts) tries: [\(er.domain) \(er.code) \(er.localizedDescription)]\n".utf8))
        throw lastError
    }

    /// Cache one window: try a fast PASSTHROUGH COPY (no decode/encode — just copy the compressed
    /// H.264/AAC samples) first; fall back to a full re-encode only for sources passthrough can't
    /// copy (MPEG-2 / H.265 / odd containers). Passthrough is ~10-50× cheaper on CPU AND can't
    /// "fail to decode" (it never decodes), which is what removes both the slowness and the false
    /// "cannot decode" failures on clips that actually play.
    private static func cacheOneWindow(sourceURL: URL, range: CMTimeRange, to out: URL) async throws {
        let t0 = Date()
        do {
            try await copyWindow(sourceURL: sourceURL, range: range, to: out)
            if CreationStudioBench.isEnabled { CreationStudioBench.mark("copy-ok \(sourceURL.lastPathComponent) \(Int(Date().timeIntervalSince(t0)*1000))ms") }
            return
        } catch {
            if error is CancellationError { throw error }
            if isPermanent(error) { throw error }          // no video track — re-encode won't help
            if CreationStudioBench.isEnabled { CreationStudioBench.mark("copy-FAIL→reencode \(sourceURL.lastPathComponent) [\((error as NSError).code)]") }
            // passthrough couldn't copy this codec/container — re-encode it (the slow but universal path).
        }
        try await reencodeWindow(sourceURL: sourceURL, range: range, to: out)
        if CreationStudioBench.isEnabled { CreationStudioBench.mark("reencode-ok \(sourceURL.lastPathComponent) \(Int(Date().timeIntervalSince(t0)*1000))ms") }
    }

    /// PASSTHROUGH copy of a SOURCE [start,end] window to a local faststart MP4 — copies compressed
    /// samples (nil reader/writer settings) through the `ResilientStreamLoader` (Decision 021/031/034),
    /// no decode/encode. The leading non-keyframe video samples are skipped so the file starts on a
    /// sync frame (decodable); the generous cache handle means the exact in-point is always past that
    /// first keyframe, so the visible clip is clean. Validated on real archive.org H.264 derivatives.
    private static func copyWindow(sourceURL: URL, range: CMTimeRange, to out: URL) async throws {
        let (srcAsset, loader) = ResilientStreamLoader.makeAsset(for: sourceURL)
        guard let srcV = try await srcAsset.loadTracks(withMediaType: .video).first else {
            throw CreationStudioError.noVideoTrack
        }
        let srcA = try? await srcAsset.loadTracks(withMediaType: .audio).first

        let srcDur = (try? await srcV.load(.timeRange).duration) ?? range.end
        let end = CMTimeMinimum(range.end, srcDur)
        let clamped = CMTimeRange(start: range.start,
                                  duration: CMTimeMaximum(CMTime(value: 1, timescale: 600), end - range.start))

        // Zero-base the window so the reader yields [0, dur] (no retiming) — same trick as re-encode.
        let comp = AVMutableComposition()
        guard let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CreationStudioError.noVideoTrack
        }
        try cv.insertTimeRange(clamped, of: srcV, at: .zero)
        var ca: AVMutableCompositionTrack?
        if let srcA, let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? track.insertTimeRange(clamped, of: srcA, at: .zero)
            ca = track
        }

        let reader = try AVAssetReader(asset: comp)
        let vOut = AVAssetReaderTrackOutput(track: cv, outputSettings: nil)   // nil = compressed passthrough
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { throw CreationStudioError.cannotCreateExportSession }
        reader.add(vOut)

        let staging = out.deletingLastPathComponent()
            .appendingPathComponent("staging-\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: staging)
        let writer = try AVAssetWriter(outputURL: staging, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        guard let vFmt = try await cv.load(.formatDescriptions).first else {
            throw CreationStudioError.noVideoTrack
        }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: vFmt)
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { throw CreationStudioError.cannotCreateExportSession }
        writer.add(vIn)

        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = [(vOut, vIn)]
        if let ca, let aFmt = try? await ca.load(.formatDescriptions).first {
            let aOut = AVAssetReaderTrackOutput(track: ca, outputSettings: nil)   // passthrough audio
            aOut.alwaysCopiesSampleData = false
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: aFmt)
            aIn.expectsMediaDataInRealTime = false
            if reader.canAdd(aOut), writer.canAdd(aIn) { reader.add(aOut); writer.add(aIn); pairs.append((aOut, aIn)) }
        }

        do {
            // Track 0 (video) must start on a keyframe for passthrough to be decodable.
            try await WindowReencoder(reader: reader, writer: writer, pairs: pairs,
                                      loader: loader, dropLeadingNonSync: [0]).run()
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        // Sanity-gate the copy: if keyframe-skipping left an empty/trackless file (no sync sample
        // found, or a container the writer mishandled), DON'T cache it as good — throw so
        // cacheOneWindow falls back to a real re-encode. Cheap to verify a local file.
        let check = AVURLAsset(url: staging)
        guard (try? await check.loadTracks(withMediaType: .video).first) != nil,
              let d = try? await check.load(.duration), d.seconds > 0.1 else {
            try? FileManager.default.removeItem(at: staging)
            throw CreationStudioError.cannotCreateExportSession
        }
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: staging, to: out)
    }

    /// Re-encode a SOURCE [start,end] window to a local faststart MP4, reading every byte through
    /// the `ResilientStreamLoader` — the SAME resilient path playback uses (Decision 021/031/034).
    ///
    /// WHY not AVAssetExportSession (the old `transcode`): it owns its own HTTP connection (no
    /// resourceLoader hook), so it can't survive archive.org dropping an idle connection mid-read,
    /// and fails "Operation Stopped" (AVFoundationErrorDomain -11838 / -12109) on a window deep
    /// inside a long remote film. AVAssetReader DOES drive the asset's resourceLoader (the same way
    /// AVPlayer does — `loadTracks` already works on the resilient asset in the preview), so reads
    /// fail over + resume invisibly. A zero-based AVMutableComposition windows the source so the
    /// reader yields [0, dur] samples (no per-sample retiming needed), and AVAssetReader →
    /// AVAssetWriter does a straight decode → H.264/AAC re-encode to a clean, faststart, GOP-safe
    /// local file (passthrough copy is unsafe from an arbitrary, mid-GOP window start).
    private static func reencodeWindow(sourceURL: URL, range: CMTimeRange, to out: URL) async throws {
        let (srcAsset, loader) = ResilientStreamLoader.makeAsset(for: sourceURL)

        guard let srcV = try await srcAsset.loadTracks(withMediaType: .video).first else {
            throw CreationStudioError.noVideoTrack
        }
        let srcA = try? await srcAsset.loadTracks(withMediaType: .audio).first

        // Clamp the requested window to what the source actually holds (a generous preview window
        // can run past the end), so insertTimeRange never throws on an out-of-bounds range.
        let srcDur = (try? await srcV.load(.timeRange).duration) ?? range.end
        let end = CMTimeMinimum(range.end, srcDur)
        let clamped = CMTimeRange(start: range.start, duration: CMTimeMaximum(CMTime(value: 1, timescale: 600), end - range.start))

        // Zero-base the window via a composition → reader output is [0, dur], no retiming.
        let comp = AVMutableComposition()
        guard let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CreationStudioError.noVideoTrack
        }
        try cv.insertTimeRange(clamped, of: srcV, at: .zero)
        var ca: AVMutableCompositionTrack?
        if let srcA, let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? track.insertTimeRange(clamped, of: srcA, at: .zero)
            ca = track
        }

        let reader = try AVAssetReader(asset: comp)

        let vOut = AVAssetReaderTrackOutput(track: cv, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { throw CreationStudioError.cannotCreateExportSession }
        reader.add(vOut)

        // Audio channel count / sample rate from the source ASBD (clamp to mono/stereo — AAC needs
        // an explicit channel layout above 2 ch, and archive films are effectively all mono/stereo).
        var outCh = 2, outRate = 44100.0
        if let srcA, let fmt = try? await srcA.load(.formatDescriptions).first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee {
            outCh = max(1, min(2, Int(asbd.mChannelsPerFrame)))
            if asbd.mSampleRate >= 8000, asbd.mSampleRate <= 48000 { outRate = asbd.mSampleRate }
        }
        var aOut: AVAssetReaderTrackOutput?
        if let ca {
            let o = AVAssetReaderTrackOutput(track: ca, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: outRate, AVNumberOfChannelsKey: outCh,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
            o.alwaysCopiesSampleData = false
            if reader.canAdd(o) { reader.add(o); aOut = o }
        }

        let staging = out.deletingLastPathComponent()
            .appendingPathComponent("staging-\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: staging)
        let writer = try AVAssetWriter(outputURL: staging, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true            // moov-at-front (faststart)

        let natural = try await srcV.load(.naturalSize)
        let pref = try await srcV.load(.preferredTransform)
        let w = max(2, Int(abs(natural.width).rounded())), h = max(2, Int(abs(natural.height).rounded()))
        let bitrate = max(4_000_000, min(40_000_000, w * h * 4))   // high — minimize generational loss
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: true]])
        vIn.expectsMediaDataInRealTime = false
        vIn.transform = pref                                  // same orientation metadata as the source
        guard writer.canAdd(vIn) else { throw CreationStudioError.cannotCreateExportSession }
        writer.add(vIn)

        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = [(vOut, vIn)]
        if let aOut {
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: outCh, AVSampleRateKey: outRate,
                AVEncoderBitRateKey: outCh >= 2 ? 192_000 : 96_000])
            aIn.expectsMediaDataInRealTime = false
            if writer.canAdd(aIn) { writer.add(aIn); pairs.append((aOut, aIn)) }
        }

        do {
            try await WindowReencoder(reader: reader, writer: writer, pairs: pairs, loader: loader).run()
        } catch {
            try? FileManager.default.removeItem(at: staging)   // don't leak partial files on retry
            throw error
        }

        // Atomic-ish move into place so a partially-written file is never treated as cached.
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: staging, to: out)
    }

    /// Race an async op against a deadline. A degraded archive.org node can STALL a cache export
    /// mid-flight (a 503 after the first bytes) with no error — the session just hangs. Capping the
    /// attempt turns a hang into a thrown timeout, so `cachedWindow`'s retry loop re-resolves a
    /// healthy node instead of freezing forever (owner: "videos hang for a long time"). On timeout
    /// the export task is cancelled (the async export observes it and stops fetching).
    private static func withTimeout(_ seconds: Double,
                                    _ op: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await op() }
            group.addTask { try await Task.sleep(for: .seconds(seconds)); throw CancellationError() }
            defer { group.cancelAll() }
            try await group.next()      // first to finish (op done, op error, or timeout)
        }
    }
}

/// Drives an AVAssetReader → AVAssetWriter re-encode to completion. @unchecked Sendable: the
/// non-Sendable AV objects are touched only via `self` from the writer's serial `q` callbacks and
/// the `run()`-scoped task group; the resume-once guard is lock-protected. The `loader` is held
/// strongly so the source asset's (weakly-held) resourceLoader delegate stays alive for the read.
private final class WindowReencoder: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)]
    private let loader: ResilientStreamLoader?
    /// Pair indices that must begin on a sync sample (passthrough video) — leading non-keyframe
    /// samples are dropped so the copied stream is decodable from its first frame.
    private let dropLeadingNonSync: Set<Int>
    private let q = DispatchQueue(label: "com.bhwilkoff.archivewatch.window-reencode")

    init(reader: AVAssetReader, writer: AVAssetWriter,
         pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)], loader: ResilientStreamLoader?,
         dropLeadingNonSync: Set<Int> = []) {
        self.reader = reader; self.writer = writer; self.pairs = pairs; self.loader = loader
        self.dropLeadingNonSync = dropLeadingNonSync
    }

    func run() async throws {
        guard reader.startReading() else { throw reader.error ?? CreationStudioError.cannotCreateExportSession }
        guard writer.startWriting() else { throw writer.error ?? CreationStudioError.cannotCreateExportSession }
        writer.startSession(atSourceTime: .zero)
        // Pump every track concurrently; each finishes when its reader output drains.
        await withTaskGroup(of: Void.self) { group in
            for index in pairs.indices { group.addTask { await self.pump(index) } }
        }
        await writer.finishWriting()
        _ = loader                                  // keep the resilient loader alive to here
        if reader.status == .failed { throw reader.error ?? CreationStudioError.cannotCreateExportSession }
        guard writer.status == .completed else { throw writer.error ?? CreationStudioError.cannotCreateExportSession }
    }

    /// Feed one (output → input) pair until the output drains or a write fails. The block runs on
    /// `q`; it re-fetches the AV objects from `self.pairs[index]` so the @Sendable closure captures
    /// only Sendable values (self, index, the resume guard).
    private func pump(_ index: Int) async {
        let once = ResumeOnce()
        let input = pairs[index].1
        let needsSyncStart = dropLeadingNonSync.contains(index)
        let started = Flag()                 // serial q → no lock needed
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: q) {
                let output = self.pairs[index].0
                let input = self.pairs[index].1
                while input.isReadyForMoreMediaData {
                    if self.reader.status != .reading {
                        input.markAsFinished(); once.fire { cont.resume() }; return
                    }
                    if let sample = output.copyNextSampleBuffer() {
                        if needsSyncStart && !started.value {
                            let att = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
                            let notSync = (att?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
                            if notSync { continue }      // drop until the first keyframe
                            started.value = true
                        }
                        if !input.append(sample) {
                            input.markAsFinished(); once.fire { cont.resume() }; return
                        }
                    } else {
                        input.markAsFinished(); once.fire { cont.resume() }; return
                    }
                }
            }
        }
    }
}

/// Mutable boolean for the serial-queue pump (no locking — accessed only on the writer's queue).
private final class Flag: @unchecked Sendable { var value = false }

/// One-shot resume guard for a continuation driven by repeated callbacks.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire(_ resume: () -> Void) {
        lock.lock(); let go = !fired; fired = true; lock.unlock()
        if go { resume() }
    }
}
#endif
