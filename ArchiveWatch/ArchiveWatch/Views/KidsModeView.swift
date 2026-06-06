import SwiftUI

// #1 Cartoon / Kids Mode — a full-screen, brightly-themed REBRAND overlay that
// turns the app into a simple color-cartoon picker for kids. Entered from
// Surprise / Home, exited with Menu.
//
// tvOS kids-UX patterns applied (researched from Apple's kids content + the HIG):
//  - shallow navigation: at most one push (a character/collection -> its grid),
//    Menu always backs out;
//  - big, colorful, image-forward tiles (recognition over reading) — characters
//    are fronted by real cartoon artwork, not icons;
//  - high-contrast bright canvas distinct from the main app's dark cinematheque
//    chrome, so it reads as a different, playful "place";
//  - large hit targets + generous spacing for imprecise navigation.
//
// Color-only, kid-safe content comes from AppStore.kids* (animation, never silent
// B&W, scary subjects filtered). See [[home_filters_and_icon]].
struct KidsModeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var characters: [(name: String, items: [Catalog.Item])] = []
    @State private var collections: [(title: String, items: [Catalog.Item])] = []
    @State private var playing: KidsLineup?
    @FocusState private var playAllFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 44) {
                    header
                    if !characters.isEmpty {
                        KidsRow(title: "Characters") {
                            ForEach(Array(characters.enumerated()), id: \.element.name) { idx, ch in
                                NavigationLink(value: KidsGroup(title: ch.name, items: ch.items)) {
                                    KidsTile(title: ch.name, cover: cover(ch.items, seed: ch.name), tint: Self.tint(idx))
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                    if !collections.isEmpty {
                        KidsRow(title: "Collections") {
                            ForEach(Array(collections.enumerated()), id: \.element.title) { idx, c in
                                NavigationLink(value: KidsGroup(title: c.title, items: c.items)) {
                                    KidsTile(title: c.title, cover: cover(c.items, seed: c.title), tint: Self.tint(idx + 3))
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                    if characters.isEmpty && collections.isEmpty {
                        Text("Loading cartoons…")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 80)
                    }
                }
                .padding(.vertical, 60)
            }
            .background(KidsBackground().ignoresSafeArea())
            .navigationDestination(for: KidsGroup.self) { group in
                KidsGroupView(group: group) { start in playing = KidsLineup(items: start) }
                    .background(KidsBackground().ignoresSafeArea())
            }
        }
        .onExitCommand { dismiss() }
        // Recompute when the catalog DB swaps (seed -> full): if Kids Mode opens
        // before the full catalog has downloaded, the seed only has the most
        // popular cartoons (Popeye/Betty Boop). Re-running on dbGeneration fills in
        // the rest the moment the full DB is ready.
        .task(id: store.dbGeneration) {
            characters = store.kidsCharacters()
            collections = store.kidsCollections()
            try? await Task.sleep(for: .milliseconds(120))
            if characters.isEmpty && collections.isEmpty { return }
            playAllFocused = true
        }
        .fullScreenCover(item: $playing) { box in
            if let screen = PlayerScreen(lineup: box.items) { screen }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cartoons!")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                Text("Pick a character or just press play")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Button { playing = KidsLineup(items: store.kidsCartoonPool(limit: 300)) } label: {
                Label("Play All", systemImage: "play.fill")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 44).padding(.vertical, 24)
            }
            .buttonStyle(.card)
            .focused($playAllFocused)
        }
        .padding(.horizontal, 80)
        // Reach Play All by pressing Up from ANY tile, not just the rightmost.
        .focusSection()
    }

    /// A representative cover, varied per group (a stable seed off the title) so
    /// neighbouring collections don't all show the same lead poster.
    private func cover(_ items: [Catalog.Item], seed: String) -> URL? {
        let art = items.filter { $0.posterURLParsed != nil }
        guard !art.isEmpty else { return nil }
        let h = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return art[h % art.count].posterURLParsed
    }

    /// Bright per-tile accent so the cards stay colorful even when the cover art
    /// is letterboxed (we show the WHOLE cover, never crop it).
    static func tint(_ i: Int) -> Color {
        let palette = ["#FF4D8D", "#FF5C35", "#E8A317", "#3FA796", "#2D5BFF", "#7C5BBA"]
        return Color(hex: palette[i % palette.count]) ?? .pink
    }
}

/// A navigable group of cartoons (a character or a themed collection). Hashed on
/// the (unique) title so the nav value stays cheap and conformance is explicit.
struct KidsGroup: Hashable {
    let title: String
    let items: [Catalog.Item]
    static func == (a: KidsGroup, b: KidsGroup) -> Bool { a.title == b.title }
    func hash(into hasher: inout Hasher) { hasher.combine(title) }
}

private struct KidsLineup: Identifiable {
    let id = UUID()
    let items: [Catalog.Item]
}

// MARK: - Bright playful canvas

private struct KidsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(hex: "#2D5BFF") ?? .blue,
                Color(hex: "#7C5BBA") ?? .purple,
                Color(hex: "#FF4D8D") ?? .pink,
                Color(hex: "#FF5C35") ?? .orange,
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(Color.black.opacity(0.22))   // keep white text + posters readable
    }
}

