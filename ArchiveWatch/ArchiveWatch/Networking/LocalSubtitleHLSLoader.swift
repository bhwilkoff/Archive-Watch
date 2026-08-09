import AVFoundation

// Plays a subtitle track obtained ON DEVICE — pulled from the viewer's own
// OpenSubtitles account, or transcribed locally — over the remote film.
//
// WHY THIS EXISTS, measured rather than assumed: `SubtitleStore` writes a local
// HLS master whose video segment is the remote https MP4, and the original
// design handed AVPlayer that `file://` master directly. It never plays.
// `tools/test_local_master_playback.swift` puts the two shapes side by side
// against the SAME film: the already-published remote master reaches
// .readyToPlay with a legible group of ["English"] and advances, while the local
// master sits at .unknown indefinitely with an EMPTY error log and zero access
// events — AVFoundation does not refuse it, it never attempts the load at all.
// It will not follow a remote reference out of a local playlist.
//
// The shape that does work is the one already shipping for published captions
// (CaptionedHLSLoader, Config C): a resource-loader delegate serves the
// PLAYLISTS through a custom scheme while the media SEGMENT stays a direct https
// URL. This loader is that same shape with the playlists read off disk instead
// of fetched. It must serve the WebVTT too — a local subtitle rendition is a
// remote reference out of a custom-scheme playlist, and hits the same wall.
//
// The segment stays AVFoundation-owned: a custom-scheme SEGMENT fails
// CoreMediaError -12881 (harness-proven), so there is no mid-stream failover
// here, exactly as in CaptionedHLSLoader.
//
// `resolveNode` is a required parameter with no default so this file compiles
// against Foundation + AVFoundation + AirPlayRouting alone, which is what lets
// `tools/test_local_subtitle_loader.swift` exercise the SHIPPED code.
//
// AVURLAsset holds its resourceLoader delegate WEAKLY — the caller must retain
// the loader for the asset's lifetime (the player screens keep it in @State).
final class LocalSubtitleHLSLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {

    static let scheme = AirPlayRouting.hlsScheme

    private let dir: URL          // Caches/subtitles/{archiveID}/
    private let downloadURL: URL  // the progressive MP4
    private let resolveNode: @Sendable (URL) async -> URL
    let queue = DispatchQueue(label: "com.bhwilkoff.archivewatch.local-subtitle-hls")

    private init(dir: URL, downloadURL: URL,
                 resolveNode: @escaping @Sendable (URL) async -> URL) {
        self.dir = dir
        self.downloadURL = downloadURL
        self.resolveNode = resolveNode
    }

    /// Build a captioned asset from a locally-stored subtitle directory.
    /// Returns nil when the directory holds no master playlist.
    static func makeAsset(dir: URL, downloadURL: URL,
                          resolveNode: @escaping @Sendable (URL) async -> URL)
    -> (asset: AVURLAsset, loader: LocalSubtitleHLSLoader)? {
        let master = dir.appendingPathComponent("master.m3u8")
        guard FileManager.default.fileExists(atPath: master.path) else { return nil }
        // The host carries nothing; the path is what we resolve siblings against.
        guard let url = URL(string: "\(scheme)://local/subtitles/master.m3u8") else { return nil }
        let loader = LocalSubtitleHLSLoader(dir: dir, downloadURL: downloadURL,
                                            resolveNode: resolveNode)
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (asset, loader)
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_ rl: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource req: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = req.request.url, url.scheme?.lowercased() == Self.scheme else { return false }
        let name = url.lastPathComponent
        // Everything except the media segment is ours, because everything except
        // the media segment lives on disk.
        guard name.hasSuffix(".m3u8") || name.hasSuffix(".vtt") else { return false }
        Task { await serve(name: name, for: req) }
        return true
    }

    private func serve(name: String, for req: AVAssetResourceLoadingRequest) async {
        let file = dir.appendingPathComponent(name)
        guard var text = try? String(contentsOf: file, encoding: .utf8) else {
            req.finishLoading(with: URLError(.fileDoesNotExist))
            return
        }
        if name == "video.m3u8" {
            // Start on a known-live storage node rather than the /download 302,
            // for the same reason Config C does.
            let seg = await resolveNode(downloadURL)
            text = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    let l = String(line)
                    return (l.hasPrefix("http://") || l.hasPrefix("https://"))
                        ? Self.encodeSegment(seg) : l
                }
                .joined(separator: "\n")
        }
        respond(req, with: text, uti: name.hasSuffix(".vtt") ? "org.w3.webvtt" : "public.m3u-playlist")
    }

    /// A segment URI carrying raw spaces, parentheses or brackets is rejected by
    /// AVFoundation even though every HTTP client accepts it — the bug that made
    /// 2,485 captioned films unplayable. Kept identical to SubtitleStore's.
    static func encodeSegment(_ url: URL) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.formUnion(CharacterSet(charactersIn: "#[]@!$&'*+,;=:/?"))
        allowed.remove(charactersIn: " \"<>\\^`{|}()")
        return url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? url.absoluteString
    }

    private func respond(_ req: AVAssetResourceLoadingRequest, with text: String, uti: String) {
        guard !req.isCancelled else { return }
        let data = Data(text.utf8)
        if let ci = req.contentInformationRequest {
            ci.contentType = uti
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
}
