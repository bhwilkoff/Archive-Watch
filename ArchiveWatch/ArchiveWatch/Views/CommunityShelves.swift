#if os(tvOS)
import SwiftUI

// Community shelves (archive.org usage signals, tools/harvest_community_signals.py):
// what people are watching, favoriting, and discussing — the "show the community
// already on archive.org" surface. Each mirrors TopRatedShelf: vote-floored to
// recognized films (CatalogDB), professional art only, hidden when empty.

private func communityShelfDef(_ id: String, _ title: String, _ subtitle: String) -> Featured.Shelf {
    Featured.Shelf(id: id, title: title, subtitle: subtitle, category: "feature-film",
                   type: "dynamic", items: nil, query: nil, sort: nil, limit: nil)
}

struct WatchingNowShelf: View {
    @Environment(AppStore.self) private var store
    @State private var items: [Catalog.Item] = []
    private static let def = communityShelfDef(
        "watching-now", "Watching Now", "Most-viewed on archive.org this month")
    var body: some View {
        Group { items.isEmpty ? AnyView(EmptyView()) : AnyView(ShelfRow(shelf: Self.def, items: items)) }
            .task(id: store.dbGeneration) { items = store.dbWatchingNow().filter { $0.hasProfessionalArtwork } }
    }
}

struct CommunityFavoritesShelf: View {
    @Environment(AppStore.self) private var store
    @State private var items: [Catalog.Item] = []
    private static let def = communityShelfDef(
        "community-favorites", "Community Favorites", "Most-favorited by archive.org viewers")
    var body: some View {
        Group { items.isEmpty ? AnyView(EmptyView()) : AnyView(ShelfRow(shelf: Self.def, items: items)) }
            .task(id: store.dbGeneration) { items = store.dbCommunityFavorites().filter { $0.hasProfessionalArtwork } }
    }
}

struct MostDiscussedShelf: View {
    @Environment(AppStore.self) private var store
    @State private var items: [Catalog.Item] = []
    private static let def = communityShelfDef(
        "most-discussed", "Most Discussed", "The films people are talking about")
    var body: some View {
        Group { items.isEmpty ? AnyView(EmptyView()) : AnyView(ShelfRow(shelf: Self.def, items: items)) }
            .task(id: store.dbGeneration) { items = store.dbMostDiscussed().filter { $0.hasProfessionalArtwork } }
    }
}

#endif
