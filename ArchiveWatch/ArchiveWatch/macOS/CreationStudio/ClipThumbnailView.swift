#if os(macOS)
import SwiftUI
import AppKit

// The Library sidebar (and any clip chip) shows a clip's ACTUAL in-point frame, pulled from
// archive.org's universal thumbnail strip (ArchiveThumbnails) — instant, tiny, cached, and
// independent of whether the catalog store is loaded or a marketing poster exists. This is the
// "clip previews use thumbnails, not freshly-generated frames" rule applied to the sidebar; it
// also fixes the regression where the poster-only row showed nothing when the AsyncImage poster
// failed/was throttled (its placeholder was Color.clear).
@MainActor
final class ClipThumbnailCache {
    static let shared = ClipThumbnailCache()
    private var strips: [String: [ArchiveThumb]] = [:]     // archive.org strip per catalogItemID
    private var frames: [String: NSImage] = [:]            // decoded frame per "id@sec"
    private var stripTasks: [String: Task<[ArchiveThumb], Never>] = [:]

    /// The frame nearest `atSeconds` for a clip, or nil if the item has no thumbnails.
    func frame(catalogItemID: String, sourceURL: URL, atSeconds: Double) async -> NSImage? {
        let key = "\(catalogItemID)@\(Int(atSeconds.rounded()))"
        if let f = frames[key] { return f }

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
              let (data, _) = try? await URLSession.shared.data(from: pick.url),
              let img = NSImage(data: data) else { return nil }
        frames[key] = img
        return img
    }
}

struct ClipThumbnailView: View {
    let catalogItemID: String
    let sourceURL: URL?
    let atSeconds: Double
    var fallbackPoster: URL? = nil
    var corner: CGFloat = 4

    @State private var frame: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner).fill(.quaternary)
            if let frame {
                Image(nsImage: frame).resizable().scaledToFill()
            } else if let fallbackPoster {
                AsyncImage(url: fallbackPoster) { $0.resizable().scaledToFill() }
                    placeholder: { Image(systemName: "film").imageScale(.small).foregroundStyle(.tertiary) }
            } else {
                Image(systemName: "film").imageScale(.small).foregroundStyle(.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: "\(catalogItemID)@\(Int(atSeconds.rounded()))") {
            guard let url = sourceURL else { return }
            frame = await ClipThumbnailCache.shared.frame(
                catalogItemID: catalogItemID, sourceURL: url, atSeconds: atSeconds)
        }
    }
}
#endif
