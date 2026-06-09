#if os(iOS)
import SwiftUI
import SwiftData

// Home: a hero banner + horizontally-scrolling shelves (curated + dynamic from
// featured.json) + Continue Watching. Touch idiom — scroll + tap, no focus engine.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]

    private var shelves: [Featured.Shelf] { store.featured?.shelves ?? [] }
    private var continueItems: [Catalog.Item] {
        store.itemsByIDs(progress.filter { !$0.isComplete && $0.positionSeconds > 10 }
            .prefix(12).map(\.archiveID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let hero = shelves.first.flatMap({ store.shelfItems($0).first }) {
                    HeroBanner(item: hero).onTapGesture { router.openDetail(hero) }
                }
                if !continueItems.isEmpty {
                    Shelf(title: "Continue Watching", subtitle: nil, items: continueItems)
                }
                ForEach(shelves) { shelf in
                    let items = store.shelfItems(shelf)
                    if items.count >= 6 {
                        Shelf(title: shelf.title, subtitle: shelf.subtitle, items: items)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Archive Watch")
        .id(store.dbVersion)   // re-query when the DB swaps (seed → full)
    }
}

private struct Shelf: View {
    let title: String
    let subtitle: String?
    let items: [Catalog.Item]
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3).fontWeight(.semibold)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        Button { router.openDetail(item) } label: { PosterTile(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct HeroBanner: View {
    let item: Catalog.Item
    var body: some View {
        PosterImage(url: item.backdropURLParsed ?? item.posterURLParsed)
            .aspectRatio(16/9, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.title2.bold()).foregroundStyle(.white)
                    if let y = item.year { Text(verbatim: String(y)).foregroundStyle(.white.opacity(0.8)) }
                }
                .padding()
                .background(LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                           startPoint: .top, endPoint: .bottom))
            }
            .padding(.horizontal)
    }
}

#endif
