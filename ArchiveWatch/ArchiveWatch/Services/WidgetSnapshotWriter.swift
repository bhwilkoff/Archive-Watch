#if os(iOS) || os(macOS)
import Foundation
import WidgetKit

// Writes the JSON snapshot the WidgetKit extension reads from the shared App Group
// container, pre-caching each surfaced item's artwork (WidgetArtCache) so the
// widget renders real posters from local files. The Codable shape MUST stay in
// lockstep with WidgetSnapshot/WidgetItem in the widget target (separate module,
// so duplicated). Shared by the iOS and macOS apps.
//
// Learning-orientation (CLAUDE.md): Continue Watching supports the user's own
// agency (resume their viewing); Pick of the Day / Surprise are discovery
// invitations (the repertory wander), never an opaque "for you" feed.
enum WidgetSnapshotWriter {
    static let appGroup = "group.app.archivewatch.tvos"
    static let file = "widget-snapshot.json"

    // MARK: Codable shape (mirror of the widget's WidgetSnapshot/WidgetItem)

    struct Item: Codable {
        let id: String
        let title: String
        let subtitle: String?
        let artFile: String?
        let progress: Double?
    }
    struct Snapshot: Codable {
        var continueWatching: [Item]
        var pickOfDay: Item?
        var favorites: [Item]
        var surprisePool: [Item]
        var generatedAt: Double
    }

    /// Build + persist the widget snapshot. Fire-and-forget: art download +
    /// downsample happens off the main actor, then the JSON is written and the
    /// timelines reloaded. Callers pass resolved Catalog.Items per surface.
    static func write(continueWatching: [Catalog.Item],
                      progressByID: [String: Double],
                      pickOfDay: Catalog.Item?,
                      favorites: [Catalog.Item],
                      surprisePool: [Catalog.Item]) {
        // Plain Sendable snapshots of the inputs so the detached task is clean.
        let cw = continueWatching.prefix(6).map { Spec(from: $0, wide: false, progress: progressByID[$0.archiveID]) }
        let pick = pickOfDay.map { Spec(from: $0, wide: true) }
        let favs = favorites.prefix(8).map { Spec(from: $0, wide: false) }
        let pool = surprisePool.prefix(12).map { Spec(from: $0, wide: false) }

        Task.detached(priority: .utility) {
            func resolve(_ specs: [Spec]) async -> [Item] {
                var out: [Item] = []
                for s in specs {
                    let art = await WidgetArtCache.ensure(archiveID: s.id, remoteURL: s.art)
                    out.append(Item(id: s.id, title: s.title, subtitle: s.subtitle,
                                    artFile: art, progress: s.progress))
                }
                return out
            }
            let cwItems = await resolve(cw)
            let pickItem = pick == nil ? nil : await resolve([pick!]).first
            let favItems = await resolve(favs)
            let poolItems = await resolve(pool)

            let snap = Snapshot(continueWatching: cwItems, pickOfDay: pickItem,
                                favorites: favItems, surprisePool: poolItems,
                                generatedAt: Date().timeIntervalSince1970)

            guard let dir = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup),
                  let data = try? JSONEncoder().encode(snap) else { return }
            try? data.write(to: dir.appendingPathComponent(file), options: .atomic)

            // Drop art files no longer referenced by any surface.
            let keep = Set(([cwItems, favItems, poolItems].flatMap { $0 } + [pickItem].compactMap { $0 })
                .compactMap(\.artFile))
            WidgetArtCache.evict(keeping: keep)

            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Compute a stable "Pick of the Day" from a pool — a deterministic daily index
    /// so it's the same all day and rotates at midnight (NOT an opaque per-user
    /// model: an editorial rotation the user can predict). Returns nil for an empty
    /// pool. `dayNumber` = days since epoch in the device's calendar.
    static func pickOfDay(from pool: [Catalog.Item], dayNumber: Int) -> Catalog.Item? {
        guard !pool.isEmpty else { return nil }
        return pool[((dayNumber % pool.count) + pool.count) % pool.count]
    }

    // A minimal Sendable view of an item for the detached task.
    private struct Spec: Sendable {
        let id: String, title: String, subtitle: String?, art: String?, progress: Double?
        init(from it: Catalog.Item, wide: Bool, progress: Double? = nil) {
            id = it.archiveID
            title = it.title
            self.progress = progress
            // Continue Watching shows time remaining (timecode, not %); otherwise year · genre.
            if let p = progress, let runtime = it.runtimeSeconds, runtime > 0 {
                let mins = Int((Double(runtime) * (1 - p)) / 60.0)
                subtitle = mins > 0 ? "\(mins) min left" : "Almost done"
            } else {
                var bits: [String] = []
                if let y = it.year { bits.append(String(y)) }
                if let g = it.genres.first { bits.append(g) }
                subtitle = bits.isEmpty ? nil : bits.joined(separator: " · ")
            }
            art = wide ? (it.backdropURL ?? it.posterURL) : (it.posterURL ?? it.backdropURL)
        }
    }
}
#endif
