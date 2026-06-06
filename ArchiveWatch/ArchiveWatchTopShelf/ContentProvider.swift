import TVServices
import Foundation

// Top Shelf content provider (Decision 015 / M4).
//
// Reads the snapshot the main app writes into the shared App Group
// container (see TopShelfSnapshot in the app target) and renders it as a
// sectioned Top Shelf shelf. Items deep-link back into the app via
// archivewatch://item/{id}.
//
// Self-contained on purpose: the extension can't share the app's
// in-memory state, and keeping the tiny reader here avoids cross-target
// file-membership coupling.

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
        }
        struct Section: Decodable {
            let title: String
            let items: [Item]
        }
        let sections: [Section]
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

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let payload = Snapshot.read(), !payload.sections.isEmpty else {
            completionHandler(nil)
            return
        }

        // #11: render a CAROUSEL (the large rotating hero at the top of the Apple
        // TV home when the app is in the top row), not sectioned shelves. Flatten
        // the snapshot sections into one deduped list and prefer items that have a
        // wide backdrop — a 2:3 poster looks wrong in the 16:9 hero.
        var seen = Set<String>()
        let unique = payload.sections.flatMap(\.items).filter { seen.insert($0.archiveID).inserted }
        let withBackdrop = unique.filter { $0.backdropURL != nil }
        let chosen = Array((withBackdrop.count >= 4 ? withBackdrop : unique).prefix(10))

        let items = chosen.map { entry -> TVTopShelfCarouselItem in
            let item = TVTopShelfCarouselItem(identifier: entry.archiveID)
            item.title = entry.title   // carousel items are 16:9 hero by default
            if let art = entry.backdropURL ?? entry.posterURL, let url = URL(string: art) {
                item.setImageURL(url, for: [.screenScale1x, .screenScale2x])
            }
            if let detail = URL(string: "archivewatch://item/\(entry.archiveID)") {
                item.displayAction = TVTopShelfAction(url: detail)
            }
            if let play = URL(string: "archivewatch://play/\(entry.archiveID)") {
                item.playAction = TVTopShelfAction(url: play)
            }
            return item
        }

        guard !items.isEmpty else { completionHandler(nil); return }
        completionHandler(TVTopShelfCarouselContent(style: .details, items: items))
    }
}
