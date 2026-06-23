#if os(macOS)
import SwiftUI

// Search over the shared FTS5 index (store.search). .searchable renders as a toolbar
// search field on macOS — native, no rebuild needed.

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var results: [Catalog.Item] = []

    var body: some View {
        ScrollView {
            if query.isEmpty {
                ContentUnavailableView("Search the archive",
                                       systemImage: "magnifyingglass",
                                       description: Text("Films, shows, people…"))
                    .padding(.top, 80)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)],
                          spacing: 18) {
                    ForEach(results) { PosterCard(item: $0) }
                }
                .padding()
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Films, shows, people…")
        .onChange(of: query) { _, q in
            results = q.trimmingCharacters(in: .whitespaces).isEmpty ? [] : store.search(q)
        }
    }
}
#endif
