#if os(iOS)
import SwiftUI

// iOS navigation state. Native idiom = a bottom tab bar (iPhone) / sidebar (iPad,
// the same sidebarAdaptable TabView). One NavigationPath per tab so
// each tab keeps its own push stack. (PARITY §1: same verb, native idiom.)
@MainActor
@Observable
final class Router {
    // Settings is not a TAB-BAR tab — on the phone it lives behind a cog in the
    // Home nav bar; the iPad sidebar lists it as a place (IPAD-DESIGN §10). Channels IS a tab
    // (owner direction 2026-06-10: "Channels should be a top level navigation
    // and not just a pill on the home page").
    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case home, browse, channels, search, library
        // Sidebar-only places (IPAD-DESIGN §10): hidden from the phone's tab
        // bar, where Browse's scope control, Library's list and Home's
        // toolbar buttons reach the same destinations.
        case films, tv, collections
        case downloads, favorites, history, playlists, clips
        case surprise, together, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Home"; case .browse: "Browse"; case .channels: "Channels"
            case .search: "Search"; case .library: "Library"
            case .films: "Films"; case .tv: "TV"; case .collections: "Collections"
            case .downloads: "Downloads"; case .favorites: "Favorites"
            case .history: "History"; case .playlists: "Playlists"; case .clips: "Clips"
            case .surprise: "Surprise"; case .together: "Watch Together"
            case .settings: "Settings"
            }
        }
        var systemImage: String {
            switch self {
            case .home: "house.fill"; case .browse: "film.fill"
            case .channels: "tv.and.mediabox"
            case .search: "magnifyingglass"; case .library: "heart.fill"
            case .films: "film"; case .tv: "tv"; case .collections: "square.stack.3d.up"
            case .downloads: "arrow.down.circle"; case .favorites: "heart"
            case .history: "clock.arrow.circlepath"; case .playlists: "rectangle.stack"
            case .clips: "scissors"
            case .surprise: "shuffle"; case .together: "person.2.wave.2"
            case .settings: "gearshape"
            }
        }
    }

    var tab: Tab = .home
    /// Settings is a sheet over Home (the gear; the menu bar's ⌘,), not a place.
    var showSettings = false
    /// "Play a Surprise Film" (Go menu): the film page plays this id when it
    /// opens, once, then clears it (the tvOS router's same field).
    var autoplayItemID: String?
    var homePath = NavigationPath()
    var browsePath = NavigationPath()
    var channelsPath = NavigationPath()
    var searchPath = NavigationPath()
    var libraryPath = NavigationPath()

    /// The sidebar-only places' stacks, one per place.
    var sidePaths: [Tab: NavigationPath] = [:]
    func path(for tab: Tab) -> Binding<NavigationPath> {
        Binding(get: { self.sidePaths[tab] ?? NavigationPath() },
                set: { self.sidePaths[tab] = $0 })
    }

    /// Push any registered destination onto the active tab's stack.
    func push<V: Hashable>(_ value: V) {
        switch tab {
        case .home: homePath.append(value)
        case .browse: browsePath.append(value)
        case .channels: channelsPath.append(value)
        case .search: searchPath.append(value)
        case .library: libraryPath.append(value)
        default: sidePaths[tab, default: NavigationPath()].append(value)
        }
    }

    /// Route any catalog item to Detail from whichever tab is active.
    func openDetail(_ item: Catalog.Item) { push(item) }

    /// True when the active tab shows its root (nothing to go Back to).
    var activeTabAtRoot: Bool {
        switch tab {
        case .home: homePath.isEmpty
        case .browse: browsePath.isEmpty
        case .channels: channelsPath.isEmpty
        case .search: searchPath.isEmpty
        case .library: libraryPath.isEmpty
        default: sidePaths[tab]?.isEmpty ?? true
        }
    }

    /// Back, for the menu bar's ⌘[ (IPAD-DESIGN §8.1).
    func popActiveTab() {
        guard !activeTabAtRoot else { return }
        switch tab {
        case .home: homePath.removeLast()
        case .browse: browsePath.removeLast()
        case .channels: channelsPath.removeLast()
        case .search: searchPath.removeLast()
        case .library: libraryPath.removeLast()
        default: sidePaths[tab]?.removeLast()
        }
    }
}

#endif
