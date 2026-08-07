#if os(tvOS)
import SwiftUI
import SwiftData
import TVServices

// Top Shelf snapshot (Decision 015 / M4; tvOS-DESIGN §15).
//
// The Top Shelf extension is a separate process — it can't reach the app's
// SwiftData store or in-memory catalog — so the app writes a small JSON into the
// shared App Group container and the extension reads it.
//
// This snapshot carries the PERSONAL half of the shelf: Continue Watching, the
// one row only the app can know (§15.4, §15.6). The editorial rows come from the
// published feed the extension fetches directly, so they stay fresh without the
// app running; the editorial rows written here are its offline fallback. Some
// fields (backdrop, synopsis, cast) are richer than the poster tiles need — they
// are kept so a future carousel moment doesn't need a schema change.
//
// Learning-orientation guardrails (CLAUDE.md): SELECT opens Detail (a look, a
// choice) — never autoplay; the Play button plays, resuming where the viewer left
// off. Rows lead with their reason ("Continue Watching", "Editor's Picks"), the
// repertory-programmer voice, never an opaque "for you".
//
// No-ops gracefully if the App Group `group.app.archivewatch.tvos` container is
// unavailable — the extension still has the network feed.

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
            // "personal" | "editorial" (tvOS-DESIGN §15.6). The extension always
            // shows personal rows and prefers the LIVE feed over these editorial
            // ones, falling back to them only when the network and its cache are
            // both unavailable. Optional so a snapshot written by an older build
            // still decodes.
            let kind: String?
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

    /// Build + write the SECTIONED snapshot from the live catalog + watch progress.
    /// Rows: Continue Watching (resume) → Editor's Picks → Top Rated. Each tile is
    /// a 2:3 POSTER, so items only need designed poster art (a wide backdrop is
    /// NOT required — that was the old carousel's constraint and it starved the
    /// snapshot: only ~23% of popular films have a backdrop). `now` is passed in
    /// so callers control the timestamp.
    ///
    /// A previous version read a non-existent shelf id ("editor-picks" vs the
    /// real "editors-picks") and required backdrops, so for a user with no watch
    /// history the whole snapshot could come out empty — nothing was written and
    /// the Top Shelf showed only the app icon. Top Rated is included last as an
    /// always-populated backstop (24 designed-art classics), so the Top Shelf is
    /// never empty for any user.
    @MainActor
    static func rebuild(store: AppStore, progress: [WatchProgress], now: Double) {
        guard store.db != nil else { return }

        var out: [Payload.Item] = []
        var seen = Set<String>()

        func entry(_ it: Catalog.Item, context: String, resume: Bool,
                   progress: Double?, kind: String) -> Payload.Item {
            Payload.Item(
                archiveID: it.archiveID, title: it.title,
                posterURL: it.hasDesignedArtwork ? it.posterURL : nil,
                backdropURL: it.backdropURL,
                year: it.year, synopsis: it.synopsis, runtimeSeconds: it.runtimeSeconds,
                genre: it.genres.first, director: it.director,
                cast: it.cast.sorted { $0.order < $1.order }.prefix(3).map(\.name),
                hasCaptions: !(it.captions?.isEmpty ?? true),
                context: context, progress: progress, resume: resume, kind: kind)
        }

        // A tile needs a real designed poster — the Archive first-frame thumbnail
        // reads as broken at Top Shelf size.
        func hasPoster(_ it: Catalog.Item) -> Bool {
            it.hasDesignedArtwork && (it.posterURL?.isEmpty == false)
        }

        // 1) Continue Watching — most personal; lead with it.
        let resuming = progress
            .filter { !$0.isComplete && $0.positionSeconds > 30 }
            .sorted { $0.lastWatchedAt > $1.lastWatchedAt }
        for p in resuming {
            guard let it = store.db?.item(p.archiveID),
                  hasPoster(it), seen.insert(it.archiveID).inserted else { continue }
            let frac = p.durationSeconds > 0
                ? min(0.98, max(0.02, p.positionSeconds / p.durationSeconds)) : nil
            out.append(entry(it, context: "Continue Watching", resume: true,
                             progress: frac, kind: "personal"))
            if out.filter({ $0.context == "Continue Watching" }).count >= 8 { break }
        }

        // 2..n) Editorial rows — designed poster required, reason-labeled, select
        //       → Detail. Each capped so the rows stay tight (WWDC: 5–10 each).
        func addRow(_ items: [Catalog.Item], context: String, limit: Int = 8) {
            var n = 0
            for it in items where hasPoster(it) {
                guard seen.insert(it.archiveID).inserted else { continue }
                out.append(entry(it, context: context, resume: false,
                                 progress: nil, kind: "editorial"))
                n += 1
                if n >= limit { break }
            }
        }
        addRow(store.items(forShelf: "editors-picks"), context: "Editor's Picks")
        // Always-populated backstop so the Top Shelf is never empty.
        addRow(store.dbTopRated(), context: "Top Rated")

        guard !out.isEmpty else { return }
        write(Payload(items: out, generatedAt: now))
    }
}

// Invisible helper that keeps the snapshot current. Embed once in the view tree
// (RootView); it owns the WatchProgress @Query so the snapshot refreshes whenever
// progress changes, and rebuilds when the catalog finishes loading.
struct TopShelfUpdater: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: store.dbGeneration) { rebuild() }
            .onChange(of: signature) { _, _ in rebuild() }
            // Leaving the app is the moment the Top Shelf is about to be seen —
            // and the moment the last position write has landed.
            .onChange(of: scenePhase) { _, phase in if phase != .active { rebuild() } }
    }

    /// What the Continue Watching row actually depends on.
    ///
    /// This used to key on `progress.count`, which changes only when a title is
    /// added to the set. Watching more of a film you had already started does not
    /// change the count, and neither does finishing one — so the snapshot froze at
    /// whatever it held the first time a title was tracked: resume positions went
    /// stale and completed films never left the shelf. Position is bucketed to the
    /// minute so a playing film rewrites the snapshot at most once a minute rather
    /// than on every periodic time observer tick.
    private var signature: String {
        progress
            .filter { !$0.isComplete && $0.positionSeconds > 30 }
            .prefix(8)
            .map { "\($0.archiveID):\(Int($0.positionSeconds / 60))" }
            .joined(separator: ",")
    }

    private func rebuild() {
        TopShelfSnapshot.rebuild(store: store, progress: progress,
                                 now: Date().timeIntervalSince1970)
    }
}

#endif
