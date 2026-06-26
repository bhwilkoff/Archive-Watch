#if os(macOS)
import Foundation
import SwiftData

// The proxy-clip LIBRARY (docs/macOS-DESIGN.md §2 "Library ≠ Project"; README "the FCP
// event browser"). App-global persistent state in SwiftData — NOT a document. A library
// entry is a reusable reference (archive.org id + URL + in/out + tags), never bytes; the
// same entry drops into many projects without mutating the library. Lives in the shared
// CloudKit container alongside Favorite/Playlist/WatchProgress so it can sync as an
// annotation layer (LWW by modifiedAt) — sync wiring is a Phase-1.x follow-up; this is
// the local persistence model + the ProxyClip bridge.
@Model
final class LibraryClip {
    @Attribute(.unique) var id: String          // ProxyClip.id UUID string
    var catalogItemID: String
    var sourceURLString: String
    var inSeconds: Double
    var outSeconds: Double
    var label: String
    var tags: [String]
    var posterFrameSeconds: Double
    var title: String
    var addedAt: Date
    var modifiedAt: Date
    /// Manual ordering for the Library sidebar (owner #5 — drag to reorder). Higher = nearer the
    /// top. Default 0 so existing rows fall back to addedAt order until first reordered; new rows
    /// get a large value so they appear on top. (Lightweight SwiftData migration: defaulted field.)
    var sortIndex: Double = 0

    init(id: String, catalogItemID: String, sourceURLString: String,
         inSeconds: Double, outSeconds: Double, label: String, tags: [String] = [],
         posterFrameSeconds: Double = 0, title: String,
         addedAt: Date = Date(), modifiedAt: Date = Date(), sortIndex: Double = 0) {
        self.id = id; self.catalogItemID = catalogItemID; self.sourceURLString = sourceURLString
        self.inSeconds = inSeconds; self.outSeconds = outSeconds
        self.label = label; self.tags = tags
        self.posterFrameSeconds = posterFrameSeconds; self.title = title
        self.addedAt = addedAt; self.modifiedAt = modifiedAt
        self.sortIndex = sortIndex
    }

    /// Stamp an edit so sync treats this device's copy as newest (#11b pattern).
    func touch() { modifiedAt = Date() }
}

extension LibraryClip {
    /// The pure-value reference used by the timeline + engine.
    var proxyClip: ProxyClip? {
        guard let url = URL(string: sourceURLString) else { return nil }
        return ProxyClip(
            id: UUID(uuidString: id) ?? UUID(),
            catalogItemID: catalogItemID, sourceURL: url,
            sourceRange: TimeRange(startSeconds: inSeconds,
                                   durationSeconds: max(0, outSeconds - inSeconds)),
            label: label, tags: tags, posterFrameSeconds: posterFrameSeconds, title: title)
    }

    convenience init(from proxy: ProxyClip) {
        self.init(id: proxy.id.uuidString, catalogItemID: proxy.catalogItemID,
                  sourceURLString: proxy.sourceURL.absoluteString,
                  inSeconds: proxy.sourceRange.start.seconds,
                  outSeconds: proxy.sourceRange.endSeconds,
                  label: proxy.label, tags: proxy.tags,
                  posterFrameSeconds: proxy.posterFrameSeconds, title: proxy.title,
                  sortIndex: Date().timeIntervalSinceReferenceDate)   // newest on top until reordered
    }
}
#endif
