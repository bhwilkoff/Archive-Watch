import SwiftUI

// Top-level navigation shell.
// Five tabs drawn as tvOS's native top tab bar — same idiom the Apple TV
// app uses. Each tab has its own NavigationStack so push navigation
// within a tab doesn't affect the others.

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: Tab = .home

    enum Tab: Hashable {
        case home, browse, collections, search, surprise
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView().commonDestinations() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            NavigationStack { BrowseView().commonDestinations() }
                .tabItem { Label("Browse", systemImage: "square.grid.3x2.fill") }
                .tag(Tab.browse)

            NavigationStack { CollectionsView().commonDestinations() }
                .tabItem { Label("Collections", systemImage: "square.stack.3d.up.fill") }
                .tag(Tab.collections)

            NavigationStack { SearchView().commonDestinations() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            NavigationStack { SurpriseView().commonDestinations() }
                .tabItem { Label("Surprise", systemImage: "dice.fill") }
                .tag(Tab.surprise)
        }
        .preferredColorScheme(.dark)
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
