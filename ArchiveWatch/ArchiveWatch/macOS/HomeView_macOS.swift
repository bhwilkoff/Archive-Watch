#if os(macOS)
import SwiftUI
import SwiftData

// Home = curated shelves over the shared CatalogDB queries (same shelves the other
// platforms show). Re-queries when the full DB swaps in (store.dbVersion).

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query private var progress: [WatchProgress]
    @Query(sort: \Favorite.addedAt, order: .reverse) private var savedFavorites: [Favorite]
    @State private var topRated: [Catalog.Item] = []
    @State private var gems: [Catalog.Item] = []
    @State private var watching: [Catalog.Item] = []
    @State private var discussed: [Catalog.Item] = []
    @State private var favorites: [Catalog.Item] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let hero = topRated.first { HeroBanner(item: hero) }
                ShelfRow(title: "Top Rated", items: topRated, accent: .orange)
                ShelfRow(title: "Watching Now", items: watching)
                ShelfRow(title: "Hidden Gems", items: gems)
                ShelfRow(title: "Community Favorites", items: favorites)
                ShelfRow(title: "Most Discussed", items: discussed)
            }
            .padding(24)
        }
        .navigationTitle("Home")
        .task(id: store.dbVersion) { reload() }
        .onChange(of: store.hideWatchedOnHome) { reload() }
    }

    private func reload() {
        // Feed the store's completed set so hideWatchedOnHome actually filters the
        // shelves (the Settings toggle was a no-op until this was wired — parity
        // with HomeView_iOS).
        store.completedArchiveIDs = Set(progress.filter(\.isComplete).map(\.archiveID))
        topRated  = store.filteringWatched(store.topRated())
        gems      = store.filteringWatched(store.hiddenGems())
        watching  = store.filteringWatched(store.watchingNow())
        discussed = store.filteringWatched(store.mostDiscussed())
        favorites = store.filteringWatched(store.communityFavorites())
        writeWidgetSnapshot()
    }

    /// Feed the macOS desktop / Notification Center widgets (App Group snapshot) —
    /// the same shared writer the iPhone uses.
    private func writeWidgetSnapshot() {
        let continueItems = store.itemsByIDs(
            progress.filter { !$0.isComplete && $0.positionSeconds > 10 }.prefix(12).map(\.archiveID))
        let progressByID = Dictionary(
            progress.compactMap { p -> (String, Double)? in
                guard p.durationSeconds > 0 else { return nil }
                return (p.archiveID, min(0.98, max(0.02, p.positionSeconds / p.durationSeconds)))
            }, uniquingKeysWith: { a, _ in a })

        let pickPool = (store.items(forShelf: "editors-picks") + store.topRated())
            .filter { $0.hasDesignedArtwork && ($0.backdropURL != nil || $0.posterURL != nil) }
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        let pick = WidgetSnapshotWriter.pickOfDay(from: pickPool, dayNumber: day)

        let favItems = store.itemsByIDs(savedFavorites.prefix(8).map(\.archiveID)).filter(\.hasDesignedArtwork)

        WidgetSnapshotWriter.write(continueWatching: continueItems,
                                   progressByID: progressByID,
                                   pickOfDay: pick,
                                   favorites: favItems,
                                   surprisePool: store.topRated().filter(\.hasProfessionalArtwork))
    }
}

struct HeroBanner: View {
    let item: Catalog.Item
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.largeTitle).fontWeight(.bold)
                if let s = item.displaySynopsis {
                    Text(s).font(.callout).lineLimit(2).foregroundStyle(.white.opacity(0.85))
                }
                HStack {
                    if item.videoURLParsed != nil {
                        Button { router.play(item) } label: {
                            Label("Play", systemImage: "play.fill")
                        }.buttonStyle(.borderedProminent)
                    }
                    Button("Details") { router.openDetail(item) }.buttonStyle(.bordered)
                }
            }
            .padding(24).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        // Backdrop as .background so the fill-mode image can't drive layout
        // (same fill-image trap as the poster cards).
        .background {
            if let url = item.backdropURLParsed ?? item.posterURLParsed {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { Color.black.opacity(0.2) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
#endif
