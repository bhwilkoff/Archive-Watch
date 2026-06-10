#if os(iOS)
import SwiftUI
import SwiftData

// Library: Favorites, Watched, and Playlists — backed by SwiftData (synced to the
// Apple TV via CloudKit). A segmented picker switches sections; each is a grid.
struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Query private var progress: [WatchProgress]
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @State private var section: Section = .favorites

    enum Section: String, CaseIterable, Identifiable { case favorites, watched, playlists
        var id: String { rawValue }; var title: String { rawValue.capitalized } }

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).padding()

            switch section {
            case .favorites: grid(store.itemsByIDs(favorites.map(\.archiveID)),
                                  empty: "No favorites yet", icon: "heart")
            case .watched: grid(store.itemsByIDs(progress.filter(\.isComplete).map(\.archiveID)),
                                empty: "Nothing watched yet", icon: "checkmark.circle")
            case .playlists: playlistList
            }
        }
        .navigationTitle("Library")
        .id(store.dbVersion)
    }

    @ViewBuilder private func grid(_ items: [Catalog.Item], empty: String, icon: String) -> some View {
        if items.isEmpty {
            ContentUnavailableView(empty, systemImage: icon)
        } else {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 18) {
                    ForEach(items) { item in
                        Button { router.openDetail(item) } label: { PosterTile(item: item) }
                            .buttonStyle(.plain)
                    }
                }.padding()
            }
        }
    }

    @ViewBuilder private var playlistList: some View {
        if playlists.isEmpty {
            ContentUnavailableView("No playlists yet", systemImage: "rectangle.stack",
                description: Text("Add titles to a playlist from their detail page."))
        } else {
            List {
                ForEach(playlists) { pl in
                    NavigationLink {
                        grid(store.itemsByIDs(pl.archiveIDs), empty: "Empty playlist", icon: "rectangle.stack")
                            .navigationTitle(pl.name)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(pl.name).font(.headline)
                            Text("\(pl.archiveIDs.count) titles").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets {
                        let pl = playlists[i]
                        ctx.delete(pl)
                        SyncNudge.recordDeletion("pl:\(pl.id)", in: ctx)
                    }
                }
            }
        }
    }
}

#endif
