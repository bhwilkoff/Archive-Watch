import SwiftUI
import AVKit

struct DetailView: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @State private var isPlaying = false

    private var isLandscape: Bool {
        item.contentType == "tv-series" || item.contentType == "tv-special" ||
        item.contentType == "newsreel" || item.contentType == "documentary" ||
        item.contentType == "home-movie"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            LinearGradient(
                colors: [.clear, .black.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )
            content
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $isPlaying) {
            if let url = item.videoURLParsed {
                PlayerScreen(url: url)
            }
        }
    }

    private var backdrop: some View {
        Group {
            if item.hasDesignedArtwork, let url = item.backdropURLParsed ?? item.posterURLParsed {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.black
                    }
                }
            } else {
                // Category accent wash for procedural items
                LinearGradient(
                    colors: [
                        store.accentColor(forCategory: categoryID).opacity(0.5),
                        .black
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .overlay(Color.black.opacity(0.35))
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: 48) {
            poster
            info
            Spacer()
        }
        .padding(80)
    }

    @ViewBuilder
    private var poster: some View {
        Group {
            if item.hasDesignedArtwork, let url = item.posterURLParsed {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ProceduralPoster(item: item, accent: store.accentColor(forCategory: categoryID),
                                         aspectRatio: isLandscape ? 16.0/9.0 : 2.0/3.0)
                    }
                }
            } else {
                ProceduralPoster(item: item, accent: store.accentColor(forCategory: categoryID),
                                 aspectRatio: isLandscape ? 16.0/9.0 : 2.0/3.0)
            }
        }
        .frame(width: 340, height: isLandscape ? 191 : 510)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var categoryID: String {
        switch item.contentType {
        case "tv-series", "tv-special": return "tv-series"
        case "silent-film": return "silent-film"
        case "animation": return "animation"
        case "newsreel": return "newsreel"
        case "documentary": return "documentary"
        case "ephemeral": return "ephemeral"
        case "short-film": return "short-film"
        default: return "feature-film"
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.title)
                .font(.system(size: 56, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)

            HStack(spacing: 16) {
                if let year = item.year { Text(String(year)) }
                if let r = item.runtimeSeconds, r > 0 { Text(formatRuntime(r)) }
                if !item.genres.isEmpty { Text(item.genres.prefix(3).joined(separator: " · ").capitalized) }
            }
            .font(.title3)
            .foregroundStyle(.white.opacity(0.7))

            if let synopsis = item.synopsis, !synopsis.isEmpty {
                Text(synopsis)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(6)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            if let byline = item.byline {
                Text(byline)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let series = item.seriesName, series != item.title {
                Text(series)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if !item.cast.isEmpty {
                Text("Starring " + item.cast.prefix(5).map(\.name).joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }

            HStack(spacing: 24) {
                Button {
                    isPlaying = true
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.title2.bold())
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.card)
                .disabled(item.videoURLParsed == nil)

                Text(sourceBadge)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 16)
        }
    }

    private var sourceBadge: String {
        var parts: [String] = ["Archive"]
        if item.tmdbID != nil { parts.append("TMDb") }
        if item.wikidataQID != nil { parts.append("Wikidata") }
        return parts.joined(separator: " · ")
    }

    private func formatRuntime(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

struct PlayerScreen: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            }
        }
        .onAppear {
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
