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
    private var entries: [CollectionMetadata.Entry] { CollectionMetadata.all }

    var body: some View {
        LazyVStack(spacing: 4) {
            ForEach(entries) { e in
                Button {
                    router.browsePath.append(CollectionRef(id: e.id, title: e.title, blurb: e.blurb))
                } label: { CollectionCard(entry: e) }
                .buttonStyle(.plain)
                Divider().padding(.leading, 18)
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
    @State private var items: [Catalog.Item] = []
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        ScrollView {
            if !ref.blurb.isEmpty {
                Text(ref.blurb).font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top])
            }
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(items) { item in
                    Button { router.openDetail(item) } label: { PosterTile(item: item) }
                        .buttonStyle(.plain)
                }
            }.padding()
        }
        .navigationTitle(ref.title).navigationBarTitleDisplayMode(.inline)
        .task(id: store.dbVersion) { items = store.byCollection(ref.id) }
    }
}

#endif
