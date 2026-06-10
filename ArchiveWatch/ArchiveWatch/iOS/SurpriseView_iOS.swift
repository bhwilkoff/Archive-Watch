#if os(iOS)
import SwiftUI

// Surprise — serendipity actions (Decisions 014/015, PARITY §5). The touch port
// of the tvOS grid: every way to wander the archive visible at once, tap to roll,
// tap again to re-roll (learning-orientation: invites participation + agency).
// Reached from the shuffle button on Home.

struct SurpriseRoute: Hashable {}

struct SurpriseView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    fileprivate struct Action: Identifiable {
        let id: String
        let title: String
        let icon: String
        let hex: String
        var accent: Color { Color(hex: hex) ?? .accentColor }
    }

    // Palette mirrors the per-category accents (Decision 013).
    private let actions: [Action] = [
        .init(id: "film",       title: "Random Film",            icon: "film.fill",           hex: "#FF5C35"),
        .init(id: "tv",         title: "Random TV Series",       icon: "tv.fill",             hex: "#2D5BFF"),
        .init(id: "animation",  title: "Random Animation",       icon: "paintbrush.fill",     hex: "#FF4D8D"),
        .init(id: "scifi",      title: "Random Sci-Fi & Horror", icon: "atom",                hex: "#7C5BBA"),
        .init(id: "newsreel",   title: "Random Newsreel",        icon: "newspaper.fill",      hex: "#8A8F98"),
        .init(id: "ephemera",   title: "Random Ephemera",        icon: "books.vertical.fill", hex: "#3FA796"),
        .init(id: "commercial", title: "Random Commercial",      icon: "tv.badge.wifi",       hex: "#E8A317"),
        .init(id: "decade",     title: "Random Decade",          icon: "calendar",            hex: "#C9A66B"),
        .init(id: "pubdomain",  title: "Public Domain Day",      icon: "party.popper.fill",   hex: "#E8A317"),
        .init(id: "channels",   title: "Channels",               icon: "tv.and.mediabox",     hex: "#0047FF"),
        .init(id: "cartoon",    title: "Cartoon Mode",           icon: "pawprint.fill",       hex: "#3FA796"),
    ]
    private let cols = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ways to wander the archive — tap one, or tap again to re-roll.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal)
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(actions) { action in
                        Button { perform(action) } label: { SurpriseTile(action: action) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Surprise Me")
        .navigationBarTitleDisplayMode(.large)
    }

    private func perform(_ action: Action) {
        switch action.id {
        case "film":
            if let item = store.randomPlayable() { router.openDetail(item) }
        case "tv":
            if let series = store.randomSeries() { router.push(SeriesRef(card: series)) }
        case "animation":
            if let item = store.randomPlayable(contentType: "animation") { router.openDetail(item) }
        case "scifi":
            if let item = store.randomByGenre(["Science Fiction", "Sci-Fi", "Horror"]) { router.openDetail(item) }
        case "newsreel":
            if let item = store.randomPlayable(contentType: "newsreel") { router.openDetail(item) }
        case "ephemera":
            if let item = store.randomPlayable(contentType: "ephemeral") { router.openDetail(item) }
        case "commercial":
            if let item = store.randomPlayable(contentType: "commercial") { router.openDetail(item) }
        case "decade":
            if let decade = store.decadeCounts().keys.randomElement() {
                router.push(BrowseFilterRoute(title: "\(String(decade))s", decade: decade))
            }
        case "pubdomain":
            router.push(PublicDomainRoute())
        case "channels":
            router.push(ChannelsRoute())
        case "cartoon":
            router.push(CartoonRoute())
        default:
            break
        }
    }
}

private struct SurpriseTile: View {
    fileprivate let action: SurpriseView.Action

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [action.accent.opacity(0.9),
                                    action.accent.mix(with: .black, by: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: action.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(action.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        .frame(height: 110)
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Public Domain Day (#15)

// The 95-year rule: a work published in year Y enters the US public domain on
// January 1 of Y+95. Year chips pick the entry year; the grid shows that class.
struct PublicDomainRoute: Hashable {}

struct PublicDomainView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private let thisYear = Calendar.current.component(.year, from: Date())
    @State private var entryYear = 0
    @State private var items: [Catalog.Item] = []

    private var entryYears: [Int] { Array(stride(from: thisYear, through: thisYear - 20, by: -1)) }
    private var pubYear: Int { entryYear - 95 }
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The Class of \(String(pubYear)) — works that entered the U.S. public domain on January 1, \(String(entryYear)).")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal)
                yearChips
                if items.isEmpty {
                    ContentUnavailableView("Nothing from \(String(pubYear)) yet", systemImage: "film",
                        description: Text("No titles from that year are in the catalog."))
                        .padding(.top, 24)
                } else {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(items) { item in
                            Button { router.openDetail(item) } label: { PosterTile(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Public Domain Day")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if entryYear == 0 { entryYear = thisYear }
            reload()
        }
        .onChange(of: entryYear) { reload() }
    }

    private var yearChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(entryYears, id: \.self) { ey in
                    let on = ey == entryYear
                    Button { entryYear = ey } label: {
                        Text(String(ey))
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(on ? Brand.primary : Color(.secondarySystemFill),
                                        in: .capsule)
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    private func reload() {
        guard pubYear > 1870 else { items = []; return }
        items = store.browse(year: pubYear, sort: .popular, limit: 200)
    }
}

#endif
