import SwiftUI
import SwiftData

// Favorites as a first-class destination (its own sidebar tab, above
// Surprise). Owns its own @Query<Favorite> so HomeView stays free of SwiftData
// macro expansion (the cross-file "Cannot find X in scope" cascade source).
//
// CRITICAL (tvOS): the empty state MUST contain a focusable element. A page
// with no focusable view traps focus — you can't move back to the sidebar or
// anywhere else (the focus engine has nothing to land on). The empty state's
// "Browse the Collection" button is both the way out and a useful action.

struct FavoritesView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]

    @FocusState private var focusedArchiveID: String?
    @FocusState private var browseFocused: Bool

    // Computed LIVE from the @Query favorites + the catalog DB. Reading
    // `store.dbGeneration` registers an @Observable dependency, so this view
    // re-renders (and re-resolves) when the catalog DB finishes loading — even
    // if that happens while the user is on a different tab.
    //
    // The previous approach (@State populated by `.task` + `.onChange(dbGeneration)`)
    // left the grid permanently EMPTY in the common case: the catalog DB loads
    // asynchronously after launch, usually while the user is NOT on the Library
    // tab. TabView keeps the tab's view alive, so neither `.task` (runs once) nor
    // the dbGeneration `.onChange` (the view isn't rendering off-screen) fired
    // again when the user returned — `items` stayed []. Deriving it live fixes that.
    private var items: [Catalog.Item] {
        _ = store.dbGeneration
        return store.dbItemsByIDs(favorites.map(\.archiveID))
    }

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                Text("Library")
                    .font(.system(size: 54, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 24)

                // Favorites FIRST (the primary thing here) and clearly LABELED so
                // users know these are the titles they saved. Playlists + Watched
                // follow below. (Previously favorites were unlabeled and rendered
                // BELOW the playlist/watched shelves, which pushed them off-screen
                // when those shelves had content.)
                if items.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                        // Reach "Browse the Collection" by pressing Up from any
                        // item in the Watched/Playlists rows below, not just the
                        // one beneath the centered button (tvOS focus section).
                        .focusSection()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("Favorites")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("\(items.count)")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.horizontal, 80)

                    LazyVGrid(columns: cols, alignment: .leading, spacing: 48) {
                        ForEach(items) { item in
                            CompactTile(item: item) {
                                router.push(item)
                            }
                            .focused($focusedArchiveID, equals: item.archiveID)
                        }
                    }
                    .padding(.horizontal, 80)
                }

                PlaylistsSection()   // #12: user playlists
                WatchedSection()     // #12b: completed titles
            }
            .padding(.bottom, 80)
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            if items.isEmpty { browseFocused = true }
            else { focusedArchiveID = items.first?.archiveID }
        }
        // Claim focus once items resolve (e.g. the DB loaded after first appear).
        .onChange(of: items.isEmpty) { _, nowEmpty in
            if nowEmpty {
                browseFocused = true
            } else if focusedArchiveID == nil {
                focusedArchiveID = items.first?.archiveID
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.2))
            Text("No favorites yet")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
            Text("Tap the heart on any title's detail page to save it here.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 700)
            Button {
                router.tab = .browse
            } label: {
                Text("Browse the Collection")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 18)
            }
            .buttonStyle(PrimaryCTAStyle(accent: Color(hex: "#FF5C35") ?? .orange))
            .focusEffectDisabled()
            .focused($browseFocused)
            .padding(.top, 12)
        }
    }
}
