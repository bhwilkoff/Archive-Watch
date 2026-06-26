#if os(macOS)
import Foundation

// archive.org generates a scrubber thumbnail every ~30–60s for EVERY video item (the web
// player uses them), named "{base}_{seconds}.jpg" inside a ".thumbs/" folder. They're tiny
// (~5–30 KB) and UNIVERSAL — present even on items with no small mp4 derivative. Creation
// Studio uses them for INSTANT whole-movie navigation in the clip-add interface, so you find a
// clip without waiting for the (large, slow-on-some-nodes) video to load; only the chosen
// window is then fetched.
struct ArchiveThumb: Identifiable, Sendable, Hashable {
    let id: Int            // timestamp in seconds (also the sort key)
    var seconds: Double { Double(id) }
    let url: URL
}

/// One-fetch-per-item cache for thumbnail strips — a stock grid often shows many shots from the
/// SAME film, and without this each card would re-fetch that item's /metadata.
private actor ThumbStripCache {
    static let shared = ThumbStripCache()
    private var store: [String: [ArchiveThumb]] = [:]
    func get(_ key: String) -> [ArchiveThumb]? { store[key] }
    func set(_ key: String, _ value: [ArchiveThumb]) { store[key] = value }
}

enum ArchiveThumbnails {
    /// The timestamped thumbnail strip for a video URL, via /metadata. Empty if unavailable.
    static func strip(for videoURL: URL) async -> [ArchiveThumb] {
        let s = videoURL.absoluteString
        guard videoURL.host?.hasSuffix("archive.org") == true, let r = s.range(of: "/download/") else { return [] }
        let after = s[r.upperBound...]
        guard let slash = after.firstIndex(of: "/") else { return [] }
        let metaID = String(after[..<slash]).removingPercentEncoding ?? String(after[..<slash])
        if let cached = await ThumbStripCache.shared.get(metaID) { return cached }
        guard let metaURL = URL(string: "https://archive.org/metadata/\(metaID)"),
              let data = await StudioNet.data(from: metaURL),   // capped session — don't storm the main host
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let files = obj["files"] as? [[String: Any]] else { return [] }

        var thumbs: [ArchiveThumb] = []
        for f in files {
            guard let name = f["name"] as? String,
                  (f["format"] as? String) == "Thumbnail" || name.contains(".thumbs/"),
                  name.lowercased().hasSuffix(".jpg") else { continue }
            // Trailing "_{seconds}.jpg" → the frame's timestamp.
            let base = (name as NSString).deletingPathExtension
            guard let us = base.range(of: "_", options: .backwards),
                  let secs = Int(base[us.upperBound...]) else { continue }
            let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            guard let url = URL(string: "https://archive.org/download/\(metaID)/\(enc)") else { continue }
            thumbs.append(ArchiveThumb(id: secs, url: url))
        }
        let sorted = thumbs.sorted { $0.id < $1.id }
        await ThumbStripCache.shared.set(metaID, sorted)
        return sorted
    }

    /// The thumbnail nearest a timestamp (a shot's start) — its representative still.
    static func nearestThumb(for videoURL: URL, seconds: Double) async -> URL? {
        let strip = await strip(for: videoURL)
        return strip.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) }?.url
    }
}
#endif
