import SwiftUI

// Browse: grid + facet chips + sort control. The density view.
// UHF's cue: dense grid with strong focus affordance. Channels' cue:
// focus reveals rich metadata in-situ (earmarked; not yet).

struct BrowseFilter: Hashable, Sendable {
    var category: String? = nil
    var decade: Int? = nil
    var genre: String? = nil
    var collection: String? = nil
    var person: String? = nil   // #4: films featuring this cast member / director

    var isEmpty: Bool {
        category == nil && decade == nil && genre == nil && collection == nil && person == nil
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
    // Memoized filtered/sorted items. Recomputed ONLY when filter,
    // sort, shuffleSeed, or catalog identity changes — NOT on every
    // body render. The old computed-property pattern re-filtered
    // 31,783 items on focus changes and locked the UI solid.
    @State private var items: [Catalog.Item] = []
    // Real catalog total for the current filter (shown in the header even though
    // only a page is loaded). Pagination appends pages as you scroll (#infinite).
    @State private var totalCount = 0
    @State private var loadingMore = false
    private let pageSize = 300
    @FocusState private var focusedArchiveID: String?
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

    // Cap for the non-paginable cases (collection / person / random) — those are
    // post-filtered / FTS / shuffled, so they fetch a single capped set. The
    // paginable cases (All Titles / type / decade / genre) load page-by-page.
    private static let filteredGridCap = 2000

    private var dbSort: CatalogDB.Sort {
        switch sort {
        case .popular, .random: return .popular
        case .alphabetical:     return .alphabetical
        case .newest:           return .newest
        case .oldest:           return .oldest
        }
    }

    /// Paginable = SQL-filterable filters in a stable sort. Collection + person
    /// browse are post-filtered / FTS, and random can't paginate meaningfully,
    /// so those keep the single capped fetch.
    private var paginable: Bool {
        filter.collection == nil && filter.person == nil && sort != .random
    }

    /// Load the first page (or the whole capped set for non-paginable filters)
    /// plus the REAL total for the header — so the page shows "36,944 titles"
    /// even though only a page is in memory.
    private func reload() {
        if paginable {
            items = store.dbBrowse(contentType: filter.category, decade: filter.decade,
                                   genre: filter.genre, sort: dbSort, limit: pageSize, offset: 0)
            totalCount = store.dbBrowseCount(contentType: filter.category,
                                             decade: filter.decade, genre: filter.genre)
        } else {
            items = computeItems()
            totalCount = items.count
        }
    }

    /// Append the next page as the user scrolls toward the end (#infinite scroll).
    /// The SQLite read runs on main (fast, single-connection-safe); the heavy
    /// JSON decode runs off-main so fast scrolling doesn't hitch.
    private func loadMore() {
        guard paginable, !loadingMore, items.count < totalCount else { return }
        loadingMore = true
        let jsons = store.dbBrowsePageJSON(contentType: filter.category, decade: filter.decade,
                                           genre: filter.genre, sort: dbSort,
                                           limit: pageSize, offset: items.count)
        Task { @MainActor in
            let decoded = await Task.detached { CatalogDB.decodeItems(jsons) }.value
            let have = Set(items.map(\.archiveID))
            items.append(contentsOf: decoded.filter { have.contains($0.archiveID) == false })
            loadingMore = false
        }
    }

    /// Single capped fetch for the non-paginable cases (collection / person / random).
    private func computeItems() -> [Catalog.Item] {
        if let p = filter.person {   // #4: person browse uses the FTS names index
            var page = store.dbByPerson(p)
            if sort == .random {
                var rng = SplitMix(seed: UInt64(shuffleSeed)); page.shuffle(using: &rng)
            }
            return page
        }
        var page = store.dbBrowse(contentType: filter.category, decade: filter.decade,
                                  genre: filter.genre, sort: dbSort, limit: Self.filteredGridCap)
        if let k = filter.collection {
            page = page.filter { $0.collections.contains(k) }
        }
        if sort == .random {
            var rng = SplitMix(seed: UInt64(shuffleSeed))
            page.shuffle(using: &rng)
        }
        return page
    }

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    Text(headline)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("\(totalCount.formatted()) titles")
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
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 48) {
                        ForEach(items) { item in
                            CompactTile(item: item) {
                                router.push(item)
                            }
                            .focused($focusedArchiveID, equals: item.archiveID)
                            .onAppear {
                                // Prefetch the next page when the last tile scrolls in.
                                if item.archiveID == items.last?.archiveID { loadMore() }
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            // Compute the first page once the view appears so we don't
            // block the navigation push animation. Then defer a tick
            // for layout + claim initial focus on the top-left cell.
            reload()
            try? await Task.sleep(for: .milliseconds(40))
            focusedArchiveID = items.first?.archiveID
        }
        .onChange(of: filter) { _, _ in reload() }
        .onChange(of: sort) { _, _ in reload() }
        .onChange(of: shuffleSeed) { _, _ in reload() }
        // Re-query when the DB swaps (seed → full) or the adult toggle flips.
        .onChange(of: store.dbGeneration) { _, _ in reload() }
    }

    private var headline: String {
        if filter.isEmpty { return "All Titles" }
        if let d = filter.decade { return "The \(d)s" }
        if let c = filter.category {
            return store.featured?.category(id: c)?.displayName ?? c.capitalized
        }
        if let g = filter.genre { return g.capitalized }
        if let k = filter.collection { return CollectionMetadata.title(for: k) }
        if let p = filter.person { return p }   // #4
        return "Browse"
    }
}

// MARK: - Filter chip bar

struct FilterChipBar: View {
    @Environment(AppStore.self) private var store
    @Binding var filter: BrowseFilter
    @State private var decades: [Int] = []
    @State private var genres: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            categoryRow
            decadeRow
            genreRow
        }
        .task(id: store.dbGeneration) {
            decades = store.dbDecadeCounts().keys.sorted()
            genres = store.dbTopGenres()
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
                ForEach(decades, id: \.self) { d in
                    let on = filter.decade == d
                    Chip(label: "\(d)s", isOn: on, accent: .accentColor) {
                        filter.decade = on ? nil : d
                    }
                }
            }
        }
    }

    private var genreRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Chip(label: "All Genres", isOn: filter.genre == nil, accent: .accentColor) {
                    filter.genre = nil
                }
                ForEach(genres, id: \.self) { g in
                    let on = filter.genre == g
                    Chip(label: g, isOn: on, accent: .accentColor) {
                        filter.genre = on ? nil : g
                    }
                }
            }
        }
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

/// A labeled, single-select horizontal row of large pills — the native-feeling
/// filter pattern from Browse, reused by the channel/playlist creators so they
/// don't fall back to tiny tvOS Pickers. Tapping the active pill clears it (back
/// to "Any"). `T: Hashable` so options key off themselves.
struct PillSelectRow<T: Hashable>: View {
    let title: String
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T?
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    Chip(label: "Any", isOn: selection == nil, accent: accent) { selection = nil }
                    ForEach(options, id: \.self) { opt in
                        let on = selection == opt
                        Chip(label: label(opt), isOn: on, accent: accent) {
                            selection = on ? nil : opt
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
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
        VStack(alignment: .leading, spacing: 24) {
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
