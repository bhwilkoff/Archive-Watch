import SwiftUI

// Search: native `.searchable` (the search-role tab hosts it). FTS5 over the same
// catalog.sqlite index the tvOS app uses; results in a poster grid.
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var results: [Catalog.Item] = []

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView("Search the archive",
                    systemImage: "magnifyingglass",
                    description: Text("Title, director, cast, genre, country, or synopsis."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(results) { item in
                            Button { router.openDetail(item) } label: { PosterTile(item: item) }
                                .buttonStyle(.plain)
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Films, shows, people…")
        .task(id: query) {
            guard query.count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(180))   // debounce
            if !Task.isCancelled { results = store.search(query) }
        }
    }
}
