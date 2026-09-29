#if os(tvOS)
import SwiftUI
import AVKit
import SwiftData

// Series detail — replaces DetailView for items with
// contentType == "tv-series". Lazy-loads the full series + episode list
// from /series/{seriesID}.json via SeriesStore, renders a hero banner
// above a season-filtered episode grid, and presents the player as a
// fullScreenCover with prev/next transport.
//
// Loading states are important on tvOS — the user is on a remote, so
// we show a lightweight skeleton while the fetch lands. Falls back to
// the SeriesCard's poster + title + year range so the view feels
// substantive even before the /series JSON arrives.

struct SeriesDetailView: View {
    let seriesCard: Catalog.Item

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var favorites: [Favorite]
    // #3: share / add-to-playlist targets (series OR a long-pressed episode).
    @State private var heroTextWidth: CGFloat = 0
    @State private var shareTarget: ShareTarget?
    @State private var playlistTarget: PlaylistTarget?
    struct ShareTarget: Identifiable { let id: String; let title: String }
    struct PlaylistTarget: Identifiable { let id: String }
    @State private var series: Series?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var selectedSeasonIndex: Int = 0
    // Presentation is driven by the episode itself via fullScreenCover(item:)
    // — NOT a separate isPresented Bool. Holding the episode in one @State and
    // a presentation Bool in another races: setting both in a tap handler does
    // not guarantee the episode is committed before the cover's content closure
    // evaluates, so the cover could present with a nil episode (black screen,
    // "does nothing"). item: makes the episode the single source of truth.
    @State private var playingEpisode: Episode?
    @FocusState private var focusedEpisode: String?
    @FocusState private var focusedSeason: Int?
    @FocusState private var playFocused: Bool
    @State private var upNext: UpNext?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                infoSection
                seasonSection
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: playingEpisode) { _, now in
            if now == nil { upNext = computeUpNext() }
        }
        .fullScreenCover(item: $playingEpisode) { episode in
            if let series {
                EpisodePlayerScreen(series: series, initialEpisode: episode)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .sheet(item: $shareTarget) { ShareSheet(title: $0.title, archiveID: $0.id) }
        .sheet(item: $playlistTarget) { AddToPlaylistSheet(archiveID: $0.id) }
        .task(id: seriesCard.archiveID) {
            // Series cards use "series:<slug>" as archiveID to avoid
            // collisions with Archive identifiers. The actual per-series
            // JSON lives at /series/<slug>.json — pull the raw slug
            // from the dedicated seriesID field, with a prefix-strip
            // fallback for older exports.
            let slug = seriesCard.seriesID
                ?? seriesCard.archiveID.replacingOccurrences(of: "series:", with: "")
            isLoading = true
            loadError = false
            let loaded = await SeriesStore.shared.load(seriesID: slug)
            if let loaded {
                series = loaded
                selectedSeasonIndex = 0
            } else {
                loadError = true
            }
            isLoading = false
            upNext = computeUpNext()
            // Claim initial focus on Play once it has rendered (playbook §2:
            // initial-focus views must imperatively claim focus).
            if upNext != nil {
                try? await Task.sleep(for: .milliseconds(60))
                playFocused = true
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            backdropArtwork
            LinearGradient(
                colors: [
                    .clear,
                    .clear,
                    .black.opacity(0.5),
                    .black.opacity(0.92),
                    .black,
                ],
                startPoint: .top, endPoint: .bottom,
            )
            .allowsHitTesting(false)
            heroText
                .padding(.leading, 80)
                .padding(.trailing, 80)
                .padding(.bottom, 64)
        }
        // Grows with the title and facts at the largest Text Sizes.
        .frame(minHeight: 700)
    }

    @ViewBuilder
    private var backdropArtwork: some View {
        let url = series?.backdropURLParsed ?? series?.posterURLParsed ?? seriesCard.posterURLParsed
        if let url {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: 1920, height: 1080),
                contentMode: .fit,
                placeholder: Color(white: 0.08),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            LinearGradient(
                colors: [Color(white: 0.18), .black],
                startPoint: .topLeading, endPoint: .bottomTrailing,
            )
        }
    }

    @ViewBuilder
    private var heroText: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SERIES")
                .scaledFont(15, weight: .bold)
                .tracking(2.2)
                .foregroundStyle(store.accentColor(forCategory: "tv-series"))
            Text(series?.title ?? seriesCard.title)
                .scaledFont(64, weight: .heavy, design: .serif)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            let factsLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 18))
            factsLayout {
                if let range = yearRangeLabel {
                    Text(range)
                }
                if let ep = episodeCountLabel {
                    Text(ep)
                }
                if let sn = seasonCountLabel {
                    Text(sn)
                }
                if let net = (series?.networks.first ?? seriesCard.networks?.first) {
                    Text("Aired on \(net)")
                }
            }
            .scaledFont(22, weight: .regular)
            .foregroundStyle(.white.opacity(0.85))
            // #3: overview + cast moved OUT of the hero (they used to overlay the
            // poster); only the title/metadata + actions sit on the artwork now.
            seriesActions
        }
        // The widest of title, facts and actions: three controls alone would
        // make a 620pt, 35-character column.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { heroTextWidth = $0 }
        .frame(maxWidth: 1200, alignment: .leading)
    }

    // #3: favorite + share the whole series, from the main info page.
    @ViewBuilder
    private var seriesActions: some View {
        HStack(spacing: 16) {
            if let upNext { playButton(upNext) }
            Button(action: toggleSeriesFavorite) {
                Image(systemName: isSeriesFavorited ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(isSeriesFavorited ? store.accentColor(forCategory: "tv-series") : .white)
                    .padding(18)
            }
            .buttonStyle(CircleIconStyle())
            .focusEffectDisabled()
            Button {
                shareTarget = ShareTarget(id: seriesCard.archiveID,
                                          title: series?.title ?? seriesCard.title)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2).foregroundStyle(.white).padding(18)
            }
            .buttonStyle(CircleIconStyle())
            .focusEffectDisabled()
        }
        .padding(.top, 8)
        .focusSection()
    }

    // MARK: - Play / Resume / Next (tvOS-DESIGN §3.4b)

    typealias UpNext = SeriesUpNext
    private func computeUpNext() -> UpNext? { SeriesUpNext.compute(for: series, in: modelContext) }

    private func playButton(_ upNext: UpNext) -> some View {
        Button {
            playingEpisode = upNext.episode
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white).frame(width: 36, height: 36)
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(store.accentColor(forCategory: "tv-series"))
                        .offset(x: 1)
                }
                Text(upNext.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 10)
            .padding(.trailing, 28)
            .padding(.vertical, 10)
        }
        .buttonStyle(PrimaryCTAStyle(accent: store.accentColor(forCategory: "tv-series")))
        .focusEffectDisabled()
        .focused($playFocused)
        .layoutPriority(1)
    }

    private var isSeriesFavorited: Bool {
        favorites.contains { $0.archiveID == seriesCard.archiveID }
    }
    private func toggleSeriesFavorite() { toggleFavorite(seriesCard.archiveID) }

    private func toggleFavorite(_ archiveID: String) {
        if let existing = favorites.first(where: { $0.archiveID == archiveID }) {
            modelContext.delete(existing)
            SyncNudge.recordDeletion("fav:\(archiveID)", in: modelContext)  // saves + syncs
        } else {
            modelContext.insert(Favorite(archiveID: archiveID))
            try? modelContext.save()
            SyncNudge.nudge(modelContext)
        }
    }

    // #3: overview + cast in their own section BELOW the hero, so the poster art
    // is no longer covered by text.
    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let overview = series?.overview ?? seriesCard.synopsis, !overview.isEmpty {
                // Ends where the hero text above ends (tvOS-DESIGN §3.4c).
                ReadableTextBlock(text: overview, collapsedLines: 4, title: seriesCard.title)
                    .scaledFont(TVType.body, weight: .regular)
                    .frame(maxWidth: heroTextWidth > 0 ? min(max(heroTextWidth, 900), 1100) : 1100, alignment: .leading)
            }
            castRow
        }
        .padding(.horizontal, 80)
        .padding(.top, 28)
    }

    @ViewBuilder
    private var castRow: some View {
        if let cast = series?.cast, !cast.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(Array(cast.prefix(14)), id: \.name) { member in
                        PersonChip(name: member.name, role: member.character,
                                   profilePath: member.profilePath) {
                            router.push(BrowseFilter(person: member.name))
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
            .focusSection()
            .padding(.top, 8)
        }
    }

    private var yearRangeLabel: String? {
        let start = series?.yearStart ?? seriesCard.year
        let end = series?.yearEnd ?? seriesCard.yearEnd
        switch (start, end) {
        case let (s?, e?) where s == e: return String(s)
        case let (s?, e?): return "\(s)–\(e)"
        case let (s?, _): return String(s)
        case (_, let e?): return String(e)
        default: return nil
        }
    }

    private var episodeCountLabel: String? {
        let n = series?.episodesCount ?? seriesCard.episodesCount ?? 0
        guard n > 0 else { return nil }
        // "32 of 431 episodes" when we know the full canonical run and have a
        // partial set — communicates completeness and that more are coming.
        if let total = series?.canonicalEpisodesCount, total > n {
            return "\(n) of \(total) episodes"
        }
        return "\(n) episode\(n == 1 ? "" : "s")"
    }

    /// Only when every episode is held: counted from a partial run, "1 season"
    /// sat over an S3 episode of a six-season show (Here's Lucy).
    private var seasonCountLabel: String? {
        if let s = series, let total = s.canonicalEpisodesCount,
           let have = s.episodesCount, total > have { return nil }
        let n = series?.seasons.count ?? seriesCard.seasonsCount ?? 0
        return n > 0 ? "\(n) season\(n == 1 ? "" : "s")" : nil
    }

    // MARK: - Seasons + episodes

    @ViewBuilder
    private var seasonSection: some View {
        if isLoading {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Loading episodes…")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 120)
        } else if loadError || series == nil {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 54))
                    .foregroundStyle(.white.opacity(0.3))
                Text("Couldn't load episodes for this series.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 120)
        } else if let series, !series.seasons.isEmpty {
            seasonPicker(series: series)
            episodeGrid(
                episodes: series.seasons[safe: selectedSeasonIndex]?.episodes ?? [],
            )
                .padding(.bottom, 80)
        }
    }

    @ViewBuilder
    private func seasonPicker(series: Series) -> some View {
        if series.seasons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(series.seasons.enumerated()), id: \.offset) { idx, season in
                        let on = idx == selectedSeasonIndex
                        Button {
                            withAnimation(Motion.chrome) { selectedSeasonIndex = idx }
                        } label: {
                            Text(season.displayTitle)
                        }
                        .buttonStyle(ChipButtonStyle(accent: .accentColor, isOn: on))
                        .focused($focusedSeason, equals: idx)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 28)
            }
            // Season changes as focus moves across the chips — no extra
            // select press (matches the Apple TV app). Focus leaving the
            // chip row sets focusedSeason to nil, which we ignore so the
            // grid keeps showing the season the user landed on.
            .onChange(of: focusedSeason) { _, season in
                if let season, season != selectedSeasonIndex {
                    withAnimation(Motion.chrome) { selectedSeasonIndex = season }
                }
            }
        }
    }

    private let episodeCols = Array(
        repeating: GridItem(.fixed(380), spacing: 32), count: 3,
    )

    @ViewBuilder
    private func episodeGrid(episodes: [Episode]) -> some View {
        LazyVGrid(columns: episodeCols, alignment: .leading, spacing: 36) {
            ForEach(episodes) { ep in
                EpisodeCard(
                    episode: ep,
                    isFavorited: favorites.contains { $0.archiveID == ep.archiveID },
                    // Open the episode's OWN Detail (Decision 045) — like any film. Falls back to
                    // inline play if the episode item isn't in the catalog DB yet.
                    action: {
                        if let it = store.db?.item(ep.archiveID) { router.push(it) }
                        else { playingEpisode = ep }
                    },
                    onToggleFavorite: { toggleFavorite(ep.archiveID) },
                    onShare: { shareTarget = ShareTarget(id: ep.archiveID, title: ep.title) },
                    onAddToPlaylist: { playlistTarget = PlaylistTarget(id: ep.archiveID) }
                )
                .focused($focusedEpisode, equals: ep.archiveID)
            }
        }
        .padding(.horizontal, 80)
    }
}

