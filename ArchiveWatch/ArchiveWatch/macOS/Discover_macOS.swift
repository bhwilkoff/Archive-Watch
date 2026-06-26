#if os(macOS)
import SwiftUI

// Parity discovery surfaces (docs/macOS-DESIGN.md §1 — same verbs, Mac-native):
// Collections, Surprise serendipity actions, Public Domain Day, and a reusable
// filtered poster grid that backs decade/genre/category browsing.

// MARK: - Reusable filtered grid

struct BrowseFilterRoute: Hashable {
    let title: String
    var contentType: String? = nil
    var decade: Int? = nil
    var genre: String? = nil
    var year: Int? = nil
}

struct FilteredGridView: View {
    let route: BrowseFilterRoute
    @Environment(AppStore.self) private var store
    @State private var items: [Catalog.Item] = []

    var body: some View {
        GridView(title: route.title, items: items)
            .task(id: store.dbVersion) {
                items = store.browse(contentType: route.contentType, decade: route.decade,
                                     genre: route.genre, year: route.year,
                                     sort: .popular, limit: 300, offset: 0)
            }
    }
}

// MARK: - Collections

struct CollectionsList: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(CollectionMetadata.all) { entry in
                    Button { router.openCollection(entry.id, entry.title) } label: {
                        CollectionRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Collections")
    }
}

private struct CollectionRow: View {
    let entry: CollectionMetadata.Entry
    @Environment(AppStore.self) private var store
    @State private var hovering = false
    @State private var posters: [Catalog.Item] = []

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: entry.accent) ?? .accentColor)
                .frame(width: 5, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.headline)
                Text(entry.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(width: 260, alignment: .leading)
            // Poster preview strip — a few real posters from the collection (lazy: only visible
            // rows query, via the enclosing LazyVStack).
            HStack(spacing: 6) {
                ForEach(posters.prefix(5)) { item in
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                        .aspectRatio(2.0/3.0, contentMode: .fit)
                        .frame(height: 64)
                        .overlay {
                            if let u = item.posterURLParsed {
                                RemoteImage(url: u, contentMode: .fill)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: store.dbVersion) {
            if posters.isEmpty { posters = Array(store.byCollection(entry.id).prefix(5)) }
        }
    }
}

// MARK: - Surprise (serendipity actions, Decisions 014/015)

struct SurpriseView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    fileprivate struct Action: Identifiable {
        let id: String
        let title: String
        let icon: String
        let hex: String
        var accent: Color { Color(hex: hex) ?? .accentColor }
    }

    private let actions: [Action] = [
        .init(id: "film",       title: "Random Film",            icon: "film.fill",           hex: "#FF5C35"),
        .init(id: "tv",         title: "Random TV Series",       icon: "tv.fill",             hex: "#2D5BFF"),
        .init(id: "animation",  title: "Random Animation",       icon: "paintbrush.fill",     hex: "#FF4D8D"),
        .init(id: "scifi",      title: "Random Sci-Fi & Horror", icon: "atom",                hex: "#7C5BBA"),
        .init(id: "newsreel",   title: "Random Newsreel",        icon: "newspaper.fill",      hex: "#8A8F98"),
        .init(id: "ephemera",   title: "Random Ephemera",        icon: "books.vertical.fill", hex: "#3FA796"),
        .init(id: "commercial", title: "Random Commercial",      icon: "tv.badge.wifi",       hex: "#E8A317"),
        .init(id: "decade",     title: "Random Decade",          icon: "calendar",            hex: "#C9A66B"),
        .init(id: "cartoon",    title: "Cartoon Mode",           icon: "pawprint.fill",       hex: "#3FA796"),
        .init(id: "party",      title: "Party Play",             icon: "sparkles.tv.fill",    hex: "#FF4D8D"),
        .init(id: "screensaver",title: "Screensaver",            icon: "photo.on.rectangle.angled", hex: "#2D5BFF"),
        .init(id: "pubdomain",  title: "Public Domain Day",      icon: "party.popper.fill",   hex: "#E8A317"),
    ]
    private let cols = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ways to wander the archive — pick one, or come back to re-roll.")
                    .font(.title3).foregroundStyle(.secondary)
                LazyVGrid(columns: cols, spacing: 16) {
                    ForEach(actions) { action in
                        Button { perform(action) } label: { SurpriseTile(action: action) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Surprise Me")
    }

    private func perform(_ action: Action) {
        switch action.id {
        case "film":       if let i = store.randomPlayable() { router.openDetail(i) }
        case "tv":         if let s = store.randomSeries() { router.openDetail(s) }
        case "animation":  if let i = store.randomPlayable(contentType: "animation") { router.openDetail(i) }
        case "scifi":      if let i = store.randomByGenre(["Science Fiction", "Sci-Fi", "Horror"]) { router.openDetail(i) }
        case "newsreel":   if let i = store.randomPlayable(contentType: "newsreel") { router.openDetail(i) }
        case "ephemera":   if let i = store.randomPlayable(contentType: "ephemeral") { router.openDetail(i) }
        case "commercial": if let i = store.randomPlayable(contentType: "commercial") { router.openDetail(i) }
        case "decade":
            if let d = store.decadeCounts().keys.randomElement() {
                router.path.append(BrowseFilterRoute(title: "\(String(d))s", decade: d))
            }
        case "cartoon":     router.path.append(CartoonRoute())
        case "party":       router.path.append(PartyRoute())
        case "screensaver": router.screensaverActive = true   // full-screen overlay (RootView)
        case "pubdomain":
            router.path.append(PublicDomainRoute())
        default: break
        }
    }
}

private struct SurpriseTile: View {
    fileprivate let action: SurpriseView.Action
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [action.accent.opacity(0.9),
                                    action.accent.mix(with: .black, by: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: action.icon)
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(action.title)
                    .font(.headline).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(radius: hovering ? 8 : 2, y: hovering ? 4 : 1)
        .scaleEffect(hovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Public Domain Day (#15)

// A work published in year Y enters the US public domain on Jan 1 of Y+95.
struct PublicDomainRoute: Hashable {}

struct PublicDomainView: View {
    @Environment(AppStore.self) private var store

    private let thisYear = Calendar.current.component(.year, from: Date())
    @State private var entryYear = 0
    @State private var items: [Catalog.Item] = []

    private var entryYears: [Int] { Array(stride(from: thisYear, through: thisYear - 20, by: -1)) }
    private var pubYear: Int { entryYear - 95 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The Class of \(String(pubYear)) — works that entered the U.S. public domain on January 1, \(String(entryYear)).")
                .font(.title3).foregroundStyle(.secondary)
                .padding([.horizontal, .top], 24)
            yearChips.padding(.horizontal, 24).padding(.vertical, 12)
            if items.isEmpty && store.isReady {
                ContentUnavailableView("Nothing from \(String(pubYear)) yet", systemImage: "film",
                    description: Text("No titles from that year are in the catalog."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GridView(title: "", items: items)
            }
        }
        .navigationTitle("Public Domain Day")
        .task { if entryYear == 0 { entryYear = thisYear } }
        .task(id: entryYear) { reload() }
    }

    private var yearChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(entryYears, id: \.self) { ey in
                    let on = ey == entryYear
                    Button { entryYear = ey } label: {
                        Text(String(ey)).font(.callout.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func reload() {
        guard pubYear > 1870, store.isReady else { items = []; return }
        items = store.browse(year: pubYear, sort: .popular, limit: 200)
    }
}
#endif
