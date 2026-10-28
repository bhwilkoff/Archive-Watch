#if os(iOS)
import SwiftUI

// Curated Archive collections (CollectionMetadata.all). Shown as a list inside
// the Browse "Collections" scope; tapping pushes a grid of that collection's
// items (db.byCollection).
struct CollectionRef: Hashable {
    let id: String
    let title: String
    let blurb: String
}

struct CollectionsList: View {
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    private var entries: [CollectionMetadata.Entry] { CollectionMetadata.all }
    /// IPAD-DESIGN §2.1: at regular width the rows form columns rather than
    /// one list whose chevrons sit a thousand points from their titles.
    private var cols: [GridItem] {
        hSize == .regular ? [GridItem(.adaptive(minimum: 340), spacing: 28, alignment: .top)]
                          : [GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(entries) { e in
                VStack(spacing: 0) {
                    Button {
                        router.push(CollectionRef(id: e.id, title: e.title, blurb: e.blurb))
                    } label: { CollectionCard(entry: e) }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    Divider().padding(.leading, 18)
                }
            }
        }
        .padding(.horizontal)
    }
}

private struct CollectionCard: View {
    let entry: CollectionMetadata.Entry
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: entry.accent) ?? .accentColor)
                .frame(width: 5, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.headline)
                Text(entry.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

// A single collection's items as a poster grid.
struct CollectionGridView: View {
    let ref: CollectionRef
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var loaded: [Catalog.Item] = []
    @State private var didLoad = false
    @State private var sort = SortMemory.sort(for: SortMemory.collection)
    @Environment(\.horizontalSizeClass) private var hSize
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    /// iOS-DESIGN 5.1c: Browse's sort, on the collection's own grid.
    private var items: [Catalog.Item] { CatalogDB.ordered(loaded, by: sort) }

    var body: some View {
        ScrollView {
            ContentTitle(text: ref.title).padding([.horizontal, .top])
            if !ref.blurb.isEmpty {
                Text(ref.blurb).font(.subheadline).foregroundStyle(.secondary)
                    // IPAD-DESIGN §2.1's measure; archive.org's descriptions run long.
                    .frame(maxWidth: hSize == .regular ? 700 : .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.top, 4)
            }
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(items) { item in
                    Button { router.openDetail(item) } label: { PosterTile(item: item) }
                        .buttonStyle(.plain)
                }
            }.padding()
        }
        .titleInContent(ref.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CatalogDB.Sort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .overlay {
            if didLoad, loaded.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "square.stack.3d.up")
            }
        }
        .task(id: store.dbVersion) {
            loaded = store.byCollection(ref.id)
            didLoad = true
        }
        .onChange(of: sort) { SortMemory.remember(sort, for: SortMemory.collection) }
    }
}

#endif
