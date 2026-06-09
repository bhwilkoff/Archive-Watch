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
final class ResilientStreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "aw-stream"

    private let realURL: URL
    private let queue = DispatchQueue(label: "com.bhwilkoff.archivewatch.stream-loader")
    private var contentLength: Int64?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    private let chunkSize: Int64 = 2 * 1024 * 1024     // 2 MB range requests
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
            var req = URLRequest(url: realURL)
            req.setValue("bytes=\(offset)-\(hi - 1)", forHTTPHeaderField: "Range")

            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                retries = 0                                // progress made → reset backoff
                if data.isEmpty { request.finishLoading(); return }   // EOF
                if request.isCancelled { return }
                dataRequest.respond(with: data)
                offset += Int64(data.count)
            } catch {
                if request.isCancelled || Task.isCancelled { return }
                retries += 1
                if retries > maxRetries { request.finishLoading(with: error as NSError); return }
                // Brief backoff, then re-request from the SAME offset (resume).
                let delay = min(2.0, 0.25 * Double(retries))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
}
