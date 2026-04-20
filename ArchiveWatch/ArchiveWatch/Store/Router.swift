import Foundation
import Observation
import SwiftUI

// Navigation state for Archive Watch.
//
// Rebuilt on the tvOS 26 native pattern: TabView + .sidebarAdaptable +
// one NavigationStack per tab. This gives us Apple's own sidebar, free
// back-button restoration, and state preservation when popping — the
// things a custom HStack + conditional ContentArea kept getting wrong.

@MainActor
@Observable
final class Router {

    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case home, browse, collections, search, surprise
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home:        return "Home"
            case .browse:      return "Browse"
            case .collections: return "Collections"
            case .search:      return "Search"
            case .surprise:    return "Surprise"
            }
        }

        var icon: String {
            switch self {
            case .home:        return "house.fill"
            case .browse:      return "square.grid.3x2.fill"
            case .collections: return "square.stack.3d.up.fill"
            case .search:      return "magnifyingglass"
            case .surprise:    return "dice.fill"
            }
        }
    }

    var tab: Tab = .home

    // One NavigationPath per tab. Each tab remembers its own push
    // stack, so switching tabs and coming back restores position;
    // NavigationStack + navigationDestination handle the actual push
    // + back semantics for us.
    var homePath = NavigationPath()
    var browsePath = NavigationPath()
    var collectionsPath = NavigationPath()
    var searchPath = NavigationPath()
    var surprisePath = NavigationPath()

    /// Push any Hashable destination onto the active tab's stack.
    /// Callers pass the concrete value (Catalog.Item, BrowseFilter)
    /// and the NavigationStack routes it via .navigationDestination(for:).
    func push<T: Hashable>(_ destination: T) {
        switch tab {
        case .home:        homePath.append(destination)
        case .browse:      browsePath.append(destination)
        case .collections: collectionsPath.append(destination)
        case .search:      searchPath.append(destination)
        case .surprise:    surprisePath.append(destination)
        }
    }

    /// Pop the active tab's stack by one level.
    func pop() {
        switch tab {
        case .home:        if !homePath.isEmpty        { homePath.removeLast() }
        case .browse:      if !browsePath.isEmpty      { browsePath.removeLast() }
        case .collections: if !collectionsPath.isEmpty { collectionsPath.removeLast() }
        case .search:      if !searchPath.isEmpty      { searchPath.removeLast() }
        case .surprise:    if !surprisePath.isEmpty    { surprisePath.removeLast() }
        }
    }
}