// MARK: - EpisodeCard

struct EpisodeCard: View {
    let episode: Episode
    var isFavorited: Bool = false
    let action: () -> Void
    var onToggleFavorite: () -> Void = {}
    var onShare: () -> Void = {}
    var onAddToPlaylist: () -> Void = {}
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat  = 380
    private let cardHeight: CGFloat = 214   // 16:9

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: action) {
                stillArt
            }
            .buttonStyle(.card)
            .focused($isFocused)
            // #3: long-press an episode for favorite / share / add-to-playlist.
            .contextMenu {
                Button(action: onToggleFavorite) {
                    Label(isFavorited ? "Remove from Favorites" : "Favorite",
                          systemImage: isFavorited ? "heart.slash" : "heart")
                }
                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button(action: onAddToPlaylist) {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let num = episode.numberLabel {
                    Text(num)
                        .scaledFont(15, weight: .bold)
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(episode.title)
                    .scaledFont(TVType.body, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .scaledFont(TVType.meta)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
            .opacity(isFocused ? 1.0 : 0.85)
            .animation(Motion.focus, value: isFocused)
        }
    }

    @ViewBuilder
    private var stillArt: some View {
        ZStack {
            Color(white: 0.08)
            if let url = episode.stillURLParsed {
                // .fit + blurred backdrop: real 16:9 stills fill the slot,
                // while off-aspect fallbacks (e.g. a 2:3 poster when no
                // TVmaze still exists) show whole over a blurred fill instead
                // of being face-cropped. (Issue #5.)
                RemoteImage(
                    url: url,
                    targetSize: CGSize(width: 760, height: 428),
                    contentMode: .fit,
                    placeholder: Color(white: 0.08),
                    blurredBackdrop: true,
                )
            } else {
                Image(systemName: "film")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.25))
            }
            // Subtle play affordance on the corner.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(14)
                        .shadow(radius: 4)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Safe array subscript

fileprivate extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

#endif
