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
            forName: AVPlayerItem.playbackStalledNotification,
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

    // NODE FAILOVER (2026-06-18): archive.org load-balances /download/ across
    // several storage nodes and a single one can be degraded (returns 5xx for
    // the whole file) while its siblings serve fine — so re-resolving through
    // the origin's 302 can keep re-pinning the bad node (a coin-flip per retry).
    // We fetch the item's OWN node list from /metadata (server + the workable
    // alternates) and, when a node hard-fails, blacklist its host and switch to
    // a healthy known node directly. Best-effort + fail-safe: if metadata is
    // unavailable, `alternateBases` stays nil and behavior is exactly as before
    // (origin 302 + pin-from-redirect). All three are queue-confined.
    private var failedHosts: Set<String> = []
    private var alternateBases: [URL]?
    private var alternatesRequested = false

    // TRANSPORT-LEVEL BLACKLISTING (2026-07): a single timeout/reset is the
    // EXPECTED Decision-021 idle drop and is NOT a node-health signal — but a
    // host that produces them REPEATEDLY with no bytes delivered in between is
    // degraded, and `markNodeFailed` was only reached by HTTP 5xx/403/404, so
    // `currentTarget()` could keep re-picking the same dead node forever on a
    // pure-transport failure. Count CONSECUTIVE transport failures per host
    // (timeout / connection-lost / resource-unavailable); after N on the SAME
    // host with no progress, blacklist it too so failover rotates away. ANY
    // delivered byte resets that host's counter. Queue-confined.
    private var transportFailsByHost: [String: Int] = [:]
    private let transportFailThreshold = 3

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

    /// Resolve an archive.org `/download/{id}/{file}` URL to a healthy node-DIRECT URL,
    /// bypassing the `/download` load-balancer (which transiently 503s an item while the
    /// item's OWN storage node serves 206). Returns the ORIGINAL url unchanged for a
    /// non-archive / non-/download URL, or when metadata is unavailable / no node verifies
    /// — so callers can use it unconditionally and degrade to current behavior.
    ///
    /// WHY: the EXPORT cache path (`ClipCache.transcode`) feeds a PLAIN `AVURLAsset` to
    /// `AVAssetExportSession`, which has NO resourceLoader and so cannot fail over the way
    /// playback does — a `/download` 503 would fail an export of an otherwise-good clip.
    /// Resolving to the node URL first gives export the same routing-around-503 the player
    /// gets via `currentTarget()`.
    /// Shared session for node resolution + metadata probes (capped per host) so these auxiliary
    /// fetches don't each spin up their own connection pool to archive.org.
    private static let nodeResolveSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: cfg)
    }()

    static func resolvedNodeURL(for url: URL) async -> URL {
        let s = url.absoluteString
        guard url.host?.hasSuffix("archive.org") == true,
              let r = s.range(of: "/download/") else { return url }
        let after = s[r.upperBound...]
        guard let slash = after.firstIndex(of: "/") else { return url }
        let id = String(after[..<slash])
        let encFile = String(after[after.index(after: slash)...])
        let metaID = id.removingPercentEncoding ?? id
        guard let metaURL = URL(string: "https://archive.org/metadata/\(metaID)") else { return url }

        // Reuse ONE shared session for node resolution — creating a fresh URLSession per call opened a
        // new connection pool to archive.org every time, and archive.org refuses an IP that opens too
        // many connections (error 61 / -1004). A shared session pools + caps them.
        let session = nodeResolveSession

        guard let (data, resp) = try? await session.data(from: metaURL),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return url }

        // Build the candidate node URLs (server + dir + encoded file), preferred first.
        var candidates: [URL] = []
        func add(_ server: String?, _ dir: String?) {
            guard let server, let dir, !server.isEmpty,
                  let u = URL(string: "https://\(server)\(dir)/\(encFile)") else { return }
            candidates.append(u)
        }
        add(obj["server"] as? String, obj["dir"] as? String)
        if let alt = obj["alternate_locations"] as? [String: Any],
           let workable = alt["workable"] as? [[String: Any]] {
            for w in workable { add(w["server"] as? String, w["dir"] as? String) }
        }
        // Return the first node that actually serves a byte range (200/206).
        for cand in candidates {
            var req = URLRequest(url: cand)
            req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            req.timeoutInterval = 30
            if let (_, r2) = try? await session.data(for: req),
               let h2 = r2 as? HTTPURLResponse, (200...299).contains(h2.statusCode) {
                return cand
            }
        }
        return url   // every node failed right now — let the caller's own retry handle it
    }

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

    // MARK: Node selection / failover (all queue-confined)

    /// The URL to request: a healthy pinned node, else a healthy known alternate
    /// node (hitting it directly skips the origin's 302 round-trip — a Decision
    /// 031 win too), else the origin (which 302-redirects to whatever node it
    /// picks). MUST be called on `queue`.
    private func currentTarget() -> URL {
        if let p = pinnedURL, !failedHosts.contains(p.host ?? "") { return p }
        if let alts = alternateBases,
           let healthy = alts.first(where: { !failedHosts.contains($0.host ?? "") }) {
            return healthy
        }
        return realURL
    }

    /// Blacklist a node's host after a HARD failure (5xx/403/404 — node-health
    /// signals, NOT the expected idle-connection resets) and drop the pin. If
    /// every known node has failed, forgive them all so we never deadlock with
    /// only the origin coin-flip — they may have recovered. MUST be on `queue`.
    private func markNodeFailed(_ url: URL) {
        if let h = url.host { failedHosts.insert(h) }
        pinnedURL = nil
        if let alts = alternateBases {
            let known = Set(alts.compactMap { $0.host })
            if !known.isEmpty && known.isSubset(of: failedHosts) { failedHosts.removeAll() }
        }
    }

    /// Best-effort, once-per-loader: fetch the item's storage nodes from
    /// /metadata so failover has explicit healthy alternates to switch to.
    /// Never throws into the playback path.
    private func ensureAlternates() {
        queue.async {
            guard !self.alternatesRequested else { return }
            self.alternatesRequested = true
            Task { await self.loadAlternates() }
        }
    }

    private func loadAlternates() async {
        // realURL.absoluteString == https://archive.org/download/{id}/{encFile}
        let s = realURL.absoluteString
        guard realURL.host?.hasSuffix("archive.org") == true,
              let r = s.range(of: "/download/") else { return }
        let after = s[r.upperBound...]
        guard let slash = after.firstIndex(of: "/") else { return }
        let id = String(after[..<slash])
        let encFile = String(after[after.index(after: slash)...])   // keep encoding
        let metaID = id.removingPercentEncoding ?? id
        guard let metaURL = URL(string: "https://archive.org/metadata/\(metaID)") else { return }

        var req = URLRequest(url: metaURL)
        req.timeoutInterval = firstByteTimeout
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        var bases: [URL] = []
        var seen = Set<String>()
        func add(_ server: String?, _ dir: String?) {
            guard let server, let dir, !server.isEmpty,
                  let u = URL(string: "https://\(server)\(dir)/\(encFile)"),
                  seen.insert(server).inserted else { return }
            bases.append(u)
        }
        add(obj["server"] as? String, obj["dir"] as? String)
        if let alt = obj["alternate_locations"] as? [String: Any],
           let workable = alt["workable"] as? [[String: Any]] {
            for w in workable { add(w["server"] as? String, w["dir"] as? String) }
        }
        guard !bases.isEmpty else { return }
        queue.sync { self.alternateBases = bases }
        if Self.diag { NSLog("AWSTREAM alternates: %d node(s) for %@", bases.count, metaID) }
    }

    private func fillContentInfo(_ info: AVAssetResourceLoadingContentInformationRequest,
                                 _ request: AVAssetResourceLoadingRequest) async {
        ensureAlternates()
        // A ranged GET both proves byte-range support (206) and yields the total
        // length via Content-Range — more reliable than HEAD on Archive nodes.
        // #10: retry with backoff (the first handshake to a cold node is the most
        // common first-play failure; a manual retry succeeds because the node is
        // warm — so just do that retry automatically here).
        var attempt = 0
        while !request.isCancelled && !Task.isCancelled {
            // Use currentTarget(), NOT realURL — the same node-failover fulfillData does.
            // This was the bug behind "couldn't read the source video" (and main-app
            // titles that "don't play at all"): archive.org's /download load-balancer
            // 503s an item while the item's OWN storage node serves 206, and the probe
            // here used to hammer the 503'ing origin maxRetries times and give up
            // WITHOUT ever trying the healthy alternate node — so the content-info load
            // (loadTracks) failed before any byte-range request could fail over.
            let target = queue.sync { currentTarget() }
            var req = URLRequest(url: target)
            req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            req.timeoutInterval = firstByteTimeout
            do {
                let (_, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                // A HARD server error (5xx/403/404) is a node-health signal: blacklist
                // this node + rotate to a healthy alternate on the next attempt (the
                // backoff also gives loadAlternates time to populate the node list).
                let st = http.statusCode
                if (500...599).contains(st) || st == 403 || st == 404 {
                    queue.sync { markNodeFailed(target) }
                    if Self.diag { NSLog("AWSTREAM probe node %@ failed (status %d) -> rotating", target.host ?? "?", st) }
                    throw URLError(.badServerResponse)
                }
                guard (200...299).contains(st) else {
                    throw URLError(.badServerResponse)
                }
                // Pin the post-redirect storage node so every data chunk skips
                // the origin's 302 round trip (~0.5-1.0s saved per request).
                if let final = response.url, final != realURL {
                    queue.sync { if !self.failedHosts.contains(final.host ?? "") { self.pinnedURL = final } }
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
            let target = queue.sync { currentTarget() }
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
                if stream.delivered > 0 {
                    retries = 0                             // progress → reset backoff
                    let host = target.host ?? ""           // ...and the host is alive
                    queue.sync { transportFailsByHost[host] = 0 }
                }
                if let final = stream.finalURL, final != target {
                    queue.sync { if !failedHosts.contains(final.host ?? "") { pinnedURL = final } }
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
                // A HARD server error (5xx/403/404) means THIS node is degraded —
                // blacklist its host and switch to a healthy known alternate
                // (markNodeFailed). A SINGLE timeout/reset is the EXPECTED
                // Decision-021 idle drop, not a node-health signal: just drop the
                // pin and re-resolve. BUT a host that yields N consecutive
                // transport failures with no bytes in between is degraded too —
                // blacklist it so `currentTarget()` rotates away instead of
                // re-picking it.
                let st = stream.status
                let host = target.host ?? ""
                let ec = (error as? URLError)?.code
                let isTransport = ec == .timedOut || ec == .networkConnectionLost
                    || ec == .resourceUnavailable
                queue.sync {
                    if (500...599).contains(st) || st == 403 || st == 404 {
                        markNodeFailed(target)
                        transportFailsByHost[host] = 0
                        if Self.diag { NSLog("AWSTREAM node %@ failed (status %d) -> rotating", host, st) }
                    } else {
                        if stream.delivered > 0 {
                            transportFailsByHost[host] = 0     // progress → host is alive
                        } else if isTransport {
                            let n = (transportFailsByHost[host] ?? 0) + 1
                            transportFailsByHost[host] = n
                            if n >= transportFailThreshold {
                                markNodeFailed(target)
                                transportFailsByHost[host] = 0
                                if Self.diag { NSLog("AWSTREAM node %@ failed (transport x%d) -> rotating", host, n) }
                            }
                        }
                        if target != realURL { pinnedURL = nil }
                    }
                }
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
