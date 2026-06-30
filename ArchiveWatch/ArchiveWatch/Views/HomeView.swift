#if os(tvOS)
import SwiftUI

// Home screen. All components that are ONLY used by Home live in this
// file so they're in-scope for the composition without SourceKit
// needing a project-wide index to resolve them — that was the cause
// of the persistent "Cannot find HeroCarousel / DecadeTilesRow in
// scope" errors after clean compile. Same-file references resolve in
// one single-file parse; cross-file ones don't.
//
// Kept as separate files:
//  • PosterTile.swift   — shared with DetailView's More Like This
//  • ContinueWatching.swift — owns its own @Query<WatchProgress>
//
// Favorites now live in their own tab (FavoritesView.swift) rather than
// a Home shelf — a single saved title used to clutter the marquee.
//
// Those @Query-owning files are isolated so SwiftData macro flakes
// don't cascade across the whole screen.

// MARK: - HomeView

struct HomeView: View {
    @Environment(AppStore.self) private var store

    // Random seed set when HomeView first appears. Stable across the
    // view's lifetime so the hero rotation doesn't reshuffle on every
    // subview update, but re-rolls when the user leaves Home and
    // comes back — an invitation to keep wandering.
    @State private var heroSeed: Int = Int.random(in: 0..<1_000_000)
    // Separate seed per shelf set so shuffle is stable within a
    // Home lifetime but changes when user leaves + returns. Combined
    // with the per-shelf id to give each shelf its own permutation.
    @State private var shelfSeed: UInt64 = UInt64.random(in: 0..<UInt64.max)

    @State private var heroItems: [Catalog.Item] = []
    // All Home shelves, computed in one render-order pass with a single shared
    // seen-set so no title repeats across any of them (see rebuild()).
    @State private var featuredPayloads: [ShelfPayload] = []
    @State private var dynamicPayloads: [ShelfPayload] = []
    @State private var directorPayloads: [ShelfPayload] = []

    /// Hero pool from the DB (Decision 017): the most-popular items with art good
    /// enough to fill the screen. #10: the hero is full-bleed, so it demands
    /// HIGH-quality wide art — we prefer items with a true TMDb backdrop and
    /// exclude frame-extracted ("generated") covers, which are only ~600px and
    /// look pixelated blown up. Falls back to high-res posters only if too few
    /// backdrops exist.
    private func loadHero() -> [Catalog.Item] {
        // Backdrops (wide TMDb art) are sparse near the very top of the
        // popularity ranking — only ~6 of the top 300 have one, which pinned the
        // hero to the same handful every launch. Draw from a much deeper window
        // so there are ~150+ backdrop-bearing candidates to shuffle through while
        // keeping the high-quality wide-art bar.
        let base = store.filteringWatched(
            store.dbBrowse(sort: .popular, limit: 3000, homeOnly: true)
        ).filter { $0.hasDesignedArtwork && $0.artworkSource != "generated" }
        // Hero must be well-composed WIDE art — a real backdrop, never a cropped 2:3 poster or a
        // frame-grab cover. Require a backdrop; if too few qualify the hero shows fewer (or hides)
        // rather than cropping a poster into the full-bleed banner (owner 2026-06-29).
        let pool = base.filter { $0.backdropURLParsed != nil }
        var rng = SplitMix(seed: UInt64(heroSeed))
        return Array(pool.shuffled(using: &rng).prefix(7))
    }

    // The canonical Home shelf order, shared with iOS/macOS (Featured.homeShelfPriority).
    private var homeShelves: [Featured.Shelf] { store.featured?.orderedHomeShelves ?? [] }

