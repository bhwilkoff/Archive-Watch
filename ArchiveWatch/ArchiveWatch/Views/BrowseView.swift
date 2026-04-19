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
    @Environment(Router.self) private var router
    @State private var filter = BrowseFilter()
    @State private var sort: BrowseSort = .popular
    @State private var shuffleSeed = 0
    @State private var filtersShown = false
    // True when the view was pushed with a specific filter (from a
    // collection tile, category tile, or decade tile). In that context
    // the user has already narrowed the catalog deliberately — showing
    // the Filters button + chip bar is redundant UI noise, so we hide
    // both entirely. They can still sort.
    private let isPreFiltered: Bool

    init(filter: BrowseFilter = BrowseFilter()) {
        _filter = State(initialValue: filter)
        _filtersShown = State(initialValue: false)
        self.isPreFiltered = !filter.isEmpty
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
                HStack(spacing: 20) {
                    Text(headline)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("\(items.count) titles")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if !isPreFiltered {
                        Button {
                            withAnimation(Motion.chrome) { filtersShown.toggle() }
                        } label: {
                            Label(filtersShown ? "Hide Filters" : "Filters",
                                  systemImage: filtersShown ? "chevron.up" : "line.3.horizontal.decrease")
                                .font(.callout)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.card)
                    }
                    SortPicker(sort: $sort, shuffle: { shuffleSeed &+= 1 })
                }
                .padding(.horizontal, 80)
                .padding(.top, 24)

                if filtersShown && !isPreFiltered {
                    FilterChipBar(filter: $filter)
                        .padding(.horizontal, 80)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if items.isEmpty {
                    EmptyState()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 44) {
                        ForEach(items) { item in
                            CompactTile(item: item) {
                                router.push(.item(item))
                            }
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
        }
        .buttonStyle(ChipButtonStyle(accent: accent, isOn: isOn))
        .focusEffectDisabled()
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
            .foregroundStyle(.white)
            .glassBackground(shape: Capsule(), isOn: false, accent: .accentColor)
        }
    }
}

// MARK: - Compact tile (Browse / Search grid)
//
// Button wraps only the poster art. The title + year sit below as
// siblings so .buttonStyle(.card) never clips them — the same
// structural fix we apply to PosterTile.

struct CompactTile: View {
    let item: Catalog.Item
    let action: () -> Void

    @Environment(AppStore.self) private var store
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat  = 200
    private let cardHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                PosterArt(item: item, width: cardWidth, height: cardHeight)
            }
            .buttonStyle(.card)
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.78)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                if let year = item.year {
                    Text(String(year))
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: cardWidth, alignment: .leading)
            .opacity(isFocused ? 1.0 : 0.85)
            .animation(Motion.focus, value: isFocused)
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
