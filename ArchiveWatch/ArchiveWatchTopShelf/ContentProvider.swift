import TVServices
import Foundation

// Top Shelf content provider (Decision 015 / M4; carousel redesign 2026-06-24).
//
// Reads the snapshot the main app writes into the shared App Group container
// (TopShelfSnapshot in the app target) and renders it as a best-in-class
// editorial CAROUSEL (the large rotating hero at the top of the Apple TV Home
// when the app icon is in the top row).
//
// Note: TVTopShelfCarouselItem has NO `title` property — the hero conveys identity
// via the artwork plus `contextTitle` (why it's shown), `summary`, `genre`,
// `duration`, `creationDate`, and up to 4 `namedAttributes`. We lead the summary
// with the title + year so it always reads.
//
// Self-contained on purpose: the extension can't share the app's in-memory state,
// and keeping the tiny reader here avoids cross-target file-membership coupling.

private enum Snapshot {
    static let appGroup = "group.app.archivewatch.tvos"
    static let fileName = "topshelf.json"

    struct Payload: Decodable {
        struct Item: Decodable {
            let archiveID: String
            let title: String
            let posterURL: String?
            let backdropURL: String?
            let year: Int?
            let synopsis: String?
            let runtimeSeconds: Int?
            let genre: String?
            let director: String?
            let cast: [String]
            let hasCaptions: Bool
            let context: String
            let progress: Double?
            let resume: Bool
        }
        let items: [Item]
    }

    static func read() -> Payload? {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}

class ContentProvider: TVTopShelfContentProvider {

    // Completion-handler overload (NOT the async one): the async form trips a
    // non-Sendable `TVTopShelfContent` error under Swift 6 strict concurrency.
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let payload = Snapshot.read(), !payload.items.isEmpty else {
            completionHandler(nil)
            return
        }

        let items = payload.items.prefix(10).compactMap { Self.carouselItem(from: $0) }
        guard !items.isEmpty else { completionHandler(nil); return }
        completionHandler(TVTopShelfCarouselContent(style: .details, items: items))
    }

    private static func carouselItem(from e: Snapshot.Payload.Item) -> TVTopShelfCarouselItem? {
        // A carousel hero needs wide art. Prefer the backdrop; allow a poster only
        // for personal Continue Watching items so an obscure resume still appears.
        let artString = e.backdropURL ?? (e.resume ? e.posterURL : nil)
        guard let art = artString, let artURL = URL(string: art) else { return nil }

        let item = TVTopShelfCarouselItem(identifier: e.archiveID)
        item.contextTitle = e.context          // "Continue Watching" / "Editor's Pick" / …

        // Title + year lead the summary, since the carousel has no title field.
        let titled = e.year.map { "\(e.title) (\($0))" } ?? e.title
        item.summary = e.synopsis.map { "\(titled). \($0)" } ?? titled

        item.genre = e.genre
        if let secs = e.runtimeSeconds, secs > 0 { item.duration = TimeInterval(secs) }
        if let y = e.year, let date = Self.date(forYear: y) { item.creationDate = date }

        // Up to 4 stylized attributes: Director, then Cast.
        var attrs: [TVTopShelfNamedAttribute] = []
        if let d = e.director, !d.isEmpty {
            attrs.append(TVTopShelfNamedAttribute(name: "Director", values: [d]))
        }
        if !e.cast.isEmpty {
            attrs.append(TVTopShelfNamedAttribute(name: "Cast", values: Array(e.cast.prefix(3))))
        }
        item.namedAttributes = attrs

        // Capability badges: HD always (we stream H.264); CC when captions exist.
        var media: TVTopShelfCarouselItem.MediaOptions = [.videoResolutionHD]
        if e.hasCaptions { media.insert(.audioTranscriptionClosedCaptioning) }
        item.mediaOptions = media

        // Light + dark art variants for tvOS 26 Liquid Glass legibility.
        item.setImageURL(artURL, for: [.screenScale1x, .screenScale2x])

        // Learning guardrail: SELECT opens Detail (a look, a choice). Resume play is
        // reserved for Continue Watching, where the intent is explicit.
        if let detail = URL(string: "archivewatch://item/\(e.archiveID)") {
            item.displayAction = TVTopShelfAction(url: detail)
        }
        let playPath = e.resume ? "play" : "item"
        if let play = URL(string: "archivewatch://\(playPath)/\(e.archiveID)") {
            item.playAction = TVTopShelfAction(url: play)
        }
        return item
    }

    private static func date(forYear year: Int) -> Date? {
        var c = DateComponents(); c.year = year; c.month = 1; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c)
    }
}
