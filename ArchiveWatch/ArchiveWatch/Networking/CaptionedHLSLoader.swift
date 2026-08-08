import AVFoundation

// Part (a) — Config C: captioned playback that STARTS reliably on a known-live
// storage node while keeping the native WebVTT CC menu.
//
// A resource-loader delegate serves the film's HLS PLAYLISTS — the master and
// the single-segment video.m3u8 — through a custom scheme, while the video
// SEGMENT is a DIRECT https URL freshly resolved to a live archive.org storage
// node AT PLAY TIME (skipping the /download 302 + node-rotation-at-start, the
// main captioned "resource unavailable" + startup-stutter cause). Subtitle
// renditions + WebVTT stay direct https (archivewatch.org, small, CORS-exempt
// in-app), so the legible AVMediaSelectionGroup still populates.
//
// This is a SEPARATE branch from ResilientStreamLoader's chunked-range MP4
// machinery, and does NOT touch it. AVFoundation OWNS the media-segment
// connection — a custom-scheme HLS segment fails CoreMediaError -12881
// (harness-proven 2026-07-22), so the segment must stay a direct https URL and
// there is NO mid-stream failover here. Mid-stream recovery is the job of the
// stall-triggered `forceDirectPlayback` fallback (Part c): a persistent stall
// drops CC and rebuilds on the resilient MP4.
//
// Harness gate cleared (House on Haunted Hill + The Invisible Man 1933):
// readyToPlay + legible group ["English"] + seek to duration/2. Config C in
// memory `hls-custom-scheme-segment-limit`.
//
// AVURLAsset holds its resourceLoader delegate WEAKLY — the caller must retain
// the loader for the asset's lifetime (the player screens keep it in @State).
final class CaptionedHLSLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    // See ResilientStreamLoader.scheme — AirPlayRouting owns the vocabulary.
    static let scheme = AirPlayRouting.hlsScheme

    private let httpsMaster: URL   // https://archivewatch.org/subs/{id}/master.m3u8
    private let downloadURL: URL   // the progressive MP4 (its bytes stay AVFoundation-owned)
    private let queue = DispatchQueue(label: "com.bhwilkoff.archivewatch.captioned-hls")
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.httpMaximumConnectionsPerHost = 3
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private init(httpsMaster: URL, downloadURL: URL) {
        self.httpsMaster = httpsMaster
        self.downloadURL = downloadURL
    }

    /// Build the captioned asset (Config C). Returns a plain, non-intercepted
    /// asset + nil loader for a non-http(s) HLS URL, so callers can use it
    /// unconditionally and degrade to the native HLS path.
    static func makeAsset(hls: URL, downloadURL: URL) -> (asset: AVURLAsset, loader: CaptionedHLSLoader?) {
        guard let s = hls.scheme?.lowercased(), s == "http" || s == "https",
              var comps = URLComponents(url: hls, resolvingAgainstBaseURL: false) else {
            return (AVURLAsset(url: hls), nil)
        }
        comps.scheme = scheme
        guard let customMaster = comps.url else { return (AVURLAsset(url: hls), nil) }
        let loader = CaptionedHLSLoader(httpsMaster: hls, downloadURL: downloadURL)
        let asset = AVURLAsset(url: customMaster)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (asset, loader)
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_ rl: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource req: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = req.request.url else { return false }
        let path = url.path.lowercased()
        if path.hasSuffix("/master.m3u8") {
            Task { await serveMaster(req) }
            return true
        } else if path.hasSuffix("/video.m3u8") {
            Task { await serveVideo(req) }
            return true
        }
        // Subtitle playlists + VTT are absolute https (not our scheme) — AVFoundation
        // fetches them directly; the media segment likewise. Not ours.
        return false
    }

    // MARK: Playlist serving

    /// The master: rewrite the subtitle-rendition URIs to ABSOLUTE https (fetched
    /// directly, bypassing this loader) and keep the `video.m3u8` variant relative
    /// (→ our custom scheme → served with a node-resolved segment). Preserves every
    /// EXT-X-MEDIA line, so multi-language caption tracks survive.
    private func serveMaster(_ req: AVAssetResourceLoadingRequest) async {
        guard let text = await fetchText(httpsMaster) else {
            req.finishLoading(with: URLError(.cannotLoadFromNetwork))
            return
        }
        let base = httpsMaster.deletingLastPathComponent().absoluteString   // .../subs/{id}/
        let rewritten = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rewriteSubtitleURI(String($0), base: base) }
            .joined(separator: "\n")
        respond(req, with: rewritten)
    }

    /// The video variant: replace the segment URI with a freshly node-resolved
    /// direct https URL (falls back to the /download URL when no node verifies, so
    /// playback never breaks). Preserves EXTINF/target-duration from the template.
    private func serveVideo(_ req: AVAssetResourceLoadingRequest) async {
        let videoTemplate = httpsMaster.deletingLastPathComponent().appendingPathComponent("video.m3u8")
        guard let text = await fetchText(videoTemplate) else {
            req.finishLoading(with: URLError(.cannotLoadFromNetwork))
            return
        }
        // Reuse the SAME /metadata node resolution ResilientStreamLoader uses.
        let node = await ResilientStreamLoader.resolvedNodeURL(for: downloadURL)
        let seg = node.absoluteString
        let rewritten = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let l = String(line)
                // The single non-tag URL line is the segment. Replace it (any absolute
                // http(s) line) with the node-resolved segment.
                return (l.hasPrefix("http://") || l.hasPrefix("https://")) ? seg : l
            }
            .joined(separator: "\n")
        respond(req, with: rewritten)
    }

    /// `URI="rel"` on an EXT-X-MEDIA line → `URI="<base>rel"` (absolute). Leaves an
    /// already-absolute URI and lines without a `URI="` untouched.
    private func rewriteSubtitleURI(_ line: String, base: String) -> String {
        guard let r = line.range(of: "URI=\"") else { return line }
        let afterOpen = r.upperBound
        guard let closeQuote = line[afterOpen...].firstIndex(of: "\"") else { return line }
        let value = String(line[afterOpen..<closeQuote])
        guard !value.lowercased().hasPrefix("http") else { return line }
        return String(line[..<afterOpen]) + base + value + String(line[closeQuote...])
    }

    private func respond(_ req: AVAssetResourceLoadingRequest, with text: String) {
        guard !req.isCancelled else { return }
        let data = Data(text.utf8)
        if let ci = req.contentInformationRequest {
            ci.contentType = "public.m3u-playlist"
            ci.contentLength = Int64(data.count)
            ci.isByteRangeAccessSupported = true
        }
        if let dr = req.dataRequest {
            let start = Int(dr.requestedOffset)
            let end = min(start + dr.requestedLength, data.count)
            if start < data.count { dr.respond(with: data.subdata(in: start..<end)) }
        }
        req.finishLoading()
    }

    private func fetchText(_ url: URL) async -> String? {
        guard let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
