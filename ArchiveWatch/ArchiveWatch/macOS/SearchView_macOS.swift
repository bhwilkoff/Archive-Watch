#if os(macOS)
import SwiftUI

// Search over the shared FTS5 index (store.search). .searchable renders as a toolbar
// search field on macOS — native. Type/decade filters narrow the result set (parity with
// iOS/tvOS Search — owner: macOS Search had "no filters").

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    @State private var results: [Catalog.Item] = []
    @State private var contentType: String? = nil
    @State private var decade: Int? = nil

    // Episode items (Decision 045) arrive in `results` like any item; grouped into
    // their own section. Shown unless filtered to a non-TV type.
    private var episodeResults: [Catalog.Item] { results.filter(\.isEpisode) }
    private var showEpisodes: Bool {
        (contentType == nil || contentType == "tv-series") && !episodeResults.isEmpty
    }

    private let types: [(String, String?)] = [
        ("All", nil), ("Films", "feature-film"), ("TV", "tv-series"),
        ("Silent", "silent-film"), ("Animation", "animation"), ("Shorts", "short-film"),
        ("Newsreels", "newsreel"), ("Documentary", "documentary"), ("Ephemera", "ephemeral")]

    private var filtered: [Catalog.Item] {
        results.filter { item in
            !item.isEpisode &&
            (contentType == nil || item.contentType == contentType) &&
            (decade == nil || item.year.map { ($0 / 10) * 10 == decade! } == true)
        }
    }
    private var filterActive: Bool { contentType != nil || decade != nil }
    private var decades: [Int] { store.decadeCounts().keys.sorted(by: >) }

    var body: some View {
        ScrollView {
            if query.isEmpty {
                ContentUnavailableView("Search the archive",
                                       systemImage: "magnifyingglass",
                                       description: Text("Title, director, cast, genre, country, or synopsis."))
                    .padding(.top, 80)
            } else if filtered.isEmpty && !showEpisodes {
                if filterActive && !results.isEmpty {
                    ContentUnavailableView("No matches with these filters",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("\(results.count) results are hidden by the type/decade filters."))
                        .padding(.top, 80)
                } else {
                    ContentUnavailableView.search(text: query).padding(.top, 80)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if showEpisodes {
                        Text("Episodes").font(.title2.bold()).padding(.horizontal)
                        VStack(spacing: 2) {
                            ForEach(episodeResults) { item in
                                Button { router.openDetail(item) } label: { EpisodeItemRow(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if !filtered.isEmpty {
                        if showEpisodes { Text("Films & Shows").font(.title2.bold()).padding([.horizontal, .top]) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)],
                                  spacing: 18) {
                            ForEach(filtered) { PosterCard(item: $0) }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Films, shows, people…")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Type", selection: $contentType) {
                        ForEach(types, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    Picker("Decade", selection: $decade) {
                        Text("All Decades").tag(Int?.none)
                        ForEach(decades, id: \.self) { Text(verbatim: "\($0)s").tag(Int?.some($0)) }
                    }
                    if filterActive {
                        Button("Clear Filters", role: .destructive) { contentType = nil; decade = nil }
                    }
                } label: {
                    Label("Filter", systemImage: filterActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .help("Filter results by type or decade")
            }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(180))   // debounce
            if !Task.isCancelled {
                results = store.search(q)
            }
        }
    }
}

// One episode search result: still thumbnail + episode title + "Series · S1·E2".
// Tapping opens the episode's own Detail (play/favorite/share/clip), Decision 045.
private struct EpisodeItemRow: View {
    let item: Catalog.Item
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                .frame(width: 96, height: 54)
                .overlay {
                    if let u = item.posterURLParsed {
                        RemoteImage(url: u, contentMode: .fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(1)
                Text([item.seriesTitle, item.episodeNumberLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
#endif
