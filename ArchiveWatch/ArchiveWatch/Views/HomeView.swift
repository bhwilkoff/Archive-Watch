import SwiftUI
import SwiftData

// Home screen composition. Individual component views live in their
// own files (HeroCarousel, ContinueWatching, ShelfRow, PosterTile,
// CategoryRow, DecadeRow) so SourceKit has less cross-file surface
// to re-resolve on each edit here.

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progressRecords: [WatchProgress]
    @Query private var favorites: [Favorite]

    // Random seed set when HomeView first appears. Stable across the
    // view's lifetime so the hero rotation doesn't reshuffle on every
    // @Query-driven re-render, but re-rolls when the user leaves Home
    // and comes back — an invitation to keep wandering.
    @State private var heroSeed: Int = Int.random(in: 0..<1_000_000)

    private var continueWatching: [(item: Catalog.Item, progress: WatchProgress)] {
        guard let catalog = store.catalog else { return [] }
        let items = Dictionary(uniqueKeysWithValues: catalog.items.map { ($0.archiveID, $0) })
        return progressRecords
            .filter { !$0.isComplete && $0.positionSeconds > 10 }
            .prefix(12)
            .compactMap { record -> (Catalog.Item, WatchProgress)? in
                guard let item = items[record.archiveID] else { return nil }
                return (item, record)
            }
    }

    private var favoriteItems: [Catalog.Item] {
        guard let catalog = store.catalog else { return [] }
        let ids = Set(favorites.map(\.archiveID))
        return catalog.items.filter { ids.contains($0.archiveID) }
    }

    // Hero carousel — 7 titles freshly sampled on each Home appearance
    // from the top-150 pool by shelf count. Stable within a session,
    // re-rolls on tab return.
    private var heroItems: [Catalog.Item] {
        guard let all = store.catalog?.items else { return [] }
        let pool = all.filter {
            $0.hasDesignedArtwork &&
            ($0.backdropURLParsed != nil || $0.posterURLParsed != nil)
        }
        let stratum = pool.sorted { $0.shelves.count > $1.shelves.count }.prefix(150)
        var rng = SplitMix(seed: UInt64(heroSeed))
        return Array(stratum.shuffled(using: &rng).prefix(7))
    }

    private var homeShelves: [Featured.Shelf] {
        let priority: [String] = [
            "popular-features", "wikidata-pd", "film-noir", "scifi-horror",
            "silent-hall-of-fame", "melies", "video-cellar", "comedy",
            "animation-all", "vintage-cartoons", "nasa", "classic-tv-1960s",
            "classic-tv-1950s", "classic-tv-1970s", "ephemera", "educational",
            "picfixer", "german-cinema", "silent-era", "popular-classic-tv",
            "all-time-features"
        ]
        let allShelves = store.featured?.shelves ?? []
        return priority.compactMap { id in allShelves.first(where: { $0.id == id }) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 48) {
                if !heroItems.isEmpty {
                    HeroCarousel(items: heroItems)
                }
                if !continueWatching.isEmpty {
                    ContinueWatchingRow(entries: continueWatching)
                }
                CategoryTilesRow()
                if !favoriteItems.isEmpty {
                    let favShelf = Featured.Shelf(
                        id: "favorites",
                        title: "Your Favorites",
                        subtitle: "Saved for later",
                        category: "feature-film",
                        type: "curated",
                        items: nil, query: nil, sort: nil, limit: nil
                    )
                    ShelfRow(shelf: favShelf, items: favoriteItems)
                }
                ForEach(homeShelves) { shelf in
                    let rawItems = store.items(forShelf: shelf.id)
                    let items = sortByArtwork(rawItems)
                    if !items.isEmpty {
                        ShelfRow(shelf: shelf, items: Array(items.prefix(20)))
                    }
                }
                DecadeTilesRow()
                    .padding(.bottom, 32)
            }
            .padding(.bottom, 80)
        }
        .background(Color.black.ignoresSafeArea())
    }

    /// Stable sort that puts items with designed art before procedural
    /// items, preserving the underlying order within each bucket.
    private func sortByArtwork(_ items: [Catalog.Item]) -> [Catalog.Item] {
        let withArt    = items.filter { $0.hasDesignedArtwork }
        let withoutArt = items.filter { !$0.hasDesignedArtwork }
        return withArt + withoutArt
    }
}
