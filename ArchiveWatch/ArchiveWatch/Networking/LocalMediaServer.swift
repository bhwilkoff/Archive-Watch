import Foundation
import Network

// A loopback HTTP server that fronts archive.org for AVPlayer (Decision 079).
//
// WHY: AVFoundation keys every platform capability on "is this a plain
// asset?". The custom-scheme resource loader — however good its transport —
// hides the asset from tvOS 27's generated captions (measured, Decision
// 067) and from AVAssetReader/export (Decision 054), and required the
// Decision 051 URL swap for AirPlay (which WORKS, and stays exactly as it
// is — the receiver gets the published origin URL on route engage). A `http://127.0.0.1` URL is a PLAIN
// HTTP asset: AVFoundation uses its entire native machinery against it, and
// we own only the far side of the socket — retrying, resuming, and failing
// over against archive.org exactly as Decisions 021/031/034 require, while
// the player neither knows nor cares. This is the production-proven pattern
// (KTVHTTPCache et al.); Apple's own forum guidance calls an on-device
// reverse proxy the valid alternative to the resource loader.
//
// NATIVE-FIRST CONDITION (owner, Decision 079): the proxy exists to RESTORE
// native-tool compatibility, never to replace native playback — files
// verified compliant and well-served should play their direct URL; this
// server is the resilience layer for the rest.
//
// HTTP contract (every item measured to matter, Decision 075's "media
// damaged" lesson): exact 206 + Content-Range + Content-Length on ranged
// GETs; 200 + Content-Length on rangeless; HEAD support; identity encoding
// (never chunked, never gzip); Content-Type video/mp4; Accept-Ranges: bytes;
// bytes streamed to the socket as they arrive from origin (Decision 031 —
// whole-chunk buffering recreates stepwise buffer growth). AVFoundation
// opens several concurrent sockets and abandons them on seeks — a peer
// close is cancellation, not an error.
//
// Security/lifecycle: loopback bind only; per-launch random path token so
// no other process can enumerate; ephemeral port; URLs are never persisted
// (the port changes every launch — the Firefox bug class). Started lazily
// on first use; lives for the process lifetime (cheap: one kqueue listener).
final class LocalMediaServer: @unchecked Sendable {
    static let shared = LocalMediaServer()

    private let queue = DispatchQueue(label: "aw-localserver")
    /// The listener gets its OWN queue: its state handler and the `port`
    /// property both dispatch onto the listener's queue, and sharing the
    /// registry queue deadlocked the very first `proxyURL` call (holding
    /// the queue in `queue.sync` while polling `l.port`, which dispatches
    /// to that same queue — measured hang, first harness run).
    private let listenerQueue = DispatchQueue(label: "aw-localserver-listen")
    private var listener: NWListener?
    private var port: UInt16 = 0
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    /// key (stable hash of origin URL) -> origin resource
    private var resources: [String: MediaResource] = [:]

    // MARK: Public

    /// The loopback URL AVPlayer should play for `origin`. Starts the server
    /// on first use. Returns nil only if the listener cannot start at all —
    /// callers fall back to the origin URL (never a hard failure).
    func proxyURL(for origin: URL) -> URL? {
        queue.sync {
            startLocked()
            guard port != 0 else { return nil }
            let key = Self.key(for: origin)
            if resources[key] == nil {
                resources[key] = MediaResource(origin: origin)
            }
            return URL(string: "http://127.0.0.1:\(port)/v/\(token)/\(key).mp4")
        }
    }

    /// True when `url` is one of ours. AirPlay works today via the
    /// Decision 051 swap and is UNCHANGED by the proxy: on route engage the
    /// receiver gets the published origin URL (it could never fetch
    /// 127.0.0.1), same as it always has.
    func isProxyURL(_ url: URL) -> Bool {
        url.host == "127.0.0.1" && url.path.hasPrefix("/v/\(token)/")
    }

    /// The origin behind a proxy URL (for the AirPlay swap).
    func origin(for url: URL) -> URL? {
        guard isProxyURL(url) else { return nil }
        let key = url.deletingPathExtension().lastPathComponent
        return queue.sync { resources[key]?.origin }
    }

    // MARK: Listener

