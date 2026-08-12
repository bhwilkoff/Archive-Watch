#if os(tvOS)
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
    @State private var showGetSubtitles = false
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
                    CommunityDetailSection(item: item)
                        .padding(.horizontal, 80)
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
            // The Top Shelf's Play button (archivewatch://play/{id}, tvOS-DESIGN
            // §15.5) routes here with autoplay armed. Consumed once, after the
            // view is settled in the hierarchy — presenting a fullScreenCover
            // from the same tick as the push is the sheet-race that shows a
            // black screen. PlayerScreen seeks to the stored WatchProgress on
            // its own, so this resumes rather than restarting.
            .task(id: item.archiveID) {
                guard router.autoplayItemID == item.archiveID else { return }
                router.autoplayItemID = nil
                try? await Task.sleep(for: .milliseconds(250))
                isPlaying = true
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
                if SubtitleFinder.shouldOffer(for: item) { subtitlesButton }
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

    // Subtitles for a film the pipeline never found any for — shown only when
    // there are none, so it disappears the moment the title has them.
    private var subtitlesButton: some View {
        Button { showGetSubtitles = true } label: {
            Image(systemName: "captions.bubble")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(18)
        }
        .buttonStyle(CircleIconStyle())
        .focusEffectDisabled()
        .sheet(isPresented: $showGetSubtitles) { GetSubtitlesView(item: item) }
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
            if let tagline = item.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: 1100, alignment: .leading)
            }

            if let synopsis = item.displaySynopsis {
                Text(synopsis)
                    .font(.system(size: 29, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(6)
                    .frame(maxWidth: 1100, alignment: .leading)
            }

            // Tier 1+2 metadata-expansion facts (Decision 046): franchise,
            // studios, full crew, awards — each shown only when present.
            detailFacts

            // Episode item (Decision 045): a focusable jump to the full series.
            if item.isEpisode, let sid = item.seriesID {
                Button {
                    if let card = store.db?.seriesCard(slug: sid) { router.push(card) }
                } label: {
                    Label("Part of \(item.seriesTitle ?? "the series")", systemImage: "tv")
                }
            }

            // #4 (tvOS-DESIGN §2.3): tappable cast + crew — each opens a browse of
            // that person's other titles (films AND TV) via the FTS names index.
            if !item.cast.isEmpty || (item.director?.isEmpty == false) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 28) {
                        if let d = item.director, !d.isEmpty {
                            PersonChip(name: d, role: "Director", profilePath: item.directorProfilePath) {
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
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                }
                // Don't clip the focus scale or the second line of long names/roles.
                .scrollClipDisabled()
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

    @ViewBuilder
    private var detailFacts: some View {
        let rows = facts
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.0)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(row.1)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    private var facts: [(String, String)] {
        var out: [(String, String)] = []
        if let f = item.franchise, !f.isEmpty { out.append(("Part of", f)) }
        if !item.studios.isEmpty { out.append(("Studio", item.studios.joined(separator: ", "))) }
        if let w = item.writer, !w.isEmpty { out.append(("Writer", w)) }
        if let c = item.composer, !c.isEmpty { out.append(("Music", c)) }
        if let dp = item.cinematographer, !dp.isEmpty { out.append(("Cinematography", dp)) }
        if let a = item.awards, !a.isEmpty { out.append(("Awards", a)) }
        return out
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
            SyncNudge.recordDeletion("fav:\(item.archiveID)", in: modelContext)  // saves + syncs
        } else {
            modelContext.insert(Favorite(archiveID: item.archiveID))
            try? modelContext.save()
            SyncNudge.nudge(modelContext)
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
    var startOffset: TimeInterval = 0   // #92 channels: join the live program in progress
    var channelContext: Bool = false    // VHS: channels opt into the analog overlay
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStore.self) private var store
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var freezeGuard = PlaybackFreezeGuard()
    @State private var captionStall = CaptionStallMonitor()
    @State private var nowPlaying = NowPlayingController()
    @State private var streamLoader: ResilientStreamLoader?
    @State private var captionedLoader: CaptionedHLSLoader?   // Part (a): Config C HLS
    @State private var localSubsLoader: LocalSubtitleHLSLoader?  // subtitles fetched on this device
    @State private var statusObserver: NSKeyValueObservation?
    @State private var timeoutTask: Task<Void, Never>?
    @State private var autoRetried = false   // #10: silently retry once before failing
    @State private var skipCount = 0         // #7: bound auto-skips in a broken lineup
    // If the native HLS-subtitle path fails to load, fall back to the direct MP4
    // through ResilientStreamLoader (proven reliable). Playback is the priority
    // (SCRATCHPAD: "play every single time"); losing the subtitle track beats a
    // dead "resource unavailable". A broken HLS segment URI is the known cause.
    @State private var forceDirectPlayback = false
    // The mirror of the above for the generated-subtitle path: a film with no
    // subtitles of its own plays on the PLAIN url from 27 so the system can
    // caption it (SystemCaptions — the resilient loader is never even offered a
    // track). If that plain path then stalls persistently, come back to
    // ResilientStreamLoader and give up the generated captions — the same
    // "smooth-without-CC beats stutter-with-CC" trade already made above.
    @State private var forceResilientPlayback = false
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
    // #92: seconds to seek into the FIRST program when joining a channel live.
    // Consumed once (zeroed after the first setup) so lineup advances start at 0.
    @State private var joinOffset: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    init(url: URL, archiveID: String, catalogItem: Catalog.Item? = nil,
         lineup: [Catalog.Item]? = nil, startMuted: Bool = false, startOffset: TimeInterval = 0,
         channelContext: Bool = false) {
        self.url = url
        self.archiveID = archiveID
        self.catalogItem = catalogItem
        self.lineup = lineup
        self.startMuted = startMuted
        self.startOffset = startOffset
        self.channelContext = channelContext
        _current = State(initialValue: catalogItem)
        _muted = State(initialValue: startMuted)
        _joinOffset = State(initialValue: startOffset)
        // #6: a lineup IS a channel/party/cartoon session, so autoplay is ON by
        // default for it (the in-player Autoplay setting reflects this, and it
        // keeps going after the fixed lineup is exhausted). Single films fall back
        // to the global Settings default (nil).
        _sessionMode = State(initialValue: lineup != nil ? .sameCategory : nil)
    }

    /// #1 channels / #3 party / #2 cartoon: start a continuous lineup at item 0.
    /// `startOffset` joins the first program in progress (#92 channels live tune-in).
    init?(lineup: [Catalog.Item], startMuted: Bool = false, startOffset: TimeInterval = 0,
          channelContext: Bool = false) {
        guard let first = lineup.first, let url = first.videoURLParsed else { return nil }
        self.init(url: url, archiveID: first.archiveID, catalogItem: first,
                  lineup: lineup, startMuted: startMuted, startOffset: startOffset,
                  channelContext: channelContext)
    }

    // #19: a broken item (dead URL, stale non-MP4 derivative, decode reject, or a
    // load that never readies) must not dead-end on the system "no-entry" circle.
    // Surface a visible, recoverable failure state — same contract as the episode
    // player.
    private enum PlaybackState: Equatable { case loading, ready, failed(String) }
    // #10: give the now-retrying ResilientStreamLoader room to warm a cold node
    // (its first-byte handshake alone allows 30s) before the player-level backstop.
    private let loadTimeout: Duration = .seconds(60)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if case .failed(let message) = playback {
                failureView(message)
            } else if let player {
                AVPlayerContainer(player: player, menuItems: autoplayMenu,
                                  liveCaptionURL: liveCaptionSource,
                                  reviewSource: subtitleReviewSource)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
                    // VHS: analog overlay over channel playback (opt-in, channels only).
                    // allowsHitTesting(false) keeps the native transport fully usable.
                    .overlay {
                        if channelContext && store.channelVHS {
                            VHSVideoOverlay().allowsHitTesting(false)
                        }
                    }
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .onAppear { store.isPlayingVideo = true; setupPlayer() }
        .onDisappear { store.isPlayingVideo = false; teardownPlayer() }
        // #10: autoplay swapped `current` -> rebuild the player for the next film.
        .onChange(of: current?.archiveID) { _, _ in
            autoRetried = false          // #10: fresh retry budget per item
            forceDirectPlayback = false  // new item tries the HLS-subtitle path fresh
            teardownPlayer()
            playback = .loading
            setupPlayer()
        }
    }

    /// What live captions should transcribe, or nil when the film carries a real
    /// subtitle track.
    ///
    /// `forceDirectPlayback` matters here: when the captioned-HLS path fails to
    /// load or stalls, playback drops to the plain MP4 and the subtitle track
    /// goes with it. Keying only on `subtitleHLSURL` left exactly those films —
    /// the ones whose subtitles just failed — with no captions at all.
    private var liveCaptionSource: URL? {
        let active = current ?? catalogItem
        guard active?.subtitleHLSURL == nil || forceDirectPlayback else { return nil }
        return active?.videoURLParsed ?? url
    }

    /// When the film HAS published subtitles, what is needed to CHECK them:
    /// the audio to transcribe and the file to check against.
    private var subtitleReviewSource: (video: URL, vtt: URL)? {
        guard liveCaptionSource == nil else { return nil }
        let active = current ?? catalogItem
        guard let video = active?.videoURLParsed ?? url as URL?,
              let vtt = active?.publishedVTTURL else { return nil }
        return (video, vtt)
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
                    autoRetried = false
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
                .buttonStyle(BarButtonStyle())
            }
            .padding(.top, 12)
        }
    }

    // #10: a load failure (status .failed or the load-timeout backstop) silently
    // rebuilds the player ONCE before surfacing the error — the overwhelmingly
    // common case is a cold Archive node that succeeds on the second attempt
    // (exactly what hitting "Try Again" did manually). Only a second failure
    // shows the recoverable error screen.
    private func handleLoadFailure(_ message: String) {
        if !autoRetried {
            autoRetried = true
            // If this item used the HLS-subtitle path, the retry drops it and
            // plays the MP4 directly — a broken HLS playlist must never make an
            // otherwise-playable film unplayable.
            if (current ?? catalogItem)?.subtitleHLSURL != nil { forceDirectPlayback = true }
            teardownPlayer(persist: false)
            playback = .loading
            setupPlayer()
        } else if lineup != nil && skipCount < 10 {
            // #7: continuous modes (channel / cartoon / party) must keep flowing —
            // a title that won't load (after its one retry) is SKIPPED to the next,
            // not turned into a dead-end error screen. Bounded so an all-broken
            // lineup eventually surfaces the error instead of looping forever.
            skipCount += 1
            advanceNow()
        } else {
            playback = .failed(message)
        }
    }

    private var activeArchiveID: String { current?.archiveID ?? archiveID }

    // Part (c): a persistent mid-stream stall on the native-HLS (captioned) path
    // drops CC and rebuilds on the resilient MP4. persist:true captures the
    // current position first so setupPlayer resumes at (within ~5s of) the stall.
    private func forceDirectFallback() {
        guard !forceDirectPlayback, (current ?? catalogItem)?.subtitleHLSURL != nil else { return }
        forceDirectPlayback = true
        teardownPlayer(persist: true)
        playback = .loading
        setupPlayer()
    }

    // The twin of the above for the generated-subtitle path: a persistent stall
    // on the plain-URL playback that lets the system caption gives the resilient
    // loader back, at the cost of those captions.
    private func forceResilientFallback() {
        guard !forceResilientPlayback else { return }
        forceResilientPlayback = true
        teardownPlayer(persist: true)
        playback = .loading
        setupPlayer()
    }

    private func setupPlayer() {
        playback = .loading
        let active = current ?? catalogItem
        let playURL = active?.videoURLParsed ?? url
        let playerItem: AVPlayerItem
        if let hls = active?.subtitleHLSURL, !forceDirectPlayback {
            // Part (a) Config C: keep the native CC menu but START on a known-live
            // storage node — a resource-loader delegate serves the HLS playlists
            // with the video segment rewritten to a freshly node-resolved direct
            // https URL (skips the /download 302 + node-rotation-at-start). The
            // segment stays AVFoundation-owned (no mid-stream failover — that's
            // Part c's stall fallback). streamLoader stays nil.
            let (asset, hlsLoader) = CaptionedHLSLoader.makeAsset(hls: hls, downloadURL: playURL)
            captionedLoader = hlsLoader
            playerItem = AVPlayerItem(asset: asset)
        } else if !forceDirectPlayback,
                  let dir = SubtitleStore.cachedDir(for: activeArchiveID),
                  let (asset, subsLoader) = LocalSubtitleHLSLoader.makeAsset(
                    dir: dir, downloadURL: playURL,
                    resolveNode: { await ResilientStreamLoader.resolvedNodeURL(for: $0) }) {
            // Subtitles the viewer fetched or transcribed on this device. Same
            // Config C shape, playlists read off disk instead of the network.
            localSubsLoader = subsLoader
            playerItem = AVPlayerItem(asset: asset)
        } else if !forceResilientPlayback,
                  SystemCaptions.prefersDirectPlayback(hasPublishedSubtitles: false) {
            // From 27 the system generates subtitles on device for video that
            // carries none — but ONLY for an ordinary asset. Measured on
            // macOS 27, one shape per process: a direct https MP4 produces text
            // in ~33s, while through our `aw-stream://` loader no subtitle track
            // is ever offered at all, and an HLS playlist wrapping the same MP4
            // is offered one that stays silent forever.
            //
            // So the resilient loader is what has to give way, and it gives way
            // HERE rather than by swapping mid-playback: the previous design
            // waited for a track, selected it, listened, and only then moved to
            // the direct URL — a sequence gated behind a track that never
            // arrives, which is why an Apple TV showed file-based captions and
            // never a generated one.
            //
            // The cost is Decisions 021/031/034's resume-on-reset and node
            // failover, for films with no subtitles, on 27 only. `captionStall`
            // below is the safety net: a persistent stall rebuilds on the
            // resilient loader.
            playerItem = AVPlayerItem(url: playURL)
        } else {
            let (asset, loader) = ResilientStreamLoader.makeAsset(for: playURL)
            streamLoader = loader
            playerItem = AVPlayerItem(asset: asset)
        }
        if let active {
            playerItem.externalMetadata = makeExternalMetadata(for: active)
        }
        // Cap commercial breaks at the user's preferred length (Channels view /
        // Settings; 0 = play in full). When capped, AVFoundation fires
        // DidPlayToEndTime at the cap and the lineup advances to the next title.
        if active?.contentType == "commercial", store.commercialBreakMaxSeconds > 0 {
            playerItem.forwardPlaybackEndTime =
                CMTime(seconds: Double(store.commercialBreakMaxSeconds), preferredTimescale: 600)
        }
        let p = AVPlayer(playerItem: playerItem)
        tunePlaybackBuffering(item: playerItem, player: p)
        p.isMuted = muted   // #3 party play (persists across lineup advances)
        player = p
        freezeGuard.attach(to: p, item: playerItem)
        nowPlaying.begin(posterURL: active?.posterURLParsed, item: playerItem)
        // Part (c): captioned items play native HLS (bypassing ResilientStreamLoader).
        // If that path STUTTERS persistently, drop CC and rebuild on the resilient
        // MP4 — smooth-without-CC beats stutter-with-CC. The existing hard-failure
        // fallback (handleLoadFailure) stays as the startup safety net.
        if active?.subtitleHLSURL != nil, !forceDirectPlayback {
            captionStall.attach(player: p, item: playerItem) { forceDirectFallback() }
        } else if !forceResilientPlayback,
                  SystemCaptions.prefersDirectPlayback(hasPublishedSubtitles: false) {
            // The generated-subtitle path gave up the resilient loader to get
            // captioned at all. Same trade, same safety net: if it stutters
            // persistently, come back to the loader and lose the captions.
            captionStall.attach(player: p, item: playerItem) { forceResilientFallback() }
        }

        // Watch the item ready or fail so a broken stream becomes a visible,
        // recoverable error instead of the dead "no-entry" circle (#19). KVO can
        // fire off-main; hop to the main actor before touching view state.
        statusObserver = playerItem.observe(\.status, options: [.new]) { observed, _ in
            Task { @MainActor in
                switch observed.status {
                case .readyToPlay:
                    playback = .ready
                    skipCount = 0          // #7: a good item resets the skip budget
                    timeoutTask?.cancel()
                    // Start playback on ready — covers BOTH the first item and
                    // every lineup/autoplay advance. The AVPlayerContainer's
                    // .onAppear { play() } only fires for the first item; when
                    // `current` swaps, the controller is updated in place (no
                    // re-appear), so without this the next video loads + seeks to
                    // its resume position but never starts (#5 Play Next bug).
                    p.play()
                case .failed:
                    timeoutTask?.cancel()
                    handleLoadFailure(observed.error?.localizedDescription
                                      ?? "The video couldn't be loaded.")
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
                handleLoadFailure("This title is taking too long to load. The source may be temporarily unavailable.")
            }
        }

        let aid = activeArchiveID
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == aid }
        )
        var didSeek = false
        if let existing = try? modelContext.fetch(descriptor).first,
           existing.positionSeconds > 10,
           !existing.isComplete {
            p.seek(to: CMTime(seconds: existing.positionSeconds, preferredTimescale: 600))
            didSeek = true
        }
        // #92: join the channel's current program in progress (only when there's
        // no resume position to honor). Consumed once so lineup advances start at 0.
        if !didSeek, joinOffset > 5 {
            p.seek(to: CMTime(seconds: joinOffset, preferredTimescale: 600))
        }
        joinOffset = 0

        let interval = CMTime(seconds: 5, preferredTimescale: 600)
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
        captionStall.detach()
        nowPlaying.end()
        if persist, let p = player {
            persistProgress(at: p.currentTime().seconds, duration: p.currentItem?.duration.seconds)
        }
        player?.pause()
        player = nil
        timeObserver = nil
        streamLoader = nil
        captionedLoader = nil
        localSubsLoader = nil
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
            SyncNudge.nudge(modelContext)   // push progress promptly (debounced) for cross-device resume
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

struct PersonChip: View {   // reused by SeriesDetailView's cast row
    let name: String
    let role: String?
    let profilePath: String?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private let chipWidth: CGFloat = 200
    private let avatar: CGFloat = 150

    var body: some View {
        // #7: only the avatar is the focusable .card button (so focus scaling
        // never clips text). Name + role sit below in a FIXED-HEIGHT block so all
        // chips align on one baseline and a 2-line name/role is never cut off.
        VStack(spacing: 12) {
            Button(action: action) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12))
                    if let url = profileURL {
                        RemoteImage(url: url, targetSize: CGSize(width: 300, height: 300))
                            .clipShape(Circle())
                    } else {
                        Text(initials)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: avatar, height: avatar)
            }
            // #5: a circular focus style (glass + ring + scale), NOT .card — the
            // .card platter drew a distracting rounded rectangle behind the circle.
            .buttonStyle(CircleIconStyle())
            .focused($isFocused)

            VStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                if let role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
            }
            // Reserve room for 2-line name + 2-line role, top-aligned — uniform
            // chips, no clipping, no overlap with neighbors.
            .frame(width: chipWidth, height: 92, alignment: .top)
            .opacity(isFocused ? 1.0 : 0.8)
            .animation(Motion.focus, value: isFocused)
        }
        .frame(width: chipWidth)
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

struct ShareSheet: View {   // reused by SeriesDetailView (series + episodes)
    let title: String
    let archiveID: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var doneFocused: Bool

    init(title: String, archiveID: String) {
        self.title = title
        self.archiveID = archiveID
    }
    init(item: Catalog.Item) {
        self.init(title: item.title, archiveID: item.archiveID)
    }

    // The QR sends people to OUR web app (Decision 030) — the same title,
    // playable in the browser, with the open-in-app handoff for phones.
    // LoC items stay on loc.gov (the web viewer can't resolve loc: ids).
    private var webURL: String {
        if archiveID.hasPrefix("loc:") { return "https://www.loc.gov" }
        if archiveID.hasPrefix("series:") {
            return "https://archivewatch.org/series/\(archiveID.dropFirst(7))"
        }
        return "https://archivewatch.org/item/\(archiveID)"
    }

    var body: some View {
        VStack(spacing: 28) {
            Text("Share \u{201C}\(title)\u{201D}")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            QRCode(string: webURL)
                .frame(width: 300, height: 300)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 6) {
                Text("Scan to watch on archivewatch.org")
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

#endif
