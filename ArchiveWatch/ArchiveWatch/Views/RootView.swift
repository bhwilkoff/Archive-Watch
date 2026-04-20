import SwiftUI

// Top-level shell on tvOS 26. Uses the native TabView +
// .tabViewStyle(.sidebarAdaptable) pattern, which renders Apple's own
// adaptive sidebar. Each tab hosts a NavigationStack bound to a path
// stored on the Router, so:
//
//   • Pushing a DetailView / filtered BrowseView appends to the
//     current tab's path via .navigationDestination(for:).
//   • Pressing Back on the Siri Remote pops naturally.
//   • The previous view's scroll position and focus are preserved by
//     NavigationStack's own lifecycle — no custom state to manage.
//   • Switching tabs and coming back restores that tab's exact spot.

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

// Each NavigationStack root attaches the same set of destinations.
// This keeps push call sites simple: router.push(item) or
// router.push(filter) just appends; the destination wiring lives here.

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
