#if os(iOS)
import SwiftUI

// iOS navigation state. Native idiom = a bottom tab bar (iPhone) / sidebar (iPad
// via NavigationSplitView), NOT the tvOS sidebar. One NavigationPath per tab so
// each tab keeps its own push stack. (PARITY §1: same verb, native idiom.)
@MainActor
@Observable
final class Router {
    // Settings is intentionally NOT a tab — it lives behind a cog in the Home nav
    // bar (a destination, not a peer of Home/Browse/Search/Library). Four tabs
    // keeps the bar legible and reserves it for content verbs.
    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case home, browse, search, library
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Home"; case .browse: "Browse"
            case .search: "Search"; case .library: "Library"
            }
        }
        var systemImage: String {
            switch self {
            case .home: "house.fill"; case .browse: "film.fill"
            case .search: "magnifyingglass"; case .library: "heart.fill"
            }
        }
    }

    var tab: Tab = .home
    var homePath = NavigationPath()
    var browsePath = NavigationPath()
    var searchPath = NavigationPath()
    var libraryPath = NavigationPath()

    /// Push any registered destination onto the active tab's stack.
    func push<V: Hashable>(_ value: V) {
        switch tab {
        case .home: homePath.append(value)
        case .browse: browsePath.append(value)
        case .search: searchPath.append(value)
        case .library: libraryPath.append(value)
        }
    }

    /// Route any catalog item to Detail from whichever tab is active.
    func openDetail(_ item: Catalog.Item) { push(item) }
}

#endif
