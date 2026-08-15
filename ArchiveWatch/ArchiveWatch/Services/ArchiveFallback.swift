import Foundation

// A lower-bitrate copy of the film the viewer is trying to watch, for when
// the best copy cannot stream (owner decision 2026-08-15: "fallback is only
// appropriate when the full version isn't feasible" — and a film must start
// within ~30 seconds or the viewer is lost).
//
// Two vetted sources, tried in order by the player:
//   1. `fallbackVideoURL` baked into the catalog (tools/bake_fallbacks.py):
//      a smaller copy of the SAME film matched by imdb identity in the
//      pipeline — Decision 026's anchoring, never a runtime title search.
//   2. A smaller derivative on the SAME archive.org item, discovered here at
//      runtime from the item's own /metadata — same item, same film, zero
//      identity risk.
//
// The filter prefers ARCHIVE-GENERATED derivatives (`source: "derivative"`):
// those are h.264 by construction. An uploader's original labeled "MPEG4"
// can hide AV1 (The Oregon Trail), which no Apple TV decodes.
enum ArchiveFallback {

    /// The best smaller playable derivative on the item, or nil.
    static func smallerCopy(itemID: String, than currentURL: URL) async -> URL? {
        guard let metaURL = URL(string: "https://archive.org/metadata/\(itemID)") else { return nil }
        var req = URLRequest(url: metaURL)
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = obj["files"] as? [[String: Any]] else { return nil }

        let currentName = currentURL.lastPathComponent.removingPercentEncoding
            ?? currentURL.lastPathComponent
        let currentSize = files.first { ($0["name"] as? String) == currentName }
            .flatMap { $0["size"] as? String }.flatMap { Int64($0) } ?? .max

        var best: (name: String, size: Int64)?
        for f in files {
            guard let name = f["name"] as? String,
                  name.lowercased().hasSuffix(".mp4"),
                  name != currentName,
                  (f["source"] as? String) == "derivative",
                  let sizeStr = f["size"] as? String, let size = Int64(sizeStr),
                  size > 5_000_000,                    // not a thumbnail-sized stub
                  size < currentSize / 2               // meaningfully lighter
            else { continue }
            if best == nil || size > best!.size {      // largest of the smaller = best quality
                best = (name, size)
            }
        }
        guard let best,
              let encoded = best.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://archive.org/download/\(itemID)/\(encoded)")
    }
}
