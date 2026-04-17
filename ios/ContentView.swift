import SwiftUI

// MARK: - Root View

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack(path: Bindable(store).navigationPath) {
            // Main app layout — sidebar + detail
            ZStack(alignment: .leading) {
                DetailView()
                // Sidebar overlay (slide-in on mobile, always visible on iPad)
                // SidebarView()
            }
            .navigationDestination(for: String.self) { destination in
                // FILL IN: your navigation destinations
                Text(destination)
            }
        }
    }
}

// MARK: - Detail View (main content area)

struct DetailView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            // FILL IN: switch on store.selectedTab to show different views
            Text("Home View")
        }
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
