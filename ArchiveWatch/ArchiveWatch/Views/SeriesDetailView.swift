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
    @Environment(\.modelContext) private var modelContext
    @State private var series: Series?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var selectedSeasonIndex: Int = 0
    @State private var isPlaying = false
    @State private var startingEpisode: Episode?
    @FocusState private var focusedEpisode: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                seasonSection
            }
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(isPresented: $isPlaying) {
            if let series, let startingEpisode {
                EpisodePlayerScreen(series: series, initialEpisode: startingEpisode)
            }
        }
        .task(id: seriesCard.archiveID) {
            isLoading = true
            loadError = false
            let loaded = await SeriesStore.shared.load(seriesID: seriesCard.archiveID)
            if let loaded {
                series = loaded
                selectedSeasonIndex = 0
            } else {
                loadError = true
            }
            isLoading = false
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
        .frame(height: 700)
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
                .font(.system(size: 15, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(store.accentColor(forCategory: "tv-series"))
            Text(series?.title ?? seriesCard.title)
                .font(.system(size: 64, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            HStack(spacing: 18) {
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
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(.white.opacity(0.85))
            if let overview = series?.overview ?? seriesCard.synopsis, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: 1200, alignment: .leading)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: 1200, alignment: .leading)
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
        return n > 0 ? "\(n) episode\(n == 1 ? "" : "s")" : nil
    }

    private var seasonCountLabel: String? {
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
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 28)
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
                EpisodeCard(episode: ep) {
                    startingEpisode = ep
                    isPlaying = true
                }
                .focused($focusedEpisode, equals: ep.archiveID)
            }
        }
        .padding(.horizontal, 80)
    }
}

// MARK: - EpisodeCard

struct EpisodeCard: View {
    let episode: Episode
    let action: () -> Void
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

            VStack(alignment: .leading, spacing: 6) {
                if let num = episode.numberLabel {
                    Text(num)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(episode.title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 17))
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
                RemoteImage(
                    url: url,
                    targetSize: CGSize(width: 760, height: 428),
                    contentMode: .fill,
                    placeholder: Color(white: 0.08),
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