    var body: some View {
        // VStack (not LazyVStack): the hero is ~940pt tall, so the first row
        // below it starts below the fold. A LazyVStack doesn't instantiate that
        // row until it's scrolled near, but on first launch the focus engine has
        // no instantiated focusable below the hero to move to — so Down is
        // trapped on the hero. VStack instantiates every row up front (each row
        // still lazy-loads its own tiles/images), giving Down a target. Home is
        // ~20 rows, so eager row containers are cheap.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 48) {
                if !heroItems.isEmpty {
                    HeroCarousel(items: heroItems)
                }
                ContinueWatchingRow()
                CategoryTilesRow()
                // Every shelf below is computed in ONE render-order pass sharing a
                // single seen-set (rebuild()), so a title never repeats across the
                // featured shelves, the dynamic/community shelves, or the directors.
                ForEach(featuredPayloads) { payload in
                    ShelfRow(shelf: payload.shelf, items: payload.items)
                }
                ForEach(dynamicPayloads) { payload in
                    ShelfRow(shelf: payload.shelf, items: payload.items)
                }
                if !directorPayloads.isEmpty {
                    VStack(alignment: .leading, spacing: 48) {
                        Text("Directors")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 80)
                        ForEach(directorPayloads) { payload in
                            ShelfRow(shelf: payload.shelf, items: payload.items)
                        }
                    }
                }
                DecadeTilesRow()
                    .padding(.bottom, 32)
            }
            .padding(.bottom, 80)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay { WatchedHomeSync() }   // #17: feeds completed + in-progress IDs into the store
        .task(id: "\(heroSeed)-\(store.dbGeneration)-\(store.hideWatchedOnHome)-\(store.completedArchiveIDs.count)-\(store.continueArchiveIDs.count)") {
            rebuild()
        }
    }

    private struct ShelfPayload: Identifiable {
        let shelf: Featured.Shelf
        let items: [Catalog.Item]
        var id: String { shelf.id }
    }

    /// Walk shelves in priority order. For each: keep only items with
    /// real designed artwork (no procedural placeholders on Home —
    /// they look empty and trigger thumbnail decode errors in the
    /// console), drop items already shown on an earlier shelf, shuffle
    /// with a per-shelf seeded RNG so repeat visits don't show the
    /// same tiles in the same order, and take the first 20.
    /// Minimum tiles for a shelf to earn a row. A shelf shorter than this
    /// looks like a stub that doesn't fill the screen width, so we drop it
    /// rather than show a half-empty row (#6). The real fix for thin but
    /// wanted shelves (NASA, 1950s/60s TV) is growing those collections in
    /// the catalog pipeline — this just guarantees Home never looks ragged.
    private let minPerShelf = 9
    private let pdYear = Calendar.current.component(.year, from: Date()) - 95

    /// Build the whole Home page in render order through ONE shared seen-set so no
    /// title appears in more than one shelf (keyed on dedupKey, not archiveID — also
    /// collapses re-uploads of the same film). Order: hero + Continue Watching seed
    /// the set; then the featured shelves, the dynamic/community shelves, and the
    /// director shelves each claim only items not already shown. A shelf that overlaps
    /// an earlier one shrinks below `minPerShelf` and HIDES — matching macOS, so the
    /// overlapping community queries don't surface as five aliases of the same films.
    private func rebuild() {
        heroItems = loadHero()

        var used = Set<String>()
        heroItems.forEach { used.insert($0.dedupKey) }
        // Continue Watching (the ids WatchedHomeSync pushed) — don't resurface them.
        for id in store.continueArchiveIDs {
            if let it = store.dbItem(id) { used.insert(it.dedupKey) }
        }

        // Claim up to `limit` fresh items from a pool (deduping within the pool too);
        // keep the shelf only if it clears `min`, and claim its items only then.
        func take(_ pool: [Catalog.Item], limit: Int = 24, min: Int = minPerShelf) -> [Catalog.Item] {
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

        func dynShelf(_ id: String, _ title: String, _ subtitle: String,
                      _ pool: [Catalog.Item], category: String = "feature-film") -> ShelfPayload? {
            let items = take(pool)
            guard !items.isEmpty else { return nil }
            return ShelfPayload(shelf: Featured.Shelf(
                id: id, title: title, subtitle: subtitle, category: category,
                type: "dynamic", items: nil, query: nil, sort: nil, limit: nil), items: items)
        }

        // Featured.json shelves, in priority order (per-shelf seeded shuffle).
        featuredPayloads = homeShelves.compactMap { shelf in
            var raw = store.filteringWatched(store.items(forShelf: shelf.id))
                .filter { $0.hasProfessionalArtwork }   // #2: professional posters only
            var rng = SplitMix(seed: shelfSeed &+ UInt64(bitPattern: Int64(shelf.id.hashValue)))
            raw.shuffle(using: &rng)
            let items = take(raw)
            return items.isEmpty ? nil : ShelfPayload(shelf: shelf, items: items)
        }

        // Dynamic shelves, in the same order they used to render as standalone views.
        dynamicPayloads = [
            dynShelf("public-domain-day", "Public Domain Day",
                     "Class of \(String(pdYear)) — newly free to share",
                     store.filteringWatched(store.dbBrowse(year: pdYear, sort: .popular, limit: 120))
                        .filter { $0.hasDesignedArtwork }),
            dynShelf("top-rated", "Top Rated", "The crowd's verdict — IMDb favorites",
                     store.filteringWatched(store.dbTopRated()).filter { $0.hasProfessionalArtwork }),
            dynShelf("watching-now", "Watching Now", "Most-viewed on archive.org this month",
                     store.filteringWatched(store.dbWatchingNow()).filter { $0.hasProfessionalArtwork }),
            dynShelf("community-favorites", "Community Favorites", "Most-favorited by archive.org viewers",
                     store.filteringWatched(store.dbCommunityFavorites()).filter { $0.hasProfessionalArtwork }),
            dynShelf("most-discussed", "Most Discussed", "The films people are talking about",
                     store.filteringWatched(store.dbMostDiscussed()).filter { $0.hasProfessionalArtwork }),
            dynShelf("hidden-gems", "Hidden Gems", "High craft, low traffic",
                     store.filteringWatched(store.dbHiddenGems()).filter { $0.hasProfessionalArtwork }),
        ].compactMap { $0 }

        // Director shelves (each prolific director's films, professional art only).
        directorPayloads = store.dbTopDirectors().compactMap { d -> ShelfPayload? in
            let films = store.filteringWatched(store.dbByDirector(d.name, homeOnly: true))
                .filter { $0.hasProfessionalArtwork }
            let items = take(films)
            guard !items.isEmpty else { return nil }
            return ShelfPayload(shelf: Featured.Shelf(
                id: "director-\(d.name)", title: d.name,
                subtitle: "\(items.count) films to discover",
                category: dominantCategory(films), type: "dynamic",
                items: nil, query: nil, sort: nil, limit: nil), items: items)
        }
    }

    private func dominantCategory(_ items: [Catalog.Item]) -> String {
        var counts: [String: Int] = [:]
        for it in items { counts[it.contentType, default: 0] += 1 }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.first?.key ?? "feature-film"
    }

}

