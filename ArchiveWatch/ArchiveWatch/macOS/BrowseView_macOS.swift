#if os(macOS)
import SwiftUI

// Browse grid with a consolidated facet/sort Filter menu in the toolbar; paginated via
// store.browse. The "Movies" section narrows by type/decade/sort; "TV" uses TVBrowseView.

struct BrowseView: View {
    let contentType: String?
    let title: String
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var items: [Catalog.Item] = []
    @State private var typeFilter: String? = nil      // narrows WITHIN the section (parity with iOS)
    @State private var decade: Int? = nil
    @State private var sort: CatalogDB.Sort = .popular
    @State private var total = 0
    @State private var offset = 0
    // Metadata-expansion facets (Decision 046) for the Filter menu.
    @State private var keywordFacets: [String] = []
    @State private var studioFacets: [String] = []
    private let page = 120

    // The effective content type: the section's fixed type, or the user-chosen narrowing.
    private var effectiveType: String? { contentType ?? typeFilter }
    private var filterActive: Bool { typeFilter != nil || decade != nil || sort != .popular }

    private let types: [(String, String?)] = [
        ("All Types", nil), ("Films", "feature-film"), ("Silent", "silent-film"),
        ("Animation", "animation"), ("Shorts", "short-film"),
        ("Newsreels", "newsreel"), ("Documentary", "documentary"), ("Ephemera", "ephemeral")]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)],
                      spacing: 18) {
                ForEach(items) { item in
                    PosterCard(item: item)
                        .onAppear { if item.id == items.last?.id { loadMore() } }
                }
            }
            .padding()
            if items.isEmpty && store.isReady {
                ContentUnavailableView("No titles", systemImage: "film.stack").padding(.top, 60)
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(total > 0 ? "\(total.formatted()) titles" : "")
        .toolbar {
            ToolbarItem {
                Menu {
                    // Only offer the Type narrowing on the generic "Movies" surface (a fixed-type
                    // section shouldn't let you switch type out from under its own title).
                    if contentType == nil {
                        Picker("Type", selection: $typeFilter) {
                            ForEach(types, id: \.1) { Text($0.0).tag($0.1) }
                        }
                    }
                    Picker("Decade", selection: $decade) {
                        Text("All Decades").tag(Int?.none)
                        ForEach(decadeList, id: \.self) { d in Text(verbatim: "\(d)s").tag(Int?.some(d)) }
                    }
                    Picker("Sort", selection: $sort) {
                        Text("Popular").tag(CatalogDB.Sort.popular)
                        Text("Top Rated").tag(CatalogDB.Sort.rating)
                        Text("A–Z").tag(CatalogDB.Sort.alphabetical)
                        Text("Newest").tag(CatalogDB.Sort.newest)
                        Text("Oldest").tag(CatalogDB.Sort.oldest)
                    }
                    // Decision 046: keyword + studio facets open a dedicated filtered
                    // grid (join-table queries, not part of this paged section).
                    if !keywordFacets.isEmpty {
                        Menu("Keyword") {
                            ForEach(keywordFacets, id: \.self) { k in
                                Button(k.capitalized) {
                                    router.path.append(BrowseFilterRoute(title: k.capitalized, keyword: k))
                                }
                            }
                        }
                    }
                    if !studioFacets.isEmpty {
                        Menu("Studio") {
                            ForEach(studioFacets, id: \.self) { s in
                                Button(s) {
                                    router.path.append(BrowseFilterRoute(title: s, studio: s))
                                }
                            }
                        }
                    }
                    if filterActive {
                        Button("Clear Filters", role: .destructive) {
                            typeFilter = nil; decade = nil; sort = .popular
                        }
                    }
                } label: {
                    Label("Filter", systemImage: filterActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .help("Filter by type, decade, or sort order")
            }
        }
        .task(id: store.dbVersion) {
            reset()
            keywordFacets = store.db?.topKeywords() ?? []
            studioFacets = store.db?.topStudios() ?? []
        }
        .onChange(of: typeFilter) { _, _ in reset() }
        .onChange(of: decade) { _, _ in reset() }
        .onChange(of: sort) { _, _ in reset() }
    }

    private var decadeList: [Int] { (store.db?.decadeCounts().keys.sorted(by: >)) ?? [] }

    private func reset() {
        offset = 0
        total = store.db?.browseCount(contentType: effectiveType, decade: decade, genre: nil, year: nil) ?? 0
        items = store.browse(contentType: effectiveType, decade: decade, genre: nil, year: nil,
                             sort: sort, limit: page, offset: 0)
        offset = items.count
    }

    private func loadMore() {
        guard items.count < total else { return }
        let next = store.browse(contentType: effectiveType, decade: decade, genre: nil, year: nil,
                               sort: sort, limit: page, offset: offset)
        items.append(contentsOf: next)
        offset += next.count
    }
}

// MARK: - TV browse (series grid + sort + TV Specials surface)

struct TVBrowseView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var series: [Catalog.Item] = []
    @State private var specialsCount = 0
    @State private var sort: CatalogDB.Sort = .popular

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Standalone TV specials/episodes not folded into a series (Decision 036) — OUT of
                // the series grid, surfaced as their own destination when present.
                if specialsCount > 0 {
                    Button {
                        router.path.append(BrowseFilterRoute(title: "TV Specials", contentType: "tv-special"))
                    } label: {
                        HStack {
                            Label("TV Specials", systemImage: "tv")
                            Spacer()
                            Text("\(specialsCount)").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain).padding(.horizontal)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)],
                          spacing: 18) {
                    ForEach(sortedSeries) { PosterCard(item: $0) }
                }
                .padding()
            }
            if series.isEmpty && store.isReady {
                ContentUnavailableView("No series", systemImage: "tv").padding(.top, 60)
            }
        }
        .navigationTitle("TV")
        .navigationSubtitle(series.isEmpty ? "" : "\(series.count) series")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Sort", selection: $sort) {
                        Text("Popular").tag(CatalogDB.Sort.popular)
                        Text("Top Rated").tag(CatalogDB.Sort.rating)
                        Text("A–Z").tag(CatalogDB.Sort.alphabetical)
                    }
                } label: {
                    Label("Filter", systemImage: sort == .popular
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task(id: store.dbVersion) {
            series = store.seriesCards()
            specialsCount = store.tvSpecialsCount()
        }
    }

    // Series cards carry no popularity, so sort them client-side by the chosen key.
    private var sortedSeries: [Catalog.Item] {
        switch sort {
        case .alphabetical: series.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating:       series.sorted { ($0.imdbRating ?? 0) > ($1.imdbRating ?? 0) }
        default:            series
        }
    }
}
#endif
