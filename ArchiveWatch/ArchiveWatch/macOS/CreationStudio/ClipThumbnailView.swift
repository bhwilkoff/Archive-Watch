#if os(macOS)
import SwiftUI
import AppKit

// The Library sidebar (and any clip chip) shows a clip's ACTUAL in-point frame, pulled from
// archive.org's universal thumbnail strip (ArchiveThumbnails) — instant, tiny, cached, and
// independent of whether the catalog store is loaded or a marketing poster exists.

/// ONE connection-capped session for ALL Creation Studio archive.org thumbnail/poster/metadata
/// fetches. The browser + library grids would otherwise fire DOZENS of requests at the MAIN
/// archive.org host at once (services/img, /metadata, covers); archive.org rate-limits an IP that
/// opens too many simultaneous connections (error 61 / -1004), and once the MAIN host blocks us it
/// also breaks clip downloads (they need the main host for the /download 302 + /metadata). Movies are
/// unaffected because they stream from storage NODES (different IPs). Capping the pool + reusing the
/// on-disk URLCache keeps the studio well under the limit. (This was the regression: the universal
/// services/img fallback + ungated AsyncImage made the grids storm the main host.)
enum StudioNet {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 3          // never storm the main archive.org host
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .returnCacheDataElseLoad   // reuse cached thumbnails (URLCache.shared)
        return URLSession(configuration: cfg)
    }()
    static func data(from url: URL) async -> Data? {
        (try? await session.data(from: url))?.0
    }
}

@MainActor
final class ClipThumbnailCache {
    static let shared = ClipThumbnailCache()
    private var strips: [String: [ArchiveThumb]] = [:]     // archive.org strip per catalogItemID
    private var images: [String: NSImage] = [:]            // decoded image per cache key
    private var stripTasks: [String: Task<[ArchiveThumb], Never>] = [:]
    private var urlImages: [URL: NSImage] = [:]            // decoded image per source URL (poster/universal)

    /// The best available still for a clip — its in-point FRAME, else the designed POSTER, else the
    /// universal archive.org item thumbnail — all fetched through the capped StudioNet session (so the
    /// grid never bursts the main host) and cached. nil → the caller shows an icon.
    func image(catalogItemID: String, sourceURL: URL?, atSeconds: Double, fallbackPoster: URL?) async -> NSImage? {
        if let url = sourceURL, let f = await frame(catalogItemID: catalogItemID, sourceURL: url, atSeconds: atSeconds) {
            return f
        }
        if let p = fallbackPoster, let img = await load(p) { return img }
        let id = catalogItemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? catalogItemID
        if let u = URL(string: "https://archive.org/services/img/\(id)"), let img = await load(u) { return img }
        return nil
    }

    /// The frame nearest `atSeconds` for a clip, or nil if the item has no thumbnails.
    private func frame(catalogItemID: String, sourceURL: URL, atSeconds: Double) async -> NSImage? {
        let key = "\(catalogItemID)@\(Int(atSeconds.rounded()))"
        if let f = images[key] { return f }

        let strip: [ArchiveThumb]
        if let s = strips[catalogItemID] { strip = s }
        else {
            // Coalesce concurrent strip fetches for the same item (many rows of one title).
            let task = stripTasks[catalogItemID] ?? {
                let t = Task { await ArchiveThumbnails.strip(for: sourceURL) }
                stripTasks[catalogItemID] = t
                return t
            }()
            strip = await task.value
            strips[catalogItemID] = strip
            stripTasks[catalogItemID] = nil
        }

        guard let pick = strip.min(by: { abs($0.seconds - atSeconds) < abs($1.seconds - atSeconds) }),
              let data = await StudioNet.data(from: pick.url),
              let img = NSImage(data: data) else { return nil }
        images[key] = img
        return img
    }

    /// Load + cache an arbitrary image URL (poster / universal thumb / grid thumbnail) through the
    /// capped session, so every Creation Studio grid shares the SAME bounded connection pool.
    func loadShared(_ url: URL) async -> NSImage? {
        if let img = urlImages[url] { return img }
        guard let data = await StudioNet.data(from: url), let img = NSImage(data: data) else { return nil }
        urlImages[url] = img
        return img
    }
    private func load(_ url: URL) async -> NSImage? { await loadShared(url) }
}

/// Drop-in for `AsyncImage(url:)` that loads through the capped StudioNet session (+ cache) instead of
/// URLSession.shared's ungated pool, so the browser / stock grids don't storm the main archive.org host.
struct StudioAsyncImage: View {
    let url: URL?
    var fill = true
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            image = nil
            if let url { image = await ClipThumbnailCache.shared.loadShared(url) }
        }
    }
}

struct ClipThumbnailView: View {
    let catalogItemID: String
    let sourceURL: URL?
    let atSeconds: Double
    var fallbackPoster: URL? = nil
    var corner: CGFloat = 4

    @State private var image: NSImage?

    var body: some View {
        // The RoundedRectangle (a Shape) takes EXACTLY the proposed frame, so it — not the image —
        // drives this view's size. The image rides in an .overlay, which is sized to the base and can
        // never enlarge the container; .scaledToFill overflow is then masked by .clipShape. (A ZStack
        // here let the scaledToFill image grow the stack and leak past the 44x30 frame, so the thumb
        // drew under the row's text — owner-reported.)
        RoundedRectangle(cornerRadius: corner)
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "film").imageScale(.small).foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
        // ONE gated, cached fetch per clip (frame → poster → universal) — no ungated AsyncImage bursts.
        .task(id: "\(catalogItemID)@\(Int(atSeconds.rounded()))") {
            image = await ClipThumbnailCache.shared.image(
                catalogItemID: catalogItemID, sourceURL: sourceURL,
                atSeconds: atSeconds, fallbackPoster: fallbackPoster)
        }
    }
}
#endif