// MARK: - HeroCarousel + HeroBanner

struct HeroCarousel: View {
    let items: [Catalog.Item]
    // ONE full-width focusable banner whose content swaps (playbook §9.2): no
    // neighbor slivers, and the index wraps with modulo. Manual paging:
    //  • RIGHT has no neighbor, so `.onMoveCommand(.right)` advances (and wraps).
    //  • LEFT is handled by an invisible 1pt focus "catcher" placed to the LEFT of
    //    the banner. While not on the first hero the catcher is focusable, so a
    //    Left press moves focus INTO it (staying in content — the sidebar does NOT
    //    open); we then step to the previous hero and bounce focus back. On the
    //    FIRST hero the catcher is disabled, so Left has no in-content target and
    //    falls through to the sidebar. This gives "Left = previous movie until the
    //    leftmost, then sidebar" without the double-trigger.
    @Environment(Router.self) private var router
    @State private var index = 0
    @FocusState private var focus: Focus?
    @State private var claimedInitialFocus = false

    private enum Focus: Hashable { case banner, leftCatch }
    private let heroHeight: CGFloat = 940   // #10: near-full-screen hero

    private var current: Catalog.Item { items[min(index, max(items.count - 1, 0))] }

    var body: some View {
        HStack(spacing: 0) {
            // Only PRESENT when there's a previous hero. It must be absent (not
            // merely non-focusable) at index 0 — a disabled 1pt view still sits at
            // the left edge and blocks Left from escaping to the sidebar.
            if index > 0 {
                Color.clear
                    .frame(width: 1, height: heroHeight)
                    .focusable()
                    .focused($focus, equals: .leftCatch)
            }

            Button { router.push(current) } label: {
                HeroBanner(item: current)
                    .id(current.archiveID)        // swap + crossfade the single banner
                    .transition(.opacity)
            }
            .buttonStyle(HeroButtonStyle())
            .frame(maxWidth: .infinity)
            .focused($focus, equals: .banner)
        }
        .frame(height: heroHeight)
        .clipped()                                // no bleed of adjacent content
        .focusSection()
        .animation(Motion.heroCrossfade, value: index)
        .overlay(alignment: .bottom) {
            pageIndicator.padding(.bottom, 56).allowsHitTesting(false)
        }
        // RIGHT (no neighbor) advances + wraps. left/up/down are NOT handled here.
        .onMoveCommand { direction in
            if direction == .right { advance(1) }
        }
        // A Left press landed on the catcher -> bounce focus back to the banner
        // FIRST (so it's never on the catcher when index hits 0 and the catcher is
        // removed), then step to the previous hero.
        .onChange(of: focus) { _, f in
            if f == .leftCatch {
                focus = .banner
                advance(-1)
            }
        }
        // Native structured-concurrency auto-advance (replaces a Combine Timer.publish whose @MainActor
        // delivery could trip a Swift-runtime executor fault). Cancelled on disappear.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                if Task.isCancelled { break }
                advance(1)
            }
        }
        .task {
            guard !claimedInitialFocus else { return }
            claimedInitialFocus = true
            try? await Task.sleep(for: .milliseconds(60))
            focus = .banner
        }
    }

    private func advance(_ step: Int) {
        guard items.count > 1 else { return }
        withAnimation(Motion.heroCrossfade) {
            index = (index + step + items.count) % items.count
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 12) {
            ForEach(0..<items.count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.white : Color.white.opacity(0.35))
                    .frame(width: i == index ? 36 : 10, height: 10)
                    .animation(Motion.chrome, value: index)
            }
        }
    }
}

