import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progressRecords: [WatchProgress]
    @Query private var favorites: [Favorite]

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

    private var hero: Catalog.Item? {
        store.items(forShelf: "editors-picks").first(where: { $0.hasDesignedArtwork })
            ?? store.items(forShelf: "editors-picks").first
            ?? store.catalog?.items.first(where: { $0.hasDesignedArtwork })
    }

    private var homeShelves: [Featured.Shelf] {
        let priority: [String] = ["editors-picks", "wikidata-pd", "popular-features",
                                  "silent-era", "government-films", "classic-cartoons",
                                  "noir", "horror"]
        let allShelves = store.featured?.shelves ?? []
        return priority.compactMap { id in allShelves.first(where: { $0.id == id }) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 48) {
                if let hero {
                    HeroBanner(item: hero)
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
                    let items = store.items(forShelf: shelf.id)
                    if !items.isEmpty {
                        ShelfRow(shelf: shelf, items: Array(items.prefix(20)))
                    }
                }
                DecadeTilesRow()
                    .padding(.bottom, 32)
            }
            .padding(.top, 24)
            .padding(.bottom, 80)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Continue Watching row

struct ContinueWatchingRow: View {
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
                        NavigationLink(value: entry.item) {
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
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
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

    var body: some View {
        NavigationLink(value: item) {
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
                        if let synopsis = item.displaySynopsis {
                            Text(synopsis)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(3)
                                .frame(maxWidth: 800, alignment: .leading)
                        }
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
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color(white: 0.1)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Category")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(store.featured?.categories ?? []) { cat in
                        NavigationLink(value: BrowseFilter(category: cat.id)) {
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
                        NavigationLink(value: BrowseFilter(decade: decade)) {
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
                        NavigationLink(value: item) {
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
            ZStack(alignment: .bottom) {
                posterArea
                // Focus peek — metadata strip slides up from the bottom
                // on focus. Channels pattern, scaled to card.
                if isFocused, let preview = focusPreviewText {
                    VStack(spacing: 0) {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 120)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        if !focusChips.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(focusChips, id: \.self) { chip in
                                    Text(chip.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.18))
                                        .clipShape(Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(3)
                    }
                    .padding(12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.18), value: isFocused)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
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

    private var focusPreviewText: String? {
        if let s = item.displaySynopsis { return s }
        if let b = item.byline { return b }
        return nil
    }

    private var focusChips: [String] {
        var out: [String] = []
        if !item.genres.isEmpty { out.append(item.genres[0]) }
        if let s = item.seriesName, s != item.title { out.append("Series") }
        if item.enrichmentTier == "fullyEnriched" { /* skip, default */ }
        return Array(out.prefix(2))
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
