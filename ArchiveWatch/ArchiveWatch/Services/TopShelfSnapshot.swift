import SwiftUI
import SwiftData

// Top Shelf snapshot (Decision 015 / M4).
//
// The Top Shelf extension can't reach the app's SwiftData store or the
// in-memory catalog, so the app writes a small JSON into the shared App
// Group container and the extension reads it. Everything here no-ops
// gracefully until the App Group `group.com.bhwilkoff.archivewatch` is
// configured on the target (see docs/top-shelf-setup.md), so it's safe to
// ship ahead of the extension target.

enum TopShelfSnapshot {
    static let appGroup = "group.com.bhwilkoff.archivewatch"
    static let fileName = "topshelf.json"

    struct Payload: Codable {
        struct Item: Codable {
            let archiveID: String
            let title: String
            let posterURL: String?
            let year: Int?
        }
        struct Section: Codable {
            let title: String
            let items: [Item]
        }
        let sections: [Section]
        let generatedAt: Double
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func write(_ payload: Payload) {
        guard let dir = containerURL else { return }   // App Group not set up yet
        let url = dir.appendingPathComponent(fileName)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func read() -> Payload? {
        guard let dir = containerURL else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Build + write a snapshot from the live catalog + watch progress.
    /// Sections: Continue Watching, Editor's Picks, What's New. Capped at
    /// ~10 each (Top Shelf has tight memory limits). `now` is passed in so
    /// callers control the timestamp.
    @MainActor
    static func rebuild(store: AppStore, progress: [WatchProgress], now: Double) {
        let items = store.visibleItems
        guard !items.isEmpty else { return }
        let byID = Dictionary(items.map { ($0.archiveID, $0) }, uniquingKeysWith: { a, _ in a })

        func map(_ list: [Catalog.Item]) -> [Payload.Item] {
            list.prefix(10).map {
                Payload.Item(archiveID: $0.archiveID, title: $0.title,
                             posterURL: $0.hasDesignedArtwork ? $0.posterURL : nil,
                             year: $0.year)
            }
        }

        var sections: [Payload.Section] = []

        let continueItems = progress
            .filter { !$0.isComplete && $0.positionSeconds > 10 }
            .sorted { $0.lastWatchedAt > $1.lastWatchedAt }
            .compactMap { byID[$0.archiveID] }
        if !continueItems.isEmpty {
            sections.append(.init(title: "Continue Watching", items: map(continueItems)))
        }

        let picks = store.items(forShelf: "editor-picks").filter { $0.hasDesignedArtwork }
        if !picks.isEmpty {
            sections.append(.init(title: "Editor's Picks", items: map(picks)))
        }

        let popular = store.items(forShelf: "popular-features").filter { $0.hasDesignedArtwork }
        if !popular.isEmpty {
            sections.append(.init(title: "Popular Now", items: map(popular)))
        }

        guard !sections.isEmpty else { return }
        write(Payload(sections: sections, generatedAt: now))
    }
}

// Invisible helper that keeps the snapshot current. Embed once in the
// view tree (RootView); it owns the WatchProgress @Query so the snapshot
// refreshes whenever progress changes, and rebuilds when the catalog
// finishes loading.
struct TopShelfUpdater: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: store.catalog?.items.count ?? 0) { rebuild() }
            .onChange(of: progress.count) { _, _ in rebuild() }
    }

    private func rebuild() {
        TopShelfSnapshot.rebuild(store: store, progress: progress,
                                 now: Date().timeIntervalSince1970)
    }
}