    private func startLocked() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: .any)
            let ready = DispatchSemaphore(value: 0)
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let p = l.port?.rawValue ?? 0
                    self?.queue.async { self?.port = p }
                    awdiag("AWPROXY listening on 127.0.0.1:%d", Int(p))
                    ready.signal()
                case .failed(let err):
                    awdiag("AWPROXY listener failed: %@", "\(err)")
                    self?.queue.async { self?.listener = nil; self?.port = 0 }
                    ready.signal()
                default: break
                }
            }
            l.start(queue: listenerQueue)
            listener = l
            // Wait for readiness (bounded) so the FIRST proxyURL call
            // returns a complete URL. Safe: the handler runs on
            // listenerQueue, not the registry queue this method holds —
            // but it writes `port` via queue.async onto the HELD queue,
            // so read the port from the listener directly here.
            _ = ready.wait(timeout: .now() + 2)
            if port == 0, let p = l.port?.rawValue { port = p }
        } catch {
            awdiag("AWPROXY failed to start: %@", "\(error)")
            listener = nil
        }
    }

    private func handle(_ conn: NWConnection) {
        let handler = ConnectionHandler(conn: conn, server: self)
        handler.start()
    }

    fileprivate func resource(forKey key: String) -> MediaResource? {
        queue.sync { resources[key] }
    }

    fileprivate var pathPrefix: String { "/v/\(token)/" }

    static func key(for url: URL) -> String {
        // FNV-1a 64 over the absolute string — stable within a launch, no
        // meaning outside it.
        var h: UInt64 = 0xcbf29ce484222325
        for b in url.absoluteString.utf8 {
            h = (h ^ UInt64(b)) &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
}

// MARK: - One origin file

/// The origin URL plus its cached size, shared by every connection that
/// plays it. Byte fetching itself is per-connection (`StreamPump`) so
/// concurrent player sockets never serialize behind one transfer.
final class MediaResource: @unchecked Sendable {
    let origin: URL
    private let lock = NSLock()
    private var _contentLength: Int64?

    init(origin: URL) { self.origin = origin }

    var contentLength: Int64? {
        lock.lock(); defer { lock.unlock() }
        return _contentLength
    }

    func setContentLength(_ v: Int64) {
        lock.lock(); _contentLength = v; lock.unlock()
    }
}

// MARK: - Per-connection HTTP handling

/// Parses one HTTP/1.1 connection's requests and streams responses. Serial
/// per connection (HTTP/1.1 pipelining is not a thing AVFoundation does);
/// concurrency comes from AVFoundation opening several connections.
private final class ConnectionHandler: @unchecked Sendable {
    private let conn: NWConnection
    private unowned let server: LocalMediaServer
    private var buffer = Data()
    private var pump: StreamPump?

    init(conn: NWConnection, server: LocalMediaServer) {
        self.conn = conn
        self.server = server
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                // Peer gone — AVFoundation abandons sockets on seeks; this
                // is cancellation, not error (Decision 079 research).
                self?.pump?.cancel()
            default: break
            }
        }
        conn.start(queue: DispatchQueue(label: "aw-localserver-conn"))
        readRequest()
    }

    private func readRequest() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if let headerEnd = self.buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = self.buffer.subdata(in: self.buffer.startIndex..<headerEnd.lowerBound)
                self.buffer.removeSubrange(self.buffer.startIndex..<headerEnd.upperBound)
                self.serve(head: String(decoding: head, as: UTF8.self))
            } else if error != nil || isComplete {
                self.conn.cancel()
            } else if self.buffer.count > 64_000 {
                self.conn.cancel()   // not an HTTP request we recognize
            } else {
                self.readRequest()
            }
        }
    }

    private func serve(head: String) {
        let lines = head.components(separatedBy: "\r\n")
        guard let request = lines.first?.components(separatedBy: " "),
              request.count >= 2 else { conn.cancel(); return }
        let method = request[0]
        let path = request[1]
        var range: (lo: Int64, hi: Int64?)?
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("range:"),
               let m = line.range(of: "bytes=", options: .caseInsensitive) {
                let spec = line[m.upperBound...].trimmingCharacters(in: .whitespaces)
                let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
                if parts.count == 2, let lo = Int64(parts[0]) {
                    range = (lo, Int64(parts[1]))
                }
            }
        }
        guard method == "GET" || method == "HEAD",
              path.hasPrefix(server.pathPrefix),
              let key = path.split(separator: "/").last.map({ String($0).replacingOccurrences(of: ".mp4", with: "") }),
              let resource = server.resource(forKey: key) else {
            send(status: "404 Not Found", headers: ["Content-Length": "0"], thenClose: true)
            return
        }
        Task { await self.respond(resource, method: method, range: range) }
    }

    private func respond(_ resource: MediaResource, method: String,
                         range: (lo: Int64, hi: Int64?)?) async {
        // Total size: cached, else one ranged probe against origin.
        var total = resource.contentLength
        if total == nil {
            total = await StreamPump.probeLength(resource.origin)
            if let t = total { resource.setContentLength(t) }
        }
        guard let total else {
            send(status: "502 Bad Gateway", headers: ["Content-Length": "0"], thenClose: true)
            return
        }

        let lo = range?.lo ?? 0
        var hi = range?.hi ?? (total - 1)
        hi = min(hi, total - 1)
        if lo >= total {
            send(status: "416 Range Not Satisfiable",
                 headers: ["Content-Range": "bytes */\(total)", "Content-Length": "0"],
                 thenClose: false)
            readRequest()
            return
        }
        let length = hi - lo + 1
        var headers: [String: String] = [
            "Content-Type": "video/mp4",
            "Accept-Ranges": "bytes",
            "Content-Length": "\(length)",
            "Connection": "keep-alive",
        ]
        let status: String
        if range != nil {
            status = "206 Partial Content"
            headers["Content-Range"] = "bytes \(lo)-\(hi)/\(total)"
        } else {
            status = "200 OK"
        }
        send(status: status, headers: headers, thenClose: false)
        if method == "HEAD" {
            readRequest()
            return
        }

        let pump = StreamPump(origin: resource.origin, from: lo, to: hi + 1)
        self.pump = pump
        let ok = await pump.run { [weak self] data in
            await self?.write(data) ?? false
        }
        self.pump = nil
        if ok {
            readRequest()          // keep-alive: next request on this socket
        } else {
            conn.cancel()
        }
    }

    private func send(status: String, headers: [String: String], thenClose: Bool) {
        var head = "HTTP/1.1 \(status)\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] _ in
            if thenClose { self?.conn.cancel() }
        })
    }

    /// Backpressured write: waits for the send to be accepted before the
    /// pump fetches more, so a paused player doesn't balloon memory.
    private func write(_ data: Data) async -> Bool {
        await withCheckedContinuation { cont in
            conn.send(content: data, completion: .contentProcessed { error in
                cont.resume(returning: error == nil)
            })
        }
    }
}

