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
    case play, favorite, watched, versions, related
}

/// Seconds of film audio to keep ahead of the picture, and the size of one
/// pull. Small on purpose: the whole point is to ask only for what the picture
/// is about to reach. Outside the view because the puller is detached — a
/// `static let` on a `@MainActor` view is main-actor isolated and cannot be
/// read from there.
private enum FilmAudioPull {
    static let lookahead = 12.0
    static let chunk = 8.0
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

    @State private var showVersions = false
    @State private var versions: [ArchiveVersions.Version] = []
    @State private var loadingVersions = false
    @State private var chosenVersionName: String?

    private var isWatched: Bool {
        store.completedArchiveIDs.contains(item.archiveID)
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

            // "Also known as" (Decision 100). Ten feet away the mismatch is
            // starker than on a phone: the title says one thing and the
            // synopsis under it opens with another name for the same film.
            if let aka = item.alsoKnownAs {
                Text("Also known as \(aka)")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            }

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
                // Play outranks the icon buttons when the row is tight: they are
                // fixed-size circles, it is the one carrying text.
                playButton.layoutPriority(1)
                favoriteButton
                watchedButton
                shareButton
                playlistButton
                versionsButton
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
                // The runtime (or the remaining time on a resume) is the whole
                // point of this label, so it must never be the thing that gives
                // way. Up to SEVEN buttons share this row inside a 1100pt cap,
                // and the Play label is its only flexible child — so SwiftUI
                // compressed it and truncated the time (owner, 2026-08-31:
                // "you should be able to see the full time of any film on the
                // play button"). fixedSize opts it out of that compression.
                Text(playLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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

    // Watched is a badge on tiles, so this is where the viewer corrects it —
    // a film abandoned near the end reads as finished, one seen elsewhere never
    // registers at all (owner, 2026-08-17: one accurate record, everywhere).
    private var watchedButton: some View {
        Button { WatchProgress.setWatched(!isWatched, in: modelContext,
                                          archiveID: item.archiveID)
                 SyncNudge.nudge(modelContext) } label: {
            Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.title2)
                .foregroundStyle(isWatched ? accent : .white)
                .padding(18)
        }
        .buttonStyle(CircleIconStyle())
        .focusEffectDisabled()
        .focused($focusTarget, equals: .watched)
        .accessibilityLabel(isWatched ? "Mark as not watched" : "Mark as watched")
    }

    // The viewer picks which copy of the film to play (owner, 2026-08-17).
    // An archive.org item often holds several transfers, and until now only
    // the pipeline had a say — so a bad evening on one copy had no remedy.
    // Loaded on demand: the list is a network call, and Detail should not pay
    // for it unless it is asked for.
    private var versionsButton: some View {
        Button {
            showVersions = true
            Task { await loadVersions() }
        } label: {
            Image(systemName: "rectangle.stack")
                .font(.title2)
                .foregroundStyle(chosenVersionName == nil ? .white : accent)
                .padding(18)
        }
        .buttonStyle(CircleIconStyle())
        .focusEffectDisabled()
        .focused($focusTarget, equals: .versions)
        .accessibilityLabel("Choose version")
        // One sheet per BUTTON, which is the pattern every other action here
        // follows for a reason: SwiftUI honours a single .sheet per view, so a
        // second one stacked on the same view silently never presents.
        .sheet(isPresented: $showVersions) {
            VersionPickerView(
                archiveID: item.archiveID,
                versions: versions,
                isLoading: loadingVersions,
                pipelineChoiceName: item.videoURLParsed?
                    .lastPathComponent.removingPercentEncoding
            ) { choice in
                ArchiveVersions.choose(choice, for: item.archiveID)
                chosenVersionName = choice?.name
            }
        }
        .onAppear { chosenVersionName = ArchiveVersions.chosenName(for: item.archiveID) }
    }

    private func loadVersions() async {
        guard versions.isEmpty else { return }
        loadingVersions = true
        versions = await ArchiveVersions.list(itemID: item.archiveID)
        loadingVersions = false
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
                // FOCUSABLE, and that is the point. A tvOS ScrollView only
                // scrolls to focusable views, so a plain Text between two
                // buttons is not merely unselectable — the remote SKIPS it and
                // the scroll never brings it into view. The description was
                // therefore unreadable past its sixth line on a television
                // (owner, 2026-08-28: "the individual detail view … skips
                // right over the description"). Focusing it also expands it,
                // so the whole synopsis can be read without a control to press.
                ReadableTextBlock(text: synopsis, collapsedLines: 6)
                    .font(.system(size: 29, weight: .regular))
                    .frame(maxWidth: 1100, alignment: .leading)
                if let prov = item.synopsisProvenance {
                    Text(prov)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 1100, alignment: .leading)
                }
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
    /// True for EPHEMERAL lineups (channel tune-ins, party walls, cartoon
    /// marathons): they never write WatchProgress. A playlist's Play All is a
    /// DELIBERATE lineup and keeps resume — the distinction fix #2 needed and
    /// "lineup == nil" was too blunt to draw.
    var ephemeralLineup: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    // Diagnostics identity (AW_PLAYBACK_DIAG): a fresh @State UUID means a fresh
    // SwiftUI identity — if two AWLIFE screen ids appear in one session, SwiftUI
    // built a SECOND PlayerScreen while the first was still alive, which is the
    // double-player bug the His Girl Friday baseline exposed.
    @State private var screenID = String(UUID().uuidString.prefix(8))
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var freezeGuard = PlaybackFreezeGuard()
    @State private var captionStall = CaptionStallMonitor()
    @State private var nowPlaying = NowPlayingController()
    @State private var streamLoader: ResilientStreamLoader?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var timeoutTask: Task<Void, Never>?
    @State private var autoRetried = false   // #10: silently retry once before failing
    // Owner-approved fallback (2026-08-15): when the best copy can't stream,
    // play a vetted lower-quality copy instead of erroring. Chain:
    // catalog-baked fallbackVideoURL -> same-item smaller derivative
    // (ArchiveFallback, prefetched during the load attempt) -> one retry of
    // the primary -> an honest error naming the Archive's servers.
    @State private var fallbackCandidate: URL?
    @State private var usingFallbackURL: URL?
    /// Copies of this film available on its archive.org item, for the transport
    /// menu. Loaded AFTER playback is under way — the list is a network call and
    /// must never sit between the viewer and the first frame.
    @State private var playerVersions: [ArchiveVersions.Version] = []
    /// Where to resume when a version switch rebuilds the player in place.
    @State private var switchResumeSeconds: Double?
    // tvOS cannot present GroupActivitySharingController (unavailable in the
    // 27.0 SDK), so when there is no call it must SAY so rather than do nothing.
    @State private var sharePlayNotice = false

    /// Starts the Studio on the player that is ALREADY playing this film —
    /// §8.8's whole point. Nothing is presented over anything; the engine adds
    /// outputs to the item the player has, and the readout is an overlay.
    ///
    /// The destination comes from `studioRequest` — the confirmation the host
    /// just filled in (Rule 8.8a) — resolved through the same
    /// `StudioGoLive.destination` iOS and macOS use, which is the one place an
    /// OAuth token becomes a stream key. It is nil ONLY on the `AW_STUDIO_TV`
    /// diagnostic door, which has no request and so encodes and discards; that
    /// used to be every path on this platform (§9.ccc).
    /// Put a card on air, or take it off. Rebuilt from the show's own
    /// overlay so removing a card restores the title and (if it is still
    /// within its twenty seconds) the provenance line, rather than clearing
    /// the lower third along with it.
    @MainActor
    private func applyStudioCard(_ card: StudioOverlay.Card?) async {
        guard let engine = studioEngine else { return }
        var o = studioOverlayBase
        if !studioProvenanceShowing { o.provenance = "" }
        o.card = card
        await engine.setOverlay(o)
        awdiag("AWCARD %@", card.map { String(describing: $0) } ?? "none")
    }

    @MainActor
    private func runStudio(for film: Catalog.Item) async {
        guard let p = player else {
            studioRefusal = "The film is not playing yet — try again in a moment."
            studioFilm = nil
            return
        }
        let engine = studioEngine ?? StudioEngine(configuration: .benchDoored())
        studioEngine = engine
        await engine.attachFilm(player: p)

        // WHY THE TELEVISION WAS SILENT (§9.jjjj). `FilmAudioTap.attach` needs
        // an `AVAssetTrack`, and an HLS asset vends none — Decision 106 makes
        // tvOS play the film as HLS from the LocalMediaServer, so the tap
        // declines and its `false` is recorded as "this film has no audio",
        // which is a real case in a silent-cinema catalog. Measured here rather
        // than inferred: the URL scheme, the track count, and the verdict.
        // Ask the SOURCE whether this film has sound at all. It is the only
        // way to tell a silent film from one whose audio we simply cannot
        // reach, and those need opposite responses from a host.
        var sourceHasAudio: Bool?
        if let src = film.downloadURL.flatMap(URL.init(string:)) {
            let tracks = try? await AVURLAsset(url: src).loadTracks(withMediaType: .audio)
            sourceHasAudio = tracks.map { !$0.isEmpty }
        }
        // Remembered so the health loop can ASK AGAIN. This call happens during
        // setup, before the puller and decoder below have started, so it can
        // only ever answer "no audio" — which is how a television went on
        // saying "the film's audio is not being sent" through a broadcast whose
        // audio was audible. A one-shot answer to a question whose truth
        // changes a second later is not a readout.
        studioSourceHasAudio = sourceHasAudio
        if let problem = await engine.filmAudioProblem(sourceHasAudio: sourceHasAudio) {
            studioAudioProblem = problem
            // The tap could not attach and the film HAS sound, which on tvOS
            // means HLS (§9.jjjj). Attach the tee instead: the segment route is
            // already fetching these bytes. For now it only COUNTS — the
            // decoder that turns AAC frames into the PCM the mixer wants is the
            // next piece, and counting first proves the bytes arrive at all
            // before anything is built on top of them.
            // AW_AUDIO_TEE_DUMP=1 writes the teed frames as ADTS, so ffmpeg can
            // say whether they really are the film's audio BEFORE a decoder is
            // built on top of them. Proving the source first is cheaper than
            // debugging a decoder fed the wrong bytes.
            if ProcessInfo.processInfo.environment["AW_AUDIO_TEE_DUMP"] == "1" {
                let dump = FileManager.default.urls(for: .cachesDirectory,
                                                    in: .userDomainMask)[0]
                    .appendingPathComponent("aw-tee.aac")
                try? FileManager.default.removeItem(at: dump)
                FileManager.default.createFile(atPath: dump.path, contents: nil)
                let handle = try? FileHandle(forWritingTo: dump)
                FilmAudioBridge.shared.setSink { frames, _, rate in
                    guard let handle else { return }
                    let rateIndex: [Int: Int] = [96000: 0, 88200: 1, 64000: 2, 48000: 3,
                                                 44100: 4, 32000: 5, 24000: 6, 22050: 7,
                                                 16000: 8, 12000: 9, 11025: 10, 8000: 11]
                    let sr = rateIndex[rate] ?? 4
                    var out = Data()
                    for frame in frames {
                        // 7-byte ADTS header, AAC-LC, 2 channels, no CRC.
                        let len = frame.count + 7
                        out.append(contentsOf: [0xFF, 0xF1])
                        // Profile bits are AOT-1: AAC-LC is AOT 2, so the field
                        // is 1. Writing 0 labels it Main — ffprobe duly read the
                        // dump back as "aac (Main)". ffmpeg decodes either, so
                        // the mislabel was invisible in the numbers and wrong in
                        // the file.
                        out.append(UInt8((1 << 6) | (sr << 2)))
                        out.append(UInt8((2 << 6) | UInt8((len >> 11) & 0x03)))
                        out.append(UInt8((len >> 3) & 0xFF))
                        out.append(UInt8(((len & 0x07) << 5) | 0x1F))
                        out.append(0xFC)
                        out.append(frame)
                    }
                    try? handle.write(contentsOf: out)
                }
            } else {
                // THE REPAIR ITSELF: tee → decoder → the mixer's film bed.
                // The decoder paces itself, because the tee arrives in bursts
                // (§9.nnnn), and it supplies samples only — the engine's show
                // clock still stamps every track (§9.qq).
                let bed = engine.filmAudioBed
                // AW_STUDIO_PCM_DUMP=1 — write the DECODER'S OWN OUTPUT to a
                // file, before the mixer, the encoder or RTMP can touch it.
                //
                // This is a bisect, not a hypothesis. Measured 2026-09-19: our
                // broadcast correlates 0.139 with the source film where the
                // correlator scores 1.000 against itself and 0.002 on
                // unrelated content — so the film audio is being degraded
                // somewhere in OUR pipeline, and eight candidates have already
                // been eliminated. Correlating this file against the film says
                // which HALF the fault is in: if the decoder's output already
                // fails, it is decode/pull; if it matches, it is downstream.
                let pcmDump: FileHandle? = {
                    guard ProcessInfo.processInfo.environment["AW_STUDIO_PCM_DUMP"] == "1",
                          let dir = FileManager.default.urls(for: .cachesDirectory,
                                                             in: .userDomainMask).first
                    else { return nil }
                    let url = dir.appendingPathComponent("filmpcm.raw")
                    try? Data().write(to: url)
                    return try? FileHandle(forWritingTo: url)
                }()
                let decoder = FilmAudioDecoder { samples, count in
                    if let pcmDump {
                        pcmDump.write(Data(bytes: samples, count: count * MemoryLayout<Float>.size))
                    }
                    bed.acceptExternalPCM(samples, count: count)
                } hasRoom: {
                    // Keep a cushion without overwriting it. 0.6 leaves ~600 ms
                    // of decoded audio ahead of the mixer, far more than the
                    // 23.2 ms a packet covers and well clear of the starvation
                    // the pump's own comment guards against.
                    //
                    // `AW_STUDIO_PUMP_FILL` makes the ceiling a CONTROL rather
                    // than an argument, the way `AW_STUDIO_RING_MS` does for the
                    // ring: on a film with roughly double the audio bitrate this
                    // ceiling coincided with `dropped=300` and a decoder running
                    // BEHIND the playhead (`decodedAhead=-0.51`), which is either
                    // this bound starving it or that film simply costing more.
                    // Change the number, and a causal effect must move with it —
                    // judged on the WIRE, because the in-app offset contains the
                    // buffer it is measuring (§9.lllll).
                    bed.filmRingFill < Self.studioPumpFill
                }
                studioFilmAudioDecoder = decoder
                FilmAudioBridge.shared.setSink { frames, firstSample, rate in
                    decoder.accept(frames, firstSample: firstSample, sampleRate: rate)
                }

                // ALIGNMENT (§9.rrrr), and it is two halves that only work
                // together.
                //
                // The playhead is PUSHED at 10 Hz so the decoder can release a
                // packet when the picture reaches it rather than when the
                // network delivered it. On its own that would play SILENCE for
                // the first 75-125 s, because everything queued is still in
                // the future.
                //
                // So the second half primes: the segment under the current
                // picture was fetched before the sink existed and the tee will
                // never offer it again, so it is fetched directly, once.
                // NOT on the main queue. The callback takes the decoder's
                // lock, and the pump holds that lock on its own thread — so
                // scheduling this on main puts UI work behind an audio lock
                // several times a second for the length of a film. 4 Hz is
                // ample against a 0.5 s tolerance.
                let obs = p.addPeriodicTimeObserver(
                    forInterval: CMTime(value: 1, timescale: 4),
                    queue: studioPlayheadQueue) { t in
                        decoder.setPlayhead(t.seconds)
                    }
                studioPlayheadObserver = obs
                decoder.setPlayhead(p.currentTime().seconds)
                decoder.start()

                // THE AUDIO SOURCE (§9.tttt): PULLED by film position.
                //
                // This replaces the tee. The tee handed over whatever the HTTP
                // segment route happened to fetch, which is a schedule the
                // player chose by BUFFERING — so the audio ran 75-125 s ahead
                // of the picture and a playhead push, a priming fetch, a drop
                // rule and a hold rule existed to walk it back (§9.rrrr).
                //
                // Asking for the audio under the picture, a window at a time,
                // makes sync a property of the REQUEST rather than a correction
                // applied afterwards. The drop/hold in the decoder stays as a
                // safety net, and `dropped`/`held` staying near zero is now the
                // evidence that the puller is keeping its side of the bargain.
                if let assetURL = (p.currentItem?.asset as? AVURLAsset)?.url,
                   let origin = LocalMediaServer.shared.origin(for: assetURL) {
                    studioAudioPuller = Task.detached(priority: .userInitiated) { [weak decoder] in
                        var through = -1.0
                        var pulls = 0
                        while !Task.isCancelled {
                            guard let decoder, let head = decoder.currentPlayhead else {
                                try? await Task.sleep(nanoseconds: 250_000_000); continue
                            }
                            // Start here, and re-seat after a seek — in either
                            // direction. Holding audio for a part of the film
                            // the viewer has left is the defect this replaced.
                            if through < head || through > head + FilmAudioPull.lookahead * 3 {
                                through = head
                            }
                            guard through - head < FilmAudioPull.lookahead else {
                                try? await Task.sleep(nanoseconds: 500_000_000); continue
                            }
                            let r = await LocalMediaServer.shared.primeFilmAudio(
                                forOrigin: origin, fromSeconds: through,
                                seconds: FilmAudioPull.chunk)
                            // Advance by what the route COVERED, never by what
                            // was asked for: fragments do not align to the
                            // request, so advancing by the span re-delivers the
                            // overlap and the film stutters.
                            if r.frames > 0, r.throughAt > through {
                                if pulls == 0 {
                                    // delta is THE CONTROL: we asked for a known
                                    // film time and the route answered from an
                                    // index it computed itself.
                                    awdiag("AWPULL first frames=%d asked=%.1f firstAt=%.1f delta=%+.2f",
                                           r.frames, through, r.firstAt, r.firstAt - through)
                                }
                                pulls += 1
                                through = r.throughAt
                            } else {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                            }
                        }
                    }
                } else {
                    awdiag("AWPULL frames=0 (no origin — the Studio has NO film audio)")
                }
            }
        }
        if let item = p.currentItem {
            let url = (item.asset as? AVURLAsset)?.url
            let n = ((try? await item.asset.loadTracks(withMediaType: .audio)) ?? []).count
            awdiag("AWAUDIO filmHasAudio=%@ playedTracks=%d sourceHasAudio=%@ scheme=%@ path=%@",
                   await engine.filmHasAudio ? "true" : "false", n,
                   sourceHasAudio.map { $0 ? "true" : "false" } ?? "unknown",
                   url?.scheme ?? "?", (url?.pathExtension ?? "?"))
        }
        // THE HOST'S CHOICE, not a constant. Rule 8.8e put the five
        // placements on the go-live screen and `request()` carries the one
        // picked — and this line still said `.corner`, so the picker changed
        // the REQUEST and the engine ignored it. Caught by a bench broadcast
        // driven with `side`: the server's recording came back showing the
        // film centred full-frame, which is what `corner` looks like when no
        // camera is attached. A picker whose value never reaches the engine is
        // worse than no picker, because it looks like it worked.
        await engine.setLayout(studioRequest?.layout ?? .corner)
        var o = StudioOverlay()
        o.title = film.title
        o.subtitle = [film.year.map(String.init), film.director]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if film.rightsBucket == "safe_pd_age", let y = film.year {
            o.provenance = "Public domain — published \(y), before 1930"
        }
        await engine.setOverlay(o)

        // THE PROVENANCE LINE IS TRANSIENT, not a permanent badge.
        //
        // The owner, after the first real broadcast: "While I like the lower
        // third overlay, the Public Domain status is not something anyone would
        // actually want to live on the top of their stream." They are right,
        // and it is their stream's face. §2's argument for showing provenance
        // is about the viewer being able to LEARN where the film came from —
        // which a line that plays for the first twenty seconds does, in the
        // ordinary broadcast idiom of a lower third that introduces and then
        // clears. A badge that never leaves is branding, not provenance.
        //
        // The film's title and subtitle stay; only the rights line goes. The
        // fuller statement still travels with the show in the platform's own
        // description, where `StudioGoLive.description(for:)` puts it.
        // The countdown starts when the STREAM does — see the health loop below.
        let introOverlay = o
        studioOverlayBase = o

        // The camera, if a phone has been paired. NOT an error when absent
        // (§8.8): a paired phone can be asleep or carried away mid-show.
        // NO PRE-RAISE HERE. An earlier attempt called `prepareAudioSession()`
        // at this point to make the microphone port appear, and it did the
        // opposite: `StudioContinuity`'s own header says `.playAndRecord` on
        // tvOS fails while there is nothing to record FROM, and that a failed
        // activation stops AVPlayer dead. The owner watched the app quit before
        // the stream started. `StudioContinuity` already raises the session
        // itself, once it HAS a port — which is the correct order and was
        // written down before I broke it.
        let continuity = StudioContinuity()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        // SAY WHAT IT FOUND. Absent is not an error (§8.8) — a paired phone can
        // be asleep or carried away mid-show — but "no phone has ever been
        // paired", "paired and asleep" and "attached fine" were one silent
        // branch, so a camera test could not tell success from never-ran.
        let camName = continuity.camera()?.localizedName ?? "none"
        let micName = continuity.microphonePort()?.portName ?? "none"
        awdiag("AWCONT connected=%@ camera=%@ micPort=%@",
               continuity.state.isConnected ? "true" : "false", camName, micName)
        // ONE LINE PER CALL. The app dies somewhere in this block with a
        // connected camera, and the last log line is the state line ABOVE it —
        // which narrows it to four calls and no further. Guessing cost a round
        // already (the microphone guard below was a correct fix for a defect
        // that was not the one killing it).
        // AW_STUDIO_MIC_PROBE=1 — diagnostic only, changes nothing, restores
        // whatever category it found. See `probeMicrophone`.
        // GATED ON A CONNECTED CAMERA, deliberately. Raising `.playAndRecord`
        // with NOTHING connected is the documented crash (§6.2, and an earlier
        // pre-raise that killed the app and was reverted) — re-running that
        // costs a crash to learn something already written down. The open
        // question is the other case: whether the category is legitimate once
        // a Continuity device IS attached and can offer a microphone.
        if ProcessInfo.processInfo.environment["AW_STUDIO_MIC_PROBE"] == "1",
           continuity.state.isConnected {
            continuity.probeMicrophone()
        }
        awdiag("AWCONT step=makeSession")
        // ONE PATH, USED TWICE: at the start of the show, and again by the
        // health loop when the camera stops. The Continuity link dropped FOUR
        // times in one session on 2026-09-19 — once ten seconds into a Twitch
        // broadcast — and until now the only response was a line on the
        // readout telling the host their audience could no longer see them.
        //
        // Recovery is possible because the CAMERA survives a drop in a way the
        // microphone does not: `AVCaptureDevice.DiscoverySession` finds a
        // paired phone without the picker, so a new session can be built from
        // nothing. `AVContinuityDevice` cannot be re-obtained that way
        // (`AVContinuityDevice.h` offers no enumeration), so a recovered show
        // may come back with the camera and without the host's microphone —
        // which is §8.8's normal state, not an error.
        // NOT `@Sendable`: `StudioContinuity` is `@MainActor` and this runs
        // inside that isolation, so marking it sendable severs it from the
        // very state it has to read (Swift 6 says so plainly).
        func attachCamera(_ why: String) async -> Bool {
            guard continuity.state.isConnected, let session = continuity.makeSession() else {
                awdiag("AWCONT %@: no camera to attach (%@)", why, continuity.state.isConnected
                       ? "connected but makeSession() returned nil"
                       : "no Continuity device")
                return false
            }
            awdiag("AWCONT step=sessionMade inputs=%d outputs=%d",
                   session.inputs.count, session.outputs.count)
            let cam = CameraFrameTap()
            cam.attach(to: session, rotationAngle: continuity.captureRotationAngle)
            awdiag("AWCONT step=cameraTapAttached")
            await engine.attachCamera(tap: cam)
            awdiag("AWCONT step=cameraEngineAttached")
            // ONLY IF THERE IS ONE. `makeSession()` adds a microphone INPUT
            // only when a port exists, and attaching a mic tap regardless hangs
            // an audio OUTPUT on a session that has no audio input — an invalid
            // configuration, and an ObjC exception no Swift `try` can catch.
            // The owner watched the app quit here twice with a paired camera
            // and `micPort=none`: the camera is found by discovery, the
            // microphone needs the picker's `AVContinuityDevice`, and when the
            // picker is dismissed there is a camera and no microphone. That is
            // a NORMAL state (§8.8) and it must not be a crash.
            // GATE ON WHAT THE SESSION ACTUALLY HAS, not on the state computed
            // before `makeSession` ran. `state.hasMicrophone` comes from a
            // query that can be nil while the Continuity microphone is still
            // arriving, so a session that DID get a mic input was being left
            // untapped — `inputs=2`, `micFrames=0`.
            if continuity.sessionHasMicrophone {
                let mic = MicAudioTap(); mic.attach(to: session)
                await engine.attachMicrophone(tap: mic)
            }
            awdiag("AWCONT step=startRunning")
            session.startRunning()
            awdiag("AWCONT attached camera=%@ mic=%@ (%@)", camName, micName, why)
            return true
        }
        if await attachCamera("initial") == false {
            awdiag("AWCONT no camera tile — pair an iPhone on this Apple TV first")
        }

        // Resolving a destination CREATES the broadcast on the platform and
        // fetches its key, so it happens once, here, and the key is handed
        // straight to the engine (§5: never stored, never printed, never
        // outliving the session that fetched it).
        var destination: URL?
        if let request = studioRequest {
            do {
                destination = try await StudioGoLive.destination(for: request, film: film)
            } catch {
                // LOG THE RAW THING, SHOW A SENTENCE. Without this line the
                // four YouTube writes failed leaving no trace anywhere: the
                // door logged "READY — going live" and the next entry in the
                // log was unrelated. A silent failure path, the fourth in this
                // feature.
                awdiag("AWGOLIVE %@ FAILED: %@", request.platform.rawValue,
                       Self.studioFlat("\(error)"))
                studioRefusalKind = .platform
                studioRefusal = Self.studioHumanError(error)
                studioFilm = nil; studioRequest = nil
                return
            }
            guard destination != nil else {
                studioRefusalKind = .configuration
                studioRefusal = "\(request.platform.label) accepted the sign-in "
                    + "but returned no address to broadcast to. Nothing was sent."
                studioFilm = nil; studioRequest = nil
                return
            }
        }

        do {
            try await engine.start(destination: destination)
        } catch {
            awdiag("AWGOLIVE engine.start FAILED: %@", Self.studioFlat("\(error)"))
            studioRefusalKind = .platform
            studioRefusal = Self.studioHumanError(error)
            studioFilm = nil; studioRequest = nil
            return
        }

        // Chat the program carries. The channel comes from the host's own
        // Twitch account once sign-in exists; `AW_STUDIO_CHAT` names one
        // meanwhile, and reading Twitch needs no credential (§6.4).
        if let channel = ProcessInfo.processInfo.environment["AW_STUDIO_CHAT"], !channel.isEmpty {
            await engine.attachTwitchChat(channel: channel)
        }

        // §6.5's `.critical`, for a television. macOS has no platform
        // override and neither does tvOS, so the engine's seam is the only
        // route to the rule here. DEBUG only, never in production.
        #if DEBUG
        if let want = ProcessInfo.processInfo.environment["AW_STUDIO_THERMAL"] {
            let at = Double(ProcessInfo.processInfo.environment["AW_STUDIO_THERMAL_AT"] ?? "") ?? 20
            let state: ProcessInfo.ThermalState? = switch want {
            case "serious": .serious
            case "critical": .critical
            default: nil
            }
            if let state {
                Task {
                    try? await Task.sleep(for: .seconds(at))
                    await engine.overrideThermalState(state)
                }
            }
        }
        #endif

        var lastFilmFrames = 0
        // Camera frames at the previous tick, so the AWCAM line reports a RATE
        // and not only a total — a total that STOPPED climbing reads exactly
        // like one that never started, which is the failure being chased.
        var lastCameraFrames = 0
        /// Consecutive one-second ticks with a camera attached and no new
        /// frames, and how many rebuilds have been tried. Both reset when
        /// frames resume.
        var cameraStall = CameraStallRecovery()
        // When the provenance line came up, measured from the moment the show
        // actually reached the wire.
        var liveSince: Date?
        var provenanceShowing = !introOverlay.provenance.isEmpty
        studioProvenanceShowing = provenanceShowing
        // Verification door, the macOS twin (AW_STUDIO_CARD). A card chosen
        // from a focus-driven menu cannot be regression-tested by a harness,
        // and a card is the one overlay an audience reads in full.
        var cardDoorApplied = false

        while !Task.isCancelled, studioFilm != nil {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.refreshHealth()
            let h = await engine.health
            studioFilmFPS = max(0, h.filmFramesPulled - lastFilmFrames)
            lastFilmFrames = h.filmFramesPulled
            studioHealth = h

            // THE CAMERA TILE. On 2026-09-19 the attach chain logged success
            // (`AWCONT attached camera=Continuity Camera`) and the program on
            // the wire had no tile in it, and nothing on any surface could
            // separate "no frames are arriving" from "frames arrive and are
            // not drawn". The renderer is handed `cameraTap?.latest()`, so a
            // nil frame draws nothing and reports nothing.
            //
            // Unconditional, and at the TOP of the loop: the audio block below
            // is inside an `if let`, and a diagnostic that only fires when an
            // unrelated thing exists cannot be trusted to have run at all. Its
            // own line, too — widening AWSYNC would change what AWSYNC means.
            if let e = studioEngine {
                let a = await e.audioSettings
                studioFilmGain = a.filmGain
                studioMicGain = a.micGain
                studioDuckEnabled = a.duckEnabled
            }
            studioCameraFPS = max(0, h.cameraFramesReceived - lastCameraFrames)
            awdiag("AWCAM frames=%d (+%d/s) %@", h.cameraFramesReceived,
                   studioCameraFPS,
                   h.cameraFramesReceived > lastCameraFrames ? "receiving" : "NO NEW FRAMES")
            // RECOVER A CAMERA THAT STOPPED. Only after it had started (a
            // camera that never delivered is a different problem, and the
            // readout says so), only while one is still discoverable, and
            // rate-limited: a rebuild that cannot succeed must not be
            // attempted once a second for the length of a show.
            if cameraStall.tick(attached: h.cameraAttached,
                                framesReceived: h.cameraFramesReceived,
                                framesPerSecond: studioCameraFPS,
                                onAir: h.showState.isOnAir) {
                awdiag("AWCONT camera stopped at %d frames — recovery attempt %d of %d",
                       h.cameraFramesReceived, cameraStall.attempts,
                       CameraStallRecovery.maximumAttempts)
                let ok = await attachCamera("recovery \(cameraStall.attempts)")
                awdiag("AWCONT recovery %d: %@", cameraStall.attempts, ok ? "re-attached" : "no camera")
            }
            lastCameraFrames = h.cameraFramesReceived

            #if DEBUG
            if !cardDoorApplied, h.showState == .live,
               let raw = ProcessInfo.processInfo.environment["AW_STUDIO_CARD"], !raw.isEmpty {
                cardDoorApplied = true
                let card: StudioOverlay.Card? = switch raw {
                case "startingSoon": .startingSoon(secondsRemaining: 60)
                case "intermission": .intermission
                case "ending":       .ending
                default:             nil
                }
                studioCard = card
                await applyStudioCard(card)
            }
            #endif

            // ASK AGAIN. The warning is only true until audio starts arriving.
            studioAudioProblem = await engine.filmAudioProblem(
                sourceHasAudio: studioSourceHasAudio)

            // Does the tee actually run? Counted from the bridge, which reads
            // zero when no sink is attached — that is the control.
            if FilmAudioBridge.shared.isAttached, Int(Date().timeIntervalSince1970) % 15 == 0 {
                awdiag("AWAUDIOTEE frames=%d bytes=%d decoded=%d pcm=%d ch=%@ err=%@",
                       FilmAudioBridge.shared.framesTeed, FilmAudioBridge.shared.bytesTeed,
                       studioFilmAudioDecoder?.packetsDecoded ?? -1,
                       studioFilmAudioDecoder?.framesWritten ?? -1,
                       studioFilmAudioDecoder?.channelState ?? "-",
                       studioFilmAudioDecoder?.lastError ?? "-")
                // THE RING, which nothing has ever reported. It holds ONE
                // SECOND while the pull path keeps a 12-18 s lookahead, so if
                // the pump outruns the mixer it wraps over unread audio and
                // the show carries fragments of the film overwritten by later
                // fragments — inaudible to a click detector, a spectrum or a
                // level meter, and exactly what the 2026-09-19 correlation
                // against the source film measured (~0.2 where the control
                // scores 1.000).
                let bedNow = await engine.filmAudioBed
                awdiag("AWRING overflowed=%d fill=%.2f buffered=%.2fs",
                       bedNow.filmRingOverflowed, bedNow.filmRingFill,
                       bedNow.bufferedSeconds)
                // THE MIX ITSELF. Until 2026-09-19 the Continuity microphone
                // never attached at all, so nothing ever reported whether the
                // host's audio was reaching the programme or whether the film
                // was ducking under it. `micFrames` climbing is the only proof
                // that the mic tap is delivering rather than merely attached —
                // the same distinction the camera counter had to make.
                awdiag("AWMIX micFrames=%d micLevel=%.3f filmLevel=%.3f ducking=%@ "
                       + "micPadded=%d micBacklog=%.3fs micTrimmed=%d",
                       h.audio.micFramesWritten, h.audio.micLevel, h.audio.filmLevel,
                       h.audio.ducking ? "yes" : "no", h.audio.micFramesPadded,
                       h.audio.micBacklogSeconds, h.audio.micDroppedForLatency)

                // THE LIP-SYNC MEASUREMENT, on the product path (§9.rrrr).
                //
                // The 8m16s soak proved the two tracks span the same WALL TIME
                // to 15 ms. That is a drift proxy and says nothing about
                // whether they describe the same INSTANT of film: a constant
                // offset is invisible to it, which is exactly what cost the
                // Android port two rounds (§9.ggg found -0.7 s that way).
                //
                // No stimulus clip is needed here. The tee already addresses
                // every packet by film sample index, so the decoder can say
                // which second of the film it just released; the player says
                // which second it is showing. The difference IS the offset.
                // Positive = audio is AHEAD of the picture.
                if let d = studioFilmAudioDecoder, let pos = d.filmPosition,
                   let now = player?.currentTime().seconds, now.isFinite {
                    // REFUSES rather than reports when its own control fails.
                    // Every burst must continue where the last one ended; if it
                    // does not, the film-time mapping is broken and the offset
                    // is an artifact. The first version of this printed -102 s
                    // to -464 s from a units error of mine and the recording
                    // disproved it — so the check now stands in front of the
                    // number, the way measure_av_sync refuses a flash/burst
                    // count mismatch rather than averaging through it.
                    // `ooo` is INFORMATION now, not a refusal.
                    //
                    // It was the control that caught a units error, when the
                    // only source was a tee whose bursts must chain. Priming
                    // deliberately breaks that chain — it inserts audio from
                    // the playhead while the tee carries on from the buffer
                    // head — so a non-zero count became the NORMAL case and the
                    // refusal fired on every healthy run. The mapping's control
                    // moved to AWPRIME's delta, which checks against a value
                    // known outside the arithmetic. A control has to be wrong
                    // only when the thing it guards is wrong.
                    // THE OFFSET HAS TO ACCOUNT FOR THE RING, and it did not
                    // until the pump changed underneath it.
                    //
                    // `pos` is the film time of the last packet DECODED. While
                    // the pump metered one packet a tick that was also roughly
                    // the audio being encoded, so `pos - now` was the A/V
                    // offset. Filling a cushion (§9.vvvv) put up to half a
                    // second of decoded audio in the ring ahead of the mixer,
                    // and the reported offset rose from +0.22 to +0.49 with
                    // nothing having gone out of sync: the ring is FIFO, so
                    // that audio is simply encoded later. Subtracting what is
                    // buffered gives the film time actually going to the wire.
                    //
                    // A measurement whose meaning changes when an unrelated
                    // part changes is the recurring fault in this feature.
                    let buffered = await engine.filmAudioBuffered
                    awdiag("AWSYNC audioFilmPos=%.2f playhead=%.2f decodedAhead=%+.2f buffered=%.2f offset=%+.2f queued=%.1f ooo=%d dropped=%d held=%d",
                           pos, now, pos - now, buffered, pos - now - buffered,
                           d.queuedSeconds,
                           d.outOfOrderBursts, d.droppedStale, d.heldEarly)
                }
            }

            // THE FIRST TWENTY SECONDS OF THE STREAM, not of the engine.
            //
            // The owner caught this: "you have to know when the stream goes
            // live to know when the first 20 seconds will be." The first
            // version slept 20 s from `engine.start`, which is the wrong
            // instant — §9.tt measured ~12 s between starting and the first
            // published packet (mostly the film loading, then the handshake
            // and the opening keyframe). So most of the window was spent
            // before anyone could see it, and a viewer who joined at the top
            // of the stream might get four seconds of provenance or none.
            //
            // `showState == .live` is true only when the publisher is
            // PUBLISHING to a destination, so the clock now starts where the
            // audience does.
            if provenanceShowing {
                if h.showState == .live {
                    if let since = liveSince {
                        if Date().timeIntervalSince(since) >= 20 {
                            provenanceShowing = false
                            studioProvenanceShowing = false
                            var later = introOverlay
                            later.provenance = ""
                            // A CARD OUTLIVES THE PROVENANCE LINE. Without
                            // this, the twenty-second expiry would quietly
                            // take a host's card off the air with it.
                            later.card = studioCard
                            await engine.setOverlay(later)
                        }
                    } else {
                        liveSince = Date()
                    }
                }
            }

            // A show that ENDS ITSELF says why (§6.5's `.critical`, §6.6's
            // expired deadline). `endedReason` was written by the engine and
            // read by nothing on Apple until now, so a television host whose
            // broadcast stopped saw the Studio simply disappear — which is
            // exactly what §5 forbids.
            if let why = h.endedReason {
                studioRefusalKind = .ended
                studioRefusal = why.prefix(1).uppercased() + why.dropFirst() + "."
                studioFilm = nil
                break
            }
        }
        await engine.stop()
        FilmAudioBridge.shared.setSink(nil)
        studioAudioPuller?.cancel(); studioAudioPuller = nil
        if let obs = studioPlayheadObserver { player?.removeTimeObserver(obs) }
        studioPlayheadObserver = nil
        studioFilmAudioDecoder?.stop()
        studioFilmAudioDecoder = nil
        studioEngine = nil
        studioRequest = nil
        continuity.lowerAudioSession()
    }

    /// Why this film may not be broadcast — shown, never swallowed (§5).
    @State private var studioRefusal: String?
    /// The film a host has asked to broadcast but not yet confirmed — the
    /// §8.8 one-time acceptance. Nil once accepted or declined.
    @State private var studioPendingConfirm: Catalog.Item?

    /// Whether this DEVICE has accepted the §3.4a warning. `UserDefaults`
    /// because there are no accounts here (§10.2) and this is a fact about
    /// the box, not about a person — a second Apple TV asks again, which is
    /// right: it may be a different household.
    private static var studioWarningAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: "AWStudioWarningAccepted") }
        set { UserDefaults.standard.set(newValue, forKey: "AWStudioWarningAccepted") }
    }
    /// Whether the standing refusal is about the FILM's rights or about this
    /// BUILD — they are different sentences and need different titles.
    /// Which of THREE things the alert is about.
    ///
    /// This was a `Bool` — film or configuration — and a third real state
    /// arrived: a broadcast that ENDED itself (§6.5's `.critical`, §6.6's
    /// expired deadline). Reusing the false branch for it titled an overheated
    /// television "Streaming is not set up yet", seen on the glass 2026-09-17.
    /// A two-state flag cannot describe three states, and the comment on the
    /// alert below already says why that matters: a wrong title tells the
    /// viewer something false.
    enum StudioRefusalKind { case film, configuration, platform, ended }

    /// A sentence a host can read on a television, out of whatever the platform
    /// threw.
    ///
    /// The go-live catch used to set `"\(error)"` straight onto the screen. For
    /// a YouTube API failure that is the entire JSON body, so the owner's TV
    /// showed brace soup under the heading "Streaming is not set up yet" — a
    /// heading that was itself wrong, because the build was configured, signed
    /// in and READY. Both halves are fixed: the raw error goes to the log where
    /// it can be diagnosed, and the screen gets the platform's own `message`.
    /// awdiag writes PER LINE and these bodies are pretty-printed JSON, so an
    /// unflattened error logs a single "{" — which has now cost a run twice in
    /// one day, in two different files.
    static func studioFlat(_ s: String) -> String {
        s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).joined(separator: " ")
    }

    static func studioHumanError(_ error: Error) -> String {
        let raw = "\(error)"
        for marker in ["\"message\": \"", "\"message\":\""] {
            if let r = raw.range(of: marker),
               let end = raw[r.upperBound...].firstIndex(of: "\"") {
                return String(raw[r.upperBound..<end])
            }
        }
        return raw.count > 180 ? "The platform refused the broadcast." : raw
    }

    /// Why this television cannot broadcast, or nil when it can.
    ///
    /// This used to read `StudioPlatformAuth.anyConfigurationProblem` — "can
    /// this BUILD sign in" — as a proxy for "can this TELEVISION reach an
    /// audience". The two came apart the moment ONE client id was registered
    /// (WATCH-TOGETHER §9.nnn): that predicate goes nil as soon as EITHER
    /// platform is configured, while tvOS still has no way to choose a
    /// destination and `runStudio` starts the engine with `destination: nil`.
    /// So a registration on Google Cloud — a change in a gitignored config
    /// file, nowhere near this code — silently opened the gate onto exactly
    /// the dead production mode §10.2b exists to prevent: encoding at 6 Mbps
    /// to nobody, with nothing on the glass saying so.
    ///
    /// The credential sentence is kept for the case it still describes, and
    /// only that case. A build with no ids at all cannot sign in on ANY
    /// platform, which is a different and more actionable thing to tell a host
    /// than "this television has no surface for it yet".
    /// AMENDED 2026-09-18, when the second half of this stopped being true.
    /// The sentence below used to continue: "Going live from Apple TV is not
    /// built yet. This television has no way to choose a platform or a title."
    /// It now has one — `GoLiveTV`, tvOS-DESIGN Rule 8.8a — so the only thing
    /// that can still stop a television is the thing the sentence's first half
    /// always described: a build with no client id can sign in nowhere, and
    /// that is a fact about the build rather than about this screen.
    static var studioTVBroadcastProblem: String? {
        StudioPlatformAuth.anyConfigurationProblem
    }

    /// The film whose go-live confirmation is on screen (Rule 8.8a). Distinct
    /// from `studioFilm`, which means the Studio is RUNNING: between them sits
    /// a host who has not pressed anything yet.
    @State private var studioSetup: Catalog.Item?
    /// What that confirmation returned. Read once by `runStudio` to resolve a
    /// destination; a nil request encodes to nowhere, which is what the
    /// `AW_STUDIO_TV` diagnostic door wants and what a host must never get.
    @State private var studioRequest: GoLiveRequest?
    /// Rule 8.8g — the card on air, or nil for the programme. Held here
    /// because the television's overlay is rebuilt from `introOverlay`
    /// whenever the provenance line expires, and a card must survive that.
    @State private var studioCard: StudioOverlay.Card?
    /// The show's overlay WITHOUT a card, and whether its provenance line is
    /// still inside its twenty seconds. Both are state rather than locals
    /// because a card is chosen from the transport menu, long after the loop
    /// that builds them has started.
    @State private var studioOverlayBase = StudioOverlay()
    @State private var studioProvenanceShowing = false
    @State private var studioRefusalKind: StudioRefusalKind = .film
    /// The film the host chose to broadcast; non-nil starts the Studio on the
    /// player that is ALREADY playing it.
    @State private var studioFilm: Catalog.Item?
    @State private var studioEngine: StudioEngine?
    /// Rule 8.8c — the live mixer, opened from the Watch Together control while
    /// a broadcast is on air. The gains are READ BACK from the mixer each tick
    /// rather than mirrored here, so this surface can never drift from what the
    /// audience is actually hearing.
    @State private var studioShowMixer = false
    @State private var studioFilmGain: Float = 1
    @State private var studioMicGain: Float = 1
    @State private var studioDuckEnabled = true
    /// A pause the HOST asked for, which Rule 8.8c says must not wear §4's
    /// "the film has stopped" alarm — that sentence is for an accidental
    /// freeze, and showing it for both teaches a host to ignore it.
    @State private var studioHostPaused = false
    @State private var studioHealth = StudioHealth()
    /// Extracted from the alert's `message:` builder. Inline, the ternary plus
    /// two string concatenations inside a body this large tipped the type
    /// checker over its limit ("unable to type-check this expression in
    /// reasonable time") the moment one more parameter was added elsewhere in
    /// the same body — the expression itself was never the problem, the body's
    /// total cost was.
    private var studioRefusalMessage: String {
        let why = studioRefusal ?? ""
        guard studioRefusalKind == .film else { return why }
        return why + "\n\n" + StudioRights.policy
    }

    /// Ring-fill ceiling for the film audio pump; see the `hasRoom` call site.
    static let studioPumpFill: Double = {
        let v = ProcessInfo.processInfo.environment["AW_STUDIO_PUMP_FILL"] ?? ""
        return Double(v) ?? 0.6
    }()

    @State private var studioFilmFPS = 0
    /// Camera frames in the last second, for the readout's "camera stopped"
    /// line. Mirrors `studioFilmFPS`.
    @State private var studioCameraFPS = 0
    /// Set when the film HAS sound that is not reaching the broadcast (§9.jjjj).
    /// Shown on the readout, never swallowed (§5).
    @State private var studioAudioProblem: String?
    /// Decodes the teed film audio for the whole life of a show (§9.oooo).
    @State private var studioFilmAudioDecoder: FilmAudioDecoder?
    @State private var studioPlayheadObserver: Any?
    private let studioPlayheadQueue = DispatchQueue(label: "aw.studio.playhead")
    @State private var studioAudioPuller: Task<Void, Never>?
    @State private var studioSourceHasAudio: Bool?
    @State private var fallbackProbe: Task<Void, Never>?
    @State private var sysCapProbe = SystemCaptionProbe()   // AW_SYSCAP_PROBE=1 only
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
    // The resume/join seek, HELD until the item is .readyToPlay. Issuing it in
    // setupPlayer — as this did — drops it on any slow-loading item (Decision
    // 051's own lesson, unapplied here): His Girl Friday showed "Resume",
    // started at 0:00, and the progress writer then OVERWROTE the viewer's
    // real position within five seconds. Nothing persists while this is set.
    @State private var pendingSeekSeconds: Double?
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
    // Per-film subtitles toggle (transport menu). nil = follow the viewer's
    // system caption preference — the default the retired native track's
    // AUTOSELECT gave. The native CC menu went with the HLS wrapper
    // (Decision 070); this is its replacement.
    // Seeded from AW_CAPTION_CHOICE (CaptionChoiceSession) so the harness can
    // drive Off/Automatic unattended — the menu itself needs a remote.
    @State private var captionChoice: CaptionCoordinator.CaptionChoice? = {
        guard let item = ProcessInfo.processInfo.environment["AW_START_ITEM"],
              let c = CaptionChoiceSession.byItem[item] else { return nil }
        return CaptionCoordinator.CaptionChoice(rawValue: c.rawValue)
    }()
    // #92: seconds to seek into the FIRST program when joining a channel live.
    // Consumed once (zeroed after the first setup) so lineup advances start at 0.
    @State private var joinOffset: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    init(url: URL, archiveID: String, catalogItem: Catalog.Item? = nil,
         lineup: [Catalog.Item]? = nil, startMuted: Bool = false, startOffset: TimeInterval = 0,
         channelContext: Bool = false, ephemeralLineup: Bool = false) {
        self.url = url
        self.archiveID = archiveID
        self.catalogItem = catalogItem
        self.lineup = lineup
        self.startMuted = startMuted
        self.startOffset = startOffset
        self.channelContext = channelContext
        self.ephemeralLineup = ephemeralLineup
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
          channelContext: Bool = false, ephemeralLineup: Bool = true) {
        guard let first = lineup.first, let url = first.videoURLParsed else { return nil }
        self.init(url: url, archiveID: first.archiveID, catalogItem: first,
                  lineup: lineup, startMuted: startMuted, startOffset: startOffset,
                  channelContext: channelContext, ephemeralLineup: ephemeralLineup)
    }

    // #19: a broken item (dead URL, stale non-MP4 derivative, decode reject, or a
    // load that never readies) must not dead-end on the system "no-entry" circle.
    // Surface a visible, recoverable failure state — same contract as the episode
    // player.
    private enum PlaybackState: Equatable { case loading, ready, failed(String) }
    // Owner requirement 2026-08-15: a film must START within ~30 seconds.
    // The budget is therefore ADAPTIVE (2026-08-17 regression fix): 25s when
    // a fallback copy is IN HAND — switching fast is what the 30s promise is
    // for — but the FULL old patience when there is nothing to switch to.
    // A flat 25s cut showed "Can't play this title" on cold-but-viable loads
    // the old player always won (measured: archive.org first bytes of
    // 24-31s on bad mornings, with playback fine after), which is exactly
    // the never-used-to-happen error the owner reported. An error is only
    // honest when patience is exhausted, and patience costs nothing when
    // there is no faster alternative to offer.
    private let fallbackAt: Duration = .seconds(25)
    private let giveUpAt: Duration = .seconds(60)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if case .failed(let message) = playback {
                failureView(message)
            } else if let player {
                AVPlayerContainer(player: player, menuItems: autoplayMenu,
                                  liveCaptionURL: liveCaptionSource,
                                  reviewSource: subtitleReviewSource,
                                  captionChoice: captionChoice)
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
        .alert("Start a FaceTime call first", isPresented: $sharePlayNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Watch Together needs a FaceTime call in progress. Start one on "
                 + "your iPhone, iPad or Mac, then choose Watch Together there — "
                 + "the film can continue on this Apple TV.")
        }
        // A rights refusal is a SENTENCE, not a missing menu item. It teaches
        // the viewer something true about the public domain (§2.1) and it is
        // the same text every other platform shows.
        // The TITLE has to match the reason. A build with no client id is not
        // a film that cannot be streamed, and putting "This film cannot be
        // streamed" over "signing in is not set up in this build" tells the
        // viewer something false about the film — and about the public domain,
        // which is the one thing this alert exists to teach (§2.1).
        .alert({ switch studioRefusalKind {
                 case .film: return "This film cannot be streamed"
                 case .configuration: return "Streaming is not set up yet"
                 case .platform: return "The broadcast could not start"
                 case .ended: return "The broadcast ended"
                 } }(),
               isPresented: .constant(studioRefusal != nil)) {
            Button("OK", role: .cancel) { studioRefusal = nil }
        } message: {
            Text(studioRefusalMessage)
        }
        // §8.8's one-time acceptance. A real choice, not an OK: it is asking a
        // host to accept a risk to their own channel, and "OK" is not consent
        // to anything.
        .alert("Before your first broadcast",
               isPresented: .constant(studioPendingConfirm != nil)) {
            Button("Start the broadcast") {
                Self.studioWarningAccepted = true
                studioFilm = studioPendingConfirm
                studioPendingConfirm = nil
            }
            Button("Not now", role: .cancel) { studioPendingConfirm = nil }
        } message: {
            Text(StudioRights.hostWarning)
        }
        // Rule 8.8a's focus-driven confirmation. Full screen rather than a
        // sheet: tvOS has no partial presentation that keeps focus sane, and
        // the film is paused behind it anyway.
        .fullScreenCover(item: $studioSetup) { film in
            GoLiveTV(film: film) { request in
                studioRequest = request
                studioSetup = nil
                // MUTE THE ROOM when a DOOR drove this, never when a person
                // did. A soak plays a film aloud in someone's living room for
                // ten minutes, and the FORCE door already carries the same
                // consideration. It costs the measurement nothing: the
                // broadcast's audio now comes from the HLS tee (§9.pppp),
                // which is upstream of local output, so muting the television
                // changes what the ROOM hears and not one sample of the wire.
                //
                // AW_STUDIO_TV_SOUND=1 opts back OUT of the mute, for a run
                // somebody is deliberately watching. Owner, 2026-09-18, on the
                // first YouTube broadcast: "When I said I don't hear the audio,
                // I meant from the speakers and not the livestream." Nothing
                // was broken — the room was silent exactly as designed, and the
                // design had no way to say so or to be turned off.
                if ProcessInfo.processInfo.environment["AW_STUDIO_TV_GOLIVE"] != nil,
                   ProcessInfo.processInfo.environment["AW_STUDIO_TV_SOUND"] != "1" {
                    player?.isMuted = true
                    awdiag("AWMUTE television speakers muted for an unattended bench run "
                           + "— the broadcast's audio is unaffected (AW_STUDIO_TV_SOUND=1 to hear it)")
                }
                // The engine reads FRAMES off the player it attaches to, so a
                // paused film would broadcast a still. Resume before the
                // Studio starts, not after.
                player?.play()
                studioFilm = film
            } onCancel: {
                studioSetup = nil
                player?.play()
            }
        }
        .fullScreenCover(isPresented: $studioShowMixer) {
            StudioMixerTV(
                health: studioHealth,
                filmGain: studioFilmGain, micGain: studioMicGain,
                duckEnabled: studioDuckEnabled, filmPaused: studioHostPaused,
                onFilmGain: { g in
                    studioFilmGain = g
                    Task { await studioEngine?.setAudio(filmGain: g) }
                },
                onMicGain: { g in
                    studioMicGain = g
                    Task { await studioEngine?.setAudio(micGain: g) }
                },
                onDuck: { on in
                    studioDuckEnabled = on
                    Task { await studioEngine?.setAudio(duckEnabled: on) }
                },
                onTogglePause: {
                    studioHostPaused.toggle()
                    studioHostPaused ? player?.pause() : player?.play()
                },
                onDone: { studioShowMixer = false })
        }
        .overlay(alignment: .topLeading) {
            if studioFilm != nil {
                StudioTVHealth(health: studioHealth, filmFramesPerSecond: studioFilmFPS,
                               audioProblem: studioAudioProblem,
                               cameraFramesPerSecond: studioCameraFPS)
            }
        }
        .task(id: studioFilm?.archiveID) {
            guard let film = studioFilm else { return }
            await runStudio(for: film)
        }
        // Dev affordance: `AW_STUDIO_TV=1` alongside AW_START_ITEM/AW_AUTOPLAY
        // starts the Studio on the film that is playing, so the ten-foot
        // readout can be SEEN without driving a transport menu blind over the
        // remote — the same reason AW_START_TAB exists. No-op in production.
        .task {
            guard ProcessInfo.processInfo.environment["AW_STUDIO_TV"] == "1" else { return }
            // Wait for the film to be PLAYING — not merely for the player
            // object to exist, which is what this used to do and which is a
            // different moment entirely.
            //
            // Measured on Ben Bedroom 2026-09-18: the door paused the film and
            // two captures twelve seconds apart showed two different scenes,
            // i.e. the pause did not hold. The cause was here, not in the
            // pause. `player` is non-nil the instant it is constructed, long
            // before the stream is ready, and the readiness observer's own
            // `p.play()` (the #5 Play Next fix) then fired AFTER this door's
            // `pause()` and restarted it.
            //
            // The product cannot hit that race — a host reaches this menu
            // while already watching, so readiness fired minutes ago — which
            // is the point: a door that opens from a state the product never
            // occupies measures something the product never does (Decision
            // 130). Waiting for `.playing` puts the door in the host's state.
            for _ in 0..<60 where player?.timeControlStatus != .playing {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            // AW_TWITCH_SIGNIN=1 — start Twitch's device flow and print what a
            // HOST would be shown, so the sign-in can be completed without
            // driving focus over a remote (four `up` presses moved no visible
            // ring, §9.gggg). The same two calls the sign-in row makes.
            //
            // What is printed is what belongs on a television: the verification
            // URI and the user code. The DEVICE code is the polling credential
            // and the access token is the session, so neither is ever logged
            // (§5) — the same line the Android door draws.
            if ProcessInfo.processInfo.environment["AW_TWITCH_SIGNIN"] == "1" {
                do {
                    let p = try await StudioPlatformAuth.beginTwitchSignIn()
                    awdiag("AWTWITCH open %@ and enter %@", p.verificationURI, p.userCode)
                    try await StudioPlatformAuth.completeTwitchSignIn(p)
                    awdiag("AWTWITCH signed in")
                } catch {
                    awdiag("AWTWITCH failed=%@", "\(error)")
                }
            }
            // AW_YT_WHOAMI=1: name the channel a broadcast would reach, and
            // nothing else. A read, never a publish.
            if ProcessInfo.processInfo.environment["AW_YT_WHOAMI"] == "1" {
                for p in StudioPlatformAuth.Platform.allCases {
                    guard StudioPlatformAuth.isSignedIn(p) else {
                        awdiag("AWYT %@ not-signed-in", p.rawValue); continue
                    }
                    do {
                        awdiag("AWYT %@ account=%@", p.rawValue,
                               try await StudioPlatformAuth.accountName(for: p))
                        switch try await StudioPlatformAuth.readiness(for: p) {
                        case .ready: awdiag("AWYT %@ readiness=READY", p.rawValue)
                        case .blocked(let why): awdiag("AWYT %@ readiness=BLOCKED %@", p.rawValue, why)
                        }
                    } catch {
                        awdiag("AWYT %@ failed=%@", p.rawValue, "\(error)")
                    }
                }
            }
            guard let film = current ?? catalogItem else { return }
            if let why = StudioRights.refusal(rightsBucket: film.rightsBucket,
                                              contentType: film.contentType,
                                              year: film.year) {
                studioRefusalKind = .film
                studioRefusal = why
                // SAY IT IN THE LOG TOO. This refusal only ever set an
                // on-screen sentence and returned, so from a console a
                // refused run and a door that never fired were the SAME
                // evidence: nothing at all. That cost two runs on
                // 2026-09-19, both of them my own bad film picks, neither
                // diagnosable without standing in the room.
                awdiag("AWGATE film REFUSED id=%@ bucket=%@ year=%@: %@",
                       film.archiveID, film.rightsBucket ?? "nil",
                       film.year.map(String.init) ?? "nil", why)
                return
            }
            // ...and the SAME configuration gate the menu applies (§10.2b).
            // A door that skips a gate the product enforces is a door onto a
            // path the product does not have. `AW_STUDIO_TV_FORCE=1` bypasses
            // THIS check only, for measuring the readout on a build with no
            // client ids — it exists nowhere in the product.
            if ProcessInfo.processInfo.environment["AW_STUDIO_TV_FORCE"] != "1",
               let problem = Self.studioTVBroadcastProblem {
                studioRefusalKind = .configuration
                studioRefusal = problem
                awdiag("AWGATE configuration REFUSED: %@", problem)
                return
            }
            // ...and Rule 8.8a's confirmation, for the same reason: a door
            // that skips a gate the product enforces is a door onto a path the
            // product does not have. This is now where the door ENDS — the
            // product's next step is a host reading a screen and pressing Go
            // live, and a diagnostic that presses it for them would broadcast
            // from a television nobody is standing in front of.
            //
            // AW_STUDIO_TV_FORCE=1 is the other half, unchanged in meaning: it
            // skips to a destination-less encode, which is how the ten-foot
            // readout gets measured without a platform account. It exists
            // nowhere in the product.
            if ProcessInfo.processInfo.environment["AW_STUDIO_TV_FORCE"] != "1" {
                player?.pause()
                studioSetup = film
                // The same deadline the encode path carries, for the same
                // reason: a dev affordance that can outlive the person using
                // it needs one (a film was left playing for an hour on
                // 2026-09-17). A paused film behind a modal is quieter than
                // that and still is not a state to leave a television in.
                let hold = Double(ProcessInfo.processInfo.environment["AW_STUDIO_TV_SECONDS"] ?? "") ?? 180
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                if studioSetup != nil { studioSetup = nil; player?.play() }
                return
            }
            // MUTE THE ROOM. This box lives in someone's house and its audio
            // routes to every HomePod they own; a dev door that leaves a film
            // playing aloud is not a diagnostic, it is a disturbance. The
            // BROADCAST still carries the film — the mixer's own filmGain is
            // the on-air level (WATCH-TOGETHER §5) — so muting here costs the
            // measurement nothing except the local tap's signal.
            player?.isMuted = true
            studioFilm = film
            // AND, OPTIONALLY, THE MIXER ITSELF — Rule 8.8c's surface.
            //
            // It is reached in the product by opening the transport menu and
            // choosing Watch Together while live, which is three focus moves
            // and a select. Driving that over Companion costs about a minute a
            // press here, because `devicectl device capture screenshot` refuses
            // for roughly a minute after every pyatv press (measured
            // 2026-09-20: five consecutive refusals, then success at +45 s),
            // so a screenshot of the mixer took longer to obtain than the
            // change it was checking took to write. This door is the fix, and
            // it opens the PRODUCT's surface with the product's own bindings —
            // it does not build a second copy of it.
            if ProcessInfo.processInfo.environment["AW_STUDIO_TV_MIXER"] == "1" {
                studioShowMixer = true
            }
            // AND IT ENDS BY ITSELF. Nothing stopped the first version: the
            // engine polled until `studioFilm` went nil, and nothing set it
            // nil once a screenshot had been taken. A film played unmuted on
            // the owner's Apple TV for an hour (2026-09-17). A dev affordance
            // that can outlive the person using it needs a deadline, not a
            // habit of remembering.
            let limit = Double(ProcessInfo.processInfo.environment["AW_STUDIO_TV_SECONDS"] ?? "") ?? 180
            try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
            studioFilm = nil
            player?.isMuted = false
        }
        .onAppear {
            if PlaybackDiag.enabled { awdiag("AWLIFE screen=%@ onAppear", screenID) }
            store.isPlayingVideo = true; setupPlayer()
        }
        .onDisappear {
            if PlaybackDiag.enabled { awdiag("AWLIFE screen=%@ onDisappear", screenID) }
            store.isPlayingVideo = false; teardownPlayer()
        }
        // #10: autoplay swapped `current` -> rebuild the player for the next film.
        .onChange(of: current?.archiveID) { _, _ in
            if PlaybackDiag.enabled { awdiag("AWLIFE screen=%@ currentChanged", screenID) }
            autoRetried = false          // #10: fresh retry budget per item
            forceDirectPlayback = false  // new item tries the HLS-subtitle path fresh
            usingFallbackURL = nil       // each item starts on its best copy
            playerVersions = []          // and offers ITS copies, not the last film's
            fallbackCandidate = nil
            fallbackProbe?.cancel(); fallbackProbe = nil
            teardownPlayer()
            playback = .loading
            setupPlayer()
        }
    }

    /// Does this title have a subtitle FILE — published in the catalog, or
    /// fetched/transcribed on this device? Decision 070: these no longer imply
    /// an HLS wrapper; the file is rendered by the caption overlay.
    private var hasFileSubtitles: Bool {
        let active = current ?? catalogItem
        return active?.subtitleHLSURL != nil
            || SubtitleStore.cachedDir(for: activeArchiveID) != nil
    }

    /// What live captions should transcribe, or nil when the film carries a real
    /// subtitle file (those go through `subtitleReviewSource` instead).
    private var liveCaptionSource: URL? {
        guard !hasFileSubtitles else { return nil }
        // The Settings toggle GATES the engine — it does not merely describe
        // it. Decision 056 removed a caption toggle that controlled nothing;
        // this one must actually stop the second stream, both because that is
        // what the words promise and because it is the A/B that localizes the
        // audio-static report.
        guard LiveCaptions.transcribeWhenMissing else { return nil }
        let active = current ?? catalogItem
        return active?.videoURLParsed ?? url
    }

    /// When the film HAS a subtitle file: the audio to transcribe and the file
    /// to check against — and, since Decision 070, to DISPLAY. A file the
    /// viewer fetched on this device wins over the published one.
    private var subtitleReviewSource: (video: URL, vtt: URL)? {
        guard hasFileSubtitles else { return nil }
        let active = current ?? catalogItem
        guard let video = active?.videoURLParsed ?? url as URL? else { return nil }
        if let dir = SubtitleStore.cachedDir(for: activeArchiveID) {
            let local = dir.appendingPathComponent("en.vtt")
            if FileManager.default.fileExists(atPath: local.path) {
                return (video, local)
            }
        }
        guard let vtt = active?.publishedVTTURL else { return nil }
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
        // SharePlay lives here rather than in the Detail action row: that row
        // already carries seven buttons inside a 1100pt cap, and an eighth is
        // what truncates the Play label. Starting a session mid-film is also the
        // more natural moment — you are already watching when you think to
        // invite someone.
        let withFriends = UIAction(
            title: "With friends…",
            image: UIImage(systemName: "shareplay")
        ) { _ in
            // `active` here is the AutoplayMode local, not the film — the item
            // is `current ?? catalogItem`.
            guard let film = current ?? catalogItem else { return }
            Task {
                let outcome = await WatchTogether.shared.share(archiveID: film.archiveID,
                                                              title: film.title,
                                                              year: film.year)
                if outcome == .needsCall { sharePlayNotice = true }
            }
        }
        // The public half (tvOS-DESIGN §8.8, docs/WATCH-TOGETHER.md §1). It
        // belongs HERE rather than on Detail for the same reason SharePlay
        // does — and better: the viewer is already watching when they decide
        // to bring the world in, and the Studio is this player plus overlays,
        // so nothing is presented over anything.
        let withTheWorld = UIAction(
            title: "With the world…",
            image: UIImage(systemName: "dot.radiowaves.left.and.right")
        ) { _ in
            guard let film = current ?? catalogItem else { return }
            // Rights first, and REFUSE WITH THE REASON (§3.4, §5). An
            // ineligible film is never silently absent from the menu.
            if let why = StudioRights.refusal(rightsBucket: film.rightsBucket,
                                              contentType: film.contentType,
                                              year: film.year) {
                studioRefusalKind = .film
                studioRefusal = why
                // SAY IT IN THE LOG TOO. This refusal only ever set an
                // on-screen sentence and returned, so from a console a
                // refused run and a door that never fired were the SAME
                // evidence: nothing at all. That cost two runs on
                // 2026-09-19, both of them my own bad film picks, neither
                // diagnosable without standing in the room.
                awdiag("AWGATE film REFUSED id=%@ bucket=%@ year=%@: %@",
                       film.archiveID, film.rightsBucket ?? "nil",
                       film.year.map(String.init) ?? "nil", why)
                return
            }
            // THEN whether this build can sign in at all (tvOS-DESIGN §10.2b).
            // A host is told where they asked to go live — in the same alert
            // that already carries a rights refusal — rather than being let
            // into a production mode that can never reach an audience. iOS
            // greys out Go Live for the same reason; a television has no
            // equivalent control to grey, so it says so here.
            if let problem = Self.studioTVBroadcastProblem {
                studioRefusalKind = .configuration
                studioRefusal = problem
                awdiag("AWGATE configuration REFUSED: %@", problem)
                return
            }
            // THEN the confirmation itself (Rule 8.8a). This used to be the
            // line `studioFilm = film` behind a one-time §3.4a alert, because
            // "a television has no moment where Go Live is pressed, so it
            // asks". It has one now, and that surface carries §3.4a's warning
            // every time — the same way iOS and macOS do — so the alert would
            // be the same paragraph twice in a row.
            //
            // The film PAUSES while the confirmation is up. A television
            // running on unattended behind a modal is the ten-foot version of
            // leaving the room with the projector going.
            //
            // THIS LINE WAS DELETED ONCE AND SHOULD NOT BE AGAIN. It was
            // removed on 2026-09-18 because two captures fifteen seconds apart
            // showed different frames, which was read as "the pause does not
            // hold". It does. A KVO probe on the player's own
            // `timeControlStatus` logged exactly one transition — to `.paused`
            // — and nothing for the next two minutes, and three captures
            // fifteen seconds apart came back BYTE-IDENTICAL (§9.xxx). What
            // differed in the original pair was the film's paused frame not
            // yet being drawn behind a cover that had just been presented:
            // the first capture's background is pure black, the second's is
            // the same still the third would show. A PNG byte-difference is
            // not evidence of playback, and treating it as such deleted
            // working code.
            //
            // The genuine bug was the diagnostic's race, fixed below: the door
            // paused before the stream was ready, so the readiness observer's
            // own `play()` landed afterwards.
            player?.pause()
            studioSetup = film
        }
        // Rule 8.8g's four choices. A checkmark marks the one on air, which
        // is how tvOS shows state in a menu — the same idiom the caption and
        // version choosers already use, rather than a control invented here.
        var studioCardActions: [UIMenuElement] {
            let options: [(String, StudioOverlay.Card?)] = [
                ("None", nil),
                ("Starting soon", .startingSoon(secondsRemaining: 60)),
                ("Intermission", .intermission),
                ("Thanks for watching", .ending),
            ]
            return options.map { label, card in
                let on = String(describing: studioCard) == String(describing: card)
                return UIAction(title: label, state: on ? .on : .off) { _ in
                    studioCard = card
                    Task { await applyStudioCard(card) }
                }
            }
        }

        // RULE 8.8c — ONE CONTROL WHOSE MEANING FOLLOWS THE STATE. While a
        // broadcast is on air this is the mixer; otherwise it is the way to
        // start one. Owner, 2026-09-20: "I think you should be able to launch
        // the controls via the same watch together button that you would press
        // to launch a stream. When you are actually live streaming, that button
        // should house controls."
        let liveChildren: [UIMenuElement] = [
            UIAction(title: "Live mixer",
                     image: UIImage(systemName: "slider.horizontal.3")) { _ in
                studioShowMixer = true
            },
            UIAction(title: studioHostPaused ? "Resume the film" : "Pause the film",
                     image: UIImage(systemName: studioHostPaused ? "play.fill" : "pause.fill")) { _ in
                studioHostPaused.toggle()
                studioHostPaused ? player?.pause() : player?.play()
            },
            // RULE 8.8g — the cards, in the television's own idiom. They live
            // in this menu and not in the mixer because 8.8c's duck toggle is
            // "the one focusable control on the screen, deliberately": a
            // second button makes the focus engine swallow the arrow keys the
            // faders need. A menu has no such problem, and §8 already says
            // everything about the show hangs off the transport menu.
            UIMenu(title: "Show a card", image: UIImage(systemName: "rectangle.on.rectangle"),
                   children: studioCardActions),
            // RULE 8.8h — END. Owner, 2026-09-21: "The stream should only end
            // when the person streaming it decides that it should end ...
            // There should be an easy way to end a stream from every platform
            // that can start one." A TELEVISION HAD NO WAY AT ALL: the only
            // thing that set `studioFilm` to nil from anything resembling a
            // host action was a debug door's timeout. The film keeps playing —
            // ending the broadcast is not ending the evening.
            UIAction(title: "End the broadcast",
                     image: UIImage(systemName: "stop.circle"),
                     attributes: .destructive) { _ in
                studioCard = nil
                studioFilm = nil
                studioRequest = nil
            }
        ]
        let watchTogether = UIMenu(
            title: "Watch Together",
            image: UIImage(systemName: "person.2.wave.2"),
            children: studioFilm != nil ? liveChildren : [withFriends, withTheWorld])
        var items: [UIMenuElement] = [playNext, muteToggle, watchTogether]
        // An EPHEMERAL lineup (Party Play, a channel, a cartoon marathon) is a
        // wall of films the viewer did not choose — so the two questions it
        // raises are "what IS this?" and "keep this". tvOS-DESIGN §9.3 bound
        // both before either was built; the owner asked for them after a
        // Party Play left a film unidentifiable. Open Title leaves the lineup
        // for the film's Detail (add to a playlist, favorite, read about it).
        // Remember writes the watch-history record NOW, without waiting for
        // the 60-second gate the automatic history write uses.
        if ephemeralLineup {
            items.append(UIAction(title: "Open Title",
                                  image: UIImage(systemName: "info.circle")) { _ in
                openCurrentTitle()
            })
            items.append(UIAction(title: "Remember",
                                  image: UIImage(systemName: "clock.arrow.circlepath")) { _ in
                print("AWLINEUP remember \(activeArchiveID)")
                WatchProgress.remember(in: modelContext, archiveID: activeArchiveID)
            })
        }
        // The caption-TYPE chooser (owner 2026-08-26): pick between the
        // subtitle FILE and AUTOMATIC captions the way the Version menu picks
        // a copy — not a bare on/off. The native CC menu went with the
        // single-segment HLS wrapper (Decision 070); this menu is its
        // replacement, now with the choice the owner asked for.
        let autoAvailable = LiveCaptions.isSupported
        if hasFileSubtitles || autoAvailable {
            let effective: CaptionCoordinator.CaptionChoice = captionChoice
                ?? (SystemCaptionStyle.viewerWantsCaptions
                    ? (hasFileSubtitles ? .file : .automatic) : .off)
            var subtitleActions: [UIAction] = []
            if hasFileSubtitles {
                subtitleActions.append(UIAction(
                    title: "Subtitle File",
                    image: UIImage(systemName: "doc.text"),
                    state: effective == .file ? .on : .off) { _ in
                        captionChoice = .file
                    })
            }
            if autoAvailable {
                subtitleActions.append(UIAction(
                    title: "Automatic",
                    image: UIImage(systemName: "waveform"),
                    state: effective == .automatic ? .on : .off) { _ in
                        captionChoice = .automatic
                    })
            }
            subtitleActions.append(UIAction(
                title: "Off",
                image: UIImage(systemName: "captions.bubble"),
                state: effective == .off ? .on : .off) { _ in
                    captionChoice = .off
                })
            items.append(UIMenu(title: "Subtitles",
                                image: UIImage(systemName: "captions.bubble"),
                                children: subtitleActions))
        }
        // Switch copy WITHOUT leaving the film (owner, 2026-08-17). Detail's
        // picker only helps before you start; the moment that matters is three
        // minutes in when the picture is stuttering, and backing out to change
        // it costs the viewer their place.
        if playerVersions.count > 1 {
            let chosen = ArchiveVersions.chosenName(for: activeArchiveID)
            let pipelineName = (current ?? catalogItem)?.videoURLParsed?
                .lastPathComponent.removingPercentEncoding
            let versionActions = playerVersions.map { version in
                UIAction(title: version.compactLabel,
                         state: (chosen ?? pipelineName) == version.name ? .on : .off) { _ in
                    switchToVersion(version)
                }
            }
            items.append(UIMenu(title: "Version",
                                image: UIImage(systemName: "rectangle.stack"),
                                children: versionActions))
        }
        items.append(UIMenu(title: "Autoplay Next",
                            image: UIImage(systemName: "play.circle"), children: actions))
        return items
    }

    /// Rebuild playback on a different copy of the same film, at the same spot.
    ///
    /// Position is PERSISTED before teardown and the reload resumes from it —
    /// the same shape the fallback swap uses (Decision 077). A switch that
    /// restarted the film would be a worse outcome than the stutter someone is
    /// trying to escape.
    private func switchToVersion(_ version: ArchiveVersions.Version) {
        ArchiveVersions.choose(version, for: activeArchiveID)
        // Carry the position ACROSS the switch explicitly rather than trusting
        // the persisted record to round-trip. Measured on the Apple TV: the
        // first version of this restarted Utopia at 00:34 from 1:16, because
        // setupPlayer resolves resume from WatchProgress and that path is
        // written for a fresh open, not for a rebuild happening inside one.
        // A switch that loses your place is worse than the stutter you were
        // trying to escape.
        let resumeAt = player?.currentTime().seconds
        switchResumeSeconds = (resumeAt?.isFinite == true && (resumeAt ?? 0) > 5)
            ? resumeAt : nil
        awdiag("AWLIFE screen=%@ VERSION SWITCH -> %@ resumeAt=%.0f", screenID,
               version.name, switchResumeSeconds ?? -1)
        // A manual choice supersedes any fallback the player fell back to.
        usingFallbackURL = nil
        teardownPlayer(persist: true)
        playback = .loading
        setupPlayer()
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
    private func handleLoadFailure(_ message: String, retryable: Bool = true) {
        if PlaybackDiag.enabled {
            awdiag("AWLIFE screen=%@ handleLoadFailure autoRetried=%d msg=%@",
                  screenID, autoRetried ? 1 : 0, message)
        }
        // A codec the hardware cannot decode does not heal on retry: the
        // rebuilt player detected AV1 again, ITS failure auto-retried again,
        // and a third player streamed audio-only over a black screen — the
        // exact symptom the detection exists to prevent.
        if !retryable {
            teardownPlayer(persist: false)
            playback = .failed(message)
            return
        }
        // FALLBACK FIRST (owner decision 2026-08-15): a startup failure with a
        // vetted lower-quality copy in hand switches to it immediately —
        // retrying the same URL against a node that just proved unable to
        // serve it wastes the viewer's start budget. Only startup failures
        // fall back (played < 30s); a mid-film failure keeps the same copy so
        // resume is seamless.
        let played = player?.currentTime().seconds ?? 0
        let startupFailure = !(played.isFinite && played > 30)
        if startupFailure, usingFallbackURL == nil,
           let fb = (current ?? catalogItem)?.fallbackVideoURLParsed ?? fallbackCandidate {
            usingFallbackURL = fb
            awdiag("AWLIFE screen=%@ FALLBACK to lower-quality copy %@", screenID, fb.absoluteString)
            teardownPlayer(persist: false)
            playback = .loading
            setupPlayer()
            return
        }
        if !autoRetried {
            autoRetried = true
            // If this item used the HLS-subtitle path, the retry drops it and
            // plays the MP4 directly — a broken HLS playlist must never make an
            // otherwise-playable film unplayable.
            if (current ?? catalogItem)?.subtitleHLSURL != nil { forceDirectPlayback = true }
            // A failure DURING playback (the captioned-HLS item can die
            // mid-film) must resume where the viewer was, not where the 5s
            // progress writer last got to. Startup failures keep persist:false —
            // there is no position worth keeping at t=0.
            teardownPlayer(persist: played.isFinite && played > 30)
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
            // Both the best copy and any fallback have failed to START. The
            // generic "request timed out" blames nobody; the true condition
            // is nearly always the source (measured 2026-08-15: archive.org
            // nodes serving 2 Mbps with 25s first bytes — no player can
            // stream a 5.7 Mbps film from that).
            let honest = usingFallbackURL != nil || fallbackCandidate == nil
                ? "The Internet Archive's servers are struggling with this title right now. It usually recovers within a few hours — please try again later."
                : message
            playback = .failed(honest)
        }
    }

    private var activeArchiveID: String { current?.archiveID ?? archiveID }

    // Part (c): a persistent mid-stream stall on the native-HLS (captioned) path
    // drops CC and rebuilds on the resilient MP4. persist:true captures the
    // current position first so setupPlayer resumes at (within ~5s of) the stall.
    private func forceDirectFallback() {
        guard !forceDirectPlayback, (current ?? catalogItem)?.subtitleHLSURL != nil else { return }
        if PlaybackDiag.enabled { awdiag("AWLIFE screen=%@ forceDirectFallback", screenID) }
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
        if PlaybackDiag.enabled { awdiag("AWLIFE screen=%@ forceResilientFallback", screenID) }
        forceResilientPlayback = true
        teardownPlayer(persist: true)
        playback = .loading
        setupPlayer()
    }

    private func setupPlayer() {
        if PlaybackDiag.enabled {
            awdiag("AWLIFE screen=%@ setupPlayer item=%@ hadPlayer=%d",
                  screenID, activeArchiveID, player != nil ? 1 : 0)
        }
        playback = .loading
        let active = current ?? catalogItem
        // Diagnostic-only: AW_URL_OVERRIDE swaps the source for the AW_START_ITEM
        // film, so a harness can play the SAME film from a controlled server —
        // the decisive mux-vs-delivery experiment (a LAN-served faststart remux
        // against the badly-interleaved archive.org original).
        var playURL = usingFallbackURL ?? active?.videoURLParsed ?? url
        // The viewer's own choice of copy wins over the pipeline's pick — but
        // never over a FALLBACK already in play, which only exists because the
        // preferred copy could not stream (Decision 077).
        if usingFallbackURL == nil {
            playURL = ArchiveVersions.preferredURL(for: activeArchiveID, default: playURL)
        }
        // D079 Phase-1 experiment gate: route playback through the
        // LocalMediaServer instead of the custom-scheme loader. Diagnostic
        // until the cutover gates pass (byte-diff green Mac-side; this env
        // exists for the on-device generated-captions verification).
        if ProcessInfo.processInfo.environment["AW_PROXY_EXP"] == "1",
           let proxied = LocalMediaServer.shared.proxyURL(for: playURL) {
            awdiag("AWLIFE PROXY EXPERIMENT %@ -> %@", playURL.absoluteString, proxied.absoluteString)
            playURL = proxied
        }
        if let ov = ProcessInfo.processInfo.environment["AW_URL_OVERRIDE"],
           let ovURL = URL(string: ov),
           ProcessInfo.processInfo.environment["AW_START_ITEM"] == activeArchiveID {
            playURL = ovURL
            awdiag("AWLIFE URL OVERRIDE -> %@", ov)
        }
        let playerItem: AVPlayerItem
        // Decision 070: the captioned-HLS wrapper (Config C) is RETIRED on tvOS.
        // Its single MP4 "segment" made AVFoundation buffer the ENTIRE film —
        // measured on device: loadedTimeRanges reached 5,300s (575 MB) while
        // preferredForwardBufferDuration asked for 300, because a segment is the
        // atomic buffering unit — and mediaserverd does not survive that on a
        // 3 GB Apple TV: AVError -11819 (media services reset) killed the item
        // ~2 minutes in, every run, on every build since the path shipped. It
        // never failed on a Mac, which is why weeks of Mac-side verification
        // kept passing. Captioned films now play through ResilientStreamLoader
        // (memory-bounded range requests, Decisions 021/031/034 resilience) and
        // their published/local VTT is rendered by the caption overlay
        // (CaptionCoordinator file-cues mode), judged by SubtitleReview as
        // before.
        // Decision 072: ONE pipeline on tvOS — every title plays through
        // ResilientStreamLoader. The plain-URL branch that lived here (Decision
        // 067's trade: give up resilience so the system could offer generated
        // captions) is retired: measured on this tvOS 27 beta the system's
        // track is offered and almost never emits, while the plain path
        // reintroduced the Decision-021 disease — archive.org idle resets
        // flushing the buffer, seen from the sofa as frame drops and "pausing
        // while it refreshes the stream" — and its stall fallback rebuilt the
        // player mid-film. Our own engine captions uncaptioned titles
        // (Decision 068); captioned files render through the overlay (070).
        // One path, one resilience story, no mid-film swaps.
        // A loopback (proxy) URL must stay a PLAIN asset — wrapping it in the
        // custom scheme would re-disqualify it from everything the proxy
        // exists to restore (D079). The resilience lives server-side.
        // ONE chooser for every tvOS surface (TVAssetChooser): plain asset
        // for loopback, HLS-over-LocalMediaServer on tvOS 27+, and Decision
        // 072's resilient loader everywhere else.
        let (chosenItem, chosenLoader) = TVAssetChooser.makeItem(for: playURL)
        playerItem = chosenItem
        streamLoader = chosenLoader

        // Prefetch a same-item smaller derivative WHILE the primary loads, so
        // a 25s-budget failure can switch instantly instead of paying a
        // metadata round-trip on top. Catalog-baked fallbacks need no fetch.
        if usingFallbackURL == nil, fallbackCandidate == nil,
           (current ?? catalogItem)?.fallbackVideoURLParsed == nil,
           let primary = (current ?? catalogItem)?.videoURLParsed {
            let itemID = activeArchiveID
            fallbackProbe?.cancel()
            fallbackProbe = Task { @MainActor in
                let found = await ArchiveFallback.smallerCopy(itemID: itemID, than: primary)
                guard !Task.isCancelled else { return }
                fallbackCandidate = found
                if let found, PlaybackDiag.enabled {
                    awdiag("AWLIFE screen=%@ fallback candidate ready %@", screenID, found.lastPathComponent)
                }
            }
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
        // SharePlay: only ever the MAIN player. The caption scout is a second,
        // muted player running ahead at 2x (Decisions 058/069/072) and would
        // drag the whole group to 2x if it were coordinated. Re-attaching on
        // every build is deliberate — a player rebuilt by the Decision-077
        // fallback carries a NEW coordinator, and keeps the same archiveID so
        // the group still considers it the same film.
        WatchTogether.shared.attach(p, archiveID: active?.archiveID ?? archiveID)
        freezeGuard.attach(to: p, item: playerItem)
        nowPlaying.begin(posterURL: active?.posterURLParsed, item: playerItem)


        // Watch the item ready or fail so a broken stream becomes a visible,
        // recoverable error instead of the dead "no-entry" circle (#19). KVO can
        // fire off-main; hop to the main actor before touching view state.
        statusObserver = playerItem.observe(\.status, options: [.new]) { observed, _ in
            Task { @MainActor in
                switch observed.status {
                case .readyToPlay:
                    if PlaybackDiag.enabled { awdiag("AWLIFE screen=%@ itemReady", screenID) }
                    if SystemCaptionProbe.enabled { sysCapProbe.attach(to: observed) }
                    // No Apple TV has an AV1 decoder, and AVFoundation does
                    // not FAIL on an AV1 track — it reports ready, plays the
                    // audio, and silently drops the video (The Oregon Trail:
                    // sound and captions over black; the pipeline's verifier
                    // runs on a Mac, which CAN decode AV1). Checked HERE, at
                    // ready — running loadTracks at setupPlayer added a moov
                    // fetch to the startup window and helped time out slow-
                    // morning loads. By ready the track info is already
                    // parsed, so this costs nothing.
                    Task { @MainActor in
                        guard let track = try? await observed.asset
                            .loadTracks(withMediaType: .video).first,
                              let descs = try? await track.load(.formatDescriptions) else { return }
                        for d in descs {
                            let sub = CMFormatDescriptionGetMediaSubType(d)
                            let name = sub == 0x6176_3031 ? "AV1" : sub == 0x7670_3039 ? "VP9" : nil
                            if let name {
                                awdiag("AWLIFE screen=%@ unsupportedCodec %@", screenID, name)
                                timeoutTask?.cancel()
                                handleLoadFailure("This copy's video is \(name), which Apple TV can't decode. The picture would stay black.", retryable: false)
                                return
                            }
                        }
                    }
                    playback = .ready
                    skipCount = 0          // #7: a good item resets the skip budget
                    timeoutTask?.cancel()
                    // NOW the held resume/join seek can land (before play, so
                    // the viewer never sees the opening frames flash by).
                    if let s = pendingSeekSeconds {
                        pendingSeekSeconds = nil
                        await observed.seek(to: CMTime(seconds: s, preferredTimescale: 600),
                                            toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
                    }
                    // Start playback on ready — covers BOTH the first item and
                    // every lineup/autoplay advance. The AVPlayerContainer's
                    // .onAppear { play() } only fires for the first item; when
                    // `current` swaps, the controller is updated in place (no
                    // re-appear), so without this the next video loads + seeks to
                    // its resume position but never starts (#5 Play Next bug).
                    p.play()
                    // Now that the picture is up, find out what other copies
                    // exist so the transport menu can offer them. Deliberately
                    // after play(): this is a network round trip and nothing
                    // about it should delay the first frame.
                    if playerVersions.isEmpty {
                        let id = activeArchiveID
                        Task { @MainActor in
                            let found = await ArchiveVersions.list(itemID: id)
                            if activeArchiveID == id { playerVersions = found }
                        }
                    }
                case .failed:
                    if PlaybackDiag.enabled {
                        awdiag("AWLIFE screen=%@ itemFailed t=%.0f error=%@", screenID,
                              observed.currentTime().seconds,
                              String(describing: observed.error))
                    }
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
            // TWO-STAGE patience. At 25s: if a fallback copy is in hand
            // (catalog-baked, or the runtime probe has answered by now),
            // switch to it — that is what the 30-second start promise is
            // for. With nothing to switch to, patience costs nothing:
            // keep loading to 60s like the old never-errors player, and
            // only then fail. A flat 25s cut was showing "Can't play this
            // title" on cold-but-viable loads (24-31s first bytes) the
            // old player always won.
            try? await Task.sleep(for: fallbackAt)
            guard !Task.isCancelled else {
                awdiag("AWLIFE screen=%@ loadTimeout CANCELLED before 25s", screenID)
                return
            }
            // Report the DECISION, not just the firing. Measured on the device:
            // Yojimbo's archive.org node took 32.7s to first byte (against 0.7s
            // for a healthy film) and the player sat silent for 130 seconds —
            // neither the 25s fallback nor the 60s give-up produced a line, so
            // there was no way to tell whether they had fired, been cancelled,
            // or found a state they did not expect.
            awdiag("AWLIFE screen=%@ loadTimeout@25s playback=%@ fallbackInHand=%d",
                   screenID, String(describing: playback),
                   ((current ?? catalogItem)?.fallbackVideoURLParsed != nil
                    || fallbackCandidate != nil) ? 1 : 0)
            if playback == .loading, usingFallbackURL == nil,
               ((current ?? catalogItem)?.fallbackVideoURLParsed != nil || fallbackCandidate != nil) {
                if PlaybackDiag.enabled { awdiag("AWLIFE screen=%@ loadTimeoutFired (fallback in hand)", screenID) }
                handleLoadFailure("This title is taking too long to load. The source may be temporarily unavailable.")
                return
            }
            try? await Task.sleep(for: giveUpAt - fallbackAt)
            guard !Task.isCancelled else {
                awdiag("AWLIFE screen=%@ loadTimeout CANCELLED before 60s", screenID)
                return
            }
            awdiag("AWLIFE screen=%@ loadTimeout@60s playback=%@",
                   screenID, String(describing: playback))
            if playback == .loading {
                if PlaybackDiag.enabled { awdiag("AWLIFE screen=%@ loadTimeoutFired", screenID) }
                handleLoadFailure("This title is taking too long to load. The source may be temporarily unavailable.")
            }
        }

        let aid = activeArchiveID
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == aid }
        )
        pendingSeekSeconds = nil
        // Diagnostic-only: a harness control experiment plays a TRUNCATED
        // remux of a film whose stored resume position exceeds it.
        let noResume = ProcessInfo.processInfo.environment["AW_NO_RESUME"] == "1"
        // An in-place version switch carries its own position and it WINS: it
        // is where the viewer actually is, one moment ago, on the same film.
        if !noResume, let carried = switchResumeSeconds {
            switchResumeSeconds = nil
            pendingSeekSeconds = carried
            awdiag("AWLIFE screen=%@ resume from version switch t=%.0f", screenID, carried)
        } else if !noResume, let existing = try? modelContext.fetch(descriptor).first,
           existing.positionSeconds > 10,
           !existing.isComplete {
            pendingSeekSeconds = existing.positionSeconds
        } else if joinOffset > 5 {
            // #92: join the channel's current program in progress (only when
            // there's no resume position to honor).
            pendingSeekSeconds = joinOffset
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
        if PlaybackDiag.enabled {
            awdiag("AWLIFE screen=%@ teardownPlayer hadPlayer=%d", screenID, player != nil ? 1 : 0)
        }
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        freezeGuard.detach()
        captionStall.detach()
        nowPlaying.end()
        if persist, let p = player {
            persistProgress(at: p.currentTime().seconds, duration: p.currentItem?.duration.seconds)
        }
        player?.pause()
        // Detach the item as well: pause() alone left a torn-down player UNDEAD
        // on tvOS — clock advancing, pipeline active, rate reading NaN — for the
        // rest of the session (measured on device, His Girl Friday baseline:
        // the orphan ran 7+ minutes alongside its replacement). Two live
        // pipelines is the "stutter with repeating lines" the owner reported:
        // the film plays twice, offset by the rebuild gap. No item, no pipeline.
        player?.replaceCurrentItem(with: nil)
        player = nil
        timeObserver = nil
        streamLoader = nil
        statusObserver?.invalidate()
        statusObserver = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// Leave the lineup for the playing film's own Detail page. The player is
    /// a fullScreenCover over the tab that started the lineup, so pushing onto
    /// that tab's path first and then dismissing lands the viewer on Detail
    /// with the lineup's landing page beneath it — Back returns to Party Play.
    private func openCurrentTitle() {
        guard let film = current ?? catalogItem else { return }
        print("AWLINEUP open-title \(film.archiveID)")
        router.push(film)
        dismiss()
    }

    private func persistProgress(at position: Double, duration: Double?) {
        // A held resume seek means the CURRENT position is not the viewer's
        // position — persisting it is how "Resume" destroyed the very place
        // it promised to return to.
        guard pendingSeekSeconds == nil else { return }
        // Ephemeral lineups (channel tune-ins, party walls, cartoon marathons)
        // never persist a RESUME POSITION — the invariant since the Channels
        // EPG shipped: channel positions polluted Continue Watching on every
        // synced device. But they DO now enter the watch HISTORY (owner,
        // 2026-08-15: a full record of everything ever watched): the record
        // gets its dates and play count while position/duration stay
        // untouched, so Continue Watching (position > 10) never sees it.
        guard position.isFinite, position > 0 else { return }
        WatchProgress.record(in: modelContext, archiveID: activeArchiveID,
                             position: position, duration: duration,
                             historyOnly: ephemeralLineup)
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

    /// An explicit URL, for things that are not a catalogue item — a shared
    /// PLAYLIST carries itself in its link (see `PlaylistShare`), so there is
    /// no archiveID to derive one from.
    private let explicitURL: String?

    init(title: String, archiveID: String) {
        self.title = title
        self.archiveID = archiveID
        self.explicitURL = nil
    }
    init(title: String, url: String) {
        self.title = title
        self.archiveID = ""
        self.explicitURL = url
    }
    init(item: Catalog.Item) {
        self.init(title: item.title, archiveID: item.archiveID)
    }


    // The QR sends people to OUR web app (Decision 030) — the same title,
    // playable in the browser, with the open-in-app handoff for phones.
    // LoC items stay on loc.gov (the web viewer can't resolve loc: ids).
    private var webURL: String {
        if let explicitURL { return explicitURL }
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



/// Long-form text a tvOS viewer can actually READ: focusable so the focus
/// engine will stop on it and the ScrollView will scroll to it, with a focus
/// ring the viewer can see — a focused element that looks identical to an
/// unfocused one is a trap by another name.
///
/// It is a Button rather than a bare `.focusable(true)` because expanding must
/// be a DELIBERATE Select. It used to expand from six lines to its full length
/// simply on gaining focus, and since focus passes through this block on the
/// way down the page, the page reflowed every time — twice per pass, out and
/// back (owner, 2026-09-04: "the description text reflows multiple times as
/// you scroll down the page"). `ReadingCardStyle` changes no geometry on
/// focus, so scrolling past is silent.
struct ReadableTextBlock: View {
    let text: String
    /// nil = never clamp. Otherwise the block shows this many lines and Select
    /// expands it — focus alone MUST NOT, because focus passes through this
    /// block on the way down the page and a block that resizes then makes
    /// everything below it jump (owner, 2026-09-04).
    var collapsedLines: Int? = 6
    var dimmed: Double = 0.85
    @State private var expanded = false

    /// Only offer the expansion when the clamp can actually be hiding
    /// something — roughly 42 characters a line at this size and width.
    private var canExpand: Bool {
        guard let n = collapsedLines else { return false }
        return text.count > n * 42
    }

    var body: some View {
        Button {
            guard canExpand else { return }
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .foregroundStyle(.white.opacity(dimmed))
                    .lineLimit(expanded ? nil : collapsedLines)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canExpand {
                    Text(expanded ? "Show less" : "Show more")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .buttonStyle(ReadingCardStyle())
        // This file's own header rule: a custom ButtonStyle still gets tvOS's
        // default halo on top of it unless the call site disables it.
        .focusEffectDisabled()
    }
}

#endif
