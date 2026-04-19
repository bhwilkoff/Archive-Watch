import Foundation
import Observation

// Central navigation state for the app.
//
// Replaces the old TabView + NavigationStack approach. The reason: on
// tvOS, NavigationStack's pushed content is a sealed focus realm — you
// cannot arrow-navigate back out of it to the tab bar. With a sidebar
// architecture and state-driven view swapping, every focusable element
// sits in one continuous focus realm, so arrow keys traverse the whole
// app and the Back button is the only thing that actually goes back.

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

    enum Destination: Hashable {
        case item(Catalog.Item)
        case filter(BrowseFilter)
        case audit   // UI Audit validator (long-press sidebar brand to open)
    }

    var tab: Tab = .home
    var stack: [Destination] = []

    var isAtRoot: Bool { stack.isEmpty }

    func select(_ tab: Tab) {
        // Re-selecting the current tab pops to its root. Selecting a
        // different tab also clears the stack — switching tabs should
        // always land at that tab's root, never inside a deep detail.
        self.tab = tab
        stack.removeAll()
    }

    func push(_ destination: Destination) {
        stack.append(destination)
    }

    func pop() {
        if !stack.isEmpty { stack.removeLast() }
    }
}
