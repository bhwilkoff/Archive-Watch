import AVFoundation
import MediaToolbox
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
// FILE-BACKED diagnostics for the external-observation harness (AW_DIAG_FILE=1).
// `devicectl` cannot hold a console stream open while the harness takes
// screenshots — two concurrent device sessions kill the console (measured: the
// stream died at the first capture, leaving a 6-minute scenario with one
// buffer sample). Diagnostics therefore write to Documents/awdiag.log,
// epoch-stamped, and the harness copies the file out afterwards
// (`devicectl device copy from --domain-type appDataContainer`). Truncated at
// launch; each write is a syscall, so a terminated app loses nothing.
enum DiagFile {
    static let enabled = ProcessInfo.processInfo.environment["AW_DIAG_FILE"] == "1"
    private static let q = DispatchQueue(label: "awdiag-file")
    private static let handle: FileHandle? = {
        guard enabled else { return nil }
        // Caches, not Documents: tvOS apps cannot write to Documents at all —
        // the first harness runs copied "Documents/awdiag.log" out of the
        // container and found no file node, because the write itself had
        // silently failed.
        let url = FileManager.default.urls(for: .cachesDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("awdiag.log")
        try? "".write(to: url, atomically: true, encoding: .utf8)
        return try? FileHandle(forWritingTo: url)
    }()
    static func log(_ s: String) {
        guard enabled, let h = handle else { return }
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, s)
        q.async { h.write(line.data(using: .utf8) ?? Data()) }
    }
}

/// Diagnostic line to console AND the harness file — NSLog-compatible
/// signature so call sites convert by name alone. Every AW* metric and every
/// [AWCAP] trace goes through here; the external harness reads the file.
func awdiag(_ format: String, _ args: CVarArg...) {
    let s = String(format: format, arguments: args)
    NSLog("%@", s)
    DiagFile.log(s)
}

// Playback diagnostics, gated by AW_PLAYBACK_DIAG=1 (no-op in production).
// Logs stall events + buffer depth so loader changes can be judged by observed
// evidence (the Decision 021 discipline): count AWSTALL lines, watch AWBUF.
enum PlaybackDiag {
    static let enabled = ProcessInfo.processInfo.environment["AW_PLAYBACK_DIAG"] == "1"

    // AW_AUDIO_DIAG=1: an RMS meter tap on the MAIN player's audio. Every other
    // diagnostic here watches the CLOCK and the BUFFER — an audio dropout with
    // video running is invisible to all of them, which is why "the audio gets
    // swallowed" could only ever be reported from a sofa. AWAUD lines make
    // silence readable from the dev Mac: rms ~0.0x during speech = swallowed.
    static let audioMeter = ProcessInfo.processInfo.environment["AW_AUDIO_DIAG"] == "1"
    /// Watchdog bookkeeping for the meter re-attach; main-queue only.
    nonisolated(unsafe) static var lastMeterReattach: CFAbsoluteTime = 0
    /// Error-log high-water mark so AWERR prints each entry once; main-queue only.
    nonisolated(unsafe) static var lastErrorLogCount = 0

    @MainActor
    static func attachAudioMeter(item: AVPlayerItem, label: String) {
        guard audioMeter else { return }
        Task {
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else {
                awdiag("AWAUD %@ no audio track found", label)
                return
            }
            guard let tap = AudioMeter.shared.makeTap() else {
                awdiag("AWAUD %@ tap creation failed", label)
                return
            }
            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            await MainActor.run {
                item.audioMix = mix
                awdiag("AWAUD %@ meter attached", label)
            }
        }
    }
}

// Plain final class, NO actor isolation — the tap callbacks run on the
// realtime audio thread (the exact trap LiveCaptions.BufferSink documents).
final class AudioMeter: @unchecked Sendable {
    static let shared = AudioMeter()
    private var accum: Float = 0
    private var samples: Int = 0
    private var lastPrint = CFAbsoluteTimeGetCurrent()
    /// When the meter last EMITTED. The tap fires on every buffer regardless
    /// of loudness (a silent film still emits rms~0 every 2s), so a stale
    /// emit while the player runs means the tap itself died — which happens
    /// across seeks/pipeline rebuilds and thins the harness's audio evidence
    /// (measured: 20 rms samples over a 304s run). Racy read from main of an
    /// RT-thread write; diagnostic-only, staleness tolerates it.
    private(set) var lastEmit = CFAbsoluteTimeGetCurrent()

