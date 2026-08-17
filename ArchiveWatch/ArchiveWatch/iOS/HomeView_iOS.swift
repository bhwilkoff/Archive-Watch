#if os(iOS)
import SwiftUI
import SwiftData

// Home: a paging hero carousel + horizontally-scrolling shelves (resolved from
// featured.json via the prebuilt item_shelves map) + Continue Watching. Touch
// idiom — swipe + tap, no focus engine. Settings lives behind a nav-bar cog,
// not a tab (Router.Tab dropped .settings).
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]

    // Seeded once per Home lifetime so the hero pool + per-shelf shuffles are
    // stable across body recomputes (don't reshuffle on every scroll tick).
    @State private var heroSeed = UInt64.random(in: 0..<UInt64.max)
    @State private var shelfSeed = UInt64.random(in: 0..<UInt64.max)
    @State private var heroItems: [Catalog.Item] = []
    // Featured shelves in the canonical Apple-TV order, ALL rendered before the
    // dynamic block (tvOS parity) — see rebuild()'s render-order dedup.
    @State private var featuredPayloads: [ShelfPayload] = []
    @State private var gems: [Catalog.Item] = []
    @State private var topRated: [Catalog.Item] = []
    @State private var watchingNow: [Catalog.Item] = []
    @State private var communityFavorites: [Catalog.Item] = []
    @State private var mostDiscussed: [Catalog.Item] = []
    @State private var pdItems: [Catalog.Item] = []
    @State private var directorShelves: [(name: String, items: [Catalog.Item])] = []
    @State private var showSettings = false

    private let pdYear = Calendar.current.component(.year, from: Date()) - 95

    // Phone shelves are narrow (~3 tiles visible). Below this a row reads as a
    // half-empty stub, so drop it rather than show a ragged shelf.
    private let minPerShelf = 6

    private var shelves: [Featured.Shelf] { store.featured?.shelves ?? [] }
    private var continueItems: [Catalog.Item] {
        store.itemsByIDs(progress.filter { !$0.isComplete && $0.positionSeconds > 2 }
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
                // Featured shelves (canonical order), then the dynamic block in the SAME order as
                // Apple TV: Public Domain Day, Top Rated, Watching Now, Community Favorites, Most
                // Discussed, Hidden Gems — then Directors (owner 2026-06-29 shelf parity).
                ForEach(featuredPayloads) { payload in
                    Shelf(title: payload.shelf.title, subtitle: payload.shelf.subtitle, items: payload.items)
                }
                if !pdItems.isEmpty {
                    Shelf(title: "Public Domain Day",
                          subtitle: "Class of \(String(pdYear)) — newly free to share", items: pdItems)
                }
                if !topRated.isEmpty {
                    Shelf(title: "Top Rated",
                          subtitle: "The crowd's verdict — IMDb favorites", items: topRated)
                }
                if !watchingNow.isEmpty {
                    Shelf(title: "Watching Now",
                          subtitle: "Most-viewed on archive.org this month", items: watchingNow)
                }
                if !communityFavorites.isEmpty {
                    Shelf(title: "Community Favorites",
                          subtitle: "Most-favorited by archive.org viewers", items: communityFavorites)
                }
                if !mostDiscussed.isEmpty {
                    Shelf(title: "Most Discussed",
                          subtitle: "The films people are talking about", items: mostDiscussed)
                }
                if !gems.isEmpty {
                    Shelf(title: "Hidden Gems",
                          subtitle: "High craft, low traffic", items: gems)
                }
                ForEach(directorShelves, id: \.name) { shelf in
                    Shelf(title: "Directed by \(shelf.name)", subtitle: nil, items: shelf.items)
                }
                // Last row, matching tvOS Home (owner direction 2026-06-11:
                // "move the browse by era to the bottom of the shelves").
                DecadeTilesRow()
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
        // isWatched (durable), not isComplete — a rewatch must not un-mark it.
        store.completedArchiveIDs = Set(progress.filter(\.isWatched).map(\.archiveID))
        heroItems = loadHero()

        // ONE ordered seen-set across EVERY home shelf so no title repeats anywhere
        // (keyed on dedupKey, not archiveID — also collapses re-uploads of the same
        // film). Claimed in the EXACT render order of `body`: hero + Continue
        // Watching seed it; the featured shelves are split around the dynamic
        // shelves (top two, then the dynamic block, then the rest).
        var used = Set<String>()
        heroItems.forEach { used.insert($0.dedupKey) }
        continueItems.forEach { used.insert($0.dedupKey) }

        // Claim up to `limit` fresh items from a pool (deduping within the pool too),
        // and only keep the shelf if it clears `min` — mirrors macOS `add()`, so a
        // shelf that overlaps an earlier one shrinks and HIDES instead of repeating.
        func take(_ pool: [Catalog.Item], limit: Int = 20, min: Int = minPerShelf) -> [Catalog.Item] {
            var taken: [Catalog.Item] = []
            var seen = Set<String>()
            for it in pool {
                let k = it.dedupKey
                if used.contains(k) || seen.contains(k) { continue }
                seen.insert(k); taken.append(it)
                if taken.count >= limit { break }
            }
            guard taken.count >= min else { return [] }
            used.formUnion(seen)
            return taken
        }

        func featuredPayload(_ shelf: Featured.Shelf) -> ShelfPayload? {
            var raw = store.filteringWatched(store.items(forShelf: shelf.id))
                .filter(\.hasProfessionalArtwork)
            var rng = SplitMix(seed: shelfSeed &+ UInt64(bitPattern: Int64(shelf.id.hashValue)))
            raw.shuffle(using: &rng)
            let items = take(raw)
            return items.isEmpty ? nil : ShelfPayload(shelf: shelf, items: items)
        }

        // Claim in render order (tvOS parity): ALL featured shelves first (canonical order), then the
        // dynamic block — Public Domain Day, Top Rated, Watching Now, Community Favorites, Most
        // Discussed, Hidden Gems — then Directors.
        featuredPayloads = (store.featured?.orderedHomeShelves ?? []).compactMap(featuredPayload)
        pdItems = take(store.filteringWatched(
            store.browse(year: pdYear, sort: .popular, limit: 120).filter(\.hasDesignedArtwork)))
        topRated = take(store.filteringWatched(store.topRated().filter(\.hasProfessionalArtwork)))
        watchingNow = take(store.filteringWatched(store.watchingNow().filter(\.hasProfessionalArtwork)))
        communityFavorites = take(store.filteringWatched(store.communityFavorites().filter(\.hasProfessionalArtwork)))
        mostDiscussed = take(store.filteringWatched(store.mostDiscussed().filter(\.hasProfessionalArtwork)))
        gems = take(store.filteringWatched(store.hiddenGems().filter(\.hasProfessionalArtwork)))
        directorShelves = store.topDirectors().compactMap { d in
            let items = take(store.filteringWatched(store.byDirector(d.name).filter(\.hasProfessionalArtwork)))
            return items.isEmpty ? nil : (name: d.name, items: items)
        }
        writeWidgetSnapshot()
    }

    /// Feed the home-screen + Lock Screen + Control widgets (App Group snapshot).
    private func writeWidgetSnapshot() {
        // Continue Watching progress fractions, keyed by id (timecode "min left").
        let progressByID = Dictionary(
            progress.compactMap { p -> (String, Double)? in
                guard p.durationSeconds > 0 else { return nil }
                return (p.archiveID, min(0.98, max(0.02, p.positionSeconds / p.durationSeconds)))
            }, uniquingKeysWith: { a, _ in a })

        // Pick of the Day: a deterministic daily rotation through designed-art picks
        // (an editorial invitation the user can predict — not an opaque "for you").
        let pickPool = (store.items(forShelf: "editors-picks") + store.topRated())
            .filter { $0.hasDesignedArtwork && ($0.backdropURL != nil || $0.posterURL != nil) }
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        let pick = WidgetSnapshotWriter.pickOfDay(from: pickPool, dayNumber: day)

        let favItems = store.itemsByIDs(favorites.prefix(8).map(\.archiveID))
            .filter(\.hasDesignedArtwork)
        let surprise = store.topRated().filter(\.hasProfessionalArtwork)

        WidgetSnapshotWriter.write(continueWatching: continueItems,
                                   progressByID: progressByID,
                                   pickOfDay: pick,
                                   favorites: favItems,
                                   surprisePool: surprise)
    }

    /// Hero pool: popular, home-eligible, designed (non-generated) art, preferring
    /// wide TMDb backdrops so the full-bleed banner isn't a blown-up poster.
    private func loadHero() -> [Catalog.Item] {
        let base = store.filteringWatched(store.dbBrowse(sort: .popular, limit: 3000, homeOnly: true))
            .filter { $0.hasDesignedArtwork && $0.artworkSource != "generated" }
        // Hero must be well-composed WIDE art — a real backdrop, never a cropped 2:3 poster or a
        // frame-grab cover. Require a backdrop; if too few qualify the hero shows fewer (or hides)
        // rather than cropping a poster into the full-bleed banner (owner 2026-06-29).
        let pool = base.filter { $0.backdropURLParsed != nil }
        // The marquee must never feature a title that doesn't play (owner:
        // "should certainly not be highlighted on the home screen"). Prefer
        // byte-verified items; fall back to the full pool while probe coverage
        // is still climbing, so the hero can never go empty. Measured
        // 2026-07-18: 244 of the 758 backdrop-bearing candidates are already
        // verified — far more than the 7 the hero shows.
        let verified = pool.filter { $0.isPlaybackVerified }
        let heroPool = verified.count >= 7 ? verified : pool
        var rng = SplitMix(seed: heroSeed)
        return Array(heroPool.shuffled(using: &rng).prefix(7))
    }

}

// MARK: - Hero carousel (paging, auto-advance)

private struct HeroCarousel: View {
    let items: [Catalog.Item]
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var index = 0

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
        // Native structured-concurrency auto-advance (replaces a Combine Timer.publish whose @MainActor
        // delivery could trip a Swift-runtime executor fault). Restarts + resets on pool swap; cancelled
        // on disappear.
        .task(id: items.map(\.archiveID)) {
            index = 0
            guard items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                if Task.isCancelled { break }
                withAnimation(.easeInOut) { index = (index + 1) % items.count }
            }
        }
    }

    private func card(_ item: Catalog.Item) -> some View {
        // Art as .background — a fill image reports its COVER size and a
        // maxWidth:.infinity frame adopts it, widening the carousel past the
        // screen (same bug class as DetailHero; see that comment).
        Color.clear
            .frame(maxWidth: cardMaxWidth ?? .infinity)
            .frame(height: cardHeight)
            .background {
                PosterImage(url: item.backdropURLParsed)
            }
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
