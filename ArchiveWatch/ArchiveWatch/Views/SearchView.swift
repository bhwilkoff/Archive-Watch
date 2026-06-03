import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query: String = ""
    @State private var results: [Catalog.Item] = []

    /// FTS5 search over the on-disk catalog (Decision 017) — title, cast, crew,
    /// genre, series, and synopsis (the FTS `extra` column), rank-ordered.
    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let db = store.db else { results = []; return }
        results = db.search(q)
    }

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // A leading + top inset so the search field and results clear the
            // floating sidebar's safe area, the same way every other tab insets
            // its content. The system .searchable field otherwise renders to the
            // very top-left, tucking under the sidebar.
            VStack(alignment: .leading, spacing: 24) {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    placeholder
                } else if results.isEmpty {
                    EmptyState()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    resultGrid
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 40)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .searchable(text: $query, placement: .automatic,
                    prompt: "Search by title, director, actor, or genre")
        .task(id: query) { runSearch() }
        .task(id: store.dbGeneration) { runSearch() }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.2))
            Text("Start typing to search")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
            Text("Searching \(store.dbSearchableCount) titles by name, cast, crew, genre, country, and synopsis.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var resultGrid: some View {
        LazyVGrid(columns: cols, alignment: .leading, spacing: 44) {
            ForEach(results) { item in
                CompactTile(item: item) {
                    router.push(item)
                }
            }
        }
    }
}
