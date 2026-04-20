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
            Tab("Browse", systemImage: "square.grid.3x2.fill", value: Router.Tab.browse) {
                NavigationStack(path: $router.browsePath) {
                    BrowseView().attachDestinations()
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

    /// Intercept sidebar tab selection so switching tabs also clears
    /// the departing tab's navigation stack. That way returning to a
    /// tab via the sidebar always lands on its root view — never
    /// stranded on a previously-opened DetailView. The user expects
    /// the sidebar to feel like top-level navigation; keeping push
    /// state across sidebar hops violates that.
    private var tabSelection: Binding<Router.Tab> {
        Binding(
            get: { router.tab },
            set: { newTab in
                let oldTab = router.tab
                if newTab != oldTab {
                    resetPath(for: oldTab)
                }
                router.tab = newTab
            }
        )
    }

    private func resetPath(for tab: Router.Tab) {
        switch tab {
        case .home:        router.homePath = NavigationPath()
        case .browse:      router.browsePath = NavigationPath()
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
                DetailView(item: item)
            }
            .navigationDestination(for: BrowseFilter.self) { filter in
                BrowseView(filter: filter)
            }
    }
}
