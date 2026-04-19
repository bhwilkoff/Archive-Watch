import SwiftUI

// Top-level navigation shell.
// Five tabs drawn as tvOS's native top tab bar. Each tab has its own
// NavigationStack with a bound path so re-selecting the active tab
// pops back to root — the behavior users expect from every major tvOS
// app (Apple TV, Channels, UHF).

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: Tab = .home
    @State private var homePath        = NavigationPath()
    @State private var browsePath      = NavigationPath()
    @State private var collectionsPath = NavigationPath()
    @State private var searchPath      = NavigationPath()
    @State private var surprisePath    = NavigationPath()

    enum Tab: Hashable {
        case home, browse, collections, search, surprise
    }

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack(path: $homePath) { HomeView().commonDestinations() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            NavigationStack(path: $browsePath) { BrowseView().commonDestinations() }
                .tabItem { Label("Browse", systemImage: "square.grid.3x2.fill") }
                .tag(Tab.browse)

            NavigationStack(path: $collectionsPath) { CollectionsView().commonDestinations() }
                .tabItem { Label("Collections", systemImage: "square.stack.3d.up.fill") }
                .tag(Tab.collections)

            NavigationStack(path: $searchPath) { SearchView().commonDestinations() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            NavigationStack(path: $surprisePath) { SurpriseView().commonDestinations() }
                .tabItem { Label("Surprise", systemImage: "dice.fill") }
                .tag(Tab.surprise)
        }
        .preferredColorScheme(.dark)
    }

    /// Re-selecting the active tab pops that tab's navigation stack to
    /// root. Selecting a different tab just switches.
    private var tabBinding: Binding<Tab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == selection {
                    switch newValue {
                    case .home:        homePath        = NavigationPath()
                    case .browse:      browsePath      = NavigationPath()
                    case .collections: collectionsPath = NavigationPath()
                    case .search:      searchPath      = NavigationPath()
                    case .surprise:    surprisePath    = NavigationPath()
                    }
                } else {
                    selection = newValue
                }
            }
        )
    }
}

extension View {
    /// Installs navigation destinations used from multiple tabs.
    func commonDestinations() -> some View {
        self
            .navigationDestination(for: Catalog.Item.self) { item in
                DetailView(item: item)
            }
            .navigationDestination(for: BrowseFilter.self) { filter in
                BrowseView(filter: filter)
            }
    }
}
