#if os(iOS)
import SwiftUI

// iOS navigation state. Native idiom = a bottom tab bar (iPhone) / sidebar (iPad
// via NavigationSplitView), NOT the tvOS sidebar. One NavigationPath per tab so
// each tab keeps its own push stack. (PARITY §1: same verb, native idiom.)
@MainActor
@Observable
final class Router {
    // Settings is intentionally NOT a tab — it lives behind a cog in the Home nav
    // bar (a destination, not a peer of the content tabs). Channels IS a tab
    // (owner direction 2026-06-10: "Channels should be a top level navigation
    // and not just a pill on the home page").
    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case home, browse, channels, search, library
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Home"; case .browse: "Browse"; case .channels: "Channels"
            case .search: "Search"; case .library: "Library"
            }
        }
        var systemImage: String {
            switch self {
            case .home: "house.fill"; case .browse: "film.fill"
            case .channels: "tv.and.mediabox"
            case .search: "magnifyingglass"; case .library: "heart.fill"
            }
        }
    }

    var tab: Tab = .home
    var homePath = NavigationPath()
    var browsePath = NavigationPath()
    var channelsPath = NavigationPath()
    var searchPath = NavigationPath()
    var libraryPath = NavigationPath()

    /// Push any registered destination onto the active tab's stack.
    func push<V: Hashable>(_ value: V) {
        switch tab {
        case .home: homePath.append(value)
        case .browse: browsePath.append(value)
        case .channels: channelsPath.append(value)
        case .search: searchPath.append(value)
        case .library: libraryPath.append(value)
        }
    }

    /// Route any catalog item to Detail from whichever tab is active.
    func openDetail(_ item: Catalog.Item) { push(item) }
}

#endif