// MARK: - Origin fetching

/// Streams one byte range from archive.org with the Decisions 021/031/034
/// contract: chunked ranged GETs on a short idle timeout, resume from the
/// exact delivered byte on any failure, storage-node pin from the first
/// redirect, blacklist-and-failover on hard node errors, never a bitrate
/// ceiling. This is the resource loader's transport engine re-fronted for
/// an HTTP consumer; the invariants are identical.
final class StreamPump: @unchecked Sendable {
    private let origin: URL
    private var offset: Int64
    private let end: Int64          // exclusive
    private var cancelled = false
    private let lock = NSLock()
    private var currentTask: URLSessionDataTask?

    private static let chunkSize: Int64 = 8 * 1024 * 1024
    private static let maxRetries = 6

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12      // the D021 short idle timeout
        cfg.timeoutIntervalForResource = 0
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// Post-redirect node pinning, shared across pumps for the same host
    /// session so every connection benefits (Decision 031).
    private static let pins = NodePins()

    init(origin: URL, from: Int64, to: Int64) {
        self.origin = origin
        self.offset = from
        self.end = to
    }

    func cancel() {
        lock.lock(); cancelled = true; let t = currentTask; lock.unlock()
        t?.cancel()
    }

    private func setTask(_ t: URLSessionDataTask?) {
        lock.lock(); currentTask = t; lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Streams [offset, end) to `sink` as slices arrive. Returns true on
    /// clean completion, false on cancellation/exhausted retries.
    func run(_ sink: @escaping (Data) async -> Bool) async -> Bool {
        var retries = 0
        while offset < end && !isCancelled {
            let hi = min(offset + Self.chunkSize, end)
            let target = Self.pins.target(for: origin)
            var req = URLRequest(url: target)
            req.setValue("bytes=\(offset)-\(hi - 1)", forHTTPHeaderField: "Range")
            req.networkServiceType = .video

            let stream = PumpChunk()
            setTask(nil)
            do {
                try await stream.run(Self.session, req,
                                     onTask: { [weak self] t in self?.setTask(t) },
                                     onData: { [weak self] data in
                                         guard let self, !self.isCancelled else { return false }
                                         let accepted = await sink(data)
                                         if accepted { self.offset += Int64(data.count) }
                                         return accepted
                                     })
                if let final = stream.finalURL, final != target {
                    Self.pins.pin(final, for: origin)
                }
                if stream.delivered > 0 { retries = 0 }
                if stream.status == 416 { return true }   // past EOF: clean end
                if stream.delivered == 0 && offset < end {
                    // 0-byte success = origin misbehaving; treat as retryable
                    retries += 1
                    if retries > Self.maxRetries { return false }
                }
            } catch {
                if isCancelled { return false }
                let st = stream.status
                if (500...599).contains(st) || st == 403 || st == 404 {
                    Self.pins.markFailed(host: target.host ?? "", for: origin)
                    if PlaybackDiag.enabled {
                        awdiag("AWPROXY node %@ failed (%d) -> rotating", target.host ?? "?", st)
                    }
                } else if target != origin {
                    Self.pins.unpin(for: origin)
                }
                retries += 1
                if PlaybackDiag.enabled {
                    awdiag("AWPROXY retry#%d off=%lld err=%@", retries, offset, "\(error)")
                }
                if retries > Self.maxRetries { return false }
                try? await Task.sleep(nanoseconds: UInt64(min(2.0, 0.25 * Double(retries)) * 1_000_000_000))
            }
        }
        return !isCancelled
    }

    /// Total size via one ranged probe (Content-Range total).
    static func probeLength(_ origin: URL) async -> Int64? {
        var req = URLRequest(url: origin)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.timeoutInterval = 30
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        if let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let totalStr = cr.split(separator: "/").last, let total = Int64(totalStr) {
            return total
        }
        if http.statusCode == 200 {
            return http.expectedContentLength > 0 ? http.expectedContentLength : nil
        }
        return nil
    }
}

/// Node pinning + failover state shared across pumps (Decisions 031/034).
private final class NodePins: @unchecked Sendable {
    private let lock = NSLock()
    private var pinned: [String: URL] = [:]        // origin absoluteString -> node URL
    private var failedHosts: [String: Set<String>] = [:]

