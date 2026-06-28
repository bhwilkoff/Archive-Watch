#if os(iOS)
import SwiftUI

// Home discovery sections (PARITY §2): category tiles, decade tiles, and the
// generic filtered grid they open. Touch idiom — compact tiles in a horizontal
// scroll, tap to push a paged grid. The tvOS versions live in HomeView.swift
// (focus-engine sized); these share the same queries and accent semantics.

/// A pushable browse filter — the iOS analog of the tvOS `BrowseFilter` route.
struct BrowseFilterRoute: Hashable {
    var title: String
    var contentType: String? = nil
    var decade: Int? = nil
    var genre: String? = nil
    var year: Int? = nil
    var person: String? = nil   // #4 parity: titles featuring this cast member / director
    var keyword: String? = nil  // Decision 046: thematic keyword facet
    var studio: String? = nil   // Decision 046: production-company facet
}

// MARK: - Filtered grid (paged)

struct FilteredGridView: View {
    let route: BrowseFilterRoute
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var items: [Catalog.Item] = []
    @State private var total = 0
    @State private var page = 0
    private let pageSize = 60
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(items) { item in
                    Button { open(item) } label: { PosterTile(item: item) }
                        .buttonStyle(.plain)
                        .onAppear { if item.id == items.last?.id { loadMore() } }
                }
            }.padding()
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if total > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(total) titles").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "film",
                    description: Text("No titles match this filter in the catalog."))
            }
        }
        .task {
            if items.isEmpty {
                if let person = route.person {
                    // Person browse rides the FTS names index — single capped
                    // fetch, not paginable (same shape as tvOS BrowseFilter).
                    items = store.byPerson(person)
                    total = items.count
                } else if let keyword = route.keyword {   // Decision 046
                    items = store.byKeyword(keyword)
                    total = items.count
                } else if let studio = route.studio {     // Decision 046
                    items = store.byStudio(studio)
                    total = items.count
                } else {
                    items = fetch(offset: 0)
                    total = store.browseCount(contentType: route.contentType, decade: route.decade,
                                              genre: route.genre, year: route.year)
                }
            }
        }
        .id(store.dbVersion)
    }

    private func open(_ item: Catalog.Item) {
        if item.contentType == "tv-series" { push(SeriesRef(card: item)) }
        else { router.openDetail(item) }
    }
    private func push(_ ref: SeriesRef) {
        switch router.tab {
        case .home: router.homePath.append(ref)
        case .browse: router.browsePath.append(ref)
        case .channels: router.channelsPath.append(ref)
        case .search: router.searchPath.append(ref)
        case .library: router.libraryPath.append(ref)
        }
    }
    private func fetch(offset: Int) -> [Catalog.Item] {
        store.browse(contentType: route.contentType, decade: route.decade,
                     genre: route.genre, year: route.year, limit: pageSize, offset: offset)
    }
    private func loadMore() {
        // person / keyword / studio browse are single capped fetches (Decision 046).
        guard route.person == nil, route.keyword == nil, route.studio == nil else { return }
        page += 1
        items += fetch(offset: page * pageSize)
    }
}

// The Home modes pill row (Channels / Surprise / Cartoon / Public Domain Day)
// was removed 2026-06-10 (owner): Channels is a tab; the rest live behind the
// Home shuffle button → Surprise grid.

// MARK: - Category tiles

struct CategoryTilesRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var categories: [Featured.Category] = []

    // A category tile must open a real browsing surface — a tile with a
    // handful of items (the classifier emits almost no "documentary") reads
    // as broken (owner report 2026-06-11).
    private let minCount = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse by Category").font(.title3).fontWeight(.semibold)
                .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(categories) { cat in
                        Button {
                            router.homePath.append(BrowseFilterRoute(
                                title: cat.displayName, contentType: cat.id))
                        } label: { CategoryTileSmall(category: cat) }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: store.dbVersion) {
            categories = (store.featured?.categories ?? [])
                .filter { !store.hiddenCategories.contains($0.id) }
                .filter { store.browseCount(contentType: $0.id) >= minCount }
        }
    }
}

private struct CategoryTileSmall: View {
    let category: Featured.Category
    private var accent: Color { Color(hex: category.accent) ?? .accentColor }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [accent.opacity(0.85), accent.mix(with: .black, by: 0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: iconName).font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                Text(category.displayName)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
        }
        .frame(width: 150, height: 96)
        .clipShape(.rect(cornerRadius: 10))
    }

    private var iconName: String {
        switch category.id {
        case "feature-film": "film.fill"
        case "tv-series":    "tv.fill"
        case "silent-film":  "moon.stars.fill"
        case "animation":    "paintbrush.fill"
        case "newsreel":     "newspaper.fill"
        case "documentary":  "camera.fill"
        case "ephemeral":    "books.vertical.fill"
        case "short-film":   "clock.fill"
        case "commercial":   "tv.badge.wifi"
        default:             "sparkles"
        }
    }
}

// MARK: - Decade tiles

struct DecadeTilesRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var counts: [Int: Int] = [:]

    private var decades: [Int] { counts.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse by Era").font(.title3).fontWeight(.semibold)
                .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(decades, id: \.self) { decade in
                        Button {
                            router.homePath.append(BrowseFilterRoute(
                                title: "\(String(decade))s", decade: decade))
                        } label: { DecadeTileSmall(decade: decade, count: counts[decade] ?? 0) }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: store.dbVersion) { counts = store.decadeCounts() }
    }
}

private struct DecadeTileSmall: View {
    let decade: Int
    let count: Int

    private var era: (label: String, accent: Color) {
        switch decade {
        case ..<1910:     ("Earliest",   Color(hex: "#C9A66B") ?? .brown)
        case 1910...1927: ("Silent Era", Color(hex: "#C9A66B") ?? .brown)
        case 1928...1939: ("Pre-Code",   Color(hex: "#FF5C35") ?? .orange)
        case 1940...1949: ("Wartime",    Color(hex: "#8A8F98") ?? .gray)
        case 1950...1959: ("Atomic Age", Color(hex: "#2D5BFF") ?? .blue)
        case 1960...1969: ("New Wave",   Color(hex: "#FF4D8D") ?? .pink)
        case 1970...1979: ("Analog",     Color(hex: "#7C5BBA") ?? .purple)
        case 1980...1989: ("Home Video", Color(hex: "#3FA796") ?? .teal)
        default:          ("Modern",     Color(hex: "#E8A317") ?? .yellow)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [era.accent.opacity(0.9), era.accent.mix(with: .black, by: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 2) {
                // verbatim: locale grouping would render "1,960s".
                Text(verbatim: "\(decade)s")
                    .font(.system(size: 24, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Text(era.label.uppercased())
                    .font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(count) titles").font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(12)
        }
        .frame(width: 130, height: 96)
        .clipShape(.rect(cornerRadius: 10))
    }
}

#endif
