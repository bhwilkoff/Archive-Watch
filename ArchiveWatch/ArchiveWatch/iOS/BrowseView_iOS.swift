#if os(iOS)
import SwiftUI

// Browse: a segmented scope (Films / TV / Collections) over the catalog.
//  • Films: poster grid + native facet/sort Menu, infinite scroll.
//  • TV: series-card grid → SeriesDetailView (episodes).
//  • Collections: curated collection list → CollectionGridView.
// The touch idiom for the tvOS focus-chip facets + separate TV/Collections tabs.
struct BrowseView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    enum Scope: String, CaseIterable, Identifiable {
        case films = "Films", tv = "TV", collections = "Collections"
        var id: String { rawValue }
    }
    @State private var scope: Scope = .films
    /// Set when the iPad sidebar opens one scope directly (IPAD-DESIGN §10.2):
    /// the sidebar is the scope control, so no segmented control is drawn.
    var fixedScope: Scope? = nil

    init(fixedScope: Scope? = nil) {
        self.fixedScope = fixedScope
        _scope = State(initialValue: fixedScope ?? .films)
    }

    // Films state
    @State private var contentType: String? = nil
    @State private var decade: Int? = nil
    @State private var runtime: RuntimeBand? = nil
    @State private var sort: CatalogDB.Sort = .popular
    @State private var items: [Catalog.Item] = []
    @State private var page = 0
    private let pageSize = 60
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    // TV state
    @State private var series: [Catalog.Item] = []
    @State private var specialsCount = 0

    // Metadata-expansion facets (Decision 046) for the filter menu.
    @State private var keywordFacets: [String] = []
    @State private var studioFacets: [String] = []

    private let types: [(String, String?)] = [
        ("All", nil), ("Films", "feature-film"), ("Silent", "silent-film"),
        ("Animation", "animation"), ("Shorts", "short-film"),
        ("Newsreels", "newsreel"), ("Documentary", "documentary"), ("Ephemera", "ephemeral")]

    // IPAD-DESIGN §1.2: size class, never a device check.
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(spacing: 0) {
            if fixedScope == nil {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            // IPAD-DESIGN §2.2a: a scope selector is capped at 560pt on a
            // regular-width screen. Stretched across 1046pt it gave a
            // one-word label a 260pt segment.
            .frame(maxWidth: hSize == .regular ? 560 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.bottom, 8)
            }

            if scope == .films { filterChips }

            switch scope {
            case .films: filmsGrid
            case .tv: tvGrid
            case .collections: ScrollView { CollectionsList() }
            }
        }
        .navigationTitle(fixedScope?.rawValue ?? "Browse")
        .task {
            #if DEBUG
            // Harness door: AW_BROWSE_FILTER="type=silent-film,decade=1920"
            // sets chips so the sweep can photograph a filtered grid.
            // AW_BROWSE_SCOPE=tv|collections opens that scope.
            if let sc = ProcessInfo.processInfo.environment["AW_BROWSE_SCOPE"] {
                scope = sc == "tv" ? .tv : sc == "collections" ? .collections : .films
            }
            if let f = ProcessInfo.processInfo.environment["AW_BROWSE_FILTER"] {
                for pair in f.split(separator: ",") {
                    let kv = pair.split(separator: "=").map(String.init)
                    guard kv.count == 2 else { continue }
                    if kv[0] == "type" { contentType = kv[1] }
                    if kv[0] == "decade" { decade = Int(kv[1]) }
                }
            }
            #endif
            if items.isEmpty { reload() }
            if series.isEmpty { series = store.seriesCards() }
            specialsCount = store.tvSpecialsCount()
            if keywordFacets.isEmpty { keywordFacets = store.topKeywords() }
            if studioFacets.isEmpty { studioFacets = store.topStudios() }
        }
        .id(store.dbVersion)
    }

    // MARK: Films

    private var filmsGrid: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(items) { item in
                    Button { router.openDetail(item) } label: { PosterTile(item: item) }
                        .buttonStyle(.plain)
                        .onAppear { if item.id == items.last?.id { loadMore() } }
                }
            }.padding()
        }
        .onChange(of: contentType) { reload() }
        .onChange(of: decade) { reload() }
        .onChange(of: runtime) { reload() }
        .onChange(of: sort) { reload() }
    }

    // MARK: Filters you can see (iOS-DESIGN §4.2a)
    //
    // Every facet and the sort used to live behind one unlabeled toolbar icon,
    // so nothing on screen said what the grid was showing. Each is now a chip
    // that names its current value and opens its own native menu; a chip that
    // narrows the grid is filled, and Clear appears once anything is set.

    private var typeLabel: String { types.first { $0.1 == contentType }?.0 ?? "All" }
    private var sortLabel: String {
        switch sort {
        case .popular: "Popular"
        case .rating: "Top Rated"
        case .alphabetical: "A–Z"
        case .newest: "Newest"
        case .oldest: "Oldest"
        }
    }
    private var anyFilter: Bool { contentType != nil || decade != nil || runtime != nil }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // First, not last: with two filters set, the end of the row is
                // off a 390pt screen.
                if anyFilter {
                    Button("Clear") {
                        contentType = nil; decade = nil; runtime = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 4)
                }
                chip(contentType == nil ? "Type" : typeLabel, active: contentType != nil) {
                    Picker("Type", selection: $contentType) {
                        ForEach(types, id: \.1) { Text($0.0).tag($0.1) }
                    }
                }
                chip(decade.map { "\($0)s" } ?? "Decade", active: decade != nil) {
                    Picker("Decade", selection: $decade) {
                        Text("All Decades").tag(Int?.none)
                        // A decade is a label, not a quantity: verbatim, never
                        // a LocalizedStringKey that groups "2,010s".
                        ForEach(decades, id: \.self) { Text(verbatim: "\($0)s").tag(Int?.some($0)) }
                    }
                }
                chip(runtime?.label ?? "Length", active: runtime != nil) {
                    Picker("Length", selection: $runtime) {
                        Text("Any Length").tag(RuntimeBand?.none)
                        ForEach(RuntimeBand.allCases) { Text($0.label).tag(RuntimeBand?.some($0)) }
                    }
                }
                chip("Sort: \(sortLabel)", active: false) {
                    Picker("Sort", selection: $sort) {
                        Text("Popular").tag(CatalogDB.Sort.popular)
                        Text("Top Rated").tag(CatalogDB.Sort.rating)
                        Text("A–Z").tag(CatalogDB.Sort.alphabetical)
                        Text("Newest").tag(CatalogDB.Sort.newest)
                        Text("Oldest").tag(CatalogDB.Sort.oldest)
                    }
                }
                // Decision 046: keyword + studio facets open a dedicated
                // filtered grid (join-table queries, not the paged grid).
                if !keywordFacets.isEmpty {
                    chip("Keyword", active: false) {
                        ForEach(keywordFacets, id: \.self) { k in
                            Button(k.capitalized) {
                                router.browsePath.append(BrowseFilterRoute(title: k.capitalized, keyword: k))
                            }
                        }
                    }
                }
                if !studioFacets.isEmpty {
                    chip("Studio", active: false) {
                        ForEach(studioFacets, id: \.self) { st in
                            Button(st) {
                                router.browsePath.append(BrowseFilterRoute(title: st, studio: st))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func chip<Content: View>(_ title: String, active: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(active ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(Color(.secondarySystemBackground)),
                        in: .capsule)
        }
        .accessibilityLabel(active ? "\(title) filter, set" : title)
    }

    private var decades: [Int] { store.decadeCounts().keys.sorted(by: >) }

    private func reload() {
        page = 0
        items = store.browse(contentType: contentType, decade: decade, sort: sort,
                             limit: pageSize, offset: 0, runtime: runtime)
    }
    private func loadMore() {
        page += 1
        items += store.browse(contentType: contentType, decade: decade, sort: sort,
                              limit: pageSize, offset: page * pageSize, runtime: runtime)
    }

    // MARK: TV

    private var tvGrid: some View {
        ScrollView {
            // Standalone TV specials/episodes not folded into a series live here,
            // OUT of the Films grid (owner directive 2026-06-18). Shown only when present.
            if specialsCount > 0 {
                Button {
                    router.browsePath.append(BrowseFilterRoute(title: "TV Specials",
                                                               contentType: "tv-special"))
                } label: {
                    HStack {
                        Label("TV Specials", systemImage: "tv")
                        Spacer()
                        Text("\(specialsCount)").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading)
            }
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(series) { card in
                    Button { router.browsePath.append(SeriesRef(card: card)) } label: {
                        PosterTile(item: card)
                    }
                    .buttonStyle(.plain)
                }
            }.padding()
        }
        .overlay {
            if series.isEmpty {
                ContentUnavailableView("No series yet", systemImage: "tv")
            }
        }
    }
}

#endif
