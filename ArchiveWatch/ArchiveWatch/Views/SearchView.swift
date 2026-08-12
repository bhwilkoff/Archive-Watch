#if os(tvOS)
import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query: String = ""
    @State private var results: [Catalog.Item] = []
    // Result filters — iOS and Android have had type/decade filters over FTS
    // results since the 2026-06 waves; the platform the feature started on
    // never got them. Only facets PRESENT in the current results are offered
    // (the iOS rule), and both reset when the query changes.
    @State private var typeFilter: String? = nil
    @State private var decadeFilter: Int? = nil

    /// FTS5 search over the on-disk catalog (Decision 017) — title, cast, crew,
    /// genre, series, country, and synopsis (the broadened FTS `extra` column).
    /// Individual TV episodes are first-class items now (Decision 045), so they
    /// come back in `results` and are simply grouped into their own section.
    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let db = store.db else { results = []; return }
        results = db.search(q)
    }

    private var filtered: [Catalog.Item] {
        results.filter { item in
            if let t = typeFilter, item.contentType != t { return false }
            if let d = decadeFilter, item.decade != d { return false }
            return true
        }
    }
    private var episodeResults: [Catalog.Item] { filtered.filter(\.isEpisode) }
    private var filmResults: [Catalog.Item] { filtered.filter { !$0.isEpisode } }

    /// Facet values actually present in the unfiltered results, largest first —
    /// a chip for a type with no hits is a dead control.
    private var presentTypes: [(type: String, count: Int)] {
        Dictionary(grouping: results, by: \.contentType)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }
    private var presentDecades: [Int] {
        Set(results.compactMap(\.decade)).sorted()
    }

    private func typeLabel(_ type: String) -> String {
        if type == "tv-special" { return "TV Specials" }
        if type == "tv-episode" { return "Episodes" }
        if type == "tv-series" { return "TV Series" }
        if let cat = store.featured?.category(id: type) {
            return cat.shortName ?? cat.displayName
        }
        return type.split(separator: "-").map(\.capitalized).joined(separator: " ")
    }

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    placeholder
                } else if results.isEmpty {
                    EmptyState()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    filterChips
                    if filtered.isEmpty {
                        // The filters can empty a non-empty result set; the
                        // chips must stay visible so the viewer can back out.
                        EmptyState()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    if !episodeResults.isEmpty {
                        Text("Episodes").font(.title2.bold()).foregroundStyle(.white)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 30) {
                                ForEach(episodeResults) { item in
                                    EpisodeItemCard(item: item) { router.push(item) }
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                    if !filmResults.isEmpty {
                        if !episodeResults.isEmpty {
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
        .onChange(of: query) { _, _ in
            typeFilter = nil
            decadeFilter = nil
            runSearch()
        }
        .onChange(of: store.dbGeneration) { _, _ in runSearch() }
    }

    /// Type + era chips over the results (Browse's own chip control). Offered
    /// only when a facet could narrow anything; the active chip clears itself.
    @ViewBuilder
    private var filterChips: some View {
        let types = presentTypes
        let decades = presentDecades
        if types.count > 1 || decades.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if types.count > 1 {
                        Chip(label: "All", isOn: typeFilter == nil, accent: .accentColor) {
                            typeFilter = nil
                        }
                        ForEach(types, id: \.type) { entry in
                            let accent = store.featured?.category(id: entry.type)
                                .flatMap { Color(hex: $0.accent) } ?? .accentColor
                            Chip(label: "\(typeLabel(entry.type)) (\(entry.count))",
                                 isOn: typeFilter == entry.type, accent: accent) {
                                typeFilter = typeFilter == entry.type ? nil : entry.type
                            }
                        }
                    }
                    if decades.count > 1 {
                        Chip(label: "All Eras", isOn: decadeFilter == nil, accent: .accentColor) {
                            decadeFilter = nil
                        }
                        ForEach(decades, id: \.self) { d in
                            Chip(label: "\(d)s", isOn: decadeFilter == d, accent: .accentColor) {
                                decadeFilter = decadeFilter == d ? nil : d
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
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
            ForEach(filmResults) { item in
                CompactTile(item: item) {
                    router.push(item)
                }
            }
        }
    }
}

// A focusable episode search result: 16:9 still + episode title + "Series · S1·E2".
// Tapping opens the episode's own Detail (play/favorite/share/clip), Decision 045.
private struct EpisodeItemCard: View {
    let item: Catalog.Item
    let action: () -> Void
    private let w: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                RemoteImage(url: item.posterURLParsed,
                            targetSize: CGSize(width: w, height: w * 9 / 16), contentMode: .fill)
                    .frame(width: w, height: w * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.card)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text([item.seriesTitle, item.episodeNumberLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            .frame(width: w, alignment: .leading)
        }
    }
}

#endif
