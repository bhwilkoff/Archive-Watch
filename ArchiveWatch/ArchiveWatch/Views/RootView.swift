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

        TabView(selection: $router.tab) {
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
