#if os(macOS)
import SwiftUI

// Mac-native navigation model (docs/macOS-DESIGN.md §7): a sidebar SECTION selection +
// one NavigationPath for drill-in. NOT the iOS per-tab-stack Router — the Mac uses a
// single split-view detail column. A PersonRoute mirrors the iOS person-filter routing.

struct PersonRoute: Hashable { let name: String }
struct CollectionRoute: Hashable { let id: String; let title: String }

@MainActor
@Observable
final class AppRouter {
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case home, movies, tv, search, library
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Home"; case .movies: "Movies"; case .tv: "TV"
            case .search: "Search"; case .library: "Library"
            }
        }
        var systemImage: String {
            switch self {
            case .home: "house"; case .movies: "film"; case .tv: "tv"
            case .search: "magnifyingglass"; case .library: "books.vertical"
            }
        }
    }

    var section: Section = .home
    var path = NavigationPath()
    var nowPlaying: Catalog.Item?          // drives the player window/sheet

    func openDetail(_ item: Catalog.Item) { path.append(item) }
    func openPerson(_ name: String) { path.append(PersonRoute(name: name)) }
    func openCollection(_ id: String, _ title: String) { path.append(CollectionRoute(id: id, title: title)) }
    func play(_ item: Catalog.Item) { nowPlaying = item }

    func surprise(_ store: AppStore) {
        if let item = store.db?.randomPlayable() { play(item) }
    }
}
#endif
