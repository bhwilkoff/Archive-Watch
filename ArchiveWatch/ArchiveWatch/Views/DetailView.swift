import SwiftUI
import AVKit
import SwiftData

// Detail view. Per docs/tvos-playbook.md §9.4: Play button pinned inside
// the hero backdrop (visible on entry, no scroll-jump) with metadata
// flowing below. Hero is 55% of viewport — headroom for the sidebar rail
// on the left and enough image to feel cinematic without swallowing the
// screen.

enum DetailFocusTarget: Hashable {
    case play, favorite, related
}

struct DetailView: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var favorites: [Favorite]
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var allProgress: [WatchProgress]
    @State private var isPlaying = false
    @FocusState private var focusTarget: DetailFocusTarget?

    private var accent: Color {
        store.accentColor(forCategory: categoryID)
    }

    private var isFavorited: Bool {
        favorites.contains { $0.archiveID == item.archiveID }
    }

    private var progress: WatchProgress? {
        allProgress.first(where: { $0.archiveID == item.archiveID })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroWithPinnedActions
                        .id("hero")
                    metadataBlock
                        .padding(.horizontal, 80)
                        .padding(.top, 40)
                        .padding(.bottom, 48)
                    relatedSection
                }
            }
            .background(Color.black)
            .fullScreenCover(isPresented: $isPlaying) {
                if let url = item.videoURLParsed {
                    PlayerScreen(url: url, archiveID: item.archiveID)
                }
            }
            .defaultFocus($focusTarget, .play, priority: .userInitiated)
            .task(id: item.archiveID) {
                // id: item.archiveID so this re-fires when the user
                // pushes a new DetailView (e.g. from "More Like This")
                // without us needing SwiftUI to tear down and rebuild
                // the view. Deferred by one run-loop tick for layout
                // to settle before we claim focus.
                try? await Task.sleep(for: .milliseconds(40))
                focusTarget = .play
            }
            // When focus returns to Play (e.g. user pressed up-arrow
            // from the Related shelf and we forwarded focus), scroll
            // the hero back into view so Play is visible — otherwise
            // the page could sit mid-scroll with focus offscreen.
            .onChange(of: focusTarget) { _, new in
                if new == .play {
                    withAnimation(Motion.transition) {
                        proxy.scrollTo("hero", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Hero with pinned actions
    //
    // Full-width backdrop at native 16:9 scale, fading to black at the
    // bottom so the image dissolves continuously into the page's dark
    // metadata block. No arbitrary crop tuning needed — the fade hides
    // whatever lives at the bottom of the image, and the top of the
    // image (where faces usually live) reads in full.

    private var heroWithPinnedActions: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                .frame(height: 820)
                .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    .clear,
                    .black.opacity(0.45),
                    .black.opacity(0.9),
                    .black
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 820)
            .allowsHitTesting(false)

            heroInfoOverlay
                .padding(.leading, 80)
                .padding(.trailing, 80)
                .padding(.bottom, 84)
        }
        .frame(height: 820)
    }

    private var heroInfoOverlay: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(categoryLabel.uppercased())
                .font(.system(size: 14, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(accent)

            Text(item.title)
                .font(.system(size: 76, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

            HStack(spacing: 18) {
                if let year = item.year { Text(String(year)) }
                if let r = item.runtimeSeconds, r > 0 { Text(formatRuntime(r)) }
                if !item.genres.isEmpty {
                    Text(item.genres.prefix(3).joined(separator: " · ").capitalized)
                }
                if let byline = item.byline { Text(byline) }
            }
            .font(.system(size: 29, weight: .regular))
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 20) {
                playButton
                favoriteButton
            }
            .padding(.top, 8)
            // Dedicated focus section for the action row so up-arrow
            // from the Related shelf below lands cleanly on Play/Fav
            // rather than bouncing through scroll-body whitespace.
            .focusSection()
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private var playButton: some View {
        Button {
            isPlaying = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white).frame(width: 36, height: 36)
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(accent)
                        .offset(x: 1)
                }
                Text(playLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 10)
            .padding(.trailing, 28)
            .padding(.vertical, 10)
        }
        .buttonStyle(PrimaryCTAStyle(accent: accent))
        .focusEffectDisabled()
        .disabled(item.videoURLParsed == nil)
        .focused($focusTarget, equals: .play)
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.title2)
                .foregroundStyle(isFavorited ? accent : .white)
                .padding(18)
        }
        .buttonStyle(CircleIconStyle())
        .focusEffectDisabled()
        .focused($focusTarget, equals: .favorite)
    }

    // MARK: - Metadata block

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let synopsis = item.displaySynopsis {
                Text(synopsis)
                    .font(.system(size: 29, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(6)
                    .frame(maxWidth: 1100, alignment: .leading)
            }

            if !item.cast.isEmpty {
                Text("Starring " + item.cast.prefix(5).map(\.name).joined(separator: ", "))
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }

            if let series = item.seriesName, series != item.title {
                Text(series)
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let p = progress, !p.isComplete, p.positionSeconds > 10 {
                ProgressBar(fraction: p.fraction)
                    .frame(maxWidth: 520)
                    .padding(.top, 6)
            }

            Text(sourceBadge)
                .font(.system(size: 19, weight: .medium))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 6)
        }
    }

    // MARK: - Related

    @ViewBuilder
    private var relatedSection: some View {
        let related = relatedItems
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("More Like This")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(related) { other in
                            PosterTile(item: other) {
                                router.push(other)
                            }
                            // Up-arrow from a related tile forwards
                            // focus to Play. Without this, tvOS can't
                            // reliably hop the ~700pt gap of non-
                            // focusable metadata between the shelf
                            // and the action row, so focus stays
                            // stuck on the shelf.
                            .onMoveCommand { direction in
                                if direction == .up { focusTarget = .play }
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
            }
            .focusSection()
            .padding(.top, 24)
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

    // MARK: - Backdrop

    @ViewBuilder
    private var backdrop: some View {
        if item.hasDesignedArtwork, let url = item.backdropURLParsed ?? item.posterURLParsed {
            // Fit, not fill — preserves the backdrop's natural 16:9
            // aspect without the 1.5× upscale that .fill produces on
            // smaller TMDb sources. Pillarbox bars on the sides blend
            // into black backdrop and fade with the bottom gradient.
            RemoteImage(
                url: url,
                targetSize: CGSize(width: 1920, height: 1080),
                contentMode: .fit,
                placeholder: Color(white: 0.1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            LinearGradient(
                colors: [accent.opacity(0.7), .black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Helpers

    private var categoryID: String {
        switch item.contentType {
        case "tv-series", "tv-special": return "tv-series"
        case "silent-film":  return "silent-film"
        case "animation":    return "animation"
        case "newsreel":     return "newsreel"
        case "documentary":  return "documentary"
        case "ephemeral":    return "ephemeral"
        case "short-film":   return "short-film"
        default:             return "feature-film"
        }
    }

    private var categoryLabel: String {
        store.featured?.category(id: categoryID)?.displayName ?? "Featured"
    }

    private var playLabel: String {
        if let p = progress, !p.isComplete, p.positionSeconds > 10 {
            let remaining = max(0, Int(p.durationSeconds - p.positionSeconds))
            return "Resume  ·  \(formatMin(remaining))"
        }
        return item.runtimeSeconds.map { "Play  ·  \(formatMin($0))" } ?? "Play"
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

    private func formatMin(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

// MARK: - Player screen (unchanged from prior implementation)

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

        let archiveID = self.archiveID
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == archiveID }
        )
        if let existing = try? modelContext.fetch(descriptor).first,
           existing.positionSeconds > 10,
           !existing.isComplete {
            p.seek(to: CMTime(seconds: existing.positionSeconds, preferredTimescale: 600))
        }

        let interval = CMTime(seconds: 10, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                persistProgress(at: time.seconds, duration: p.currentItem?.duration.seconds)
            }
        }
    }

    private func teardownPlayer() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        if let p = player {
            persistProgress(at: p.currentTime().seconds, duration: p.currentItem?.duration.seconds)
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
            // Best-effort save; never interrupt playback.
        }
    }
}

// MARK: - Progress bar

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
