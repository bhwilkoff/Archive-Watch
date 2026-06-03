import SwiftUI
import Combine

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

    /// Hero pool from the DB (Decision 017): the most-popular items with real
    /// designed artwork + a usable backdrop/poster, shuffled per launch.
    private func loadHero() -> [Catalog.Item] {
        let pool = store.dbBrowse(sort: .popular, limit: 200, homeOnly: true).filter {
            $0.hasDesignedArtwork &&
            ($0.backdropURLParsed != nil || $0.posterURLParsed != nil)
        }
        var rng = SplitMix(seed: UInt64(heroSeed))
        return Array(pool.shuffled(using: &rng).prefix(7))
    }

    private var homeShelves: [Featured.Shelf] {
        let priority: [String] = [
            "popular-features", "wikidata-pd", "film-noir", "scifi-horror",
            "silent-hall-of-fame", "melies", "video-cellar", "comedy",
            "animation-all", "vintage-cartoons", "nasa", "classic-tv-1960s",
            "classic-tv-1950s", "classic-tv-1970s", "ephemera", "newsreels",
            "educational", "picfixer", "silent-era", "popular-classic-tv",
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
                ContinueWatchingRow()
                CategoryTilesRow()
                // Dedupe across shelves: once a film appears in a shelf
                // earlier in the page, the next shelf gets the NEXT 20
                // items instead of resurfacing the same ones. Keeps Home
                // from looking like five aliases of the same 20 items.
                ForEach(dedupedShelfPayloads()) { payload in
                    ShelfRow(shelf: payload.shelf, items: payload.items)
                }
                HiddenGemsShelf()
                DirectorShelvesSection()
                DecadeTilesRow()
                    .padding(.bottom, 32)
            }
            .padding(.bottom, 80)
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: "\(heroSeed)-\(store.dbGeneration)") { heroItems = loadHero() }
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

    private func dedupedShelfPayloads() -> [ShelfPayload] {
        var used: Set<String> = Set(heroItems.map { $0.archiveID })
        var out: [ShelfPayload] = []
        for shelf in homeShelves {
            let raw = store.items(forShelf: shelf.id)
            var fresh = raw.filter {
                $0.hasDesignedArtwork && !used.contains($0.archiveID)
            }
            // Seeded shuffle: per-shelf (include the id hash) so each
            // shelf gets a different permutation, but stable across
            // body recomputes within a single Home lifetime.
            var rng = SplitMix(
                seed: shelfSeed &+ UInt64(bitPattern: Int64(shelf.id.hashValue))
            )
            fresh.shuffle(using: &rng)
            let taken = Array(fresh.prefix(24))
            guard taken.count >= minPerShelf else { continue }
            for item in taken { used.insert(item.archiveID) }
            out.append(ShelfPayload(shelf: shelf, items: taken))
        }
        return out
    }

}

// MARK: - HeroCarousel + HeroBanner

struct HeroCarousel: View {
    let items: [Catalog.Item]
    // A horizontal paging ScrollView of full-width focusable banners — so a
    // Siri Remote SWIPE pages the hero exactly like every other row in the app
    // (focus moves to the next banner, paging snaps it in). The old design was
    // a single crossfading banner driven by onMoveCommand, which only responded
    // to clickpad PRESSES, not touch swipes (#2).
    @State private var scrolledID: String?
    @FocusState private var focusedID: String?
    @State private var hasClaimedInitialFocus = false
    @State private var autoAdvance = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    private let heroHeight: CGFloat = 720

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    HeroBanner(item: item)
                        .containerRelativeFrame(.horizontal)   // one banner per page
                        .focused($focusedID, equals: item.archiveID)
                        .id(item.archiveID)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledID)
        .frame(height: heroHeight)
        .scrollClipDisabled()
        // One focus-traversal unit so up/down between the hero and the shelves
        // below lands cleanly.
        .focusSection()
        .overlay(alignment: .bottom) {
            pageIndicator.padding(.bottom, 56).allowsHitTesting(false)
        }
        // Auto-advance only while the hero ISN'T focused (user is reading the
        // shelves below) — never yank the page out from under an active swipe.
        .onReceive(autoAdvance) { _ in
            guard focusedID == nil, items.count > 1 else { return }
            let next = (currentIndex + 1) % items.count
            withAnimation(Motion.heroCrossfade) { scrolledID = items[next].archiveID }
        }
        // Claim focus + initial page ONCE on first appearance.
        .task {
            guard !hasClaimedInitialFocus, let first = items.first else { return }
            hasClaimedInitialFocus = true
            scrolledID = first.archiveID
            try? await Task.sleep(for: .milliseconds(60))
            focusedID = first.archiveID
        }
        // Keep the page indicator in step when focus drives the scroll.
        .onChange(of: focusedID) { _, new in
            if let new { scrolledID = new }
        }
    }

    private var currentIndex: Int {
        items.firstIndex { $0.archiveID == scrolledID } ?? 0
    }

    private var pageIndicator: some View {
        HStack(spacing: 12) {
            ForEach(0..<items.count, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex ? Color.white : Color.white.opacity(0.35))
                    .frame(width: i == currentIndex ? 36 : 10, height: 10)
                    .animation(Motion.chrome, value: currentIndex)
            }
        }
    }
}

struct HeroBanner: View {
    let item: Catalog.Item

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.push(item) } label: {
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
        }
        .buttonStyle(.card)
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
        if item.hasDesignedArtwork, let url = item.backdropURLParsed ?? item.posterURLParsed {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: 1920, height: 1080),
                contentMode: .fit,
                placeholder: Color(white: 0.08)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Category")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(store.featured?.categories ?? []) { cat in
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
