#if os(macOS)
import SwiftUI
import SwiftData

// Home = curated shelves over the shared CatalogDB queries (same shelves the other
// platforms show). Re-queries when the full DB swaps in (store.dbVersion).

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]
    @Query(sort: \Favorite.addedAt, order: .reverse) private var savedFavorites: [Favorite]
    @State private var topRated: [Catalog.Item] = []
    @State private var gems: [Catalog.Item] = []
    @State private var watching: [Catalog.Item] = []
    @State private var discussed: [Catalog.Item] = []
    @State private var favorites: [Catalog.Item] = []
    @State private var pdItems: [Catalog.Item] = []
    @State private var payloads: [ShelfPayload] = []
    @State private var directorShelves: [(name: String, items: [Catalog.Item])] = []

    private let pdYear = Calendar.current.component(.year, from: Date()) - 95
    private let minPerShelf = 6

    private var shelves: [Featured.Shelf] { store.featured?.shelves ?? [] }
    private var continueItems: [Catalog.Item] {
        store.itemsByIDs(progress.filter { !$0.isComplete && $0.positionSeconds > 10 }
            .prefix(12).map(\.archiveID))
    }

    struct ShelfPayload: Identifiable {
        let shelf: Featured.Shelf
        let items: [Catalog.Item]
        var id: String { shelf.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let hero = topRated.first { HeroBanner(item: hero) }
                if !continueItems.isEmpty { ShelfRow(title: "Continue Watching", items: continueItems) }
                CategoryTilesRow()
                ForEach(payloads.prefix(2)) { ShelfRow(title: $0.shelf.title, items: $0.items) }
                ShelfRow(title: "Top Rated", items: topRated, accent: .orange)
                ShelfRow(title: "Watching Now", items: watching)
                ShelfRow(title: "Community Favorites", items: favorites)
                ShelfRow(title: "Most Discussed", items: discussed)
                ShelfRow(title: "Hidden Gems", items: gems)
                if !pdItems.isEmpty { ShelfRow(title: "Public Domain Day", items: pdItems) }
                ForEach(directorShelves, id: \.name) { ShelfRow(title: "Directed by \($0.name)", items: $0.items) }
                ForEach(payloads.dropFirst(2)) { ShelfRow(title: $0.shelf.title, items: $0.items) }
                DecadeTilesRow()   // last row (tvOS/iOS parity — browse-by-era at the bottom)
            }
            .padding(24)
        }
        .navigationTitle("Home")
        .task(id: store.dbVersion) { reload() }
        .onChange(of: store.hideWatchedOnHome) { reload() }
    }

    private func reload() {
        // Feed the store's completed set so hideWatchedOnHome actually filters the shelves.
        store.completedArchiveIDs = Set(progress.filter(\.isComplete).map(\.archiveID))
        topRated  = store.filteringWatched(store.topRated().filter(\.hasProfessionalArtwork))
        gems      = store.filteringWatched(store.hiddenGems())
        watching  = store.filteringWatched(store.watchingNow().filter(\.hasProfessionalArtwork))
        discussed = store.filteringWatched(store.mostDiscussed().filter(\.hasProfessionalArtwork))
        favorites = store.filteringWatched(store.communityFavorites().filter(\.hasProfessionalArtwork))
        pdItems   = store.filteringWatched(
            store.browse(year: pdYear, sort: .popular, limit: 24).filter(\.hasDesignedArtwork))
        directorShelves = store.topDirectors().map { d in
            (name: d.name, items: store.filteringWatched(store.byDirector(d.name)))
        }.filter { $0.items.count >= minPerShelf }
        payloads = dedupedPayloads()
        writeWidgetSnapshot()
    }

    /// Resolve each curated featured.json shelf, keep professional art, drop items already shown,
    /// and per-shelf shuffle so Home isn't five aliases of the same popular list (iOS parity).
    private func dedupedPayloads() -> [ShelfPayload] {
        var used = Set(topRated.map(\.archiveID)).union(continueItems.map(\.archiveID))
            .union(gems.map(\.archiveID)).union(pdItems.map(\.archiveID))
            .union(directorShelves.flatMap { $0.items.map(\.archiveID) })
        var out: [ShelfPayload] = []
        for shelf in shelves {
            let fresh = store.filteringWatched(store.items(forShelf: shelf.id))
                .filter { $0.hasProfessionalArtwork && !used.contains($0.archiveID) }
            let taken = Array(fresh.prefix(20))
            guard taken.count >= minPerShelf else { continue }
            taken.forEach { used.insert($0.archiveID) }
            out.append(ShelfPayload(shelf: shelf, items: taken))
        }
        return out
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

// MARK: - Category tiles (Home "Browse by Category" row — parity with iOS DiscoverSections)

struct CategoryTilesRow: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var categories: [Featured.Category] = []
    private let minCount = 30   // a tile must open a real surface, not 3 items

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !categories.isEmpty {
                Text("Browse by Category").font(.title3).fontWeight(.semibold)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(categories) { cat in
                            Button {
                                router.path.append(BrowseFilterRoute(title: cat.displayName, contentType: cat.id))
                            } label: { CategoryTileSmall(category: cat) }
                            .buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 2)
                }
            }
        }
        .task(id: store.dbVersion) {
            categories = (store.featured?.categories ?? [])
                .filter { !store.hiddenCategories.contains($0.id) }
                .filter { store.browseCount(contentType: $0.id) >= minCount }
        }
    }
}

