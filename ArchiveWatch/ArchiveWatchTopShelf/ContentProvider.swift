import TVServices
import Foundation

// Top Shelf content provider (Decision 015 / M4; sectioned rewrite 2026-07-20).
//
// Renders the snapshot the main app writes into the shared App Group container
// as SECTIONED content — named rows of poster tiles, exactly like Apple TV's own
// "Continue Watching / Recommended" shelves and how Netflix / Plex / Infuse
// present their Top Shelf.
//
// WHY sectioned, not a carousel (the previous implementation): the full-screen
// carousel hero is shown ONLY when the app icon is in the top row AND focused,
// and it presents a SINGLE rotating title. Sectioned content is the tasteful
// default for a repertory app — it shows MANY individual movies as rows of
// posters. That is the "individual movies, not just the app icon" experience.
// (Both styles require the top row + App Group data; sectioned is the one that
// actually surfaces a browsable set of titles.)
//
// Robustness (the extension is out-of-process + memory-constrained): never
// decode/resize images here — hand the system a URL and let it load + cache.
// Return nil only when there is genuinely nothing to show (the system then
// falls back to the static Top Shelf brandasset).
//
// Self-contained on purpose: the extension can't share the app's in-memory
// state, and keeping the tiny reader here avoids cross-target file coupling.

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
            let context: String       // section name / "why shown"
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
            completionHandler(nil)      // nothing to show -> system uses the brandasset
            return
        }

        // Group into rows by the snapshot's `context` label, preserving the
        // first-seen order the app wrote them in (Continue Watching leads).
        var order: [String] = []
        var byContext: [String: [Snapshot.Payload.Item]] = [:]
        for it in payload.items {
            if byContext[it.context] == nil { order.append(it.context) }
            byContext[it.context, default: []].append(it)
        }

        let collections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = order.compactMap { ctx in
            let items = (byContext[ctx] ?? []).prefix(12).compactMap { Self.sectionedItem(from: $0) }
            guard !items.isEmpty else { return nil }
            let collection = TVTopShelfItemCollection(items: items)
            collection.title = ctx
            return collection
        }
        guard !collections.isEmpty else { completionHandler(nil); return }

        completionHandler(TVTopShelfSectionedContent(sections: collections))
    }

    private static func sectionedItem(from e: Snapshot.Payload.Item) -> TVTopShelfSectionedItem? {
        // A sectioned tile is a 2:3 POSTER. Require designed poster art; the
        // Archive first-frame thumbnail reads as broken at this size. (A resume
        // item without a poster still can't render a tile — skip it rather than
        // show a blank.)
        guard let posterString = e.posterURL, let posterURL = URL(string: posterString) else {
            return nil
        }

        let item = TVTopShelfSectionedItem(identifier: e.archiveID)
        item.title = e.year.map { "\(e.title) (\($0))" } ?? e.title
        item.imageShape = .poster
        item.setImageURL(posterURL, for: [.screenScale1x, .screenScale2x])

        // Continue Watching shows a progress bar; editorial rows don't.
        if e.resume, let p = e.progress { item.playbackProgress = p }

        // Learning guardrail (CLAUDE.md): SELECT opens Detail (a look, a choice).
        // The Play button resumes only for Continue Watching, where intent is
        // explicit; elsewhere Play also opens Detail rather than autoplaying.
        if let detail = URL(string: "archivewatch://item/\(e.archiveID)") {
            item.displayAction = TVTopShelfAction(url: detail)
        }
        let playPath = e.resume ? "play" : "item"
        if let play = URL(string: "archivewatch://\(playPath)/\(e.archiveID)") {
            item.playAction = TVTopShelfAction(url: play)
        }
        return item
    }
}
