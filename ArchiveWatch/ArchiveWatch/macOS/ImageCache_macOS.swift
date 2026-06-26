#if os(macOS)
import SwiftUI
import AppKit

// App-wide poster/still loader for the BROWSE/PLAY face (the Creation Studio grids have their
// own StudioNet pool). Bare `AsyncImage(url:)` was the cause of the "posters load extremely
// slowly at startup and as new views are revealed" report: it holds no decoded-image cache (so
// every view reveal re-decodes — or re-downloads, since URLCache only keeps bytes), and it bursts
// unlimited concurrent connections, which archive.org throttles (the same per-host limit that bit
// Creation Studio — see creation_studio_connection_discipline). This pipeline fixes both:
//   • an NSCache of DECODED NSImages → a re-revealed view is instant, no re-decode,
//   • a single capped URLSession (reuses URLCache.shared, set to 64/400 MB at launch) so a grid
//     of 200 posters never storms one host,
//   • in-flight coalescing so the same URL requested by many cells downloads once.

@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 6        // brisk but never a flood (per host)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = .shared
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg)
    }()
    private let cache = NSCache<NSURL, NSImage>()
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    private init() { cache.countLimit = 800 }

    /// The decoded image for a URL, served from the in-memory cache when present, otherwise
    /// downloaded once (concurrent callers for the same URL share one fetch). nil on failure.
    func image(_ url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inflight[url] { return await task.value }
        let task = Task<NSImage?, Never> { [session] in
            guard let (data, resp) = try? await session.data(from: url) else { return nil }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            return NSImage(data: data)
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// Drop-in for `AsyncImage(url:)` backed by `ImagePipeline` — cached + capped. Shows the cached
/// image resizable in the given content mode, else a clear placeholder (the surrounding view
/// supplies its own background fill, exactly as the AsyncImage call sites already did).
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            image = nil
            if let url { image = await ImagePipeline.shared.image(url) }
        }
    }
}
#endif