struct HeroBanner: View {
    let item: Catalog.Item

    @Environment(AppStore.self) private var store

    // Pure visual content (no Button) — HeroCarousel wraps it in a single stable
    // focusable Button so the hero can change item without rebuilding the focused
    // control or trapping vertical focus.
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            LinearGradient(
                colors: [
                    .clear,
                    .clear,
                    .black.opacity(0.45),
                    .black.opacity(0.9),
                    .black
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
            heroOverlay
                .padding(.leading, 80)
                .padding(.trailing, 80)
                .padding(.bottom, 112)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()   // #10: full-bleed image stays within its frame, no bleed
    }

    private var heroOverlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(categoryLabel.uppercased())
                .font(.system(size: 15, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(store.accentColor(forCategory: categoryID))
            Text(item.title)
                .font(.system(size: 64, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            HStack(spacing: 18) {
                if let year = item.year { Text(String(year)) }
                if let r = item.runtimeSeconds, r > 0 { Text(formatRuntime(r)) }
                if let byline = item.byline { Text(byline) }
            }
            .font(.system(size: 25, weight: .regular))
            .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: 1200, alignment: .leading)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let url = item.backdropURLParsed {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: 1920, height: 1080),
                contentMode: .fill,   // #10: fill + crop to the full hero, not letterboxed
                placeholder: Color(white: 0.08)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            LinearGradient(
                colors: [store.accentColor(forCategory: categoryID).opacity(0.85), .black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var categoryLabel: String {
        store.featured?.category(id: categoryID)?.displayName ?? "Featured"
    }

    private var categoryID: String {
        switch item.contentType {
        case "tv-series", "tv-special": return "tv-series"
        case "silent-film": return "silent-film"
        case "animation":   return "animation"
        case "newsreel":    return "newsreel"
        case "documentary": return "documentary"
        case "ephemeral":   return "ephemeral"
        case "short-film":  return "short-film"
        default:            return "feature-film"
        }
    }

    private func formatRuntime(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

/// Non-scaling, still-focusable style for the full-width hero banner. A custom
/// ButtonStyle stays focusable on tvOS but, unlike .card, doesn't scale the
/// focused view — so each banner stays exactly one page wide and never overlaps
/// its neighbors at the seam (#10).
private struct HeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - ShelfRow

struct ShelfRow: View {
    let shelf: Featured.Shelf
    let items: [Catalog.Item]

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(store.accentColor(forCategory: shelf.category))
                        .frame(width: 10, height: 10)
                    Text(shelf.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                if let subtitle = shelf.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 28) {
                    ForEach(items) { item in
                        PosterTile(item: item) {
                            router.push(item)
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        // Each shelf is one focus-traversal unit: vertical moves jump
        // row-to-row regardless of horizontal scroll position, so "up"
        // from anywhere in a shelf reliably reaches the row above (and
        // ultimately the hero).
        .focusSection()
    }
}

// MARK: - CategoryTilesRow + CategoryTile

struct CategoryTilesRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var categories: [Featured.Category] = []

    // A category tile must open a real browsing surface — a tile with a
    // handful of items (the classifier emits almost no "documentary") reads
    // as broken (owner report 2026-06-11). Same gate as iOS.
    private let minCount = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Category")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(categories) { cat in
                        Button { router.push(BrowseFilter(category: cat.id)) } label: {
                            CategoryTile(category: cat)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
        .focusSection()
        .task(id: store.dbGeneration) {
            categories = (store.featured?.categories ?? [])
                .filter { (store.db?.browseCount(contentType: $0.id) ?? 0) >= minCount }
        }
    }
}

struct CategoryTile: View {
    let category: Featured.Category

    private var accent: Color { Color(hex: category.accent) ?? .accentColor }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [accent.opacity(0.85), accent.mix(with: .black, 0.4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                Text(category.displayName)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .frame(width: 280, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var iconName: String {
        switch category.id {
        case "feature-film": return "film.fill"
        case "tv-series":    return "tv.fill"
        case "silent-film":  return "moon.stars.fill"
        case "animation":    return "paintbrush.fill"
        case "newsreel":     return "newspaper.fill"
        case "documentary":  return "camera.fill"
        case "ephemeral":    return "books.vertical.fill"
        case "short-film":   return "clock.fill"
        default:             return "sparkles"
        }
    }
}

// MARK: - DecadeTilesRow + DecadeTile

struct DecadeTilesRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var counts: [Int: Int] = [:]

    private var decades: [Int] { counts.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Era")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(decades, id: \.self) { decade in
                        Button { router.push(BrowseFilter(decade: decade)) } label: {
                            DecadeTile(decade: decade, count: countFor(decade))
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
        .focusSection()
        .task(id: store.dbGeneration) { counts = store.dbDecadeCounts() }
    }

    private func countFor(_ decade: Int) -> Int {
        counts[decade] ?? 0
    }
}

struct DecadeTile: View {
    let decade: Int
    let count: Int

    private var era: (label: String, accent: Color) {
        switch decade {
        case ..<1910:     return ("Earliest",   Color(hex: "#C9A66B") ?? .brown)
        case 1910...1927: return ("Silent Era", Color(hex: "#C9A66B") ?? .brown)
        case 1928...1939: return ("Pre-Code",   Color(hex: "#FF5C35") ?? .orange)
        case 1940...1949: return ("Wartime",    Color(hex: "#8A8F98") ?? .gray)
        case 1950...1959: return ("Atomic Age", Color(hex: "#2D5BFF") ?? .blue)
        case 1960...1969: return ("New Wave",   Color(hex: "#FF4D8D") ?? .pink)
        case 1970...1979: return ("Analog",     Color(hex: "#7C5BBA") ?? .purple)
        case 1980...1989: return ("Home Video", Color(hex: "#3FA796") ?? .teal)
        default:          return ("Modern",     Color(hex: "#E8A317") ?? .yellow)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [era.accent.opacity(0.9), era.accent.mix(with: .black, 0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 6) {
                // verbatim: SwiftUI's LocalizedStringKey interpolation formats an
                // Int with locale grouping → "1,960s"; verbatim keeps it "1960s".
                Text(verbatim: "\(decade)s")
                    .font(.system(size: 48, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Text(era.label.uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(count) titles")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(22)
        }
        .frame(width: 260, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


#endif
