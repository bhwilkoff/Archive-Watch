#if os(macOS)
import SwiftUI
import SwiftData

// Home = curated shelves over the shared CatalogDB queries (same shelves the other
// platforms show). Re-queries when the full DB swaps in (store.dbVersion).

struct HomeShelf: Identifiable { let id: String; let title: String; let items: [Catalog.Item]; var accent: Color = .primary }

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]
    @Query(sort: \Favorite.addedAt, order: .reverse) private var savedFavorites: [Favorite]
    @State private var heroItems: [Catalog.Item] = []
    @State private var shelves: [HomeShelf] = []
    // Stable per-Home-lifetime seed so the hero pool doesn't reshuffle on every reload tick.
    @State private var heroSeed = UInt64.random(in: 0..<UInt64.max)

    private let pdYear = Calendar.current.component(.year, from: Date()) - 95
    // A shelf needs this many professional-art items (after cross-shelf dedup) to earn a row.
    // Matches the tvOS `minPerShelf` so a thin/redundant shelf HIDES (parity: on Apple TV the
    // overlapping community shelves end up empty after dedup, so they don't appear).
    private let minPerShelf = 9

    private var continueItems: [Catalog.Item] {
        store.itemsByIDs(progress.filter { !$0.isComplete && $0.positionSeconds > 10 }
            .prefix(12).map(\.archiveID)).filter(\.hasProfessionalArtwork)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !heroItems.isEmpty { HeroCarousel(items: heroItems) }
                if !continueItems.isEmpty { ShelfRow(title: "Continue Watching", items: continueItems) }
                CategoryTilesRow()
                ForEach(shelves) { ShelfRow(title: $0.title, items: $0.items, accent: $0.accent) }
                DecadeTilesRow()   // last row (tvOS/iOS parity — browse-by-era at the bottom)
            }
            .padding(24)
        }
        .navigationTitle("Home")
        .task(id: store.dbVersion) { reload() }
        .onChange(of: store.hideWatchedOnHome) { reload() }
    }

    /// Build Home in the SAME order as Apple TV (tvOS HomeView), with ONE cross-shelf dedup so no
    /// item appears twice — Watching Now / Community Favorites / Most Discussed are vote-floored
    /// community queries that heavily overlap, so deduping (Watching Now first) shrinks the later
    /// ones below `minPerShelf` and they HIDE → "only one community shelf shows" (owner). Every
    /// shelf is professional-art only (no missing posters / generated covers, like tvOS).
    private func reload() {
        store.completedArchiveIDs = Set(progress.filter(\.isComplete).map(\.archiveID))

        var used = Set<String>()
        // Hero POOL (parity: the hero ROTATES on every other platform — was a single static banner
        // on macOS). Popular, home-eligible, designed (non-generated) art, preferring wide backdrops
        // so the banner isn't a blown-up poster. None of these repeat in the shelves below.
        let base = store.filteringWatched(store.dbBrowse(sort: .popular, limit: 3000, homeOnly: true))
            .filter { $0.hasDesignedArtwork && $0.artworkSource != "generated" }
        let withBackdrop = base.filter { $0.backdropURLParsed != nil }
        let pool = withBackdrop.count >= 7 ? withBackdrop
            : base.filter { $0.backdropURLParsed != nil || $0.posterURLParsed != nil }
        var rng = SplitMix(seed: heroSeed)
        heroItems = Array(pool.shuffled(using: &rng).prefix(7))
        heroItems.forEach { used.insert($0.dedupKey) }
        continueItems.forEach { used.insert($0.dedupKey) }   // don't resurface Continue Watching

        var built: [HomeShelf] = []
        func add(_ id: String, _ title: String, _ pool: [Catalog.Item], accent: Color = .primary) {
            let fresh = store.filteringWatched(pool)
                .filter { $0.hasProfessionalArtwork && !used.contains($0.dedupKey) }
            let taken = Array(fresh.prefix(24))
            guard taken.count >= minPerShelf else { return }
            taken.forEach { used.insert($0.dedupKey) }
            built.append(HomeShelf(id: id, title: title, items: taken, accent: accent))
        }

        // Curated featured.json shelves (all, in order) — same as tvOS dedupedShelfPayloads.
        for shelf in (store.featured?.shelves ?? []) { add(shelf.id, shelf.title, store.items(forShelf: shelf.id)) }
        // Then the dynamic shelves, in tvOS order.
        add("public-domain-day", "Public Domain Day", store.browse(year: pdYear, sort: .popular, limit: 120))
        add("top-rated", "Top Rated", store.topRated(), accent: .orange)
        add("watching-now", "Watching Now", store.watchingNow())
        add("community-favorites", "Community Favorites", store.communityFavorites())
        add("most-discussed", "Most Discussed", store.mostDiscussed())
        add("hidden-gems", "Hidden Gems", store.hiddenGems())
        for d in store.topDirectors() { add("dir-\(d.name)", "Directed by \(d.name)", store.byDirector(d.name)) }

        shelves = built
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

// A ROTATING hero (parity: the hero auto-advances on every other platform; macOS was static).
// Cross-fades through the pool every 7s; the dots jump to a slot; hovering pauses the rotation
// (pointer idiom) so it doesn't shift out from under the cursor.
struct HeroCarousel: View {
    let items: [Catalog.Item]
    @State private var index = 0
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i == index { HeroBanner(item: item).transition(.opacity) }
            }
            if items.count > 1 {
                HStack(spacing: 7) {
                    ForEach(items.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Color.white : Color.white.opacity(0.35))
                            .frame(width: i == index ? 18 : 7, height: 7)
                            .onTapGesture { withAnimation(.easeInOut) { index = i } }
                    }
                }
                .padding(14)
            }
        }
        .onHover { hovering = $0 }
        // Native structured-concurrency auto-advance (replaces a Combine Timer.publish whose delivery
        // to this @MainActor closure could trip a Swift-runtime executor fault). The task is bound to
        // the item pool: SwiftUI cancels + restarts it when the pool swaps (resetting the index) and
        // cancels it on disappear, so there is no stray timer firing into a torn-down view.
        .task(id: items.map(\.archiveID)) {
            index = 0
            guard items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                if Task.isCancelled { break }
                if hovering { continue }                       // @State read live — pause while hovered
                withAnimation(.easeInOut(duration: 0.6)) { index = (index + 1) % items.count }
            }
        }
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
                RemoteImage(url: url, contentMode: .fill)
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
