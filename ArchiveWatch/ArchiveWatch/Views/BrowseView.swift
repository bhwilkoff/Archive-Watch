import SwiftUI

// Browse: grid + facet chips + sort control. The density view.
// UHF's cue: dense grid with strong focus affordance. Channels' cue:
// focus reveals rich metadata in-situ (earmarked; not yet).

struct BrowseFilter: Hashable, Sendable {
    var category: String? = nil
    var decade: Int? = nil
    var genre: String? = nil
    var collection: String? = nil

    var isEmpty: Bool {
        category == nil && decade == nil && genre == nil && collection == nil
    }
}

enum BrowseSort: String, CaseIterable, Identifiable {
    case popular      = "Popular"
    case alphabetical = "A–Z"
    case newest       = "Newest"
    case oldest       = "Oldest"
    case random       = "Random"
    var id: String { rawValue }
}

struct BrowseView: View {
    @Environment(AppStore.self) private var store
    @State private var filter = BrowseFilter()
    @State private var sort: BrowseSort = .popular
    @State private var shuffleSeed = 0

    init(filter: BrowseFilter = BrowseFilter()) {
        _filter = State(initialValue: filter)
    }

    private var items: [Catalog.Item] {
        guard let all = store.catalog?.items else { return [] }
        let filtered = all.filter { it in
            if let c = filter.category, it.contentType != c { return false }
            if let d = filter.decade, it.decade != d { return false }
            if let g = filter.genre, !it.genres.contains(g) { return false }
            if let k = filter.collection, !it.collections.contains(k) { return false }
            return true
        }
        return sorted(filtered)
    }

    private func sorted(_ xs: [Catalog.Item]) -> [Catalog.Item] {
        switch sort {
        case .popular:      return xs.sorted { ($0.shelves.count, $0.title) > ($1.shelves.count, $1.title) }
        case .alphabetical: return xs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .newest:       return xs.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .oldest:       return xs.sorted { ($0.year ?? 9999) < ($1.year ?? 9999) }
        case .random:
            var rng = SplitMix(seed: UInt64(shuffleSeed))
            var copy = xs
            copy.shuffle(using: &rng)
            return copy
        }
    }

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                FilterChipBar(filter: $filter)
                    .padding(.horizontal, 80)
                    .padding(.top, 16)

                HStack(spacing: 24) {
                    Text(headline)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("\(items.count) titles")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    SortPicker(sort: $sort, shuffle: { shuffleSeed &+= 1 })
                }
                .padding(.horizontal, 80)

                if items.isEmpty {
                    EmptyState()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: cols, spacing: 36) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                CompactPoster(item: item)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var headline: String {
        if filter.isEmpty { return "All Titles" }
        if let d = filter.decade { return "The \(d)s" }
        if let c = filter.category {
            return store.featured?.category(id: c)?.displayName ?? c.capitalized
        }
        if let g = filter.genre { return g.capitalized }
        if let k = filter.collection { return k }
        return "Browse"
    }
}

// MARK: - Filter chip bar

struct FilterChipBar: View {
    @Environment(AppStore.self) private var store
    @Binding var filter: BrowseFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            categoryRow
            decadeRow
        }
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Chip(label: "All", isOn: filter.category == nil, accent: .accentColor) {
                    filter.category = nil
                }
                ForEach(store.featured?.categories ?? []) { cat in
                    let on = filter.category == cat.id
                    let accent = Color(hex: cat.accent) ?? .accentColor
                    Chip(label: cat.shortName ?? cat.displayName, isOn: on, accent: accent) {
                        filter.category = on ? nil : cat.id
                    }
                }
            }
        }
    }

    private var decadeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Chip(label: "All Eras", isOn: filter.decade == nil, accent: .accentColor) {
                    filter.decade = nil
                }
                ForEach(availableDecades, id: \.self) { d in
                    let on = filter.decade == d
                    Chip(label: "\(d)s", isOn: on, accent: .accentColor) {
                        filter.decade = on ? nil : d
                    }
                }
            }
        }
    }

    private var availableDecades: [Int] {
        guard let items = store.catalog?.items else { return [] }
        let ds = Set(items.compactMap { $0.decade })
        return ds.sorted()
    }
}

struct Chip: View {
    let label: String
    let isOn: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(isOn ? accent : Color.white.opacity(0.08))
                .foregroundStyle(isOn ? .white : .white.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(isOn ? accent : Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sort picker

struct SortPicker: View {
    @Binding var sort: BrowseSort
    let shuffle: () -> Void

    var body: some View {
        Menu {
            ForEach(BrowseSort.allCases) { s in
                Button {
                    sort = s
                    if s == .random { shuffle() }
                } label: {
                    if sort == s {
                        Label(s.rawValue, systemImage: "checkmark")
                    } else {
                        Text(s.rawValue)
                    }
                }
            }
            if sort == .random {
                Divider()
                Button("Shuffle again", systemImage: "shuffle", action: shuffle)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                Text("Sort: \(sort.rawValue)")
            }
            .font(.callout)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Compact poster (denser grid version)

struct CompactPoster: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store

    private var isLandscape: Bool {
        item.contentType == "tv-series" || item.contentType == "tv-special" ||
        item.contentType == "newsreel" || item.contentType == "documentary" ||
        item.contentType == "home-movie"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            posterArea
                .frame(width: 200, height: isLandscape ? 112 : 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

            Text(item.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)
            if let year = item.year {
                Text(String(year))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var posterArea: some View {
        if item.hasDesignedArtwork, let url = item.posterURLParsed {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
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
            aspectRatio: isLandscape ? 16.0/9.0 : 2.0/3.0
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
}

// MARK: - Empty state

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.2))
            Text("Nothing here yet")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
            Text("Try a different filter combination.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

// Small seeded RNG for deterministic shuffle
struct SplitMix: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
