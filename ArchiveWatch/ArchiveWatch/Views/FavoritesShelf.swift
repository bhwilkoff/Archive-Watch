import SwiftUI
import SwiftData

// "Your Favorites" shelf — appears on Home only when the user has
// marked at least one favorite. Owns its own @Query so HomeView
// doesn't need SwiftData, which keeps HomeView.swift free of macro
// expansion (the source of the flaky cross-file "Cannot find X in
// scope" cascades in Xcode's editor index).

struct FavoritesShelf: View {
    @Environment(AppStore.self) private var store
    @Query private var favorites: [Favorite]

    private var items: [Catalog.Item] {
        guard let catalog = store.catalog else { return [] }
        let ids = Set(favorites.map(\.archiveID))
        return catalog.items.filter { ids.contains($0.archiveID) }
    }

    private static let favShelf = Featured.Shelf(
        id: "favorites",
        title: "Your Favorites",
        subtitle: "Saved for later",
        category: "feature-film",
        type: "curated",
        items: nil, query: nil, sort: nil, limit: nil
    )

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ShelfRow(shelf: Self.favShelf, items: items)
        }
    }
}
