#if os(tvOS)
import SwiftUI

// Dedicated TV Shows browser — one grid cell per series card, tap
// pushes SeriesDetailView. Separate tab from Browse (which is
// film-focused) so TV content doesn't get lost among 25k films.
//
// Series are fronted by their TMDb poster when we have one and
// Archive's thumbnail otherwise, same art cascade as films. Filter
// chips let the user narrow to a decade or genre.
//
// Backed by AppStore.seriesCards — the precomputed list of items
// with contentType == "tv-series". That list is built once on
// catalog assignment and is O(1) to read here.

struct TVShowsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var filter = BrowseFilter()
    @State private var sort: BrowseSort = .popular
    @State private var shuffleSeed = 0
    @State private var items: [Catalog.Item] = []
    @State private var specialsCount = 0
    @FocusState private var focusedArchiveID: String?

    private let cols = Array(repeating: GridItem(.fixed(240), spacing: 28), count: 5)

    private func computeItems() -> [Catalog.Item] {
        let pool = store.dbSeriesCards().filter { it in
            if let d = filter.decade, it.decade != d { return false }
            if let g = filter.genre, !it.genres.contains(g) { return false }
            return true
        }
        switch sort {
        case .popular:
            // Series carry no popularityScore, so fall back to how complete a
            // show is (available episodes) — the richest series lead the grid.
            return pool.sorted { a, b in
                let pa = a.popularityScore ?? 0, pb = b.popularityScore ?? 0
                if pa != pb { return pa > pb }
                return (a.episodesCount ?? 0) > (b.episodesCount ?? 0)
            }
        case .rating:
            // Series cards rarely carry an IMDb rating; rated shows lead,
            // the rest keep their episode-depth order behind them. Compared
            // field-by-field rather than as a tuple — the tuple form times out
            // the type-checker on the released toolchain.
            return pool.sorted { a, b in
                let ra = a.imdbRating ?? -1, rb = b.imdbRating ?? -1
                if ra != rb { return ra > rb }
                let va = a.imdbVotes ?? 0, vb = b.imdbVotes ?? 0
                if va != vb { return va > vb }
                return (a.episodesCount ?? 0) > (b.episodesCount ?? 0)
            }
        case .alphabetical:
            return pool.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .newest:
            return pool.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .oldest:
            return pool.sorted { ($0.year ?? 9999) < ($1.year ?? 9999) }
        case .random:
            var rng = SplitMix(seed: UInt64(shuffleSeed))
            var copy = pool
            copy.shuffle(using: &rng)
            return copy
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .padding(.horizontal, 80)
                    .padding(.top, 24)
                    // Reach Sort by pressing Up from any grid cell, not just the
                    // rightmost column (tvOS focus section).
                    .focusSection()

                if items.isEmpty {
                    EmptyState()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 44) {
                        ForEach(items) { item in
                            SeriesCardTile(item: item) {
                                router.push(item)
                            }
                            .focused($focusedArchiveID, equals: item.archiveID)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            items = computeItems()
            specialsCount = store.dbTVSpecialsCount()
            try? await Task.sleep(for: .milliseconds(40))
            focusedArchiveID = items.first?.archiveID
        }
        .onChange(of: filter) { _, _ in items = computeItems() }
        .onChange(of: sort) { _, _ in items = computeItems() }
        .onChange(of: shuffleSeed) { _, _ in items = computeItems() }
        .onChange(of: store.dbGeneration) { _, _ in
            items = computeItems()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TV Shows")
                    .font(.system(size: 54, weight: .heavy, design: .serif))  // #6: match every other page
                    .foregroundStyle(.white)
                Text("\(items.count) series to settle into")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            // Standalone TV specials/episodes not folded into a series live here,
            // OUT of Movies (owner directive 2026-06-18). Shown only when present.
            if specialsCount > 0 {
                Button {
                    router.tvShowsPath.append(BrowseFilter(category: "tv-special"))
                } label: {
                    Label("TV Specials", systemImage: "tv")
                }
                .padding(.trailing, 8)
            }
            SortPicker(sort: $sort, shuffle: { shuffleSeed &+= 1 })
        }
    }
}

// MARK: - SeriesCardTile

struct SeriesCardTile: View {
    let item: Catalog.Item
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat  = 240
    private let cardHeight: CGFloat = 360   // 2:3 poster

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: action) {
                posterArt
            }
            .buttonStyle(.card)
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let yearLabel = seriesYearLabel {
                        Text(yearLabel)
                    }
                    if let n = item.episodesCount, n > 0 {
                        Text("·")
                        Text("\(n) episode\(n == 1 ? "" : "s")")
                    }
                }
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: cardWidth, alignment: .leading)
            .opacity(isFocused ? 1.0 : 0.85)
            .animation(Motion.focus, value: isFocused)
        }
    }

    private var seriesYearLabel: String? {
        switch (item.year, item.yearEnd) {
        case let (s?, e?) where s == e: return String(s)
        case let (s?, e?): return "\(s)–\(e)"
        case let (s?, _): return String(s)
        default: return nil
        }
    }

    @ViewBuilder
    private var posterArt: some View {
        if let url = item.posterURLParsed {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: cardWidth * 2, height: cardHeight * 2),
                contentMode: .fill,
                placeholder: Color(white: 0.08),
            )
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.08))
                .frame(width: cardWidth, height: cardHeight)
                .overlay(
                    Image(systemName: "tv")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.25))
                )
        }
    }
}

#endif
