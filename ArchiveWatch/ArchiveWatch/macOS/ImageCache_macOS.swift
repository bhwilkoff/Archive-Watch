#if os(macOS)
import SwiftUI
import AppKit
import CoreGraphics
import ImageIO

// Decode image bytes to an NSImage SwiftUI can render. NSImage(data:) preserves the source
// colorspace, and SwiftUI's `Image(nsImage:)` Metal path renders a GRAYSCALE (DeviceGray /
// monochrome) image as a SOLID WHITE box — CPU draw works, the GPU compositor doesn't (the
// "Frozen Frolics" B&W cartoon poster, a genuine 1-component grayscale TMDb JPEG, rendered
// white). Fix once, here: any image whose colorspace model isn't RGB is redrawn into 8-bit
// sRGB RGBA before it reaches SwiftUI. Covers grayscale + CMYK + 16-bit + exotic profiles for
// every RemoteImage call site (poster, cast circles, cards).
private func decodedRGBImage(_ data: Data) -> NSImage? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        return NSImage(data: data)            // fallback: let AppKit try
    }
    if cg.colorSpace?.model == .rgb && cg.bitsPerComponent == 8 {
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    let w = cg.width, h = cg.height
    guard w > 0, h > 0, let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return NSImage(data: data)
    }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let out = ctx.makeImage() else { return NSImage(data: data) }
    return NSImage(cgImage: out, size: NSSize(width: w, height: h))
}

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
            return decodedRGBImage(data)
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
