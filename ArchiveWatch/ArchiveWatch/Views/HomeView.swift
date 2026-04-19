import SwiftUI
import SwiftData
import Combine

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
    // from the full pool of well-enriched items. Hero must have real
    // designed artwork with a usable backdrop or poster; we weight the
    // pool toward items that appear on multiple shelves (a decent
    // popularity proxy) then randomize within the top strata so heroes
    // never feel locked to the same handful on every launch.
    private var heroItems: [Catalog.Item] {
        guard let all = store.catalog?.items else { return [] }
        let pool = all.filter {
            $0.hasDesignedArtwork &&
            ($0.backdropURLParsed != nil || $0.posterURLParsed != nil)
        }
        // Top 150 by shelf count is still a wide enough net to feel
        // serendipitous without surfacing no-art ephemera.
        let stratum = pool.sorted { $0.shelves.count > $1.shelves.count }.prefix(150)
        var rng = SplitMix(seed: UInt64(heroSeed))
        return Array(stratum.shuffled(using: &rng).prefix(7))
    }

    private var homeShelves: [Featured.Shelf] {
        // Editor's Picks omitted from Home — surfaced from Collections tab.
        // Priority order favors populated, well-enriched shelves.
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
                    // Prefer items with real artwork at the front of each shelf
                    // so shelves don't open with a wall of procedural cards.
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

    /// Stable sort that puts items with designed art before procedural items,
    /// preserving the underlying order within each bucket.
    private func sortByArtwork(_ items: [Catalog.Item]) -> [Catalog.Item] {
        let withArt    = items.filter { $0.hasDesignedArtwork }
        let withoutArt = items.filter { !$0.hasDesignedArtwork }
        return withArt + withoutArt
    }
}

// MARK: - Hero Carousel

struct HeroCarousel: View {
    let items: [Catalog.Item]
    @State private var index: Int = 0
    @State private var autoAdvanceTimer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Banners stacked, only the current one visible
            ForEach(Array(items.enumerated()), id: \.element.archiveID) { i, item in
                HeroBanner(item: item)
                    .opacity(i == index ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6), value: index)
            }
            // Page-dot indicators
            HStack(spacing: 10) {
                ForEach(0..<items.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.white : Color.white.opacity(0.3))
                        .frame(width: i == index ? 28 : 8, height: 6)
                        .animation(.easeOut(duration: 0.3), value: index)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(height: 620)
        .onReceive(autoAdvanceTimer) { _ in
            withAnimation { index = (index + 1) % items.count }
        }
    }
}

// MARK: - Continue Watching row

struct ContinueWatchingRow: View {
    @Environment(Router.self) private var router
    let entries: [(item: Catalog.Item, progress: WatchProgress)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue Watching")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
                    ForEach(entries, id: \.item.archiveID) { entry in
                        Button { router.push(.item(entry.item)) } label: {
                            ContinueWatchingCard(item: entry.item, progress: entry.progress)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
    }
}

struct ContinueWatchingCard: View {
    let item: Catalog.Item
    let progress: WatchProgress
    @Environment(AppStore.self) private var store

    private var isLandscape: Bool {
        item.contentType == "tv-series" || item.contentType == "tv-special" ||
        item.contentType == "newsreel" || item.contentType == "documentary" ||
        item.contentType == "home-movie"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottom) {
                posterArea
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 80)
                }
                VStack(spacing: 6) {
                    Spacer()
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        Text(remainingLabel)
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    ProgressBar(fraction: progress.fraction)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
            .frame(width: 320, height: isLandscape ? 180 : 240)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 320, alignment: .leading)
        }
    }

    @ViewBuilder
    private var posterArea: some View {
        // Prefer backdrop for in-progress cards (scene-like).
        let url = item.backdropURLParsed ?? item.posterURLParsed
        if item.hasDesignedArtwork, let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: procedural
                }
            }
        } else {
            procedural
        }
    }

    private var procedural: some View {
        ProceduralPoster(
            item: item,
            accent: store.accentColor(forCategory: categoryID),
            aspectRatio: isLandscape ? 16.0/9.0 : 4.0/3.0
        )
    }

    private var categoryID: String {
        switch item.contentType {
        case "tv-series", "tv-special": return "tv-series"
        case "silent-film": return "silent-film"
        case "animation": return "animation"
        case "newsreel": return "newsreel"
        case "documentary": return "documentary"
        case "ephemeral": return "ephemeral"
        case "short-film": return "short-film"
        default: return "feature-film"
        }
    }

    private var remainingLabel: String {
        if progress.durationSeconds > 0 {
            let remaining = max(0, Int(progress.durationSeconds - progress.positionSeconds))
            let m = remaining / 60
            if m >= 60 { return "\(m / 60)h \(m % 60)m left" }
            return "\(m)m left"
        }
        let watched = Int(progress.positionSeconds) / 60
        return "\(watched)m watched"
    }
}

// MARK: - Hero Banner

