import TVServices
import Foundation

// Top Shelf content provider (Decision 015 / M4; network-feed rewrite 2026-07-20).
//
// Renders SECTIONED content — named rows of poster tiles, like Apple TV's own
// "Continue Watching / Recommended" shelves and how Netflix / Plex / Infuse do
// it. This is the "individual movies, not just the app icon" experience.
//
// DATA SOURCE — why the network, not only the App Group:
// The App Groups capability was never enabled on the bundle ids in the developer
// portal, so on DEVICE the shared container is nil (verified: the tvOS
// provisioning profiles carry no `application-groups` entitlement). The app
// therefore couldn't hand the extension a snapshot, and the Top Shelf fell back
// to the static app image. (The simulator does not enforce App Group
// provisioning, which masked this.)
//
// So the extension fetches a small PUBLIC feed over the network
// (archivewatch.org/topshelf.json) — no App Group, no provisioning dependency,
// and it even populates before the user first launches the app. When the App
// Group IS provisioned, the app's local snapshot is preferred because it also
// carries personalized Continue Watching; otherwise the network feed is the
// always-present editorial backbone.
//
// Robustness (the extension is out-of-process + memory-constrained): never
// decode/resize images here — hand the system a URL and let it load + cache.
// The one network call is a few-KB JSON with a short timeout.

private let kAppGroup = "group.app.archivewatch.tvos"
private let kSnapshotFile = "topshelf.json"
private let kFeedURL = URL(string: "https://archivewatch.org/topshelf.json")!

// A row item, normalized from either source.
private struct Card {
    let id: String
    let title: String
    let year: Int?
    let posterURL: URL
    let resume: Bool
    let progress: Double?
}
private struct Section { let title: String; let cards: [Card] }

// MARK: - App Group snapshot (personalized; present only when provisioned)

private struct SnapshotPayload: Decodable {
    struct Item: Decodable {
        let archiveID: String
        let title: String
        let posterURL: String?
        let year: Int?
        let context: String
        let progress: Double?
        let resume: Bool
    }
    let items: [Item]
}

private func readSnapshotSections() -> [Section] {
    guard let dir = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: kAppGroup),
          let data = try? Data(contentsOf: dir.appendingPathComponent(kSnapshotFile)),
          let payload = try? JSONDecoder().decode(SnapshotPayload.self, from: data)
    else { return [] }

    var order: [String] = []
    var byContext: [String: [Card]] = [:]
    for it in payload.items {
        guard let p = it.posterURL, let url = URL(string: p) else { continue }
        if byContext[it.context] == nil { order.append(it.context) }
        byContext[it.context, default: []].append(
            Card(id: it.archiveID, title: it.title, year: it.year,
                 posterURL: url, resume: it.resume, progress: it.progress))
    }
    return order.compactMap { ctx in
        (byContext[ctx]?.isEmpty == false) ? Section(title: ctx, cards: byContext[ctx]!) : nil
    }
}

// MARK: - Public network feed (always present)

private struct FeedPayload: Decodable {
    struct Item: Decodable { let id: String; let title: String; let year: Int?; let poster: String }
    struct Section: Decodable { let title: String; let items: [Item] }
    let sections: [Section]
}

private func fetchFeedSections(_ completion: @escaping ([Section]) -> Void) {
    var req = URLRequest(url: kFeedURL)
    req.timeoutInterval = 12
    req.cachePolicy = .reloadRevalidatingCacheData
    URLSession.shared.dataTask(with: req) { data, _, _ in
        guard let data, let payload = try? JSONDecoder().decode(FeedPayload.self, from: data) else {
            completion([]); return
        }
        let sections: [Section] = payload.sections.compactMap { s in
            let cards = s.items.compactMap { i -> Card? in
                guard let url = URL(string: i.poster) else { return nil }
                return Card(id: i.id, title: i.title, year: i.year,
                            posterURL: url, resume: false, progress: nil)
            }
            return cards.isEmpty ? nil : Section(title: s.title, cards: cards)
        }
        completion(sections)
    }.resume()
}

// MARK: - Provider

class ContentProvider: TVTopShelfContentProvider {

    // Completion-handler overload (NOT the async one): the async form trips a
    // non-Sendable `TVTopShelfContent` error under Swift 6 strict concurrency.
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        // Prefer the app's local snapshot (has personalized Continue Watching)
        // when the App Group is provisioned; otherwise fetch the public feed.
        let local = readSnapshotSections()
        if !local.isEmpty {
            completionHandler(Self.content(from: local))
            return
        }
        fetchFeedSections { sections in
            completionHandler(sections.isEmpty ? nil : Self.content(from: sections))
        }
    }

    private static func content(from sections: [Section]) -> TVTopShelfContent? {
        let collections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = sections.compactMap { s in
            let items = s.cards.prefix(12).map { sectionedItem(from: $0) }
            guard !items.isEmpty else { return nil }
            let c = TVTopShelfItemCollection(items: items)
            c.title = s.title
            return c
        }
        guard !collections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: collections)
    }

    private static func sectionedItem(from c: Card) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: c.id)
        item.title = c.year.map { "\(c.title) (\($0))" } ?? c.title
        item.imageShape = .poster
        item.setImageURL(c.posterURL, for: [.screenScale1x, .screenScale2x])
        if c.resume, let p = c.progress { item.playbackProgress = p }

        // Learning guardrail (CLAUDE.md): SELECT opens Detail (a look, a choice);
        // Play resumes only for Continue Watching, else also opens Detail.
        if let detail = URL(string: "archivewatch://item/\(c.id)") {
            item.displayAction = TVTopShelfAction(url: detail)
        }
        let playPath = c.resume ? "play" : "item"
        if let play = URL(string: "archivewatch://\(playPath)/\(c.id)") {
            item.playAction = TVTopShelfAction(url: play)
        }
        return item
    }
}
