import AVFoundation
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
    /// Live connections. The handler must be RETAINED for the connection's
    /// life — NWConnection callbacks hold it weakly, and an unretained
    /// handler deallocates the instant `handle()` returns, leaving every
    /// request unanswered (measured: 8/8 harness failures, all silent).
    private var handlers: [ObjectIdentifier: ConnectionHandler] = [:]

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
    /// The HLS view of the same origin. Used on tvOS 27+, where a
    /// non-fragmented mp4 loses its audio a few minutes in.
    func hlsURL(for origin: URL) -> URL? {
        guard let plain = proxyURL(for: origin) else { return nil }
        return URL(string: plain.absoluteString.replacingOccurrences(of: ".mp4", with: ".m3u8"))
    }

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
        handlers[ObjectIdentifier(handler)] = handler
        handler.start()
    }

    fileprivate func connectionEnded(_ handler: ConnectionHandler) {
        queue.async { self.handlers[ObjectIdentifier(handler)] = nil }
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

    // --- HLS (tvOS 27 loses audio on a NON-fragmented mp4; fragmented and
    // HLS are immune -- measured on the owner's Apple TV). The film is
    // remuxed to fragments on the fly and published as a VOD playlist.
    // Segments go over real HTTP because a custom-scheme HLS media segment
    // is refused with -12881 (harness-proven 2026-07-22).
    private var _movie: MP4Fragmenter.Movie?
    private var _plan: MP4Fragmenter.Plan?
    private var preparing = false

    var plan: MP4Fragmenter.Plan? { lock.lock(); defer { lock.unlock() }; return _plan }
    var movie: MP4Fragmenter.Movie? { lock.lock(); defer { lock.unlock() }; return _movie }

    /// Fetch ftyp + moov and compute the whole fragment layout once.
    /// NSLock may not be held across an `await`, so every critical section
    /// here is a small synchronous helper.
    private func claimPreparation() -> Bool? {
        lock.lock(); defer { lock.unlock() }
        if _plan != nil { return true }
        if preparing { return false }
        preparing = true
        return nil
    }
    private func releasePreparation() { lock.lock(); preparing = false; lock.unlock() }
    private func store(_ m: MP4Fragmenter.Movie, _ p: MP4Fragmenter.Plan) {
        lock.lock(); _movie = m; _plan = p; lock.unlock()
    }

    func prepareHLS() async -> Bool {
        if let early = claimPreparation() { return early }
        defer { releasePreparation() }
        guard let head = await StreamPump.rangeData(origin, 0, 65_535) else { return false }
        // Header-only scan: a faststart moov is megabytes and this probe is
        // kilobytes, so a containment-checked box walk reports "no moov".
        let heads = MP4Fragmenter.scanHeaders(head)
        let ftyp = heads.first { $0.type == "ftyp" }.flatMap { h -> Data? in
            guard h.offset + h.size <= head.count else { return nil }
            return head.subdata(in: h.offset..<(h.offset + h.size))
        } ?? Data()

        // WALK to the moov rather than assuming it is at the front. Plenty of
        // archive.org uploads are not faststart: they are ftyp + mdat + moov,
        // and the moov sits behind a gigabyte of media. Every box states its
        // own size, so the chain can be skipped WITHOUT downloading the
        // payload -- one small read per hop. Guessing by scanning bytes for
        // "moov" would match inside media data; this cannot.
        var mv: MP4Fragmenter.Header? = heads.first { $0.type == "moov" }
        if mv == nil {
            var cursor = heads.last.map { $0.offset + $0.size } ?? head.count
            var hops = 0
            while mv == nil, hops < 12, cursor > 0 {
                hops += 1
                guard let probe = await StreamPump.rangeData(origin, cursor, cursor + 4095),
                      probe.count >= 8 else { break }
                let hs = MP4Fragmenter.scanHeaders(probe)
                guard let first = hs.first, first.size >= 8 else { break }
                if let found = hs.first(where: { $0.type == "moov" }) {
                    mv = MP4Fragmenter.Header(type: "moov",
                                              offset: cursor + found.offset,
                                              size: found.size)
                    break
                }
                cursor += hs.reduce(0) { $0 + $1.size }
            }
            if mv != nil { awdiag("AWHLS moov found late (non-faststart)") }
        }

        guard let mv, mv.size > 8, mv.size < 128_000_000,
              let moov = await StreamPump.rangeData(origin, mv.offset, mv.offset + mv.size - 1),
              moov.count >= mv.size else {
            awdiag("AWHLS could not locate moov for %@", origin.lastPathComponent)
            return false
        }
        var buf = ftyp; buf.append(moov)
        guard let m = try? MP4Fragmenter.parse(head: buf) else { return false }
        let p = MP4Fragmenter.plan(m, seconds: 2.0)
        store(m, p)
        awdiag("AWHLS planned %d segments for %@", p.fragments.count, origin.lastPathComponent)
        return true
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
                if let self { self.server.connectionEnded(self) }
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
        guard method == "GET" || method == "HEAD", path.hasPrefix(server.pathPrefix) else {
            send(status: "404 Not Found", headers: ["Content-Length": "0"], thenClose: true)
            return
        }
        let comp = String(path.split(separator: "/").last ?? "")

        // --- HLS routes. Relative URIs in the playlist resolve beside it, so
        // every name shares the resource key and the existing lookup works.
        if comp.hasSuffix(".m3u8"), let r = server.resource(forKey: String(comp.dropLast(5))) {
            Task { await self.serveHLS(r, key: String(comp.dropLast(5)), what: .playlist, method: method) }
            return
        }
        if comp.hasSuffix(".init.mp4"), let r = server.resource(forKey: String(comp.dropLast(9))) {
            Task { await self.serveHLS(r, key: String(comp.dropLast(9)), what: .initSegment, method: method) }
            return
        }
        if comp.hasSuffix(".m4s"), let dot = comp.range(of: ".seg", options: .backwards),
           let idx = Int(comp[dot.upperBound...].dropLast(4)),
           let r = server.resource(forKey: String(comp[comp.startIndex..<dot.lowerBound])) {
            Task { await self.serveHLS(r, key: "", what: .segment(idx), method: method) }
            return
        }

        guard let key = path.split(separator: "/").last.map({ String($0).replacingOccurrences(of: ".mp4", with: "") }),
              let resource = server.resource(forKey: key) else {
            send(status: "404 Not Found", headers: ["Content-Length": "0"], thenClose: true)
            return
        }
        Task { await self.respond(resource, method: method, range: range) }
    }

    fileprivate enum HLSWhat { case playlist, initSegment, segment(Int) }

    private func serveHLS(_ resource: MediaResource, key: String,
                          what: HLSWhat, method: String) async {
        guard await resource.prepareHLS(), let plan = resource.plan,
              let movie = resource.movie else {
            send(status: "503 Service Unavailable", headers: ["Content-Length": "0"], thenClose: true)
            return
        }
        var body = Data()
        var type = "video/mp4"
        switch what {
        case .playlist:
            body = Data(Self.playlist(movie, plan, key: key).utf8)
            type = "application/vnd.apple.mpegurl"
        case .initSegment:
            body = plan.initSegment
        case .segment(let i):
            guard i >= 0, i < plan.fragments.count else {
                send(status: "404 Not Found", headers: ["Content-Length": "0"], thenClose: true)
                return
            }
            let f = plan.fragments[i]
            // Only the byte ranges this segment needs, merged so the holes
            // between a coarse audio/video interleave are never downloaded.
            var want: [(Int, Int)] = []
            for ft in f.tracks {
                guard let ti = movie.tracks.firstIndex(where: { $0.id == ft.trackID }) else { continue }
                let t = movie.tracks[ti]
                for sIdx in ft.firstSample..<(ft.firstSample + ft.count) {
                    want.append((t.samples[sIdx].offset, t.samples[sIdx].size))
                }
            }
            want.sort { $0.0 < $1.0 }
            var merged: [(lo: Int, hi: Int)] = []
            for (off, size) in want {
                if var last = merged.last, off <= last.hi + 262_144 {
                    last.hi = max(last.hi, off + size); merged[merged.count - 1] = last
                } else { merged.append((off, off + size)) }
            }
            var chunks: [(lo: Int, hi: Int, data: Data)] = []
            for r in merged {
                guard let d = await StreamPump.rangeData(resource.origin, r.lo, r.hi - 1) else {
                    send(status: "502 Bad Gateway", headers: ["Content-Length": "0"], thenClose: true)
                    return
                }
                chunks.append((r.lo, r.lo + d.count, d))
            }
            guard let built = try? MP4Fragmenter.fragment(movie, f, media: { off, len in
                for c in chunks where c.lo <= off && off + len <= c.hi {
                    return c.data.subdata(in: (off - c.lo)..<(off - c.lo + len))
                }
                throw URLError(.dataNotAllowed)
            }) else {
                send(status: "500 Internal Server Error", headers: ["Content-Length": "0"], thenClose: true)
                return
            }
            body = built
        }
        send(status: "200 OK", headers: [
            "Content-Type": type,
            "Content-Length": "\(body.count)",
            "Accept-Ranges": "bytes",
        ], thenClose: false)
        if method == "GET" { _ = await write(body) }
        conn.cancel()
    }

    /// A VOD playlist naming every fragment, so the player never has to scan
    /// the film to discover its structure.
    fileprivate static func playlist(_ m: MP4Fragmenter.Movie,
                                     _ p: MP4Fragmenter.Plan, key: String) -> String {
        let ref = m.tracks.first { $0.handler == "vide" } ?? m.tracks[0]
        var durs: [Double] = []
        for f in p.fragments {
            var d: UInt64 = 0
            if let ft = f.tracks.first(where: { $0.trackID == ref.id }) {
                for i in ft.firstSample..<(ft.firstSample + ft.count) {
                    d += UInt64(ref.samples[i].duration)
                }
            }
            durs.append(Double(d) / Double(ref.timescale))
        }
        var out = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-PLAYLIST-TYPE:VOD\n"
        out += "#EXT-X-TARGETDURATION:\(Int(ceil(durs.max() ?? 6)))\n"
        out += "#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-INDEPENDENT-SEGMENTS\n"
        out += "#EXT-X-MAP:URI=\"\(key).init.mp4\"\n"
        for (i, d) in durs.enumerated() {
            out += String(format: "#EXTINF:%.5f,\n\(key).seg%d.m4s\n", d, i)
        }
        return out + "#EXT-X-ENDLIST\n"
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

    /// A buffered ranged read for the HLS routes, going through the SAME
    /// session and node pins as the streaming pump so fragments inherit
    /// Decision 031's pinning and 034's failover instead of re-inventing them.
    static func rangeData(_ origin: URL, _ lo: Int, _ hi: Int,
                          attempt: Int = 0) async -> Data? {
        let target = pins.target(for: origin)
        var req = URLRequest(url: target)
        req.setValue("bytes=\(lo)-\(hi)", forHTTPHeaderField: "Range")
        req.timeoutInterval = 30
        do {
            let (d, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if let final = http.url, final != origin { pins.pin(final, for: origin) }
                return d
            }
            throw URLError(.badServerResponse)
        } catch {
            guard attempt < 3 else { return nil }
            pins.markFailed(host: target.host ?? "", for: origin)
            try? await Task.sleep(nanoseconds: UInt64((attempt + 1) * 400_000_000))
            return await rangeData(origin, lo, hi, attempt: attempt + 1)
        }
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

// MARK: - System-captions probe (diagnostic)

/// AW_SYSCAP_PROBE=1: the D079 verification instrument. Observe-only — lists
/// the item's legible options and reports whether the system's generated
/// track is OFFERED, and whether it ever EMITS text (offered ≠ selected ≠
/// emitting: the distinction that cost four decisions to learn, D063/065/
/// 067). Run with AW_NO_CAPTIONS=1 so nothing of ours is in the process.
@MainActor
final class SystemCaptionProbe {
    static let enabled = ProcessInfo.processInfo.environment["AW_SYSCAP_PROBE"] == "1"
    private var output: AVPlayerItemLegibleOutput?
    private var delegate: ProbeDelegate?

    func attach(to item: AVPlayerItem) {
        guard Self.enabled else { return }
        Task { @MainActor in
            let asset = item.asset
            let group = try? await asset.loadMediaSelectionGroup(for: .legible)
            let names = group?.options.map { $0.displayName } ?? []
            awdiag("AWSYSCAP legible options: %@", names.isEmpty ? "(none)" : names.joined(separator: " | "))
            if let group {
                let selected = item.currentMediaSelection.selectedMediaOption(in: group)
                awdiag("AWSYSCAP selected: %@", selected?.displayName ?? "(none)")
                // Select the first option so an offered-but-unselected track
                // gets its fair chance to emit (the D065 lesson).
                if selected == nil, let first = group.options.first {
                    item.select(first, in: group)
                    awdiag("AWSYSCAP selected option: %@", first.displayName)
                }
            }
            let out = AVPlayerItemLegibleOutput()
            out.suppressesPlayerRendering = false
            let d = ProbeDelegate()
            out.setDelegate(d, queue: .main)
            item.add(out)
            self.output = out
            self.delegate = d
        }
    }

    private final class ProbeDelegate: NSObject, AVPlayerItemLegibleOutputPushDelegate {
        private var emitted = 0
        func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                           didOutputAttributedStrings strings: [NSAttributedString],
                           nativeSampleBuffers nativeSamples: [Any],
                           forItemTime itemTime: CMTime) {
            let text = strings.map(\.string).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            emitted += 1
            if emitted <= 10 || emitted % 25 == 0 {
                awdiag("AWSYSCAP EMIT #%d t=%.1f: %@", emitted, itemTime.seconds, String(text.prefix(60)))
            }
        }
    }
}
