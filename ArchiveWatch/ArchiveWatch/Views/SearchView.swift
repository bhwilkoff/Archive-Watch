#if os(tvOS)
import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query: String = ""
    @State private var results: [Catalog.Item] = []
    @State private var episodeHits: [EpisodeHit] = []

    /// FTS5 search over the on-disk catalog (Decision 017) — title, cast, crew,
    /// genre, series, country, and synopsis (the broadened FTS `extra` column),
    /// plus individual TV EPISODES via the episodes_fts index.
    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let db = store.db else { results = []; episodeHits = []; return }
        results = db.search(q)
        episodeHits = db.searchEpisodes(q)
    }
    private func openEpisode(_ hit: EpisodeHit) {
        if let card = store.db?.seriesCard(slug: hit.seriesID) { router.push(card) }
    }

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    placeholder
                } else if results.isEmpty && episodeHits.isEmpty {
                    EmptyState()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    if !episodeHits.isEmpty {
                        Text("Episodes").font(.title2.bold()).foregroundStyle(.white)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 30) {
                                ForEach(episodeHits) { hit in
                                    EpisodeHitCard(hit: hit) { openEpisode(hit) }
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                    if !results.isEmpty {
                        if !episodeHits.isEmpty {
                            Text("Films & Shows").font(.title2.bold()).foregroundStyle(.white).padding(.top, 12)
                        }
                        resultGrid
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .searchable(text: $query, placement: .automatic,
                    prompt: "Search by title, director, actor, or genre")
        // Pad the whole search surface (field + keyboard + content) down from the
        // top so it clears the floating sidebar's area, like every other tab.
        .padding(.top, 60)
        // Black must be the OUTERMOST layer so it fills behind the top padding
        // too — otherwise that 60pt strip shows the system's grey nav material.
        .background(Color.black.ignoresSafeArea())
        .onChange(of: query) { _, _ in runSearch() }
        .onChange(of: store.dbGeneration) { _, _ in runSearch() }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.18))
            Text("Start typing to search")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
            Text("Searching \(store.dbSearchableCount) titles by name, cast, crew, genre, country, and synopsis.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var resultGrid: some View {
        LazyVGrid(columns: cols, alignment: .leading, spacing: 44) {
            ForEach(results) { item in
                CompactTile(item: item) {
                    router.push(item)
                }
            }
        }
    }
}

// A focusable episode search result: 16:9 still + episode title + "Series · S1·E2".
private struct EpisodeHitCard: View {
    let hit: EpisodeHit
    let action: () -> Void
    private let w: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                RemoteImage(url: hit.stillURLParsed,
                            targetSize: CGSize(width: w, height: w * 9 / 16), contentMode: .fill)
                    .frame(width: w, height: w * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.card)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text([hit.seriesTitle, hit.numberLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            .frame(width: w, alignment: .leading)
        }
    }
}

#endif
