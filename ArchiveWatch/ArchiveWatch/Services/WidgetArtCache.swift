#if os(iOS) || os(macOS)
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

// Widget art cache (2026-06-24). Widgets render in a small, memory-limited process
// and CANNOT reliably async-load remote artwork (no AsyncImage caching). So the
// MAIN APP pre-downloads each surfaced item's poster/backdrop, downsamples it with
// ImageIO, and writes a small JPEG into the shared App Group container; the widget
// reads the local file synchronously. Cross-platform (ImageIO + CoreGraphics) so
// the same cache serves the iOS and macOS widgets.
enum WidgetArtCache {
    static let appGroup = "group.app.archivewatch.tvos"
    static let subdir = "widget-art"
    private static let maxPixel: CGFloat = 600     // ample for systemLarge @3x; tiny on disk

    static func directory() -> URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let dir = base.appendingPathComponent(subdir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileName(for archiveID: String) -> String {
        let safe = archiveID.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : "_"
        }
        return String(safe) + ".jpg"
    }

    static func fileURL(for archiveID: String) -> URL? {
        directory()?.appendingPathComponent(fileName(for: archiveID))
    }

    /// Download → downsample → write if not already cached. Returns the filename
    /// (relative to the widget-art dir) on success, nil otherwise.
    static func ensure(archiveID: String, remoteURL: String?) async -> String? {
        guard let dir = directory() else { return nil }
        let name = fileName(for: archiveID)
        let dest = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) { return name }   // already cached
        guard let s = remoteURL, let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let cg = downsample(data, maxPixel: maxPixel),
              writeJPEG(cg, to: dest) else { return nil }
        return name
    }

    /// Remove cached files whose names aren't in `keep` (LRU-by-relevance: the
    /// writer passes the currently-surfaced set).
    static func evict(keeping keep: Set<String>) {
        guard let dir = directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where !keep.contains(f.lastPathComponent) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private static func writeJPEG(_ cg: CGImage, to url: URL) -> Bool {
        guard let dst = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dst, cg,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(dst)
    }
}
#endif
