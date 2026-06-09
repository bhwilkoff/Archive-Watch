import WidgetKit
import SwiftUI

// Home-screen widgets (iOS, Phase 1): "Continue Watching" + "Editor's Picks".
// Reads a small JSON snapshot the main app writes to the shared App Group
// container (group.com.bhwilkoff.archivewatch) — the widget never touches the
// catalog DB. Tapping deep-links into the app via archivewatch://item/{id}.

private let appGroup = "group.com.bhwilkoff.archivewatch"
private let snapshotFile = "widget-snapshot.json"

// MARK: - Shared snapshot model (the main app writes the identical shape)

struct WidgetItem: Codable, Identifiable, Hashable {
    let id: String      // archiveID
    let title: String
    let year: Int?
}

struct WidgetSnapshot: Codable {
    var continueWatching: [WidgetItem]
    var editorsPicks: [WidgetItem]

    static let empty = WidgetSnapshot(continueWatching: [], editorsPicks: [])

    static func load() -> WidgetSnapshot {
        guard let dir = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup),
              let data = try? Data(contentsOf: dir.appendingPathComponent(snapshotFile)),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snap
    }
}

// MARK: - Timeline

struct AWEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]
    let heading: String
}

struct AWProvider: TimelineProvider {
    func placeholder(in context: Context) -> AWEntry {
        AWEntry(date: Date(), items: [], heading: "Continue Watching")
    }
    func getSnapshot(in context: Context, completion: @escaping (AWEntry) -> Void) {
        completion(entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AWEntry>) -> Void) {
        // Static content; reloaded by the app via WidgetCenter when state changes.
        completion(Timeline(entries: [entry()], policy: .never))
    }
    private func entry() -> AWEntry {
        let snap = WidgetSnapshot.load()
        if !snap.continueWatching.isEmpty {
            return AWEntry(date: Date(), items: snap.continueWatching, heading: "Continue Watching")
        }
        return AWEntry(date: Date(), items: snap.editorsPicks, heading: "Editor's Picks")
    }
}

// MARK: - Views

struct AWWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AWEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    private var heading: some View {
        Text(entry.heading.uppercased())
            .font(.caption2).fontWeight(.bold)
            .foregroundStyle(.orange)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
            Spacer(minLength: 0)
            if let first = entry.items.first {
                Text(first.title).font(.headline).lineLimit(3)
                if let y = first.year { Text(verbatim: String(y)).font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("Wander the archive").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .widgetURL(URL(string: entry.items.first.map { "archivewatch://item/\($0.id)" } ?? "archivewatch://random"))
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            if entry.items.isEmpty {
                Spacer()
                Text("Open Archive Watch to start watching.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.items.prefix(3)) { item in
                    Link(destination: URL(string: "archivewatch://item/\(item.id)")!) {
                        HStack {
                            Image(systemName: "play.circle.fill").foregroundStyle(.orange)
                            Text(item.title).font(.subheadline).lineLimit(1)
                            Spacer()
                            if let y = item.year {
                                Text(verbatim: String(y)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

// MARK: - Widget + bundle

struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ArchiveWatchContinue", provider: AWProvider()) { entry in
            AWWidgetView(entry: entry)
                .containerBackground(.black.gradient, for: .widget)
        }
        .configurationDisplayName("Archive Watch")
        .description("Pick up where you left off, or jump into Editor's Picks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ArchiveWatchWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWatchingWidget()
    }
}
