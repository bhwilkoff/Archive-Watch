import WidgetKit
import SwiftUI

// Archive Watch widgets (art-forward redesign 2026-06-24). Home Screen + Lock
// Screen surfaces that read a small JSON snapshot the main app writes into the
// shared App Group container, with poster/backdrop art PRE-CACHED by the app into
// `widget-art/` (widgets can't reliably async-load remote images). Tapping
// deep-links into the app.
//
// Learning-orientation (CLAUDE.md): Continue Watching supports the user's own
// agency; Pick of the Day / Surprise are discovery invitations (the repertory
// wander) — every tile lands on a SPECIFIC title or the surprise route, never a
// generic "open app".

private let appGroup = "group.app.archivewatch.tvos"
private let snapshotFile = "widget-snapshot.json"
private let brand = Color(red: 1.0, green: 0.36, blue: 0.21)   // marquee orange

// MARK: - Shared snapshot model (mirror of WidgetSnapshotWriter in the app)

struct WidgetItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let artFile: String?
    let progress: Double?
}

struct WidgetSnapshot: Codable {
    var continueWatching: [WidgetItem]
    var pickOfDay: WidgetItem?
    var favorites: [WidgetItem]
    var surprisePool: [WidgetItem]
    var generatedAt: Double

    static let empty = WidgetSnapshot(continueWatching: [], pickOfDay: nil,
                                      favorites: [], surprisePool: [], generatedAt: 0)

    static func load() -> WidgetSnapshot {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let data = try? Data(contentsOf: dir.appendingPathComponent(snapshotFile)),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snap
    }
}

/// Load a pre-cached art file from the App Group as a SwiftUI Image (cross-platform).
private func awArt(_ artFile: String?) -> Image? {
    guard let artFile,
          let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    else { return nil }
    let url = dir.appendingPathComponent("widget-art").appendingPathComponent(artFile)
    #if os(macOS)
    guard let ns = NSImage(contentsOf: url) else { return nil }
    return Image(nsImage: ns)
    #else
    guard let ui = UIImage(contentsOfFile: url.path) else { return nil }
    return Image(uiImage: ui)
    #endif
}

private func deepLink(_ path: String) -> URL { URL(string: "archivewatch://\(path)")! }

// MARK: - Providers

struct SnapshotEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot }

/// One entry; the app reloads timelines when state changes (policy .never).
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load())], policy: .never))
    }
}

/// Surprise rotates a poster from the pool ~hourly so the tile feels alive.
struct SurpriseEntry: TimelineEntry { let date: Date; let item: WidgetItem? }
struct SurpriseProvider: TimelineProvider {
    func placeholder(in context: Context) -> SurpriseEntry { SurpriseEntry(date: Date(), item: nil) }
    func getSnapshot(in context: Context, completion: @escaping (SurpriseEntry) -> Void) {
        completion(SurpriseEntry(date: Date(), item: WidgetSnapshot.load().surprisePool.first))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SurpriseEntry>) -> Void) {
        let pool = WidgetSnapshot.load().surprisePool
        guard !pool.isEmpty else {
            completion(Timeline(entries: [SurpriseEntry(date: Date(), item: nil)], policy: .never)); return
        }
        let now = Date()
        let entries = (0..<min(12, pool.count)).map { i in
            SurpriseEntry(date: now.addingTimeInterval(Double(i) * 3600), item: pool[i % pool.count])
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Reusable art card

private struct PosterCard: View {
    let item: WidgetItem
    var showProgress = false
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = awArt(item.artFile) {
                img.resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [brand.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
                Text(item.title).font(.caption).bold().foregroundStyle(.white)
                    .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.caption).bold().foregroundStyle(.white).lineLimit(2)
                if let s = item.subtitle { Text(s).font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(1) }
                if showProgress, let p = item.progress {
                    ProgressView(value: p).tint(brand).scaleEffect(x: 1, y: 0.6).padding(.top, 1)
                }
            }
            .padding(8)
        }
        .clipped()
    }
}

// MARK: - Continue Watching

struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ArchiveWatchContinue", provider: SnapshotProvider()) { entry in
            ContinueWatchingView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Continue Watching")
        .description("Pick up where you left off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct ContinueWatchingView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot
    private var items: [WidgetItem] {
        snapshot.continueWatching.isEmpty ? snapshot.favorites : snapshot.continueWatching
    }

    var body: some View {
        switch family {
        case .accessoryRectangular: accessory
        case .systemSmall: small
        default: grid
        }
    }

    @ViewBuilder private var accessory: some View {
        if let first = items.first {
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text(first.title).font(.headline).lineLimit(1)
                    if let s = first.subtitle { Text(s).font(.caption2).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(deepLink("play/\(first.id)"))
        } else {
            Label("Wander the archive", systemImage: "film").font(.caption)
                .widgetURL(deepLink("surprise"))
        }
    }

    @ViewBuilder private var small: some View {
        if let first = items.first {
            Link(destination: deepLink("play/\(first.id)")) {
                PosterCard(item: first, showProgress: !snapshot.continueWatching.isEmpty)
            }
            .containerBackground(.black, for: .widget)
        } else { empty }
    }

    @ViewBuilder private var grid: some View {
        if items.isEmpty { empty } else {
            let count = family == .systemLarge ? 6 : 3
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.continueWatching.isEmpty ? "FROM YOUR FAVORITES" : "CONTINUE WATCHING")
                    .font(.caption2).bold().foregroundStyle(brand)
                HStack(spacing: 8) {
                    ForEach(items.prefix(count)) { item in
                        Link(destination: deepLink(snapshot.continueWatching.isEmpty ? "item/\(item.id)" : "play/\(item.id)")) {
                            PosterCard(item: item, showProgress: !snapshot.continueWatching.isEmpty)
                                .aspectRatio(2.0/3.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .containerBackground(.black, for: .widget)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "film.stack").font(.title2).foregroundStyle(brand)
            Text("Open Archive Watch to start watching").font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(deepLink("surprise"))
        .containerBackground(.black, for: .widget)
    }
}

// MARK: - Pick of the Day

struct PickOfDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ArchiveWatchPick", provider: SnapshotProvider()) { entry in
            PickOfDayView(item: entry.snapshot.pickOfDay)
        }
        .configurationDisplayName("Pick of the Day")
        .description("A hand-picked public-domain gem, refreshed daily.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PickOfDayView: View {
    let item: WidgetItem?
    var body: some View {
        if let item {
            ZStack(alignment: .bottomLeading) {
                (awArt(item.artFile) ?? Image(systemName: "film"))
                    .resizable().aspectRatio(contentMode: .fill)
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PICK OF THE DAY").font(.caption2).bold().foregroundStyle(brand)
                    Text(item.title).font(.headline).foregroundStyle(.white).lineLimit(2)
                    if let s = item.subtitle { Text(s).font(.caption2).foregroundStyle(.white.opacity(0.85)) }
                }
                .padding(12)
            }
            .clipped()
            .widgetURL(deepLink("item/\(item.id)"))
            .containerBackground(.black, for: .widget)
        } else {
            VStack(spacing: 6) {
                Text("PICK OF THE DAY").font(.caption2).bold().foregroundStyle(brand)
                Text("Open Archive Watch").font(.caption).foregroundStyle(.secondary)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(deepLink("surprise"))
            .containerBackground(.black, for: .widget)
        }
    }
}

// MARK: - Favorites

struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ArchiveWatchFavorites", provider: SnapshotProvider()) { entry in
            FavoritesView(items: entry.snapshot.favorites)
        }
        .configurationDisplayName("Favorites")
        .description("Jump back into the films you've saved.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FavoritesView: View {
    @Environment(\.widgetFamily) private var family
    let items: [WidgetItem]
    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "heart").font(.title2).foregroundStyle(brand)
                Text("Save films to see them here").font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(deepLink("surprise"))
            .containerBackground(.black, for: .widget)
        } else {
            let count = family == .systemSmall ? 1 : 3
            VStack(alignment: .leading, spacing: 6) {
                Text("FAVORITES").font(.caption2).bold().foregroundStyle(brand)
                HStack(spacing: 8) {
                    ForEach(items.prefix(count)) { item in
                        Link(destination: deepLink("item/\(item.id)")) {
                            PosterCard(item: item)
                                .aspectRatio(2.0/3.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .containerBackground(.black, for: .widget)
        }
    }
}

// MARK: - Surprise Me

struct SurpriseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ArchiveWatchSurprise", provider: SurpriseProvider()) { entry in
            SurpriseView(item: entry.item)
        }
        .configurationDisplayName("Surprise Me")
        .description("Tap to wander to a film you wouldn't have chosen.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct SurpriseView: View {
    @Environment(\.widgetFamily) private var family
    let item: WidgetItem?
    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "dice.fill").font(.title3)
            }
            .widgetURL(deepLink("surprise"))
        default:
            ZStack(alignment: .bottom) {
                if let img = awArt(item?.artFile) {
                    img.resizable().aspectRatio(contentMode: .fill)
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                } else {
                    LinearGradient(colors: [brand, .black], startPoint: .top, endPoint: .bottom)
                }
                VStack(spacing: 4) {
                    Image(systemName: "dice.fill").font(.title2).foregroundStyle(.white)
                    Text("Surprise Me").font(.caption).bold().foregroundStyle(.white)
                }
                .padding(.bottom, 12)
            }
            .clipped()
            .widgetURL(deepLink("surprise"))
            .containerBackground(.black, for: .widget)
        }
    }
}

// MARK: - Bundle

@main
struct ArchiveWatchWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWatchingWidget()
        PickOfDayWidget()
        FavoritesWidget()
        SurpriseWidget()
    }
}