private struct CategoryTileSmall: View {
    let category: Featured.Category
    @State private var hovering = false
    private var accent: Color { Color(hex: category.accent) ?? .accentColor }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [accent.opacity(0.85), accent.mix(with: .black, by: 0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: iconName).font(.system(size: 18)).foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                Text(category.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
            }.padding(12)
        }
        .frame(width: 160, height: 100)
        .clipShape(.rect(cornerRadius: 10))
        .shadow(radius: hovering ? 6 : 1, y: hovering ? 3 : 1)
        .scaleEffect(hovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }

    private var iconName: String {
        switch category.id {
        case "feature-film": "film.fill"; case "tv-series": "tv.fill"
        case "silent-film": "moon.stars.fill"; case "animation": "paintbrush.fill"
        case "newsreel": "newspaper.fill"; case "documentary": "camera.fill"
        case "ephemeral": "books.vertical.fill"; case "short-film": "clock.fill"
        case "commercial": "tv.badge.wifi"; default: "sparkles"
        }
    }
}

// MARK: - Decade tiles (Home "Browse by Era" row)

struct DecadeTilesRow: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var counts: [Int: Int] = [:]
    private var decades: [Int] { counts.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !decades.isEmpty {
                Text("Browse by Era").font(.title3).fontWeight(.semibold)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(decades, id: \.self) { decade in
                            Button {
                                router.path.append(BrowseFilterRoute(title: "\(String(decade))s", decade: decade))
                            } label: { DecadeTileSmall(decade: decade, count: counts[decade] ?? 0) }
                            .buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 2)
                }
            }
        }
        .task(id: store.dbVersion) { counts = store.decadeCounts() }
    }
}

private struct DecadeTileSmall: View {
    let decade: Int
    let count: Int
    @State private var hovering = false

    private var era: (label: String, accent: Color) {
        switch decade {
        case ..<1910:     ("Earliest",   Color(hex: "#C9A66B") ?? .brown)
        case 1910...1927: ("Silent Era", Color(hex: "#C9A66B") ?? .brown)
        case 1928...1939: ("Pre-Code",   Color(hex: "#FF5C35") ?? .orange)
        case 1940...1949: ("Wartime",    Color(hex: "#8A8F98") ?? .gray)
        case 1950...1959: ("Atomic Age", Color(hex: "#2D5BFF") ?? .blue)
        case 1960...1969: ("New Wave",   Color(hex: "#FF4D8D") ?? .pink)
        case 1970...1979: ("Analog",     Color(hex: "#7C5BBA") ?? .purple)
        case 1980...1989: ("Home Video", Color(hex: "#3FA796") ?? .teal)
        default:          ("Modern",     Color(hex: "#E8A317") ?? .yellow)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [era.accent.opacity(0.9), era.accent.mix(with: .black, by: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(decade)s").font(.system(size: 24, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Text(era.label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(count) titles").font(.caption2).foregroundStyle(.white.opacity(0.75))
            }.padding(12)
        }
        .frame(width: 140, height: 100)
        .clipShape(.rect(cornerRadius: 10))
        .shadow(radius: hovering ? 6 : 1, y: hovering ? 3 : 1)
        .scaleEffect(hovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}
#endif