struct HeroBanner: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.push(.item(item)) } label: {
            ZStack(alignment: .bottomLeading) {
                backdrop
                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.6), .black],
                    startPoint: .top, endPoint: .bottom
                )
                HStack(alignment: .bottom, spacing: 48) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(categoryLabel.uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(store.accentColor(forCategory: categoryID))
                        Text(item.title)
                            .font(.system(size: 60, weight: .heavy, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                        HStack(spacing: 16) {
                            if let year = item.year { Text(String(year)) }
                            if let r = item.runtimeSeconds, r > 0 { Text(formatRuntime(r)) }
                            if let byline = item.byline { Text(byline) }
                        }
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.leading, 80)
                    .padding(.bottom, 40)
                    .padding(.trailing, 40)
                    Spacer()
                }
            }
            .frame(height: 620)
        }
        .buttonStyle(.plain)
    }

    private var backdrop: some View {
        Group {
            if item.hasDesignedArtwork, let url = item.backdropURLParsed ?? item.posterURLParsed {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            // Align to the upper third — faces and subjects
                            // on movie backdrops are almost always in the
                            // top half, so center-crop (the default) often
                            // loses them. `.top` keeps heads in frame.
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .clipped()
                    default:
                        Color(white: 0.1)
                    }
                }
            } else {
                LinearGradient(
                    colors: [store.accentColor(forCategory: categoryID).opacity(0.8), .black],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
    }

    private var categoryLabel: String {
        store.featured?.category(id: categoryID)?.displayName ?? "Featured"
    }
    private var categoryID: String {
        switch item.contentType {
        case "tv-series", "tv-special": return "tv-series"
        case "silent-film": return "silent-film"
        case "animation": return "animation"
        case "newsreel": return "newsreel"
        case "documentary": return "documentary"
        case "ephemeral": return "ephemeral"
        case "short-film": return "short-film"
        default: return "feature-film"
        }
    }
    private func formatRuntime(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

// MARK: - Category quick-access tiles

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
                        Button { router.push(.filter(BrowseFilter(category: cat.id))) } label: {
                            CategoryTile(category: cat)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
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
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(category.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
        }
        .frame(width: 260, height: 150)
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

// MARK: - Decade tiles row

struct DecadeTilesRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var decades: [Int] {
        guard let items = store.catalog?.items else { return [] }
        return Set(items.compactMap { $0.decade }).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Era")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(decades, id: \.self) { decade in
                        Button { router.push(.filter(BrowseFilter(decade: decade))) } label: {
                            DecadeTile(decade: decade, count: countFor(decade))
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
    }

    private func countFor(_ decade: Int) -> Int {
        store.catalog?.items.filter { $0.decade == decade }.count ?? 0
    }
}

struct DecadeTile: View {
    let decade: Int
    let count: Int

    private var era: (label: String, accent: Color) {
        switch decade {
        case ..<1910:  return ("Earliest",    Color(hex: "#C9A66B") ?? .brown)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("\(decade)s")
                    .font(.system(size: 44, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Text(era.label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(count) titles")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(20)
        }
        .frame(width: 220, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Shelf row (the per-shelf horizontal list) — was in the old HomeView

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
                LazyHStack(spacing: 28) {
                    ForEach(items) { item in
                        Button { router.push(.item(item)) } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
    }
}

// MARK: - PosterCard

struct PosterCard: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(\.isFocused) private var isFocused

    // Uniform portrait 2:3 across all content types. Landscape-native
    // posters (TV, newsreels) are center-cropped into the poster frame
    // so shelves stay rhythmically aligned.
    private let cardWidth: CGFloat  = 240
    private let cardHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                posterArea
                // Category chip overlays the top-left of the poster ONLY.
                // No synopsis peek — too noisy as focus moves shelf-to-shelf.
                if let chip = categoryChipLabel {
                    Text(chip.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.18), value: isFocused)

            // Title gets up to 2 lines at a compact size so the vast
            // majority of real-world film/TV titles fit fully without
            // truncation. `minimumScaleFactor` lets SwiftUI shrink a
            // shade further before falling back to tail truncation —
            // and tail truncation itself breaks on whole words.
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let year = item.year { Text(String(year)) }
                    if let r = item.runtimeSeconds, r > 0 {
                        Text("·")
                        Text(formatRuntime(r))
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: cardWidth, alignment: .leading)
        }
    }

    private var categoryChipLabel: String? {
        switch item.contentType {
        case "tv-series", "tv-special": return "TV"
        case "silent-film":             return "Silent"
        case "animation":               return "Animation"
        case "newsreel":                return "Newsreel"
        case "documentary":             return "Doc"
        case "ephemeral":               return "Ephemeral"
        case "short-film":              return "Short"
        default:                        return nil
        }
    }

    @ViewBuilder
    private var posterArea: some View {
        if item.hasDesignedArtwork, let url = item.posterURLParsed {
            AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .empty, .failure: procedural
                @unknown default: procedural
                }
            }
        } else {
            procedural
        }
    }

    private var procedural: some View {
        ProceduralPoster(
            item: item,
            accent: store.accentColor(forCategory: categoryID),
            aspectRatio: 2.0/3.0
        )
    }

    private var categoryID: String {
        switch item.contentType {
        case "tv-series", "tv-special": return "tv-series"
        case "silent-film": return "silent-film"
        case "animation": return "animation"
        case "newsreel": return "newsreel"
        case "documentary": return "documentary"
        case "ephemeral": return "ephemeral"
        case "short-film": return "short-film"
        default: return "feature-film"
        }
    }

    private func formatRuntime(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