// MARK: - Rows + tiles

private struct KidsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 36) { content }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 10)
            }
            .scrollClipDisabled()
        }
    }
}

private struct KidsTile: View {
    let title: String
    let cover: URL?
    let tint: Color

    // Uniform 3:2 cards. The cover is shown WHOLE (.fit) over a bright colored
    // field — cartoon covers are a mix of landscape title-cards and portrait
    // posters, so fitting (not cropping) is the only way nothing gets cut off,
    // and the color keeps the card vibrant where the art letterboxes.
    private let w: CGFloat = 320
    private let h: CGFloat = 214

    var body: some View {
        VStack(spacing: 14) {
            RemoteImage(url: cover,
                        targetSize: CGSize(width: w * 2, height: h * 2),
                        contentMode: .fit,
                        placeholder: tint.opacity(0.6))
                .frame(width: w, height: h)
                .background(
                    LinearGradient(colors: [tint, tint.mix(with: .black, 0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.9), lineWidth: 4))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)

            Text(title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: w)
        }
    }
}

// MARK: - A group's cartoons as a big-tile grid

private struct KidsGroupView: View {
    let group: KidsGroup
    let onPlay: ([Catalog.Item]) -> Void
    @FocusState private var firstFocused: Bool

    private let cols = Array(repeating: GridItem(.fixed(240), spacing: 36), count: 5)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 28) {
                    Text(group.title)
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Button { onPlay(group.items.shuffled()) } label: {
                        Label("Play All", systemImage: "play.fill")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 30).padding(.vertical, 16)
                    }
                    .buttonStyle(.card)
                    Spacer()
                }
                .padding(.horizontal, 80)

                LazyVGrid(columns: cols, alignment: .leading, spacing: 44) {
                    ForEach(Array(group.items.enumerated()), id: \.element.archiveID) { idx, item in
                        Button {
                            // Start at this cartoon, then continue through the rest.
                            onPlay(Array(group.items[idx...]) + Array(group.items[..<idx]))
                        } label: {
                            KidsPoster(item: item)
                        }
                        .buttonStyle(.card)
                        .focused($firstFocused, equals: idx == 0)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
            .padding(.top, 50)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(120))
            firstFocused = true
        }
    }
}

private struct KidsPoster: View {
    let item: Catalog.Item
    var body: some View {
        VStack(spacing: 12) {
            RemoteImage(url: item.posterURLParsed,
                        targetSize: CGSize(width: 480, height: 720),
                        contentMode: .fill,
                        placeholder: Color.white.opacity(0.15))
                .frame(width: 240, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.7), lineWidth: 4))
            Text(item.title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(width: 240, height: 50, alignment: .top)
        }
    }
}
