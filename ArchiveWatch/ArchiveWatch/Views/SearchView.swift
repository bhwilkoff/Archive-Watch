import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query: String = ""
    @State private var results: [Catalog.Item] = []

    /// FTS5 search over the on-disk catalog (Decision 017) — title/cast/
    /// director, rank-ordered — instead of scanning an in-memory array.
    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let db = store.db else { results = []; return }
        results = db.search(q)
    }

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if query.trimmingCharacters(in: .whitespaces).count < 2 {
                placeholder
            } else if results.isEmpty {
                EmptyState()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                resultGrid
            }
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .searchable(text: $query, placement: .automatic, prompt: "Title, director, or actor")
        .task(id: query) { runSearch() }
        .task(id: store.dbGeneration) { runSearch() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search")
                .font(.system(size: 54, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("Over \(store.db?.itemCount ?? store.visibleItems.count) titles, cast, and crews.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 80)
        .padding(.top, 48)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.2))
            Text("Start typing to search")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var resultGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 44) {
                ForEach(results) { item in
                    CompactTile(item: item) {
                        router.push(item)
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
    }
}
