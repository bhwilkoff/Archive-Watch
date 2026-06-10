#if os(tvOS)
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
        case home, browse, tvShows, channels, cartoons, party, screensaver,
             collections, search, favorites, surprise, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home:        return "Home"
            case .browse:      return "Movies"
            case .tvShows:     return "TV Shows"
            case .channels:    return "Channels"
            case .cartoons:    return "Cartoons"
            case .party:       return "Party Play"
            case .screensaver: return "Screensaver"
            case .collections: return "Collections"
            case .search:      return "Search"
            case .favorites:   return "Library"
            case .surprise:    return "Surprise"
            case .settings:    return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .home:        return "house.fill"
            case .browse:      return "film.fill"
            case .tvShows:     return "tv.fill"
            case .channels:    return "play.tv.fill"
            case .cartoons:    return "pawprint.fill"
            case .party:       return "sparkles.tv.fill"
            case .screensaver: return "photo.stack.fill"
            case .collections: return "square.stack.3d.up.fill"
            case .search:      return "magnifyingglass"
            case .favorites:   return "books.vertical.fill"
            case .surprise:    return "dice.fill"
            case .settings:    return "gearshape.fill"
            }
        }
    }

    var tab: Tab = Router.initialTab

    // Screenshot/dev affordance: `AW_START_TAB=channels` (etc.) lands on that tab
    // at launch. Unset in production, so this is a no-op (defaults to .home).
    static var initialTab: Tab {
        if let raw = ProcessInfo.processInfo.environment["AW_START_TAB"],
           let t = Tab(rawValue: raw) { return t }
        return .home
    }

    // One NavigationPath per tab. Each tab remembers its own push
    // stack, so switching tabs and coming back restores position;
    // NavigationStack + navigationDestination handle the actual push
    // + back semantics for us.
    var homePath = NavigationPath()
    var browsePath = NavigationPath()
    var tvShowsPath = NavigationPath()
    var channelsPath = NavigationPath()
    var cartoonsPath = NavigationPath()
    var partyPath = NavigationPath()
    var screensaverPath = NavigationPath()
    var collectionsPath = NavigationPath()
    var searchPath = NavigationPath()
    var favoritesPath = NavigationPath()
    var surprisePath = NavigationPath()
    var settingsPath = NavigationPath()

    /// Push any Hashable destination onto the active tab's stack.
    /// Callers pass the concrete value (Catalog.Item, BrowseFilter)
    /// and the NavigationStack routes it via .navigationDestination(for:).
    func push<T: Hashable>(_ destination: T) {
        switch tab {
        case .home:        homePath.append(destination)
        case .browse:      browsePath.append(destination)
        case .tvShows:     tvShowsPath.append(destination)
        case .channels:    channelsPath.append(destination)
        case .cartoons:    cartoonsPath.append(destination)
        case .party:       partyPath.append(destination)
        case .screensaver: screensaverPath.append(destination)
        case .collections: collectionsPath.append(destination)
        case .search:      searchPath.append(destination)
        case .favorites:   favoritesPath.append(destination)
        case .surprise:    surprisePath.append(destination)
        case .settings:    settingsPath.append(destination)
        }
    }

    /// Pop the active tab's stack by one level.
    func pop() {
        switch tab {
        case .home:        if !homePath.isEmpty        { homePath.removeLast() }
        case .browse:      if !browsePath.isEmpty      { browsePath.removeLast() }
        case .tvShows:     if !tvShowsPath.isEmpty     { tvShowsPath.removeLast() }
        case .channels:    if !channelsPath.isEmpty    { channelsPath.removeLast() }
        case .cartoons:    if !cartoonsPath.isEmpty    { cartoonsPath.removeLast() }
        case .party:       if !partyPath.isEmpty       { partyPath.removeLast() }
        case .screensaver: if !screensaverPath.isEmpty { screensaverPath.removeLast() }
        case .collections: if !collectionsPath.isEmpty { collectionsPath.removeLast() }
        case .search:      if !searchPath.isEmpty      { searchPath.removeLast() }
        case .favorites:   if !favoritesPath.isEmpty   { favoritesPath.removeLast() }
        case .surprise:    if !surprisePath.isEmpty    { surprisePath.removeLast() }
        case .settings:    if !settingsPath.isEmpty    { settingsPath.removeLast() }
        }
    }
}

#endif
