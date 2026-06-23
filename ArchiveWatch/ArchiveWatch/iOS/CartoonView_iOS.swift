#if os(iOS)
import SwiftUI

// Cartoon / Kids Mode (PARITY §5) — the touch port of tvOS KidsModeView: a
// kid-safe COLOR-leaning cartoon surface (never silent, scary subjects filtered,
// Decision 025 color flags). Selection logic mirrors the tvOS AppStore pool
// (unify into shared Core after the tvOS review settles — don't let them drift).

struct CartoonRoute: Hashable {}

// KidsContent (the kid-safe cartoon pool logic) is now shared with macOS in
// Components/KidsContent.swift so the two can't drift.

struct CartoonView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var characters: [(name: String, items: [Catalog.Item])] = []
    @State private var collections: [(title: String, items: [Catalog.Item])] = []
    @State private var marathon: ChannelLineup?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Button { startMarathon() } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play a Cartoon Marathon").fontWeight(.bold)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background((Color(hex: "#3FA796") ?? .teal).gradient,
                                in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                ForEach(characters, id: \.name) { group in
                    shelf(title: group.name, items: group.items)
                }
                ForEach(collections, id: \.title) { group in
                    shelf(title: group.title, items: group.items)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Cartoon Mode")
        .navigationBarTitleDisplayMode(.large)
        .task(id: store.dbVersion) {
            characters = KidsContent.characters(store)
            collections = KidsContent.collections(store)
        }
        .fullScreenCover(item: $marathon) { box in
            if let player = PlayerView(lineup: box.items, startOffset: 0) {
                player.ignoresSafeArea()
            } else {
                ContentUnavailableView("No cartoons available", systemImage: "tv.slash")
            }
        }
    }

    private func startMarathon() {
        let pool = KidsContent.cartoonPool(store)
        guard !pool.isEmpty else { return }
        marathon = ChannelLineup(items: pool, startOffset: 0)
    }

    private func shelf(title: String, items: [Catalog.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3).fontWeight(.semibold).padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(items.prefix(20)) { item in
                        Button { router.openDetail(item) } label: { PosterTile(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }
}

#endif
