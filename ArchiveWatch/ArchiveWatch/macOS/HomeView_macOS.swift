#if os(macOS)
import SwiftUI

// Home = curated shelves over the shared CatalogDB queries (same shelves the other
// platforms show). Re-queries when the full DB swaps in (store.dbVersion).

struct HomeView: View {
    @Environment(AppStore.self) private var store
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
    }

    private func reload() {
        topRated  = store.topRated()
        gems      = store.hiddenGems()
        watching  = store.watchingNow()
        discussed = store.mostDiscussed()
        favorites = store.communityFavorites()
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
