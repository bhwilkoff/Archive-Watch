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
    static let appGroup = "group.com.bhwilkoff.archivewatch"
    static let fileName = "topshelf.json"

    struct Payload: Decodable {
        struct Item: Decodable {
            let archiveID: String
            let title: String
            let posterURL: String?
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

        let collections = payload.sections.map { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem> in
            let items = section.items.map { entry -> TVTopShelfSectionedItem in
                let item = TVTopShelfSectionedItem(identifier: entry.archiveID)
                item.title = entry.title
                item.imageShape = .poster
                if let poster = entry.posterURL, let url = URL(string: poster) {
                    item.setImageURL(url, for: [.screenScale1x, .screenScale2x])
                }
                if let action = URL(string: "archivewatch://item/\(entry.archiveID)") {
                    item.displayAction = TVTopShelfAction(url: action)
                }
                return item
            }
            let collection = TVTopShelfItemCollection(items: items)
            collection.title = section.title
            return collection
        }

        completionHandler(TVTopShelfSectionedContent(sections: collections))
    }
}
