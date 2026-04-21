import Foundation
import UIKit
import ImageIO

// Custom image pipeline. Replaces AsyncImage for anything on a shelf or
// grid. Mirrors docs/tvos-playbook.md §7: NSCache for decoded UIImages,
// ImageIO for off-main downsampled decoding (the magic flag
// kCGImageSourceShouldCacheImmediately forces eager decode so we never
// pay a main-thread hitch when the cell first paints), inflight-coalesced
// so duplicate URLs only hit the network once.

actor ImageLoader {
    static let shared = ImageLoader()

    enum Failure: Error { case decode, invalidURL, notAnImage, httpError(Int) }

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private let session: URLSession

    private init() {
        // ATV 4K has ~3GB RAM (~700MB practical); ATV HD has ~1GB (~300MB).
        // 150MB decoded cache is a conservative ceiling that leaves
        // headroom for SwiftData, video buffer, and UIKit itself.
        cache.countLimit = 400
        cache.totalCostLimit = 150_000_000

        let config = URLSessionConfiguration.default
        config.urlCache = URLCache.shared
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
    }

    /// Load and decode an image at the given target display size. Returns
    /// a UIImage that's already decoded in memory (no draw-time hitch).
    func image(for url: URL, targetSize: CGSize, scale: CGFloat = 2) async throws -> UIImage {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let task = inFlight[url] { return try await task.value }

        let task = Task<UIImage, Error> {
            // Upgrade plain HTTP to HTTPS — tvOS ATS blocks plain HTTP
            // by default. Historical catalog data has Commons URLs
            // with http:// that we now rewrite transparently; the
            // enrichment pipeline has been corrected to emit https://
            // going forward.
            var fetchURL = url
            if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               comps.scheme == "http" {
                comps.scheme = "https"
                fetchURL = comps.url ?? url
            }

            let (data, response) = try await session.data(from: fetchURL)
            try Task.checkCancellation()

            // Validate BEFORE handing the bytes to ImageIO — non-image
            // responses (404 HTML pages, redirects, timeouts with
            // partial data) trigger the confusing
            // "CGImageSourceCreateThumbnailAtIndex -50" errors in the
            // console because ImageIO can't decode HTML as a JPEG.
            // Rejecting them here keeps the logs clean and turns the
            // failure into a clean placeholder instead of a log-spammy
            // decode attempt.
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else {
                    throw Failure.httpError(http.statusCode)
                }
                let ct = http.value(forHTTPHeaderField: "Content-Type") ?? ""
                if !ct.lowercased().hasPrefix("image/") {
                    throw Failure.notAnImage
                }
            }

            let image = try await Self.decode(data: data, targetSize: targetSize, scale: scale)
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: url as NSURL, cost: cost)
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }

    /// Best-effort prefetch — errors are swallowed. Used to warm the
    /// cache ahead of the user's focus.
    func prefetch(_ url: URL, targetSize: CGSize, scale: CGFloat = 2) {
        Task.detached(priority: .utility) { [self] in
            _ = try? await image(for: url, targetSize: targetSize, scale: scale)
        }
    }

    /// Off-main, downsampled decode via ImageIO. One pass — no raw
    /// UIImage allocation at the source resolution.
    private static func decode(data: Data, targetSize: CGSize, scale: CGFloat) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            let maxDim = max(targetSize.width, targetSize.height) * scale
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDim
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { throw Failure.decode }
            return UIImage(cgImage: cg, scale: scale, orientation: .up)
        }.value
    }
}
