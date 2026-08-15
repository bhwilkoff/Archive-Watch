#if os(macOS)
import SwiftUI
import SwiftData

// Library = the user's synced state (SwiftData, shared CloudKit container): Continue
// Watching, Favorites, Playlists. archiveIDs resolve to items via the shared store.

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Query(sort: \Playlist.modifiedAt, order: .reverse) private var playlists: [Playlist]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                let continueItems = store.itemsByIDs(progress.filter { !$0.isComplete }.map(\.archiveID))
                ShelfRow(title: "Continue Watching", items: continueItems)

                let favItems = store.itemsByIDs(favorites.map(\.archiveID))
                ShelfRow(title: "Favorites", items: favItems)

                ForEach(playlists) { pl in
                    ShelfRow(title: pl.name, items: store.itemsByIDs(pl.archiveIDs))
                }

                // The complete watch record (Decision 078): everything ever
                // played on any synced device, finished or not, newest first.
                // Watched = durable (a rewatch never removes a title).
                let watchedItems = store.itemsByIDs(progress.filter(\.isWatched).map(\.archiveID))
                ShelfRow(title: "Watched", items: watchedItems)
                let historyItems = store.itemsByIDs(progress.map(\.archiveID))
                ShelfRow(title: "History", items: historyItems)

                if continueItems.isEmpty && favItems.isEmpty && playlists.isEmpty {
                    ContentUnavailableView("Your library is empty",
                                           systemImage: "books.vertical",
                                           description: Text("Favorite a film or start watching to see it here."))
                        .padding(.top, 80)
                }
            }
            .padding(24)
        }
        .navigationTitle("Library")
    }
}
#endif
