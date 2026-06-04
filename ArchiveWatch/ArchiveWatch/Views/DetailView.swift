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
    static let viewingActivityType = "com.bhwilkoff.archivewatch.viewing"
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var favorites: [Favorite]
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var allProgress: [WatchProgress]
    @State private var isPlaying = false
    @State private var showShare = false
    @State private var showAddPlaylist = false
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
            // NSUserActivity (Decision 015): advertises the open title to
            // Siri suggestions, Spotlight, and Handoff. Full "Add to Up
            // Next" additionally needs `NSUserActivityTypes` declared in
            // Info.plist with this type string (see SCRATCHPAD next steps).
            .userActivity(Self.viewingActivityType, isActive: true) { activity in
                // Note: persistentIdentifier + isEligibleForPrediction are
                // iOS-only; on tvOS only handoff + search are available.
                activity.title = item.title
                activity.userInfo = ["archiveID": item.archiveID]
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch = true
            }
            .fullScreenCover(isPresented: $isPlaying) {
                if let url = item.videoURLParsed {
                    PlayerScreen(url: url, archiveID: item.archiveID, catalogItem: item)
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
                if let rating = item.imdbRatingDisplay {
                    HStack(spacing: 7) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(hex: "#F5C518") ?? .yellow)  // IMDb gold
                        Text(rating)
                            .fontWeight(.semibold)
                        if let votes = item.imdbVotesDisplay {
                            Text("(\(votes))")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                if let rated = item.contentRating {
                    Text(rated)
                        .font(.system(size: 21, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                }
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
                shareButton
                playlistButton
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

    // #16 (tvOS-DESIGN §8.6): tvOS has no share sheet — hand off to a phone via a
    // QR + deep link / archive.org URL.
    private var shareButton: some View {
        Button { showShare = true } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(18)
        }
        .buttonStyle(CircleIconStyle())
        .focusEffectDisabled()
        .sheet(isPresented: $showShare) { ShareSheet(item: item) }
    }

    // #12: add this title to a playlist (or create one).
    private var playlistButton: some View {
        Button { showAddPlaylist = true } label: {
            Image(systemName: "text.badge.plus")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(18)
        }
        .buttonStyle(CircleIconStyle())
        .focusEffectDisabled()
        .sheet(isPresented: $showAddPlaylist) { AddToPlaylistSheet(archiveID: item.archiveID) }
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

            // #4 (tvOS-DESIGN §2.3): tappable cast + crew — each opens a browse of
            // that person's other titles (films AND TV) via the FTS names index.
            if !item.cast.isEmpty || (item.director?.isEmpty == false) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        if let d = item.director, !d.isEmpty {
                            PersonChip(name: d, role: "Director", profilePath: nil) {
                                router.push(BrowseFilter(person: d))
                            }
                        }
                        ForEach(Array(item.cast.prefix(12)), id: \.name) { member in
                            PersonChip(name: member.name, role: member.character,
                                       profilePath: member.profilePath) {
                                router.push(BrowseFilter(person: member.name))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .focusSection()
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
        // Candidate pool from the DB (Decision 017): same content type +
        // same director — then scored in-view for the best matches, instead
        // of scanning the whole catalog.
        var pool = store.dbRelated(to: item)
        if let d = item.director, !d.isEmpty { pool += store.dbByDirector(d) }
        var seen = Set([item.archiveID]); pool = pool.filter { seen.insert($0.archiveID).inserted }
        guard !pool.isEmpty else { return [] }
        var scored: [(Catalog.Item, Int)] = []
        for other in pool where other.archiveID != item.archiveID {
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
    var catalogItem: Catalog.Item? = nil
    var lineup: [Catalog.Item]? = nil   // #1 channels: a fixed continuous lineup
    var startMuted: Bool = false        // #3 party play: video-only by default
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStore.self) private var store
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var freezeGuard = PlaybackFreezeGuard()
    @State private var nowPlaying = NowPlayingController()
    @State private var streamLoader: ResilientStreamLoader?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var timeoutTask: Task<Void, Never>?
    @State private var endObserver: NSObjectProtocol?
    @State private var playback: PlaybackState = .loading
    // #10: the item currently playing. Autoplay swaps this on end-of-item; the
    // player rebuilds (like EpisodePlayerScreen's currentEpisode). nil only when
    // launched without a catalog item (deep link) — then autoplay is inert.
    @State private var current: Catalog.Item?
    // Per-video autoplay override; nil = use the global Settings default.
    @State private var sessionMode: AutoplayMode?
    @State private var lineupIndex = 0
    @State private var muted = false
    @Environment(\.dismiss) private var dismiss

    init(url: URL, archiveID: String, catalogItem: Catalog.Item? = nil,
         lineup: [Catalog.Item]? = nil, startMuted: Bool = false) {
        self.url = url
        self.archiveID = archiveID
        self.catalogItem = catalogItem
        self.lineup = lineup
        self.startMuted = startMuted
        _current = State(initialValue: catalogItem)
        _muted = State(initialValue: startMuted)
        // #6: a lineup IS a channel/party/cartoon session, so autoplay is ON by
        // default for it (the in-player Autoplay setting reflects this, and it
        // keeps going after the fixed lineup is exhausted). Single films fall back
        // to the global Settings default (nil).
        _sessionMode = State(initialValue: lineup != nil ? .sameCategory : nil)
    }

    /// #1 channels / #3 party / #2 cartoon: start a continuous lineup at item 0.
    init?(lineup: [Catalog.Item], startMuted: Bool = false) {
        guard let first = lineup.first, let url = first.videoURLParsed else { return nil }
        self.init(url: url, archiveID: first.archiveID, catalogItem: first,
                  lineup: lineup, startMuted: startMuted)
    }

    // #19: a broken item (dead URL, stale non-MP4 derivative, decode reject, or a
    // load that never readies) must not dead-end on the system "no-entry" circle.
    // Surface a visible, recoverable failure state — same contract as the episode
    // player.
    private enum PlaybackState: Equatable { case loading, ready, failed(String) }
    private let loadTimeout: Duration = .seconds(30)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if case .failed(let message) = playback {
                failureView(message)
            } else if let player {
                AVPlayerContainer(player: player, menuItems: autoplayMenu)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
        // #10: autoplay swapped `current` -> rebuild the player for the next film.
        .onChange(of: current?.archiveID) { _, _ in
            teardownPlayer()
            playback = .loading
            setupPlayer()
        }
    }

    // #10/#3 (tvOS-DESIGN §8.5): per-video transport menu — autoplay override + a
    // mute toggle (the audio toggle for party/background play).
    private var autoplayMenu: [UIMenuElement] {
        let active = sessionMode ?? store.autoplayMode
        let actions = AutoplayMode.allCases.map { mode in
            UIAction(title: mode.label, state: mode == active ? .on : .off) { _ in
                sessionMode = mode
            }
        }
        // #5: a manual "Play Next" in the transport bar so you can advance on
        // demand instead of only at end-of-film (the episode player already has
        // "Next Episode"; movies/channels had no manual next).
        let playNext = UIAction(
            title: "Play Next",
            image: UIImage(systemName: "forward.end.fill")
        ) { _ in advanceNow() }
        let muteToggle = UIAction(
            title: muted ? "Play with Sound" : "Mute",
            image: UIImage(systemName: muted ? "speaker.wave.2.fill" : "speaker.slash.fill")
        ) { _ in
            muted.toggle()
            player?.isMuted = muted
        }
        return [playNext, muteToggle,
                UIMenu(title: "Autoplay Next",
                       image: UIImage(systemName: "play.circle"), children: actions)]
    }

    /// Advance to the next title now: the next lineup item if any, otherwise the
    /// autoplay pick. Falls back to "More Like This" when autoplay is Off so the
    /// manual control is never a dead end. Shared by the manual "Play Next" (#5)
    /// and the end-of-film autoplay (#10).
    private func advanceNow() {
        if let lineup, lineupIndex + 1 < lineup.count {
            lineupIndex += 1
            current = lineup[lineupIndex]
            return
        }
        guard let cur = current else { return }
        let mode = sessionMode ?? store.autoplayMode
        let effective: AutoplayMode = (mode == .off) ? .sameCategory : mode
        if let nextItem = ContinuousPlayback.next(after: cur, mode: effective, store: store) {
            current = nextItem
        }
    }

    @ViewBuilder
    private func failureView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("Can't play this title")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
            HStack(spacing: 20) {
                Button {
                    teardownPlayer(persist: false)
                    playback = .loading
                    setupPlayer()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 24, weight: .semibold))
                        .padding(.horizontal, 28).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                Button { dismiss() } label: {
                    Text("Back")
                        .font(.system(size: 24, weight: .semibold))
                        .padding(.horizontal, 28).padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 12)
        }
    }

    private var activeArchiveID: String { current?.archiveID ?? archiveID }

    private func setupPlayer() {
        playback = .loading
        let active = current ?? catalogItem
        let playURL = active?.videoURLParsed ?? url
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: playURL)
        streamLoader = loader
        let playerItem = AVPlayerItem(asset: asset)
        if let active {
            playerItem.externalMetadata = makeExternalMetadata(for: active)
        }
        let p = AVPlayer(playerItem: playerItem)
        tunePlaybackBuffering(item: playerItem, player: p)
        p.isMuted = muted   // #3 party play (persists across lineup advances)
        player = p
        freezeGuard.attach(to: p, item: playerItem)
        nowPlaying.begin(posterURL: active?.posterURLParsed, item: playerItem)

        // Watch the item ready or fail so a broken stream becomes a visible,
        // recoverable error instead of the dead "no-entry" circle (#19). KVO can
        // fire off-main; hop to the main actor before touching view state.
        statusObserver = playerItem.observe(\.status, options: [.new]) { observed, _ in
            Task { @MainActor in
                switch observed.status {
                case .readyToPlay:
                    playback = .ready
                    timeoutTask?.cancel()
                case .failed:
                    playback = .failed(observed.error?.localizedDescription
                                       ?? "The video couldn't be loaded.")
                    timeoutTask?.cancel()
                default: break
                }
            }
        }
        // Backstop: if the item never readies (silent stall), fail visibly.
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: loadTimeout)
            guard !Task.isCancelled else { return }
            if playback == .loading {
                playback = .failed("This title is taking too long to load. The source may be temporarily unavailable.")
            }
        }

        let aid = activeArchiveID
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == aid }
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

        // #10: when this film finishes, autoplay the next per the effective mode.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { _ in
            Task { @MainActor in
                // #1 channels: advance through the fixed lineup first.
                if let lineup, lineupIndex + 1 < lineup.count {
                    lineupIndex += 1
                    current = lineup[lineupIndex]
                    return
                }
                guard let cur = current else { return }
                let mode = sessionMode ?? store.autoplayMode
                if let nextItem = ContinuousPlayback.next(after: cur, mode: mode, store: store) {
                    current = nextItem   // -> onChange rebuilds the player
                }
            }
        }
    }

    private func teardownPlayer(persist: Bool = true) {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        freezeGuard.detach()
        nowPlaying.end()
        if persist, let p = player {
            persistProgress(at: p.currentTime().seconds, duration: p.currentItem?.duration.seconds)
        }
        player?.pause()
        player = nil
        timeObserver = nil
        streamLoader = nil
        statusObserver?.invalidate()
        statusObserver = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func persistProgress(at position: Double, duration: Double?) {
        guard position.isFinite, position > 0 else { return }
        let aid = activeArchiveID
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == aid }
        )
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.positionSeconds = position
                if let d = duration, d.isFinite, d > 0 { existing.durationSeconds = d }
                existing.lastWatchedAt = Date()
            } else {
                let record = WatchProgress(
                    archiveID: aid,
                    positionSeconds: position,
                    durationSeconds: (duration?.isFinite == true) ? (duration ?? 0) : 0,
                    seriesID: nil,
                    episodeTitle: nil,
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

// MARK: - Cast / crew chip (#4)

private struct PersonChip: View {
    let name: String
    let role: String?
    let profilePath: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12))
                    if let url = profileURL {
                        RemoteImage(url: url, targetSize: CGSize(width: 180, height: 180))
                            .clipShape(Circle())
                    } else {
                        Text(initials)
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: 130, height: 130)
                Text(name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1).frame(width: 156)
                if let role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1).frame(width: 156)
                }
            }
        }
        .buttonStyle(.card)
    }

    private var profileURL: URL? {
        guard let p = profilePath, !p.isEmpty else { return nil }
        let path = p.hasPrefix("http") ? p : "https://image.tmdb.org/t/p/w185\(p)"
        return URL(string: path)
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Share sheet (#16, tvOS-DESIGN §8.6)

private struct ShareSheet: View {
    let item: Catalog.Item
    @Environment(\.dismiss) private var dismiss
    @FocusState private var doneFocused: Bool

    private var webURL: String {
        item.archiveID.hasPrefix("loc:")
            ? "https://www.loc.gov"
            : "https://archive.org/details/\(item.archiveID)"
    }

    var body: some View {
        VStack(spacing: 28) {
            Text("Share \u{201C}\(item.title)\u{201D}")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            QRCode(string: webURL)
                .frame(width: 300, height: 300)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 6) {
                Text("Scan with your phone to open on the web")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
                Text(webURL)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .focused($doneFocused)
                .padding(.top, 8)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92).ignoresSafeArea())
        .onAppear { doneFocused = true }
    }
}
