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

    @State private var items: [Catalog.Item] = []
    @FocusState private var focusedArchiveID: String?
    @FocusState private var browseFocused: Bool

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    Text("Favorites")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    if !items.isEmpty {
                        Text("\(items.count) titles")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 80)
                .padding(.top, 24)

                if items.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                } else {
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 48) {
                        ForEach(items) { item in
                            CompactTile(item: item) {
                                router.push(item)
                            }
                            .focused($focusedArchiveID, equals: item.archiveID)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            items = resolveItems()
            try? await Task.sleep(for: .milliseconds(50))
            if items.isEmpty { browseFocused = true }
            else { focusedArchiveID = items.first?.archiveID }
        }
        .onChange(of: favorites.map(\.archiveID)) { _, _ in items = resolveItems() }
        .onChange(of: store.dbGeneration) { _, _ in items = resolveItems() }
    }

    private func resolveItems() -> [Catalog.Item] {
        // dbItemsByIDs preserves the requested order, so favorites stay in
        // most-recently-added order.
        store.dbItemsByIDs(favorites.map(\.archiveID))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.2))
            Text("No favorites yet")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
            Text("Press and hold a title, or use the heart on its detail page, to save it here.")
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
