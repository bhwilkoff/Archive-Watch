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
                items = fetch(offset: 0)
                total = store.browseCount(contentType: route.contentType, decade: route.decade,
                                          genre: route.genre, year: route.year)
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
        case .search: router.searchPath.append(ref)
        case .library: router.libraryPath.append(ref)
        }
    }
    private func fetch(offset: Int) -> [Catalog.Item] {
        store.browse(contentType: route.contentType, decade: route.decade,
                     genre: route.genre, year: route.year, limit: pageSize, offset: offset)
    }
    private func loadMore() {
        page += 1
        items += fetch(offset: page * pageSize)
    }
}

// MARK: - Modes row (PARITY §2/§5 — links Channels / Surprise / Public Domain Day)

struct ModesRow: View {
    @Environment(Router.self) private var router

    private struct Mode: Identifiable {
        let id: String; let title: String; let icon: String; let hex: String
        var accent: Color { Color(hex: hex) ?? .accentColor }
    }
    private let modes: [Mode] = [
        .init(id: "channels", title: "Channels",          icon: "tv.and.mediabox",     hex: "#2D5BFF"),
        .init(id: "surprise", title: "Surprise Me",       icon: "shuffle",             hex: "#FF5C35"),
        .init(id: "cartoons", title: "Cartoon Mode",      icon: "pawprint.fill",       hex: "#3FA796"),
        .init(id: "pubday",   title: "Public Domain Day", icon: "party.popper.fill",   hex: "#E8A317"),
    ]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(modes) { mode in
                    Button { open(mode.id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.icon).font(.subheadline.weight(.semibold))
                            Text(mode.title).font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(mode.accent.gradient, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    private func open(_ id: String) {
        switch id {
        case "channels": router.push(ChannelsRoute())
        case "surprise": router.push(SurpriseRoute())
        case "cartoons": router.push(CartoonRoute())
        case "pubday":   router.push(PublicDomainRoute())
        default: break
        }
    }
}

// MARK: - Category tiles

struct CategoryTilesRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse by Category").font(.title3).fontWeight(.semibold)
                .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(visibleCategories) { cat in
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
    }

    private var visibleCategories: [Featured.Category] {
        (store.featured?.categories ?? []).filter { !store.hiddenCategories.contains($0.id) }
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
