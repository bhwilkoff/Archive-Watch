import SwiftUI
import AVKit
import SwiftData

struct DetailView: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [Favorite]
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var allProgress: [WatchProgress]
    @State private var isPlaying = false

    private var isFavorited: Bool {
        favorites.contains { $0.archiveID == item.archiveID }
    }

    private var progress: WatchProgress? {
        allProgress.first(where: { $0.archiveID == item.archiveID })
    }

    private var isLandscape: Bool {
        item.contentType == "tv-series" || item.contentType == "tv-special" ||
        item.contentType == "newsreel" || item.contentType == "documentary" ||
        item.contentType == "home-movie"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                relatedSection
            }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .fullScreenCover(isPresented: $isPlaying) {
            if let url = item.videoURLParsed {
                PlayerScreen(url: url, archiveID: item.archiveID)
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            LinearGradient(
                colors: [.clear, .black.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )
            content
        }
        .frame(minHeight: 900)
    }

    @ViewBuilder
    private var relatedSection: some View {
        let related = relatedItems
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("More Like This")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 28) {
                        ForEach(related) { other in
                            NavigationLink(value: other) {
                                PosterCard(item: other)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 20)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 80)
        }
    }

    private var relatedItems: [Catalog.Item] {
        guard let catalog = store.catalog else { return [] }
        var scored: [(Catalog.Item, Int)] = []
        for other in catalog.items where other.archiveID != item.archiveID {
            var score = 0
            if let d = item.director, !d.isEmpty, d == other.director { score += 100 }
            let sharedCollections = Set(item.collections).intersection(other.collections)
            score += sharedCollections.count * 8
            if item.decade == other.decade { score += 4 }
            if item.contentType == other.contentType { score += 3 }
            let sharedGenres = Set(item.genres).intersection(other.genres)
            score += sharedGenres.count * 2
            if score > 0 { scored.append((other, score)) }
        }
        return scored
            .sorted { ($0.1, $0.0.title) > ($1.1, $1.0.title) }
            .prefix(14)
            .map { $0.0 }
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

            HStack(spacing: 20) {
                Button { isPlaying = true } label: {
                    Label(playLabel, systemImage: "play.fill")
                        .font(.title2.bold())
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.card)
                .disabled(item.videoURLParsed == nil)

                Button(action: toggleFavorite) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.title2)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .foregroundStyle(isFavorited ? Color(hex: "#FF5C35") ?? .red : .white)
                }
                .buttonStyle(.card)

                Text(sourceBadge)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 16)

            if let p = progress, !p.isComplete, p.positionSeconds > 10 {
                ProgressBar(fraction: p.fraction)
                    .frame(maxWidth: 520)
                    .padding(.top, 8)
            }
        }
    }

    private var playLabel: String {
        if let p = progress, !p.isComplete, p.positionSeconds > 10 {
            return "Resume"
        }
        return "Play"
    }

    private func toggleFavorite() {
        if let existing = favorites.first(where: { $0.archiveID == item.archiveID }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(Favorite(archiveID: item.archiveID))
        }
        try? modelContext.save()
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
    let archiveID: String
    @Environment(\.modelContext) private var modelContext
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
    }

    private func setupPlayer() {
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p

        // Resume if we have a prior position.
        let archiveID = self.archiveID
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == archiveID }
        )
        if let existing = try? modelContext.fetch(descriptor).first,
           existing.positionSeconds > 10,
           !existing.isComplete {
            p.seek(to: CMTime(seconds: existing.positionSeconds, preferredTimescale: 600))
        }

        // Record progress every 10 seconds while playing.
        let interval = CMTime(seconds: 10, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                persistProgress(at: time.seconds, duration: p.currentItem?.duration.seconds)
            }
        }
    }

    private func teardownPlayer() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        // One last save on exit.
        if let p = player {
            let position = p.currentTime().seconds
            let duration = p.currentItem?.duration.seconds
            persistProgress(at: position, duration: duration)
        }
        player?.pause()
        player = nil
        timeObserver = nil
    }

    private func persistProgress(at position: Double, duration: Double?) {
        guard position.isFinite, position > 0 else { return }
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == archiveID }
        )
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.positionSeconds = position
                if let d = duration, d.isFinite, d > 0 { existing.durationSeconds = d }
                existing.lastWatchedAt = Date()
            } else {
                let record = WatchProgress(
                    archiveID: archiveID,
                    positionSeconds: position,
                    durationSeconds: (duration?.isFinite == true) ? (duration ?? 0) : 0
                )
                modelContext.insert(record)
            }
            try modelContext.save()
        } catch {
            // Best-effort; don't interrupt playback on save failure.
        }
    }
}

// MARK: - Progress bar used on Detail + Continue Watching cards

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(Color(hex: "#FF5C35") ?? .orange)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
            }
        }
        .frame(height: 4)
    }
}
