#if os(tvOS)
import SwiftUI

// "Top Rated" — the IMDb community's favorites among everything we hold.
// The Detail view already shows each film's gold-star IMDb score; this
// shelf turns that same signal into a browsing surface (owner request
// 2026-06-12: "it should be its own shelf on the Home Screen"). A votes
// floor (1,000+) keeps tiny-sample curios from outranking the classics.

struct TopRatedShelf: View {
    @Environment(AppStore.self) private var store
    @State private var items: [Catalog.Item] = []

    private static let shelfDef = Featured.Shelf(
        id: "top-rated",
        title: "Top Rated",
        subtitle: "The crowd's verdict — IMDb favorites",
        category: "feature-film",
        type: "dynamic",
        items: nil, query: nil, sort: nil, limit: nil
    )

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                ShelfRow(shelf: Self.shelfDef, items: items)
            }
        }
        // Home shows only professional posters, never frame-extracted covers.
        .task(id: store.dbGeneration) { items = store.dbTopRated().filter { $0.hasProfessionalArtwork } }
    }
}

#endif
