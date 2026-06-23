#if os(macOS)
import SwiftUI

// Browse grid with facet + sort controls in the toolbar; paginated via store.browse.

struct BrowseView: View {
    let contentType: String?
    let title: String
    @Environment(AppStore.self) private var store

    @State private var items: [Catalog.Item] = []
    @State private var decade: Int? = nil
    @State private var sort: CatalogDB.Sort = .popular
    @State private var total = 0
    @State private var offset = 0
    private let page = 120

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
                Picker("Decade", selection: $decade) {
                    Text("All decades").tag(Int?.none)
                    ForEach(decadeList, id: \.self) { d in
                        Text(verbatim: "\(d)s").tag(Int?.some(d))
                    }
                }
            }
            ToolbarItem {
                Picker("Sort", selection: $sort) {
                    Text("Popular").tag(CatalogDB.Sort.popular)
                    Text("Top Rated").tag(CatalogDB.Sort.rating)
                    Text("A–Z").tag(CatalogDB.Sort.alphabetical)
                    Text("Newest").tag(CatalogDB.Sort.newest)
                }
            }
        }
        .task(id: store.dbVersion) { reset() }
        .onChange(of: decade) { _, _ in reset() }
        .onChange(of: sort) { _, _ in reset() }
    }

    private var decadeList: [Int] {
        (store.db?.decadeCounts().keys.sorted(by: >)) ?? []
    }

    private func reset() {
        offset = 0
        total = store.db?.browseCount(contentType: contentType, decade: decade, genre: nil, year: nil) ?? 0
        items = store.browse(contentType: contentType, decade: decade, genre: nil, year: nil,
                             sort: sort, limit: page, offset: 0)
        offset = items.count
    }

    private func loadMore() {
        guard items.count < total else { return }
        let next = store.browse(contentType: contentType, decade: decade, genre: nil, year: nil,
                               sort: sort, limit: page, offset: offset)
        items.append(contentsOf: next)
        offset += next.count
    }
}
#endif