    func target(for origin: URL) -> URL {
        lock.lock(); defer { lock.unlock() }
        let key = origin.absoluteString
        if let p = pinned[key], !(failedHosts[key] ?? []).contains(p.host ?? "") {
            return p
        }
        return origin
    }

    func pin(_ node: URL, for origin: URL) {
        lock.lock(); pinned[origin.absoluteString] = node; lock.unlock()
    }

    func unpin(for origin: URL) {
        lock.lock(); pinned[origin.absoluteString] = nil; lock.unlock()
    }

    func markFailed(host: String, for origin: URL) {
        lock.lock()
        let key = origin.absoluteString
        failedHosts[key, default: []].insert(host)
        pinned[key] = nil
        // Forgive everyone rather than deadlock when all known nodes failed.
        if (failedHosts[key]?.count ?? 0) > 4 { failedHosts[key] = [] }
        lock.unlock()
    }
}

/// One streamed ranged GET delivering slices via callback; counts delivered
/// bytes so the pump resumes byte-exactly (Decision 031's ChunkStream, with
/// an async sink and backpressure).
private final class PumpChunk: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private(set) var delivered = 0
    private(set) var finalURL: URL?
    private(set) var status = 0
    private var onData: ((Data) async -> Bool)?
    private var cont: CheckedContinuation<Void, Error>?
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    /// Serializes slice delivery so backpressure holds.
    private let deliverQueue = AsyncSerialQueue()

    func run(_ session: URLSession, _ req: URLRequest,
             onTask: (URLSessionDataTask) -> Void,
             onData: @escaping (Data) async -> Bool) async throws {
        self.onData = onData
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock()
                cont = c
                let t = session.dataTask(with: req)
                t.delegate = self
                task = t
                lock.unlock()
                onTask(t)
                t.resume()
            }
        } onCancel: {
            lock.lock(); let t = task; lock.unlock()
            t?.cancel()
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
        // Suspend the transport while the consumer drains — real
        // backpressure, so a paused AVPlayer pauses the origin fetch too.
        dataTask.suspend()
        let d = data
        deliverQueue.enqueue { [weak self] in
            guard let self, let onData = self.onData else { dataTask.cancel(); return }
            let ok = await onData(d)
            if ok {
                self.delivered += d.count
                dataTask.resume()
            } else {
                dataTask.cancel()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // Take the continuation synchronously (delegate queue), but resume
        // it only AFTER queued slice deliveries drain, so `delivered` is
        // final when run() returns.
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        let status = self.status
        deliverQueue.enqueue {
            if let error {
                c?.resume(throwing: error)
            } else if !(200...299).contains(status) && status != 416 {
                c?.resume(throwing: URLError(.badServerResponse))
            } else {
                c?.resume()
            }
        }
    }
}

/// Minimal serial async executor (order-preserving) for delegate callbacks
/// that must await an async consumer.
private final class AsyncSerialQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never> = Task {}

    func enqueue(_ op: @escaping @Sendable () async -> Void) {
        lock.lock()
        let prev = tail
        tail = Task { [prev] in
            await prev.value
            await op()
        }
        lock.unlock()
    }
}