    // The tap thread does MATH ONLY. The first version called awdiag (NSLog +
    // a queue dispatch) from here every 2s — a priority inversion on the
    // REALTIME audio thread. On a light decode the system tolerated it; under
    // the 4K file's load the RT thread missed deadlines and CoreAudio tore
    // the tap down every ~10-20s (ten "meter deaths" per run, gaps with no
    // I/O activity anywhere near them) — the instrument was perturbing the
    // very render it was built to observe, and plausibly audibly. Logging
    // moved to the main-thread AWBUF tick (`drain()`); these vars are read
    // racily there, which a diagnostic tolerates.
    func report(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount) {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        var sum: Float = 0
        var n = 0
        for buf in abl {
            guard let data = buf.mData else { continue }
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let ptr = data.bindMemory(to: Float.self, capacity: count)
            var i = 0
            while i < count { sum += ptr[i] * ptr[i]; n += 1; i += 16 }
        }
        accum += sum
        samples += n
        lastEmit = CFAbsoluteTimeGetCurrent()   // liveness = tap firing, not logging
    }

    /// Called from the MAIN-side diagnostics tick: read + reset the
    /// accumulator and return the rms since last drain, or nil if the tap
    /// delivered nothing.
    func drain() -> Float? {
        guard samples > 0 else { return nil }
        let rms = (accum / Float(samples)).squareRoot()
        accum = 0; samples = 0
        return rms
    }

    func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: nil,
            prepare: nil,
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList,
                                                                flagsOut, nil, framesOut)
                guard status == noErr else { return }
                let m = Unmanaged<AudioMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                m.report(bufferList, frames: framesOut.pointee)
            })
        var out: MTAudioProcessingTap?
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                             kMTAudioProcessingTapCreationFlag_PostEffects, &out)
        return err == noErr ? out : nil
    }
}

extension PlaybackDiag {
    @MainActor
    static func attach(item: AVPlayerItem, player: AVPlayer) {
        guard enabled else { return }
        // Tag every line with the PLAYER's identity: the baseline run that broke
        // the His Girl Friday case open showed two interleaved AWBUF timelines —
        // a leaked player advancing for the whole session next to the visible
        // one — and without an id per line that took forensics to notice.
        let pid = String(UInt(bitPattern: ObjectIdentifier(player).hashValue) % 0xFFFF, radix: 16)
        awdiag("AWLIFE tune player=%@", pid)
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item, queue: .main) { _ in
            awdiag("AWSTALL playback stalled player=%@", pid)
        }
        _ = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak player] t in
            let ahead = item.loadedTimeRanges
                .map { $0.timeRangeValue }
                .filter { $0.containsTime(t) || $0.start >= t }
                .map { $0.end.seconds - max(t.seconds, $0.start.seconds) }
                .reduce(0, +)
            // Dropped frames + decode errors, because "the picture looks like
            // 240p" and "the audio has static" are invisible to every other
            // metric here: corrupt bytes surface as ERROR-LOG entries, a
            // starved decoder as DROPPED frames — opposite fixes.
            let acc = item.accessLog()?.events.last
            let dropped = acc?.numberOfDroppedVideoFrames ?? -1
            let stallCt = acc?.numberOfStalls ?? -1
            awdiag("AWBUF p=%@ t=%.0f ahead=%.0f rate=%.2f drop=%ld stalls=%ld",
                   pid, t.seconds, ahead, player?.rate ?? -1, dropped, stallCt)
            if let errs = item.errorLog()?.events, errs.count > lastErrorLogCount {
                for e in errs.suffix(errs.count - lastErrorLogCount) {
                    awdiag("AWERR domain=%@ code=%ld %@", e.errorDomain, e.errorStatusCode,
                           e.errorComment ?? "")
                }
                lastErrorLogCount = errs.count
            }
            if audioMeter, let rms = AudioMeter.shared.drain() {
                awdiag("AWAUD rms=%.4f", rms)
            }
            // Meter watchdog: the tap dies across seeks/pipeline rebuilds and
            // never comes back on its own — re-attach a fresh tap so the
            // harness's audio-continuity evidence covers the whole run.
            if audioMeter, let pl = player, pl.rate > 0,
               let cur = pl.currentItem,
               CFAbsoluteTimeGetCurrent() - AudioMeter.shared.lastEmit > 8,
               CFAbsoluteTimeGetCurrent() - lastMeterReattach > 10 {
                lastMeterReattach = CFAbsoluteTimeGetCurrent()
                awdiag("AWAUD meter stale — re-attaching")
                MainActor.assumeIsolated { attachAudioMeter(item: cur, label: "reattach") }
            }
        }
    }
}

