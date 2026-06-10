#if os(iOS)
import SwiftUI
import SwiftData
import Combine

// Home: a paging hero carousel + horizontally-scrolling shelves (resolved from
// featured.json via the prebuilt item_shelves map) + Continue Watching. Touch
// idiom — swipe + tap, no focus engine. Settings lives behind a nav-bar cog,
// not a tab (Router.Tab dropped .settings).
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]

    // Seeded once per Home lifetime so the hero pool + per-shelf shuffles are
    // stable across body recomputes (don't reshuffle on every scroll tick).
    @State private var heroSeed = UInt64.random(in: 0..<UInt64.max)
    @State private var shelfSeed = UInt64.random(in: 0..<UInt64.max)
    @State private var heroItems: [Catalog.Item] = []
    @State private var payloads: [ShelfPayload] = []
    @State private var gems: [Catalog.Item] = []
    @State private var pdItems: [Catalog.Item] = []
    @State private var directorShelves: [(name: String, items: [Catalog.Item])] = []
    @State private var showSettings = false

    private let pdYear = Calendar.current.component(.year, from: Date()) - 95

    // Phone shelves are narrow (~3 tiles visible). Below this a row reads as a
    // half-empty stub, so drop it rather than show a ragged shelf.
    private let minPerShelf = 6

    private var shelves: [Featured.Shelf] { store.featured?.shelves ?? [] }
    private var continueItems: [Catalog.Item] {
        store.itemsByIDs(progress.filter { !$0.isComplete && $0.positionSeconds > 10 }
            .prefix(12).map(\.archiveID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !heroItems.isEmpty {
                    HeroCarousel(items: heroItems)
                }
                if !continueItems.isEmpty {
                    Shelf(title: "Continue Watching", subtitle: nil, items: continueItems)
                }
                CategoryTilesRow()
                DecadeTilesRow()
                ForEach(payloads.prefix(2)) { payload in
                    Shelf(title: payload.shelf.title, subtitle: payload.shelf.subtitle, items: payload.items)
                }
                if !gems.isEmpty {
                    Shelf(title: "Hidden Gems",
                          subtitle: "Lovingly restored, rarely watched", items: gems)
                }
                if !pdItems.isEmpty {
                    Shelf(title: "Public Domain Day",
                          subtitle: "Class of \(String(pdYear)) — newly free to share", items: pdItems)
                }
                ForEach(directorShelves, id: \.name) { shelf in
                    Shelf(title: "Directed by \(shelf.name)", subtitle: nil, items: shelf.items)
                }
                ForEach(payloads.dropFirst(2)) { payload in
                    Shelf(title: payload.shelf.title, subtitle: payload.shelf.subtitle, items: payload.items)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Archive Watch")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.push(SurpriseRoute()) } label: {
                    Image(systemName: "shuffle").accessibilityLabel("Surprise me")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        .id(store.dbVersion)   // re-query when the DB swaps (seed → full)
        .task(id: store.dbVersion) { rebuild() }
    }

    private struct ShelfPayload: Identifiable {
        let shelf: Featured.Shelf
        let items: [Catalog.Item]
        var id: String { shelf.id }
    }

    private func rebuild() {
        // Feed the store's watched set (the iOS WatchedHomeSync — HomeView already
        // owns the WatchProgress @Query) so hide-watched (#17) works on iOS.
        store.completedArchiveIDs = Set(progress.filter(\.isComplete).map(\.archiveID))
        heroItems = loadHero()
        gems = store.filteringWatched(store.hiddenGems())
        pdItems = store.filteringWatched(
            store.browse(year: pdYear, sort: .popular, limit: 24).filter(\.hasDesignedArtwork))
        directorShelves = store.topDirectors().map { d in
            (name: d.name, items: store.filteringWatched(store.byDirector(d.name)))
        }.filter { $0.items.count >= minPerShelf }
        payloads = dedupedPayloads()
        // Feed the home-screen widgets (App Group snapshot).
        WidgetSnapshotWriter.write(continueWatching: continueItems,
                                   editorsPicks: store.items(forShelf: "editors-picks"))
    }

    /// Hero pool: popular, home-eligible, designed (non-generated) art, preferring
    /// wide TMDb backdrops so the full-bleed banner isn't a blown-up poster.
    private func loadHero() -> [Catalog.Item] {
        let base = store.filteringWatched(store.dbBrowse(sort: .popular, limit: 3000, homeOnly: true))
            .filter { $0.hasDesignedArtwork && $0.artworkSource != "generated" }
        let withBackdrop = base.filter { $0.backdropURLParsed != nil }
        let pool = withBackdrop.count >= 7 ? withBackdrop
            : base.filter { $0.backdropURLParsed != nil || $0.posterURLParsed != nil }
        var rng = SplitMix(seed: heroSeed)
        return Array(pool.shuffled(using: &rng).prefix(7))
    }

    /// Resolve each shelf by id, keep only professional artwork, drop items
    /// already shown above (hero + an earlier shelf), and per-shelf shuffle —
    /// so Home isn't five aliases of the same popular list.
    private func dedupedPayloads() -> [ShelfPayload] {
        var used = Set(heroItems.map(\.archiveID)).union(continueItems.map(\.archiveID))
            .union(gems.map(\.archiveID)).union(pdItems.map(\.archiveID))
            .union(directorShelves.flatMap { $0.items.map(\.archiveID) })
        var out: [ShelfPayload] = []
        for shelf in shelves {
            let raw = store.filteringWatched(store.items(forShelf: shelf.id))
            var fresh = raw.filter { $0.hasProfessionalArtwork && !used.contains($0.archiveID) }
            var rng = SplitMix(seed: shelfSeed &+ UInt64(bitPattern: Int64(shelf.id.hashValue)))
            fresh.shuffle(using: &rng)
            let taken = Array(fresh.prefix(20))
            guard taken.count >= minPerShelf else { continue }
            taken.forEach { used.insert($0.archiveID) }
            out.append(ShelfPayload(shelf: shelf, items: taken))
        }
        return out
    }
}

// MARK: - Hero carousel (paging, auto-advance)

private struct HeroCarousel: View {
    let items: [Catalog.Item]
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var index = 0
    private let autoAdvance = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    // iPhone portrait: a full-bleed banner ~16:9. iPad / regular width: a
    // width-capped, centered 16:9 card so a wide screen doesn't stretch a short
    // strip into an extreme crop. Heights track ~16:9 of the respective widths.
    private var isRegular: Bool { hSize == .regular }
    private var cardMaxWidth: CGFloat? { isRegular ? 760 : nil }   // nil = full width
    private var cardHeight: CGFloat { isRegular ? 428 : 232 }      // 760*9/16 ≈ 428

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                card(item)
                    .tag(i)
                    .onTapGesture { router.openDetail(item) }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: cardHeight + 32)   // + room for the page dots
        .onReceive(autoAdvance) { _ in
            guard items.count > 1 else { return }
            withAnimation(.easeInOut) { index = (index + 1) % items.count }
        }
    }

    private func card(_ item: Catalog.Item) -> some View {
        PosterImage(url: item.backdropURLParsed ?? item.posterURLParsed)
            .frame(maxWidth: cardMaxWidth ?? .infinity)
            .frame(height: cardHeight)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.title3.bold()).foregroundStyle(.white).lineLimit(2)
                    if let y = item.year {
                        Text(verbatim: String(y)).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                           startPoint: .top, endPoint: .bottom))
            }
            .clipShape(.rect(cornerRadius: 16))
            .frame(maxWidth: .infinity)   // center the (capped) card on iPad
            .padding(.horizontal)
            .padding(.bottom, 28)   // room for the page dots
    }
}

// MARK: - Shelf

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

#endif
