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
                            ForEach(characters, id: \.name) { ch in
                                NavigationLink(value: KidsGroup(title: ch.name, items: ch.items)) {
                                    KidsTile(title: ch.name, cover: cover(ch.items), circular: true)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                    if !collections.isEmpty {
                        KidsRow(title: "Collections") {
                            ForEach(collections, id: \.title) { c in
                                NavigationLink(value: KidsGroup(title: c.title, items: c.items)) {
                                    KidsTile(title: c.title, cover: cover(c.items), circular: false)
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
        .task {
            characters = store.kidsCharacters()
            collections = store.kidsCollections()
            try? await Task.sleep(for: .milliseconds(120))
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
    }

    private func cover(_ items: [Catalog.Item]) -> URL? {
        items.first(where: { $0.posterURLParsed != nil })?.posterURLParsed
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
    let circular: Bool

    private var size: CGSize { circular ? CGSize(width: 280, height: 280) : CGSize(width: 360, height: 240) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: cover,
                            targetSize: CGSize(width: size.width * 2, height: size.height * 2),
                            contentMode: .fill,
                            placeholder: Color.white.opacity(0.15))
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: circular ? size.width / 2 : 28))
            }
            .overlay(
                RoundedRectangle(cornerRadius: circular ? size.width / 2 : 28)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 5)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)

            Text(title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: size.width)
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
