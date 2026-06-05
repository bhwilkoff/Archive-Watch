import SwiftUI
import SwiftData

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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserChannel.createdAt, order: .reverse) private var userChannels: [UserChannel]
    @State private var playing: ChannelLineup?
    @State private var showCreate = false

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 32), count: 3)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                LazyVGrid(columns: cols, spacing: 32) {
                    // #1b: create-your-own + saved user channels first.
                    Button { showCreate = true } label: { CreateChannelCard() }
                        .buttonStyle(.card)
                    ForEach(userChannels) { uc in
                        Button { play(lineup(forUser: uc)) } label: { UserChannelCard(channel: uc) }
                            .buttonStyle(.card)
                            .contextMenu {
                                Button(role: .destructive) {
                                    modelContext.delete(uc); try? modelContext.save()
                                } label: { Label("Delete Channel", systemImage: "trash") }
                            }
                    }
                    ForEach(Channel.all) { channel in
                        Button { play(lineup(for: channel)) } label: { ChannelCard(channel: channel) }
                            .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
            }
            .padding(.vertical, 44)
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(item: $playing) { box in
            if let screen = PlayerScreen(lineup: box.items) { screen } else { ChannelUnavailable() }
        }
        .sheet(isPresented: $showCreate) { CreateChannelSheet() }
    }

    private func play(_ items: [Catalog.Item]) { playing = ChannelLineup(items: items) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channels")
                .font(.system(size: 52, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("Tune in and it just plays — each title rolls into the next. Build your own from any filter.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 80)
    }

    private func lineup(for channel: Channel) -> [Catalog.Item] {
        let raw = channel.genre.map { store.dbBrowse(genre: $0, sort: .popular, limit: 200) }
            ?? store.dbBrowse(contentType: channel.contentType, sort: .popular, limit: 200)
        return finalize(raw)
    }

    private func lineup(forUser uc: UserChannel) -> [Catalog.Item] {
        finalize(store.dbBrowse(contentType: uc.contentType, decade: uc.decade,
                                genre: uc.genre, sort: .popular, limit: 250))
    }

    private func finalize(_ items: [Catalog.Item]) -> [Catalog.Item] {
        var programs = items.filter { $0.videoURLParsed != nil && $0.hasDesignedArtwork }
        programs.shuffle()
        return weaveCommercials(into: programs)
    }

    /// #89 (Channels P1): drop a vintage PD commercial between programs so a
    /// channel feels like broadcast TV, not a playlist. Gated by the
    /// channelCommercialBreaks setting. Commercials use procedural posters, so
    /// they're filtered on playability only (not designed artwork).
    private func weaveCommercials(into programs: [Catalog.Item]) -> [Catalog.Item] {
        guard store.channelCommercialBreaks, programs.count > 1 else { return programs }
        let ads = store.dbRandomCommercials(limit: 60).filter { $0.videoURLParsed != nil }
        guard !ads.isEmpty else { return programs }
        var out: [Catalog.Item] = []
        out.reserveCapacity(programs.count * 2)
        for (i, program) in programs.enumerated() {
            out.append(program)
            if i < programs.count - 1 { out.append(ads[i % ads.count]) }
        }
        return out
    }
}

struct ChannelLineup: Identifiable { let id = UUID(); let items: [Catalog.Item] }

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

// MARK: - #1b user channels: create card, card, sheet

private struct CreateChannelCard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10]))
                .foregroundStyle(.white.opacity(0.3))
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.system(size: 50))
                Text("Create Channel").font(.system(size: 24, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
        }
        .frame(height: 220)
    }
}

private struct UserChannelCard: View {
    let channel: UserChannel
    private var summary: String {
        [channel.genre, channel.contentType.map { $0.replacingOccurrences(of: "-", with: " ").capitalized },
         channel.decade.map { "\(String($0))s" }].compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: "#0047FF") ?? .blue, .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56)).foregroundStyle(.white.opacity(0.18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(20)
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name).font(.system(size: 30, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(summary.isEmpty ? "All titles" : summary)
                    .font(.system(size: 19)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
            .padding(22)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct CreateChannelSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var genre = "Any"
    @State private var type = "Any"
    @State private var decade = 0   // 0 = Any
    @FocusState private var nameFocused: Bool

    private let genres = ["Any", "Drama", "Comedy", "Crime", "Thriller", "Romance",
                          "Action", "Horror", "Mystery", "Western", "Documentary",
                          "Adventure", "War", "Fantasy", "Family", "Music", "Science Fiction"]
    private let types = ["Any", "feature-film", "animation", "silent-film",
                         "short-film", "newsreel", "documentary"]
    private let decades = [0, 1900, 1910, 1920, 1930, 1940, 1950, 1960, 1970, 1980, 1990, 2000, 2010]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (genre != "Any" || type != "Any" || decade != 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Create a Channel").font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
            TextField("Channel name", text: $name)
                .textFieldStyle(.plain).padding(14)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .focused($nameFocused)
            Picker("Genre", selection: $genre) { ForEach(genres, id: \.self) { Text($0) } }
            Picker("Type", selection: $type) {
                ForEach(types, id: \.self) { Text($0 == "Any" ? "Any" : $0.replacingOccurrences(of: "-", with: " ").capitalized) }
            }
            Picker("Era", selection: $decade) {
                ForEach(decades, id: \.self) { Text($0 == 0 ? "Any" : "\(String($0))s") }
            }
            HStack(spacing: 20) {
                Button("Create") {
                    ctx.insert(UserChannel(
                        name: name.trimmingCharacters(in: .whitespaces),
                        genre: genre == "Any" ? nil : genre,
                        contentType: type == "Any" ? nil : type,
                        decade: decade == 0 ? nil : decade))
                    try? ctx.save(); dismiss()
                }
                .buttonStyle(.borderedProminent).disabled(!canSave)
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .padding(60)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.93).ignoresSafeArea())
        .onAppear { nameFocused = true }
    }
}
