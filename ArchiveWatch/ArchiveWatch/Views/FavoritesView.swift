import SwiftUI
import SwiftData

// Favorites as a first-class destination (its own sidebar tab, above
// Surprise) rather than a single-title shelf cluttering Home. Owns its
// own @Query<Favorite> so HomeView stays free of SwiftData macro
// expansion (the cross-file "Cannot find X in scope" cascade source).
//
// Layout mirrors BrowseView's grid (CompactTile + 6-column fixed grid)
// so favorites feel like the rest of the catalog, just scoped to saved
// titles. Most-recently-favorited first.

struct FavoritesView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]

    @State private var items: [Catalog.Item] = []
    @FocusState private var focusedArchiveID: String?

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    Text("Favorites")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    if !items.isEmpty {
                        Text("\(items.count) titles")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 80)
                .padding(.top, 24)

                if items.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                } else {
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 48) {
                        ForEach(items) { item in
                            CompactTile(item: item) {
                                router.push(item)
                            }
                            .focused($focusedArchiveID, equals: item.archiveID)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            items = resolveItems()
            try? await Task.sleep(for: .milliseconds(40))
            focusedArchiveID = items.first?.archiveID
        }
        // Re-resolve when the saved set changes or the DB swaps / filters flip.
        .onChange(of: favorites.map(\.archiveID)) { _, _ in items = resolveItems() }
        .onChange(of: store.dbGeneration) { _, _ in items = resolveItems() }
    }

    private func resolveItems() -> [Catalog.Item] {
        // dbItemsByIDs preserves the requested order, so favorites stay in
        // most-recently-added order.
        store.dbItemsByIDs(favorites.map(\.archiveID))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.2))
            Text("No favorites yet")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
            Text("Press and hold a title, or use the heart on its detail page, to save it here.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 700)
        }
    }
}
