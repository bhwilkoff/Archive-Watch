#if os(tvOS)
import SwiftUI
import SwiftData
import TVServices

// Top Shelf snapshot (Decision 015 / M4; carousel redesign 2026-06-24).
//
// The Top Shelf extension is a separate process — it can't reach the app's
// SwiftData store or in-memory catalog — so the app writes a small JSON into the
// shared App Group container and the extension reads it. The extension renders a
// best-in-class editorial CAROUSEL (TVTopShelfCarouselContent .details), so the
// snapshot carries everything a hero card shows: backdrop art, a "why it's here"
// context label, synopsis, genre, runtime, year, director + cast, captions flag,
// and a resume flag for Continue Watching.
//
// Learning-orientation guardrails (CLAUDE.md): every hero's SELECT opens Detail
// (a look, a choice) — not autoplay; only Continue Watching carries a resume
// play action where the intent is explicit. Editorial heroes lead with their
// reason ("Editor's Pick", "Public Domain Day"), the repertory-programmer voice,
// never an opaque "for you".
//
// No-ops gracefully until the App Group `group.app.archivewatch.tvos` is
// configured, so it's safe to ship ahead of the extension.

enum TopShelfSnapshot {
    static let appGroup = "group.app.archivewatch.tvos"
    static let fileName = "topshelf.json"

    struct Payload: Codable {
        struct Item: Codable {
            let archiveID: String
            let title: String
            let posterURL: String?
            let backdropURL: String?     // wide 16:9 art — preferred for the carousel hero
            let year: Int?
            let synopsis: String?
            let runtimeSeconds: Int?
            let genre: String?
            let director: String?
            let cast: [String]
            let hasCaptions: Bool
            let context: String          // "why shown": Continue Watching / Editor's Pick / …
            let progress: Double?        // 0…1, Continue Watching only (ordering)
            let resume: Bool             // Continue Watching → play action resumes
        }
        let items: [Item]
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
            // Poke tvOS to re-query the provider — without this a fresh snapshot
            // isn't picked up until the system happens to refresh on its own.
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    /// Build + write the carousel snapshot from the live catalog + watch progress.
    /// Order: Continue Watching (resume) → Editor's Picks → Popular Now. Capped at
    /// 10 heroes (Top Shelf memory budget is tight + WWDC says 5–10). `now` is
    /// passed in so callers control the timestamp.
    @MainActor
    static func rebuild(store: AppStore, progress: [WatchProgress], now: Double) {
        guard store.db != nil else { return }

        var out: [Payload.Item] = []
        var seen = Set<String>()

        func entry(_ it: Catalog.Item, context: String, resume: Bool, progress: Double?) -> Payload.Item {
            Payload.Item(
                archiveID: it.archiveID, title: it.title,
                posterURL: it.hasDesignedArtwork ? it.posterURL : nil,
                backdropURL: it.backdropURL,
                year: it.year, synopsis: it.synopsis, runtimeSeconds: it.runtimeSeconds,
                genre: it.genres.first, director: it.director,
                cast: it.cast.sorted { $0.order < $1.order }.prefix(3).map(\.name),
                hasCaptions: !(it.captions?.isEmpty ?? true),
                context: context, progress: progress, resume: resume)
        }

        // 1) Continue Watching — highest-value, most personal; lead with it. Personal
        //    enough to include even without wide art (the provider falls back to poster).
        let resuming = progress
            .filter { !$0.isComplete && $0.positionSeconds > 30 }
            .sorted { $0.lastWatchedAt > $1.lastWatchedAt }
        for p in resuming {
            guard let it = store.db?.item(p.archiveID), seen.insert(it.archiveID).inserted else { continue }
            let frac = p.durationSeconds > 0
                ? min(0.98, max(0.02, p.positionSeconds / p.durationSeconds)) : nil
            out.append(entry(it, context: "Continue Watching", resume: true, progress: frac))
            if out.count >= 4 { break }   // cap so editorial heroes get room
        }

        // 2) Editorial heroes — REQUIRE a wide backdrop (a 2:3 poster reads wrong in
        //    the 16:9 hero) and designed art. Reason-labeled, select → Detail.
        func addEditorial(_ items: [Catalog.Item], context: String) {
            for it in items where it.backdropURL != nil && it.hasDesignedArtwork {
                guard out.count < 10, seen.insert(it.archiveID).inserted else { continue }
                out.append(entry(it, context: context, resume: false, progress: nil))
            }
        }
        addEditorial(store.items(forShelf: "editor-picks"), context: "Editor's Pick")
        addEditorial(store.items(forShelf: "popular-features"), context: "Popular Now")

        guard !out.isEmpty else { return }
        write(Payload(items: Array(out.prefix(10)), generatedAt: now))
    }
}

// Invisible helper that keeps the snapshot current. Embed once in the view tree
// (RootView); it owns the WatchProgress @Query so the snapshot refreshes whenever
// progress changes, and rebuilds when the catalog finishes loading.
struct TopShelfUpdater: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: store.dbGeneration) { rebuild() }
            .onChange(of: progress.count) { _, _ in rebuild() }
    }

    private func rebuild() {
        TopShelfSnapshot.rebuild(store: store, progress: progress,
                                 now: Date().timeIntervalSince1970)
    }
}

#endif
