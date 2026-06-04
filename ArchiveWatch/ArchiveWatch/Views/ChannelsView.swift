import SwiftUI

// #1 24-hour programming channels (tvOS-DESIGN §2.2 / §9.1). A channel is a saved
// query realized as a continuous now/next lineup, played through the shared F4
// ContinuousPlayback path (PlayerScreen's lineup). Tapping a channel tunes in —
// it plays straight through, autoplaying each title into the next. Channel queries
// are measured-populated genres + content types (Drama 5.7k … Sci-Fi 599).
struct Channel: Identifiable, Hashable {
    let id: String
    let title: String
    let tagline: String
    let hex: String
    let icon: String
    var contentType: String? = nil
    var genre: String? = nil
    var accent: Color { Color(hex: hex) ?? .accentColor }

    static let all: [Channel] = [
        .init(id: "drama",   title: "Drama Theater",   tagline: "The big stories", hex: "#FF5C35", icon: "theatermasks.fill", genre: "Drama"),
        .init(id: "comedy",  title: "Comedy Hour",     tagline: "Laughs around the clock", hex: "#E8A317", icon: "face.smiling.fill", genre: "Comedy"),
        .init(id: "noir",    title: "Crime & Mystery", tagline: "Shadows and suspects", hex: "#2D5BFF", icon: "magnifyingglass", genre: "Crime"),
        .init(id: "thrill",  title: "Thriller",        tagline: "Edge of your seat", hex: "#0047FF", icon: "bolt.fill", genre: "Thriller"),
        .init(id: "horror",  title: "Horror",          tagline: "After dark", hex: "#7C5BBA", icon: "moon.stars.fill", genre: "Horror"),
        .init(id: "western", title: "Western Trail",   tagline: "The frontier rolls on", hex: "#C9A66B", icon: "hare.fill", genre: "Western"),
        .init(id: "scifi",   title: "Sci-Fi Theater",  tagline: "Worlds beyond", hex: "#3FA796", icon: "atom", genre: "Science Fiction"),
        .init(id: "silent",  title: "Silent Cinema",   tagline: "The age before sound", hex: "#C9A66B", icon: "film.stack.fill", contentType: "silent-film"),
        .init(id: "cartoon", title: "Cartoon Classics",tagline: "Animation all day", hex: "#FF4D8D", icon: "paintbrush.fill", contentType: "animation"),
        .init(id: "news",    title: "Newsreel Desk",   tagline: "History as it broke", hex: "#8A8F98", icon: "newspaper.fill", contentType: "newsreel"),
        .init(id: "docs",    title: "Documentary",     tagline: "Real stories", hex: "#3FA796", icon: "globe.americas.fill", contentType: "documentary"),
    ]
}

struct ChannelsView: View {
    @Environment(AppStore.self) private var store
    @State private var playing: Channel?

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 32), count: 3)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                LazyVGrid(columns: cols, spacing: 32) {
                    ForEach(Channel.all) { channel in
                        Button { playing = channel } label: { ChannelCard(channel: channel) }
                            .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
            }
            .padding(.vertical, 44)
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(item: $playing) { channel in
            if let screen = PlayerScreen(lineup: lineup(for: channel)) {
                screen
            } else {
                ChannelUnavailable()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channels")
                .font(.system(size: 52, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("Tune in and it just plays — each title rolls into the next.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 80)
    }

    private func lineup(for channel: Channel) -> [Catalog.Item] {
        var items: [Catalog.Item]
        if let g = channel.genre {
            items = store.dbBrowse(genre: g, sort: .popular, limit: 200)
        } else {
            items = store.dbBrowse(contentType: channel.contentType, sort: .popular, limit: 200)
        }
        items = items.filter { $0.videoURLParsed != nil && $0.hasDesignedArtwork }
        items.shuffle()
        return items
    }
}

private struct ChannelCard: View {
    let channel: Channel
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [channel.accent.opacity(0.9), channel.accent.mix(with: .black, 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: channel.icon)
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.22))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(20)
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text(channel.tagline)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(22)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct ChannelUnavailable: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 24) {
            Text("This channel has no playable titles yet.")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
            Button("Back") { dismiss() }
                .buttonStyle(.borderedProminent)
                .focused($focused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear { focused = true }
    }
}
