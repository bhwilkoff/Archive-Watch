#if os(iOS)
import SwiftUI

// Search: native `.searchable` (the search-role tab hosts it). FTS5 over the same
// catalog.sqlite index the tvOS app uses; results in a poster grid. Type/decade
// filters (the Browse facet vocabulary) narrow the result set — owner request
// 2026-06-10: "implement filters on the search view".
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var results: [Catalog.Item] = []
    @State private var contentType: String? = nil
    @State private var decade: Int? = nil
    @State private var episodeHits: [EpisodeHit] = []
    // Episodes shown unless the user has filtered to a non-TV type.
    private var showEpisodes: Bool { (contentType == nil || contentType == "tv-series") && !episodeHits.isEmpty }

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]
    private let types: [(String, String?)] = [
        ("All", nil), ("Films", "feature-film"), ("TV", "tv-series"),
        ("Silent", "silent-film"), ("Animation", "animation"), ("Shorts", "short-film"),
        ("Newsreels", "newsreel"), ("Documentary", "documentary"), ("Ephemera", "ephemeral")]

    private var filtered: [Catalog.Item] {
        results.filter { item in
            (contentType == nil || item.contentType == contentType) &&
            (decade == nil || item.year.map { ($0 / 10) * 10 == decade! } == true)
        }
    }
    private var filterActive: Bool { contentType != nil || decade != nil }

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView("Search the archive",
                    systemImage: "magnifyingglass",
                    description: Text("Title, director, cast, genre, country, or synopsis."))
            } else if filtered.isEmpty && !showEpisodes {
                if filterActive && !results.isEmpty {
                    ContentUnavailableView("No matches with these filters",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("\(results.count) results are hidden by the "
                                          + "type/decade filters. Clear them to see all."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                ScrollView {
                    if showEpisodes {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Episodes").font(.title3.bold()).padding(.horizontal)
                            ForEach(episodeHits) { hit in
                                Button { openEpisode(hit) } label: { EpisodeHitRow(hit: hit) }
                                    .buttonStyle(.plain)
                            }
                        }.padding(.top, 8)
                    }
                    if !filtered.isEmpty {
                        if showEpisodes {
                            Text("Films & Shows").font(.title3.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding([.horizontal, .top])
                        }
                        LazyVGrid(columns: cols, spacing: 18) {
                            ForEach(filtered) { item in
                                Button { open(item) } label: { PosterTile(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }.padding()
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Films, shows, people…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Filter", systemImage: filterActive
                     ? "line.3.horizontal.decrease.circle.fill"
                     : "line.3.horizontal.decrease.circle") {
                    Picker("Type", selection: $contentType) {
                        ForEach(types, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    Picker("Decade", selection: $decade) {
                        Text("All Decades").tag(Int?.none)
                        ForEach(decades, id: \.self) { Text(verbatim: "\($0)s").tag(Int?.some($0)) }
                    }
                    if filterActive {
                        Button("Clear Filters", role: .destructive) {
                            contentType = nil; decade = nil
                        }
                    }
                }
            }
        }
        .task(id: query) {
            guard query.count >= 2 else { results = []; episodeHits = []; return }
            try? await Task.sleep(for: .milliseconds(180))   // debounce
            if !Task.isCancelled {
                results = store.search(query)
                episodeHits = store.searchEpisodes(query)
            }
        }
    }

    private var decades: [Int] { store.decadeCounts().keys.sorted(by: >) }

    /// Route an episode hit to its series (the user lands on the series with the full episode list).
    private func openEpisode(_ hit: EpisodeHit) {
        if let card = store.seriesCard(seriesID: hit.seriesID) {
            router.searchPath.append(SeriesRef(card: card))
        }
    }

    private func open(_ item: Catalog.Item) {
        if item.contentType == "tv-series" {
            router.searchPath.append(SeriesRef(card: item))
        } else {
            router.openDetail(item)
        }
    }
}

// One episode search hit: still thumbnail + episode title + "Series · S1·E2".
private struct EpisodeHitRow: View {
    let hit: EpisodeHit
    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: hit.stillURLParsed, contentMode: .fill)
                .frame(width: 84, height: 47).clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text([hit.seriesTitle, hit.numberLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(.horizontal).padding(.vertical, 6)
        .contentShape(.rect)
    }
}

#endif
