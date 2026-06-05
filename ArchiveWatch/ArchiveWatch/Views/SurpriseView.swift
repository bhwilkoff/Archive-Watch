import SwiftUI

// Surprise — serendipity actions (Decisions 014/015). Seven clearly-labelled
// ways to wander the archive, all visible at once in a grid so the viewer sees
// every choice and picks deliberately (learning-orientation: invites
// participation + agency, no hidden funnel). Each tile re-rolls on every press,
// so "roll again" is just pressing the same tile again — no separate control.

struct SurpriseView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @FocusState private var focused: String?

    fileprivate struct Action: Identifiable {
        let id: String
        let title: String
        let icon: String
        let hex: String
        var accent: Color { Color(hex: hex) ?? .accentColor }
    }

    // Palette mirrors the per-category accents (Decision 013).
    private let actions: [Action] = [
        .init(id: "film",      title: "Random Film",            icon: "film.fill",            hex: "#FF5C35"),
        .init(id: "tv",        title: "Random TV Episode",      icon: "tv.fill",              hex: "#2D5BFF"),
        .init(id: "animation", title: "Random Animation",       icon: "paintbrush.fill",      hex: "#FF4D8D"),
        .init(id: "scifi",     title: "Random Sci-Fi & Horror", icon: "atom",                 hex: "#7C5BBA"),
        .init(id: "newsreel",  title: "Random Newsreel",        icon: "newspaper.fill",       hex: "#8A8F98"),
        .init(id: "ephemera",  title: "Random Ephemera",        icon: "books.vertical.fill",  hex: "#3FA796"),
        .init(id: "commercial", title: "Random Commercial",     icon: "tv.badge.wifi",        hex: "#E8A317"),
        .init(id: "decade",    title: "Random Decade",          icon: "calendar",             hex: "#C9A66B"),
        .init(id: "pubdomain", title: "Public Domain Day",      icon: "party.popper.fill",    hex: "#E8A317"),
        .init(id: "party",     title: "Party Play",             icon: "sparkles.tv.fill",     hex: "#FF4D8D"),
        .init(id: "cartoon",   title: "Cartoon Mode",           icon: "pawprint.fill",        hex: "#3FA796"),
        .init(id: "saver",     title: "Cover Art Wall",         icon: "square.grid.3x3.fill", hex: "#0047FF"),
    ]
    @State private var showSaver = false

    // #3/#2: a lineup presented full-screen (muted for party play).
    fileprivate struct ModeLineup: Identifiable {
        let id = UUID()
        let items: [Catalog.Item]
        let muted: Bool
    }
    @State private var mode: ModeLineup?

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 32), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            header
            LazyVGrid(columns: cols, spacing: 32) {
                ForEach(actions) { action in
                    Button { perform(action) } label: {
                        SurpriseTile(action: action)
                    }
                    .buttonStyle(.card)
                    .focused($focused, equals: action.id)
                }
            }
            .padding(.horizontal, 80)
            Spacer(minLength: 0)
        }
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            focused = actions.first?.id
        }
        .fullScreenCover(item: $mode) { m in
            if let screen = PlayerScreen(lineup: m.items, startMuted: m.muted) {
                screen
            }
        }
        .fullScreenCover(isPresented: $showSaver) { ScreensaverView() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Surprise Me")
                .font(.system(size: 52, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("Eleven ways to wander the archive — pick one, or press again to re-roll.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 80)
    }

    private func perform(_ action: Action) {
        switch action.id {
        case "film":
            if let item = store.dbRandomPlayable() { router.push(item) }
        case "tv":
            if let series = store.dbRandomSeries() { router.push(series) }
        case "animation":
            if let item = store.dbRandomPlayable(contentType: "animation") { router.push(item) }
        case "scifi":
            if let item = store.dbRandomByGenre(["Science Fiction", "Sci-Fi", "Horror"]) { router.push(item) }
        case "newsreel":
            if let item = store.dbRandomPlayable(contentType: "newsreel") { router.push(item) }
        case "ephemera":
            if let item = store.dbRandomPlayable(contentType: "ephemeral") { router.push(item) }
        case "commercial":
            if let item = store.dbRandomPlayable(contentType: "commercial") { router.push(item) }
        case "decade":
            if let decade = store.dbDecadeCounts().keys.randomElement() {
                router.push(BrowseFilter(decade: decade))
            }
        case "pubdomain":
            router.push(PublicDomainRoute())
        case "party":
            mode = ModeLineup(items: partyLineup(), muted: true)
        case "cartoon":
            mode = ModeLineup(items: cartoonLineup(), muted: false)
        case "saver":
            showSaver = true
        default:
            break
        }
    }

    // #3 party play: a visually-striking, muted continuous lineup — animation +
    // silent cinema + popular features, all with real artwork, shuffled.
    private func partyLineup() -> [Catalog.Item] {
        var pool = store.dbBrowse(contentType: "animation", sort: .popular, limit: 120)
            + store.dbBrowse(contentType: "silent-film", sort: .popular, limit: 120)
            + store.dbBrowse(sort: .popular, limit: 120)
        pool = pool.filter { $0.videoURLParsed != nil && $0.hasDesignedArtwork }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.archiveID).inserted }
        pool.shuffle()
        return Array(pool.prefix(200))
    }

    // #2 cartoon mode (minimal): a continuous animation lineup; adult content is
    // already filtered by default, so this is kid-safe. Full simplified shell -> #2b.
    private func cartoonLineup() -> [Catalog.Item] {
        var pool = store.dbBrowse(contentType: "animation", sort: .popular, limit: 250)
            .filter { $0.videoURLParsed != nil && $0.hasDesignedArtwork }
        pool.shuffle()
        return pool
    }
}

// MARK: - Action tile

private struct SurpriseTile: View {
    fileprivate let action: SurpriseView.Action

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [action.accent.opacity(0.9), action.accent.mix(with: .black, 0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: action.icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(action.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(26)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
