import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query: String = ""

    private var results: [Catalog.Item] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2, let items = store.catalog?.items else { return [] }
        return items.filter { item in
            item.title.lowercased().contains(q) ||
            (item.director?.lowercased().contains(q) ?? false) ||
            (item.producer?.lowercased().contains(q) ?? false) ||
            item.cast.contains { $0.name.lowercased().contains(q) }
        }
        .prefix(200)
        .map { $0 }
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search")
                .font(.system(size: 54, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("Over \(store.catalog?.items.count ?? 0) titles, cast, and crews.")
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
                        router.push(.item(item))
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
    }
}
