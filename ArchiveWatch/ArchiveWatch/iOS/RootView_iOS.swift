#if os(iOS)
import SwiftUI

// Native iOS shell: a bottom TabView (iPhone). Each tab is a NavigationStack with a
// shared `navigationDestination` for Catalog.Item → Detail. Search is its own tab
// (`role: .search` on iOS 26). iPad adaptivity (NavigationSplitView) is Phase 2.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        if let error = store.loadError {
            ContentUnavailableView("Catalog unavailable", systemImage: "wifi.slash",
                                   description: Text(error))
        } else if !store.isReady {
            ProgressView("Loading the archive…")
        } else {
            TabView(selection: $router.tab) {
                Tab(Router.Tab.home.title, systemImage: Router.Tab.home.systemImage, value: Router.Tab.home) {
                    NavigationStack(path: $router.homePath) { HomeView().withItemDestination() }
                }
                Tab(Router.Tab.browse.title, systemImage: Router.Tab.browse.systemImage, value: Router.Tab.browse) {
                    NavigationStack(path: $router.browsePath) { BrowseView().withItemDestination() }
                }
                Tab(Router.Tab.search.title, systemImage: Router.Tab.search.systemImage,
                    value: Router.Tab.search, role: .search) {
                    NavigationStack(path: $router.searchPath) { SearchView().withItemDestination() }
                }
                Tab(Router.Tab.library.title, systemImage: Router.Tab.library.systemImage, value: Router.Tab.library) {
                    NavigationStack(path: $router.libraryPath) { LibraryView().withItemDestination() }
                }
                Tab(Router.Tab.settings.title, systemImage: Router.Tab.settings.systemImage, value: Router.Tab.settings) {
                    NavigationStack { SettingsView() }
                }
            }
        }
    }
}

extension View {
    /// Shared push destination so every tab opens Detail identically.
    func withItemDestination() -> some View {
        navigationDestination(for: Catalog.Item.self) { DetailView(item: $0) }
    }
}

#endif
