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

    // Films state
    @State private var contentType: String? = nil
    @State private var decade: Int? = nil
    @State private var sort: CatalogDB.Sort = .popular
    @State private var items: [Catalog.Item] = []
    @State private var page = 0
    private let pageSize = 60
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    // TV state
    @State private var series: [Catalog.Item] = []

    private let types: [(String, String?)] = [
        ("All", nil), ("Films", "feature-film"), ("Silent", "silent-film"),
        ("Animation", "animation"), ("Shorts", "short-film"),
        ("Newsreels", "newsreel"), ("Documentary", "documentary"), ("Ephemera", "ephemeral")]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 8)

            switch scope {
            case .films: filmsGrid
            case .tv: tvGrid
            case .collections: ScrollView { CollectionsList() }
            }
        }
        .navigationTitle("Browse")
        .toolbar {
            if scope == .films {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
        }
        .navigationDestination(for: SeriesRef.self) { SeriesDetailView(card: $0.card) }
        .navigationDestination(for: CollectionRef.self) { CollectionGridView(ref: $0) }
        .task {
            if items.isEmpty { reload() }
            if series.isEmpty { series = store.seriesCards() }
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
        .onChange(of: sort) { reload() }
    }

    private var filterMenu: some View {
        Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
            Picker("Type", selection: $contentType) {
                ForEach(types, id: \.1) { Text($0.0).tag($0.1) }
            }
            Picker("Decade", selection: $decade) {
                Text("All Decades").tag(Int?.none)
                ForEach(decades, id: \.self) { Text("\($0)s").tag(Int?.some($0)) }
            }
            Picker("Sort", selection: $sort) {
                Text("Popular").tag(CatalogDB.Sort.popular)
                Text("A–Z").tag(CatalogDB.Sort.alphabetical)
                Text("Newest").tag(CatalogDB.Sort.newest)
                Text("Oldest").tag(CatalogDB.Sort.oldest)
            }
        }
    }

    private var decades: [Int] { store.decadeCounts().keys.sorted(by: >) }

    private func reload() {
        page = 0
        items = store.browse(contentType: contentType, decade: decade, sort: sort,
                             limit: pageSize, offset: 0)
    }
    private func loadMore() {
        page += 1
        items += store.browse(contentType: contentType, decade: decade, sort: sort,
                              limit: pageSize, offset: page * pageSize)
    }

    // MARK: TV

    private var tvGrid: some View {
        ScrollView {
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
