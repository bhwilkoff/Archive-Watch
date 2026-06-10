#if os(iOS)
import Foundation
import WidgetKit

// Writes the small JSON snapshot the WidgetKit extension reads from the shared
// App Group container, then asks WidgetKit to reload. The Codable shape MUST match
// WidgetSnapshot/WidgetItem in the widget target (separate module, so duplicated).
enum WidgetSnapshotWriter {
    private static let appGroup = "group.app.archivewatch.tvos"
    private static let file = "widget-snapshot.json"

    private struct Item: Codable { let id: String; let title: String; let year: Int? }
    private struct Snapshot: Codable { var continueWatching: [Item]; var editorsPicks: [Item] }

    static func write(continueWatching: [Catalog.Item], editorsPicks: [Catalog.Item]) {
        let snap = Snapshot(
            continueWatching: continueWatching.prefix(5).map { Item(id: $0.archiveID, title: $0.title, year: $0.year) },
            editorsPicks: editorsPicks.prefix(5).map { Item(id: $0.archiveID, title: $0.title, year: $0.year) }
        )
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: dir.appendingPathComponent(file))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
