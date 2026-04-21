import SwiftUI

// Top-level shell. Uses tvOS 26's native TabView with
// .sidebarAdaptable — Apple's own adaptive sidebar. This is the only
// navigation pattern where tvOS's focus engine reliably lets you walk
// back and forth between the sidebar and the content with arrow keys.
// Every custom attempt broke that traversal in a different way.
//
// Each Tab hosts a NavigationStack bound to a path on the Router, so:
//   • Pushing a DetailView or filtered BrowseView appends to the
//     current tab's path via .navigationDestination(for:).
//   • Pressing Back on the Siri Remote pops naturally.
//   • NavigationStack preserves the underlying view's scroll + focus
//     state when popping — no custom state persistence to manage.
//   • Switching tabs and returning restores that tab's exact spot.

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house.fill", value: Router.Tab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView().attachDestinations()
                }
            }
            Tab("Movies", systemImage: "film.fill", value: Router.Tab.browse) {
                NavigationStack(path: $router.browsePath) {
                    BrowseView().attachDestinations()
                }
            }
            Tab("TV Shows", systemImage: "tv.fill", value: Router.Tab.tvShows) {
                NavigationStack(path: $router.tvShowsPath) {
                    TVShowsView().attachDestinations()
                }
            }
            Tab("Collections", systemImage: "square.stack.3d.up.fill", value: Router.Tab.collections) {
                NavigationStack(path: $router.collectionsPath) {
                    CollectionsView().attachDestinations()
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: Router.Tab.search, role: .search) {
                NavigationStack(path: $router.searchPath) {
                    SearchView().attachDestinations()
                }
            }
            Tab("Surprise", systemImage: "dice.fill", value: Router.Tab.surprise) {
                NavigationStack(path: $router.surprisePath) {
                    SurpriseView().attachDestinations()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .preferredColorScheme(.dark)
    }

    /// Sidebar tab selection always lands at that tab's root view.
    /// Three cases, all handled the same way — reset the incoming
    /// tab's NavigationPath:
    ///   • Switching tabs (old != new): clear both paths.
    ///   • Re-selecting the current tab while on a pushed view
    ///     (old == new): pop back to that tab's root — matches the
    ///     standard iOS/tvOS tab-bar convention where tapping the
    ///     current tab takes you to top.
    /// On tvOS, the TabView binding setter fires for both cases
    /// (same-value writes are not suppressed by SwiftUI here).
    private var tabSelection: Binding<Router.Tab> {
        Binding(
            get: { router.tab },
            set: { newTab in
                if newTab != router.tab {
                    resetPath(for: router.tab)
                }
                resetPath(for: newTab)
                router.tab = newTab
            }
        )
    }

    private func resetPath(for tab: Router.Tab) {
        switch tab {
        case .home:        router.homePath = NavigationPath()
        case .browse:      router.browsePath = NavigationPath()
        case .tvShows:     router.tvShowsPath = NavigationPath()
        case .collections: router.collectionsPath = NavigationPath()
        case .search:      router.searchPath = NavigationPath()
        case .surprise:    router.surprisePath = NavigationPath()
        }
    }
}

extension View {
    func attachDestinations() -> some View {
        self
            .navigationDestination(for: Catalog.Item.self) { item in
                // Only real series cards (with a seriesID populated by the
                // exporter) route to SeriesDetailView for the lazy
                // /series/{seriesID}.json fetch. Individual tv-series-
                // classified items that fell out of clustering stay on
                // the regular DetailView and play as single items.
                if item.contentType == "tv-series" && item.seriesID != nil {
                    SeriesDetailView(seriesCard: item)
                } else {
                    DetailView(item: item)
                }
            }
            .navigationDestination(for: BrowseFilter.self) { filter in
                BrowseView(filter: filter)
            }
    }
}
