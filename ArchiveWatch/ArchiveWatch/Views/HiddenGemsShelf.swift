import SwiftUI

// "Hidden Gems" — high-quality, low-popularity items with real artwork.
// The long tail of the full catalog deserves a spotlight: items that
// would otherwise never surface because popularity-sorted shelves push
// them to the bottom. Computed client-side from the pipeline's
// qualityScore + popularityScore signals.
//
// Heuristic: qualityScore ≥ 60 means the item has solid
// enrichment + verified playability; popularityScore ≤ 40 means it sits
// below the Archive traffic median. Both scores are already filtered to
// be ≥ the shipping floor (45 / 40) by the exporter — so we're looking
// inside the population that's already "good enough to ship" and
// surfacing the quiet half of it.

struct HiddenGemsShelf: View {
    @Environment(AppStore.self) private var store

    private static let qualityFloor:     Int = 60
    private static let popularityCeiling: Int = 40
    private static let maxItems:         Int = 20

    private var items: [Catalog.Item] {
        guard let catalog = store.catalog else { return [] }
        return catalog.items
            .filter { item in
                item.hasDesignedArtwork &&
                (item.qualityScore     ?? 0)   >= Self.qualityFloor &&
                (item.popularityScore  ?? 100) <= Self.popularityCeiling
            }
            .sorted { ($0.qualityScore ?? 0) > ($1.qualityScore ?? 0) }
            .prefix(Self.maxItems)
            .map { $0 }
    }

    private static let shelfDef = Featured.Shelf(
        id: "hidden-gems",
        title: "Hidden Gems",
        subtitle: "High craft, low traffic",
        category: "feature-film",
        type: "dynamic",
        items: nil, query: nil, sort: nil, limit: nil
    )

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ShelfRow(shelf: Self.shelfDef, items: items)
        }
    }
}
