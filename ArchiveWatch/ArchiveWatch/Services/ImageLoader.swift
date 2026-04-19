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

    enum Failure: Error { case decode, invalidURL }

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
            let (data, _) = try await session.data(from: url)
            try Task.checkCancellation()
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
