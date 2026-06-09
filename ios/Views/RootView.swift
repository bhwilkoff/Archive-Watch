import SwiftUI

// Native iOS shell: a bottom TabView (iPhone). Each tab is a NavigationStack with a
// shared `navigationDestination` for Catalog.Item → Detail. Search is its own tab
// (`role: .search` on iOS 26). iPad adaptivity (NavigationSplitView) is Phase 2.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        Group {
            if let error = store.loadError {
                ContentUnavailableView("Catalog unavailable", systemImage: "wifi.slash",
                                       description: Text(error))
            } else if !store.isReady {
                ProgressView("Loading the archive…")
            } else {
                TabView(selection: $router.tab) {
                    tab(.home, path: $router.homePath) { HomeView() }
                    tab(.browse, path: $router.browsePath) { BrowseView() }
                    Tab(Router.Tab.search.title, systemImage: Router.Tab.search.systemImage,
                        value: Router.Tab.search, role: .search) {
                        NavigationStack(path: $router.searchPath) {
                            SearchView().withItemDestination()
                        }
                    }
                    tab(.library, path: $router.libraryPath) { LibraryView() }
                    tab(.settings, path: .constant(NavigationPath())) { SettingsView() }
                }
            }
        }
    }

    private func tab<Content: View>(_ t: Router.Tab, path: Binding<NavigationPath>,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        Tab(t.title, systemImage: t.systemImage, value: t) {
            NavigationStack(path: path) { content().withItemDestination() }
        }
    }
}

extension View {
    /// Shared push destination so every tab opens Detail identically.
    func withItemDestination() -> some View {
        navigationDestination(for: Catalog.Item.self) { DetailView(item: $0) }
    }
}
