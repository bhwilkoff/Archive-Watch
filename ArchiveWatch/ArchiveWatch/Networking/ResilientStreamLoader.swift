import AVFoundation
import UniformTypeIdentifiers

// Streams a remote progressive MP4 through our OWN URLSession instead of letting
// AVFoundation own the HTTP connection.
//
// WHY (measured on-device, 2026-06): Archive serves a single progressive file
// over a connection it periodically drops/resets (TCP RST + read timeout) once
// the client's buffer is full and AVFoundation goes idle. When that happens
// AVFoundation discards its ENTIRE forward buffer and re-downloads — so even with
// 120-210s banked and throughput 15-70x the file's bitrate (1.15 Mbps file,
// 18-84 Mbps observed), playback hitches ~once every reconnect, and sometimes
// the connection dies and never recovers. A bigger buffer can't fix a
// flush-on-reset.
//
// This delegate makes reconnects invisible: AVFoundation talks to a custom-scheme
// URL, so it hands every byte-range request to us; we serve it with short, chunked
// URLSession range requests that retry/resume from the exact offset on any
// timeout or reset. AVFoundation never sees a broken connection, so it never
// flushes. Same bytes, same file — quality is identical.
//
// AVURLAsset holds its resourceLoader delegate WEAKLY, so the caller must retain
// the loader for the asset's lifetime (the player screens keep it in @State).
//
// @unchecked Sendable: all mutable state (`tasks`, `contentLength`) is confined to
// the serial `queue` — the delegate callbacks run on it, and the per-request Tasks
// reach it via queue.sync/async. The URLSession and immutable lets are safe.
// Playback diagnostics, gated by AW_PLAYBACK_DIAG=1 (no-op in production).
// Logs stall events + buffer depth so loader changes can be judged by observed
// evidence (the Decision 021 discipline): count AWSTALL lines, watch AWBUF.
enum PlaybackDiag {
    static let enabled = ProcessInfo.processInfo.environment["AW_PLAYBACK_DIAG"] == "1"

    @MainActor
    static func attach(item: AVPlayerItem, player: AVPlayer) {
        guard enabled else { return }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVPlayerItemPlaybackStalled,
            object: item, queue: .main) { _ in
            NSLog("AWSTALL playback stalled")
        }
        _ = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { t in
            let ahead = item.loadedTimeRanges
                .map { $0.timeRangeValue }
                .filter { $0.containsTime(t) || $0.start >= t }
                .map { $0.end.seconds - max(t.seconds, $0.start.seconds) }
                .reduce(0, +)
            NSLog("AWBUF t=%.0f ahead=%.0f rate=%.2f", t.seconds, ahead, player.rate)
        }
    }
}