final class ResilientStreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    // Single source of truth: AirPlayRouting must know every loader scheme, or a
    // receiver can be handed a URL only this device can serve.
    static let scheme = AirPlayRouting.streamScheme
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

    // BLOCK CACHE for small random reads (2026-08-14). A long, oddly-muxed MP4
    // makes AVFoundation page its sample tables in tiny random dataRequests —
    // measured on a 2 GB / 136 min upload: 669 requests of 64 KB across three
    // file regions at once, each paying 60-180 ms of request latency, an
    // effective ~3-4 Mbps ceiling on a node that sustains ~100. The decoder
    // starves (visible frame drops), and the forward buffer can never build.
    // Small reads are served from aligned 2 MB blocks instead: one ranged GET
    // per block, LRU-capped, in-flight-deduped (concurrent 64 KB reads of one
    // region await a single fetch). Sequential media requests keep the
    // streaming path and every Decision 021/031/034 invariant untouched.
    private let blockSize: Int64 = 2 * 1024 * 1024
    private let smallReadLimit = 512 * 1024
    // The working set is the ~50 MB of interleaved media around the playhead
    // (this mux makes AVFoundation fetch each tiny sample chunk separately):
    // an 8-block cap thrashed — blocks 438-462 re-fetched 6-7x each, every
    // miss a 0.5-1.5s buffered fetch blocking the decode feed. 24 blocks
    // (48 MB) covers the set; still bounded on a 3 GB Apple TV.
    private let blockCacheCap = 40
    /// Highest byte offset the SEQUENTIAL chunk path has delivered — the
    /// video frontier. Small reads far BEHIND it are the audio track of a
    /// badly-muxed file (audio chunks trail the video by ~200 MB on
    /// TtCRB-4K), and they must never wait on a cold fetch: an audio-queue
    /// underrun silences the soundtrack for 8-13s while CoreAudio re-primes
    /// (measured: 15 dropouts in one run, rms gaps bracketed by meter
    /// deaths). Updated on `queue`.
    private var sequentialFrontier: Int64 = 0
    private var blockTasks: [Int64: Task<Data, Error>] = [:]   // queue-confined
    private var blockLRU: [Int64] = []                          // queue-confined
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
        // A SUBORDINATE loader (the caption scout) is marked background at the
        // socket level, so when it shares a constrained link with the viewer's
        // own stream the OS starves the SCOUT, not the film. App-level yielding
        // reacts only after a stall is already visible; QoS prevents the
        // contention underneath it.
        if subordinate { cfg.networkServiceType = .background }
        return URLSession(configuration: cfg)
    }()

    /// True for streams whose bytes serve something OTHER than what the viewer
    /// is watching right now — they must lose every bandwidth contest.
    private let subordinate: Bool

    private init(url: URL, subordinate: Bool = false) {
        self.realURL = url
        self.subordinate = subordinate
    }

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
    static func makeAsset(for url: URL,
                          subordinate: Bool = false) -> (asset: AVURLAsset, loader: ResilientStreamLoader?) {
        guard let s = url.scheme?.lowercased(), s == "http" || s == "https",
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (AVURLAsset(url: url), nil)
        }
        comps.scheme = scheme
        guard let customURL = comps.url else { return (AVURLAsset(url: url), nil) }
        let loader = ResilientStreamLoader(url: url, subordinate: subordinate)
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
        let usable = { (h: String?) in
            !self.failedHosts.contains(h ?? "") && !self.slowHosts.contains(h ?? "")
        }
        if let p = pinnedURL, usable(p.host) { return p }
        if let alts = alternateBases {
            if let fresh = alts.first(where: { usable($0.host) }) { return fresh }
            // Every node is failed or slow: a slow node still serves bytes,
            // which beats the origin coin-flip — forgive slowness rather
            // than deadlock (mirror of markNodeFailed's forgiveness).
            slowHosts.removeAll()
            if let healthy = alts.first(where: { !failedHosts.contains($0.host ?? "") }) {
                return healthy
            }
        }
        return realURL
    }

    /// Demote a node whose completed-or-cancelled chunks are TRICKLING — a
    /// different signal from a hard failure. Decision 034 rightly forbids
    /// blacklisting on a timeout (the expected idle drop), but a chunk that
    /// spends 18.7 seconds delivering 8 MB at 3.6 Mbps is measured
    /// throughput, and it starved playback to a stall twice in scenario
    /// atvrun-ttcrb5 — with no second stream running at all. Demoted, not
    /// failed: `currentTarget` prefers others and forgives when all are slow.
    private func markNodeSlow(_ url: URL) {
        if let h = url.host { slowHosts.insert(h) }
        pinnedURL = nil
    }
    private var slowHosts: Set<String> = []

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
        if Self.diag { awdiag("AWSTREAM alternates: %d node(s) for %@", bases.count, metaID) }
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
                    if Self.diag { awdiag("AWSTREAM probe node %@ failed (status %d) -> rotating", target.host ?? "?", st) }
                    throw URLError(.badServerResponse)
                }
                guard (200...299).contains(st) else {
                    throw URLError(.badServerResponse)
                }
                // Pin the post-redirect storage node so every data chunk skips
                // the origin's 302 round trip (~0.5-1.0s saved per request).
                if let final = response.url, final != realURL {
                    queue.sync { if !self.failedHosts.contains(final.host ?? "") { self.pinnedURL = final } }
                    if Self.diag { awdiag("AWSTREAM pinned node %@ (probe)", final.host ?? "?") }
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

    /// Serve `[from, to)` from aligned cached blocks, fetching missing ones.
    private func serveFromBlocks(_ dataRequest: AVAssetResourceLoadingDataRequest,
                                 _ request: AVAssetResourceLoadingRequest,
                                 from: Int64, to: Int64) async {
        var cursor = from
        while cursor < to && !request.isCancelled && !request.isFinished {
            let index = cursor / blockSize
            do {
                // The small-read pattern advances forward with the playhead;
                // warming the NEXT block turns each upcoming miss into a hit
                // and keeps a 0.5-1.5s fetch out of the decode path. And when
                // the read sits far BEHIND the video frontier it is the AUDIO
                // track of a badly-muxed file, whose next chunk lands 12-28 MB
                // ahead (measured strides 8 and 14 blocks) — warm a whole
                // stride window so no audio chunk is ever a cold 1-2s fetch.
                // Bandwidth is the cheap resource here (the same run banked
                // 377s of video); audio-queue LATENCY is what silences the
                // soundtrack.
                _ = queue.sync { () -> Bool in
                    let trailing = index < (sequentialFrontier / blockSize) - 50
                    let ahead: ClosedRange<Int64> = trailing ? 1...13 : 1...1
                    for d in ahead where blockTasks[index + d] == nil {
                        let next = index + d
                        let t = Task { [weak self] () throws -> Data in
                            guard let self else { throw URLError(.cancelled) }
                            return try await self.fetchBlock(next)
                        }
                        blockTasks[next] = t
                        blockLRU.append(next)
                    }
                    return true
                }
                let block = try await blockData(index)
                let blockStart = index * blockSize
                let lo = Int(cursor - blockStart)
                guard lo < block.count else { request.finishLoading(); return }  // past EOF
                let hi = Int(min(Int64(block.count), to - blockStart))
                dataRequest.respond(with: block.subdata(in: lo..<hi))
                cursor = blockStart + Int64(hi)
                if Int64(block.count) < blockSize && cursor < to {
                    request.finishLoading(); return          // short block == EOF
                }
            } catch {
                if !request.isCancelled && !request.isFinished {
                    request.finishLoading(with: error)
                }
                return
            }
        }
        if !request.isCancelled && !request.isFinished { request.finishLoading() }
    }

    /// The block's bytes, from cache or a single shared fetch (queue-confined
    /// task map dedupes concurrent readers of the same region).
    private func blockData(_ index: Int64) async throws -> Data {
        let task: Task<Data, Error> = queue.sync {
            if let existing = blockTasks[index] {
                blockLRU.removeAll { $0 == index }
                blockLRU.append(index)
                return existing
            }
            let t = Task { [weak self] () throws -> Data in
                guard let self else { throw URLError(.cancelled) }
                return try await self.fetchBlock(index)
            }
            blockTasks[index] = t
            blockLRU.append(index)
            while blockLRU.count > blockCacheCap {
                let evict = blockLRU.removeFirst()
                blockTasks[evict]?.cancel()
                blockTasks.removeValue(forKey: evict)
            }
            return t
        }
        return try await task.value
    }

    /// TEST-ONLY: read a byte range through the exact block-cache code the
    /// player's small reads use, so a harness can compare it byte-for-byte
    /// with a direct fetch (tools/test_loader_block_integrity.swift).
    func debugReadRange(offset: Int64, length: Int) async throws -> Data {
        var out = Data()
        var cursor = offset
        let to = offset + Int64(length)
        while cursor < to {
            let index = cursor / blockSize
            let block = try await blockData(index)
            let blockStart = index * blockSize
            let lo = Int(cursor - blockStart)
            guard lo < block.count else { break }
            let hi = Int(min(Int64(block.count), to - blockStart))
            out.append(block.subdata(in: lo..<hi))
            cursor = blockStart + Int64(hi)
            if Int64(block.count) < blockSize { break }
        }
        return out
    }

    private func fetchBlock(_ index: Int64) async throws -> Data {
        let lo = index * blockSize
        let hi = lo + blockSize - 1
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<3 {
            let target = queue.sync { attempt == 0 ? currentTarget() : realURL }
            var req = URLRequest(url: target)
            req.setValue("bytes=\(lo)-\(hi)", forHTTPHeaderField: "Range")
            req.networkServiceType = .video
            do {
                let started = Date()
                let (data, resp) = try await session.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status == 416 { return Data() }           // past EOF
                // 206 ONLY. A node that answers a Range request with 200 sends
                // the WHOLE FILE from byte zero — slicing that as if it were
                // the requested block would hand the demuxer garbage, which a
                // viewer perceives as degraded picture and broken sync.
                guard status == 206 else {
                    if (500...599).contains(status) || status == 403 || status == 404 {
                        queue.sync { markNodeFailed(target) }
                    }
                    lastError = URLError(.badServerResponse)
                    continue
                }
                // Belt and braces: a 206 whose payload exceeds the asked range
                // is equally poisonous.
                guard Int64(data.count) <= blockSize else {
                    lastError = URLError(.badServerResponse)
                    continue
                }
                if Self.diag {
                    let ms = Date().timeIntervalSince(started) * 1000
                    awdiag("AWSTREAM block idx=%lld bytes=%d ms=%.0f", index, data.count, ms)
                }
                return data
            } catch {
                lastError = error
                queue.sync { pinnedURL = nil }               // node may have rotated
            }
        }
        throw lastError
    }

    private func fulfillData(_ dataRequest: AVAssetResourceLoadingDataRequest,
                             _ request: AVAssetResourceLoadingRequest) async {
        var offset = dataRequest.currentOffset
        var upperBound: Int64? = dataRequest.requestsAllDataToEndOfResource
            ? queue.sync { contentLength }
            : dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
        // AUDIO-REGION RUNAWAY CAP. On a badly-muxed file AVFoundation asks
        // for the audio track — hundreds of MB BEHIND the video frontier —
        // with an OPEN-ENDED request, and this loop then streams forward
        // through video bytes it does not want until the lazy cancellation
        // lands (measured: 72 MB per runaway, 38 of them in one 6-minute
        // run, 41%% of all delivered bytes wasted — which starved the buffer
        // to a 13s knife edge and silenced the audio every ~20s). A request
        // that begins far behind the frontier gets 16 MB and an early
        // finishLoading(): a partially-fulfilled request is legal, and
        // AVFoundation simply asks again for exactly what it still needs.
        let frontier = queue.sync { sequentialFrontier }
        if dataRequest.requestsAllDataToEndOfResource,
           frontier > 0, offset < frontier - 100_000_000 {
            let capped = offset + 16_777_216
            upperBound = upperBound.map { min($0, capped) } ?? capped
            if Self.diag { awdiag("AWSTREAM trailing open-ended req off=%lld capped to 16MB", offset) }
        }
        var retries = 0

        // Small bounded reads (sample-table paging) go through the block cache.
        if !dataRequest.requestsAllDataToEndOfResource,
           dataRequest.requestedLength <= smallReadLimit,
           let upper = upperBound {
            await serveFromBlocks(dataRequest, request, from: offset, to: upper)
            return
        }

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
            // SLOW-CHUNK WATCHDOG. The 12s idle timeout never fires on a slow
            // TRICKLE (bytes keep arriving), so one glacial request can drain
            // the whole forward buffer — measured: an 8 MB chunk at 3.6 Mbps
            // held the stream for 18.7s while playback ran dry and stalled.
            //
            // The first version fired at <4 MB in 6s (~5.6 Mbps) — which is a
            // NORMAL living-room connection, not a glacial one. It cancelled a
            // measured 5.2 Mbps chunk, killed every TCP ramp at six seconds,
            // marked healthy nodes slow, and on the owner's wifi left titles
            // with no video at all (build 915). Only a genuinely DEAD trickle
            // justifies abandoning a connection: under 256 KB after ten full
            // seconds (~0.2 Mbps). Everything faster is left to finish — the
            // 18.7s outlier still trips this; a modest link never does.
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if stream.delivered < 262_144 { stream.cancelSlow() }
            }
            defer { watchdog.cancel() }
            do {
                try await stream.run(session, req)
                offset += Int64(stream.delivered)
                if stream.delivered > 0 {
                    retries = 0                             // progress → reset backoff
                    let host = target.host ?? ""           // ...and the host is alive
                    queue.sync {
                        transportFailsByHost[host] = 0
                        sequentialFrontier = max(sequentialFrontier, offset)
                    }
                }
                if let final = stream.finalURL, final != target {
                    queue.sync { if !failedHosts.contains(final.host ?? "") { pinnedURL = final } }
                    if Self.diag { awdiag("AWSTREAM pinned node %@", final.host ?? "?") }
                }
                if stream.delivered == 0 {
                    request.finishLoading(); return        // clean EOF
                }
                if Self.diag {
                    let ms = Date().timeIntervalSince(started) * 1000
                    awdiag("AWSTREAM chunk off=%lld bytes=%d ms=%.0f mbps=%.1f pinned=%d",
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
                        if Self.diag { awdiag("AWSTREAM node %@ failed (status %d) -> rotating", host, st) }
                    } else if stream.slowCancelled {
                        markNodeSlow(target)
                        transportFailsByHost[host] = 0
                        if Self.diag { awdiag("AWSTREAM node %@ slow (%d bytes in 6s) -> rotating", host, stream.delivered) }
                    } else {
                        if stream.delivered > 0 {
                            transportFailsByHost[host] = 0     // progress → host is alive
                        } else if isTransport {
                            let n = (transportFailsByHost[host] ?? 0) + 1
                            transportFailsByHost[host] = n
                            if n >= transportFailThreshold {
                                markNodeFailed(target)
                                transportFailsByHost[host] = 0
                                if Self.diag { awdiag("AWSTREAM node %@ failed (transport x%d) -> rotating", host, n) }
                            }
                        }
                        if target != realURL { pinnedURL = nil }
                    }
                }
                retries += 1
                if Self.diag { awdiag("AWSTREAM retry#%d off=%lld err=%@", retries, offset, "\(error)") }
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
    private(set) var slowCancelled = false

    init(dataRequest: AVAssetResourceLoadingDataRequest,
         request: AVAssetResourceLoadingRequest) {
        self.dataRequest = dataRequest
        self.request = request
    }

    /// Abort a chunk that is TRICKLING, so the caller resumes byte-exactly on
    /// another node. A distinct flag, because the resulting URLError is the
    /// same .cancelled the player's own teardown produces — the retry loop
    /// must be able to tell "we gave up on this node" from "the request died".
    func cancelSlow() {
        lock.lock(); slowCancelled = true; let t = task; lock.unlock()
        t?.cancel()
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
