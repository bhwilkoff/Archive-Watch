import SwiftUI

// Browse: a poster grid with native facet controls (a Menu of content types +
// decades, and a sort Menu) — the touch idiom for the tvOS focus-chip facets.
// Infinite scroll via .onAppear paging. (PARITY §3.)
struct BrowseView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var contentType: String? = nil
    @State private var decade: Int? = nil
    @State private var sort: CatalogDB.Sort = .popular
    @State private var items: [Catalog.Item] = []
    @State private var page = 0
    private let pageSize = 60
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    private let types: [(String, String?)] = [
        ("All", nil), ("Films", "feature-film"), ("Silent", "silent-film"),
        ("Animation", "animation"), ("Shorts", "short-film"),
        ("Newsreels", "newsreel"), ("Documentary", "documentary"), ("Ephemera", "ephemeral")]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(items) { item in
                    Button { router.openDetail(item) } label: { PosterTile(item: item) }
                        .buttonStyle(.plain)
                        .onAppear { if item.id == items.last?.id { loadMore() } }
                }
            }.padding()
        }
        .navigationTitle("Browse")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        }
        .onChange(of: contentType) { reload() }
        .onChange(of: decade) { reload() }
        .onChange(of: sort) { reload() }
        .task { if items.isEmpty { reload() } }
        .id(store.dbVersion)
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
}