final class ResilientStreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "aw-stream"
    private static let diag = PlaybackDiag.enabled

    private let realURL: URL
    private let queue = DispatchQueue(label: "com.bhwilkoff.archivewatch.stream-loader")
    private var contentLength: Int64?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    // archive.org/download/... 302-redirects EVERY request to a storage node —
    // measured 0.5-1.0s extra time-to-first-byte per chunk vs hitting the node
    // directly (2026-06-10). Pin the post-redirect node URL after the first
    // response and request it directly; drop the pin on failure (nodes rotate)
    // so the next attempt re-resolves through the origin.
    private var pinnedURL: URL?

    // 8 MB ranges: with STREAMING delivery (bytes reach the player as they
    // arrive, not at chunk completion) a large chunk has no latency downside,
    // and it quarters how often we pay per-request time-to-first-byte.
    private let chunkSize: Int64 = 8 * 1024 * 1024
    private let maxRetries = 12                         // #6: ride out long, flaky films
    // #10: the FIRST handshake to a cold Archive storage node can be slow (302 to
    // a node that then spins up). Give it a generous per-request timeout so the
    // first play doesn't fail where a manual retry (warm node) would succeed.
    private let firstByteTimeout: TimeInterval = 30

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        // Abandon a stalled read FAST (vs AVFoundation's long timeout that drained
        // the whole buffer before recovering) so we can re-request and resume.
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 0          // no overall cap (long films)
        cfg.waitsForConnectivity = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: cfg)
    }()

    private init(url: URL) { self.realURL = url }

    /// Build an AVURLAsset whose loads route through this delegate. Returns a
    /// plain asset (no interception) for non-HTTP URLs so callers can use it
    /// unconditionally. The returned loader is `nil` when not intercepting.
    static func makeAsset(for url: URL) -> (asset: AVURLAsset, loader: ResilientStreamLoader?) {
        guard let s = url.scheme?.lowercased(), s == "http" || s == "https",
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (AVURLAsset(url: url), nil)
        }
        comps.scheme = scheme
        guard let customURL = comps.url else { return (AVURLAsset(url: url), nil) }
        let loader = ResilientStreamLoader(url: url)
        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (asset, loader)
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let id = ObjectIdentifier(loadingRequest)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.handle(loadingRequest, id: id)
        }
        tasks[id] = task                                   // on `queue`
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let id = ObjectIdentifier(loadingRequest)
        tasks[id]?.cancel()                                // on `queue`
        tasks.removeValue(forKey: id)
    }

    // MARK: Request handling

    private func handle(_ request: AVAssetResourceLoadingRequest, id: ObjectIdentifier) async {
        defer { queue.async { self.tasks.removeValue(forKey: id) } }
        if let info = request.contentInformationRequest {
            await fillContentInfo(info, request)
        } else if let data = request.dataRequest {
            await fulfillData(data, request)
        }
    }

    private func fillContentInfo(_ info: AVAssetResourceLoadingContentInformationRequest,
                                 _ request: AVAssetResourceLoadingRequest) async {
        // A ranged GET both proves byte-range support (206) and yields the total
        // length via Content-Range — more reliable than HEAD on Archive nodes.
        // #10: retry with backoff (the first handshake to a cold node is the most
        // common first-play failure; a manual retry succeeds because the node is
        // warm — so just do that retry automatically here).
        var attempt = 0
        while !request.isCancelled && !Task.isCancelled {
            var req = URLRequest(url: realURL)
            req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            req.timeoutInterval = firstByteTimeout
            do {
                let (_, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                // Pin the post-redirect storage node so every data chunk skips
                // the origin's 302 round trip (~0.5-1.0s saved per request).
                if let final = response.url, final != realURL {
                    queue.sync { self.pinnedURL = final }
                    if Self.diag { NSLog("AWSTREAM pinned node %@ (probe)", final.host ?? "?") }
                }

                let mime = http.mimeType ?? "video/mp4"
                info.contentType = UTType(mimeType: mime)?.identifier ?? AVFileType.mp4.rawValue

                if http.statusCode == 206,
                   let range = http.value(forHTTPHeaderField: "Content-Range"),
                   let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
                    info.isByteRangeAccessSupported = true
                    info.contentLength = total
                    queue.sync { self.contentLength = total }
                } else if http.expectedContentLength > 0 {
                    let len = http.expectedContentLength
                    info.isByteRangeAccessSupported = (http.statusCode == 206)
                    info.contentLength = len
                    queue.sync { self.contentLength = len }
                }
                request.finishLoading()
                return
            } catch {
                if request.isCancelled || Task.isCancelled { return }
                attempt += 1
                if attempt > maxRetries { request.finishLoading(with: error as NSError); return }
                let delay = min(2.5, 0.3 * Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func fulfillData(_ dataRequest: AVAssetResourceLoadingDataRequest,
                             _ request: AVAssetResourceLoadingRequest) async {
        var offset = dataRequest.currentOffset
        let upperBound: Int64? = dataRequest.requestsAllDataToEndOfResource
            ? queue.sync { contentLength }
            : dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
        var retries = 0

        while !request.isCancelled && !request.isFinished {
            if let upperBound, offset >= upperBound { request.finishLoading(); return }

            let hi = upperBound.map { min(offset + chunkSize, $0) } ?? (offset + chunkSize)
            let target = queue.sync { pinnedURL } ?? realURL
            var req = URLRequest(url: target)
            req.setValue("bytes=\(offset)-\(hi - 1)", forHTTPHeaderField: "Range")
            req.networkServiceType = .video

            let started = Date()
            // STREAMING delivery: every Data slice reaches the player the moment
            // it arrives, so the buffer grows continuously instead of in 2 MB
            // steps — and a mid-chunk timeout/reset loses NOTHING: `offset`
            // advances with each delivered byte and the retry resumes exactly
            // there. (The old whole-chunk `session.data` held bytes back until
            // chunk completion and re-downloaded the whole chunk on failure —
            // each such event was a multi-second hole in buffer feed.)
            let stream = ChunkStream(dataRequest: dataRequest, request: request)
            do {
                try await stream.run(session, req)
                offset += Int64(stream.delivered)
                if stream.delivered > 0 { retries = 0 }    // progress → reset backoff
                if let final = stream.finalURL, final != target {
                    queue.sync { pinnedURL = final }
                    if Self.diag { NSLog("AWSTREAM pinned node %@", final.host ?? "?") }
                }
                if stream.delivered == 0 {
                    request.finishLoading(); return        // clean EOF
                }
                if Self.diag {
                    let ms = Date().timeIntervalSince(started) * 1000
                    NSLog("AWSTREAM chunk off=%lld bytes=%d ms=%.0f mbps=%.1f pinned=%d",
                          offset - Int64(stream.delivered), stream.delivered, ms,
                          Double(stream.delivered) * 8 / max(ms / 1000, 0.001) / 1_000_000,
                          target != realURL ? 1 : 0)
                }
            } catch {
                offset += Int64(stream.delivered)          // keep what got through
                if stream.delivered > 0 { retries = 0 }
                if stream.status == 416 {                  // ranged past EOF
                    request.finishLoading(); return
                }
                if request.isCancelled || Task.isCancelled { return }
                // A pinned node can rotate/expire — fall back to the origin
                // (which re-resolves a fresh node) before burning retries.
                if target != realURL { queue.sync { pinnedURL = nil } }
                retries += 1
                if Self.diag { NSLog("AWSTREAM retry#%d off=%lld err=%@", retries, offset, "\(error)") }
                if retries > maxRetries { request.finishLoading(with: error as NSError); return }
                // Brief backoff, then re-request from the SAME offset (resume).
                let delay = min(2.0, 0.25 * Double(retries))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
}

/// One streamed ranged GET. Delivers each arriving Data slice straight to the
/// AVAssetResourceLoadingDataRequest and counts delivered bytes so the caller
/// can resume byte-exactly after a failure. Redirects are followed by
/// URLSession; `finalURL` carries the post-redirect node for pinning.
/// @unchecked Sendable: URLSession serializes its delegate callbacks; the
/// continuation handoff is lock-guarded.
private final class ChunkStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let dataRequest: AVAssetResourceLoadingDataRequest
    private let request: AVAssetResourceLoadingRequest
    private let lock = NSLock()
    private var cont: CheckedContinuation<Void, Error>?
    private var task: URLSessionDataTask?

    private(set) var delivered = 0
    private(set) var finalURL: URL?
    private(set) var status = 0

    init(dataRequest: AVAssetResourceLoadingDataRequest,
         request: AVAssetResourceLoadingRequest) {
        self.dataRequest = dataRequest
        self.request = request
    }

    func run(_ session: URLSession, _ req: URLRequest) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock()
                cont = c
                let t = session.dataTask(with: req)
                t.delegate = self
                task = t
                lock.unlock()
                t.resume()
            }
        } onCancel: {
            lock.lock(); let t = task; lock.unlock()
            t?.cancel()    // didCompleteWithError(.cancelled) resumes the continuation
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        finalURL = response.url
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        status = code
        completionHandler((200...299).contains(code) ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !request.isCancelled, !request.isFinished else { return }
        dataRequest.respond(with: data)
        delivered += data.count
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        if let error {
            c?.resume(throwing: error)
        } else if !(200...299).contains(status) {
            c?.resume(throwing: URLError(.badServerResponse))
        } else {
            c?.resume()
        }
    }
}
