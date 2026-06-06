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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Surprise Me")
                .font(.system(size: 52, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("A dozen ways to wander the archive — pick one, or press again to re-roll.")
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
            router.tab = .party        // now a top-level tab
        case "cartoon":
            router.tab = .cartoons     // now a top-level tab
        case "saver":
            router.tab = .screensaver  // now a top-level tab
        default:
            break
        }
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
