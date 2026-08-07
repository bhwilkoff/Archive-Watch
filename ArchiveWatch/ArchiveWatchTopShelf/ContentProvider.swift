import TVServices
import Foundation

// Top Shelf content provider (Decision 015 / M4; tvOS-DESIGN §15).
//
// Renders SECTIONED content (§15.1) — named rows of 2:3 poster tiles, like the
// Apple TV app's own shelves and how Plex / Infuse / Jellyfin do it. Rows are
// doorways; the carousel's single rotating hero is the most passive shape we
// could pick, so it stays reserved for a genuine editorial moment.
//
// TWO SOURCES, MERGED — never either/or (§15.6):
//   • PERSONAL (Continue Watching) comes from the App Group snapshot the app
//     writes (`TopShelfSnapshot`). It leads when it exists.
//   • EDITORIAL comes from the public feed at archivewatch.org/topshelf.json,
//     which needs no App Group and populates even before the first launch.
// A previous version returned early whenever the snapshot was non-empty — and
// since the app always wrote editorial rows into it, the network feed was dead
// code for anyone who had ever launched the app, and the Top Shelf froze on
// whatever the snapshot last held.
//
// IT MUST CHANGE (§15.3). The feed publishes POOLS — ~15 named rows of ~30
// candidates each — and this provider picks which rows and which titles to show
// from a time bucket. Stable while someone is looking at it, different by the
// next sitting, with no republish needed. That selection logic lives in
// `TopShelfRotation.swift` (Foundation-only, so the harness can test it).
//
// Robustness: the extension is a separate ~16 MB process, so never decode or
// resize images here — hand the system a URL and let it load + cache. The feed
// is cached on disk, so a fresh cache paints with no network at all and a failed
// fetch degrades to yesterday's rows rather than the static app image.

private let kAppGroup = "group.app.archivewatch.tvos"
private let kSnapshotFile = "topshelf.json"
private let kFeedURL = URL(string: "https://archivewatch.org/topshelf.json")!
private let kFeedCacheFile = "topshelf-feed.json"

/// Serve the cache without touching the network while it is this fresh.
private let kCacheFreshFor: TimeInterval = 6 * 60 * 60

// MARK: - App Group snapshot (personal; written by the app)

private struct SnapshotPayload: Decodable {
    struct Item: Decodable {
        let archiveID: String
        let title: String
        let posterURL: String?
        let year: Int?
        let context: String
        let progress: Double?
        let resume: Bool
        /// "personal" | "editorial". Absent in snapshots written by older builds —
        /// those are read as personal only for the Continue Watching context.
        let kind: String?
    }
    let items: [Item]
}

/// Returns (personal rows, editorial rows). Editorial is a fallback only — the
/// live feed is preferred (§15.6).
private func readSnapshotSections() -> (personal: [Section], editorial: [Section]) {
    guard let dir = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: kAppGroup),
          let data = try? Data(contentsOf: dir.appendingPathComponent(kSnapshotFile)),
          let payload = try? JSONDecoder().decode(SnapshotPayload.self, from: data)
    else { return ([], []) }

    var order: [String] = []
    var byContext: [String: [Card]] = [:]
    var personalContexts = Set<String>()

    for it in payload.items {
        guard let p = it.posterURL, let url = URL(string: p) else { continue }
        if byContext[it.context] == nil { order.append(it.context) }
        byContext[it.context, default: []].append(
            Card(id: it.archiveID, title: it.title, year: it.year,
                 posterURL: url, resume: it.resume, progress: it.progress))
        let isPersonal = it.kind.map { $0 == "personal" }
            ?? (it.context == "Continue Watching")
        if isPersonal { personalContexts.insert(it.context) }
    }

    var personal: [Section] = []
    var editorial: [Section] = []
    for ctx in order {
        guard let cards = byContext[ctx], !cards.isEmpty else { continue }
        let section = Section(title: ctx, cards: cards)
        if personalContexts.contains(ctx) { personal.append(section) }
        else { editorial.append(section) }
    }
    return (personal, editorial)
}

// MARK: - Public network feed (editorial; rotating pools)

private func cacheURL() -> URL? {
    // Writable directories on tvOS are Caches and the App Group container only
    // (tvOS-playbook). Prefer the group so the cache survives a Caches purge and
    // is inspectable from the app.
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: kAppGroup)
        ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
}

private func readCachedFeed() -> (payload: FeedPayload, age: TimeInterval)? {
    guard let url = cacheURL()?.appendingPathComponent(kFeedCacheFile),
          let data = try? Data(contentsOf: url),
          let payload = try? JSONDecoder().decode(FeedPayload.self, from: data)
    else { return nil }
    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
    return (payload, Date().timeIntervalSince(modified))
}

private func fetchFeed(_ completion: @escaping (FeedPayload?) -> Void) {
    var req = URLRequest(url: kFeedURL)
    req.timeoutInterval = 8            // never make first paint wait on a slow network
    req.cachePolicy = .reloadRevalidatingCacheData
    URLSession.shared.dataTask(with: req) { data, _, _ in
        guard let data, let payload = try? JSONDecoder().decode(FeedPayload.self, from: data) else {
            completion(nil); return
        }
        if let url = cacheURL()?.appendingPathComponent(kFeedCacheFile) {
            try? data.write(to: url, options: .atomic)
        }
        completion(payload)
    }.resume()
}

// MARK: - Provider

class ContentProvider: TVTopShelfContentProvider {

    // Completion-handler overload (NOT the async one): the async form trips a
    // non-Sendable `TVTopShelfContent` error under Swift 6 strict concurrency.
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let snapshot = readSnapshotSections()
        let window = rotationWindow()

        func finish(_ editorial: [Section]) {
            let rows = editorial.isEmpty ? snapshot.editorial : editorial
            completionHandler(Self.content(from: dedupe(snapshot.personal + rows)))
        }

        // A fresh cache paints with zero network. Otherwise fetch, and fall back
        // to the stale cache (then to the snapshot's editorial rows) on failure.
        if let cached = readCachedFeed(), cached.age < kCacheFreshFor {
            finish(rotate(cached.payload, window: window))
            return
        }
        fetchFeed { payload in
            if let payload { finish(rotate(payload, window: window)) }
            else if let cached = readCachedFeed() { finish(rotate(cached.payload, window: window)) }
            else { finish([]) }
        }
    }

    private static func content(from sections: [Section]) -> TVTopShelfContent? {
        let collections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = sections.map {
            let c = TVTopShelfItemCollection(items: $0.cards.map(sectionedItem))
            c.title = $0.title
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

        // §15.5 — two actions, two verbs. Select opens Detail (a look, a choice,
        // never autoplay); the Play button plays, resuming where the viewer left
        // off. `archivewatch://play/{id}` was previously emitted but NOT routed by
        // IntentInbox, so Play on a Continue Watching tile did nothing at all.
        if let detail = URL(string: "archivewatch://item/\(c.id)") {
            item.displayAction = TVTopShelfAction(url: detail)
        }
        if let play = URL(string: "archivewatch://play/\(c.id)") {
            item.playAction = TVTopShelfAction(url: play)
        }
        return item
    }
}
