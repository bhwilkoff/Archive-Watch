#if os(iOS)
import SwiftUI

// A series card pushed from Browse → TV. The full episode list is lazy-loaded
// from /series/{slug}.json via the shared SeriesStore (the card's archiveID IS
// the series slug). Tapping an episode plays it via the episode initializer on
// PlayerView, so each episode keeps its own resume position.
struct SeriesRef: Hashable {
    let card: Catalog.Item
}

struct SeriesDetailView: View {
    let card: Catalog.Item

    @State private var series: Series?
    @State private var loading = true
    @State private var selectedSeason: Int? = nil
    @State private var playingEpisode: Episode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PosterImage(url: series?.backdropURLParsed ?? card.backdropURLParsed
                            ?? series?.posterURLParsed ?? card.posterURLParsed)
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxWidth: .infinity).frame(height: 220).clipped()

                VStack(alignment: .leading, spacing: 12) {
                    Text(series?.title ?? card.title).font(.title.bold())
                    if let meta = metaLine {
                        Text(meta).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let o = series?.overview ?? card.synopsis, !o.isEmpty {
                        Text(o).font(.body).foregroundStyle(.primary.opacity(0.9))
                    }
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else if shownEpisodes.isEmpty {
                        ContentUnavailableView("No episodes yet", systemImage: "tv",
                            description: Text("This series is in the catalog, but no playable episodes have been matched yet."))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                    } else {
                        seasonPicker
                        episodeList
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(series?.title ?? card.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .fullScreenCover(item: $playingEpisode) { ep in
            EpisodePlayerContainer(start: ep, in: series).ignoresSafeArea()
        }
        .task { await load() }
    }

    private func load() async {
        // Series cards use "series:<slug>" as their archiveID, but the per-series
        // JSON lives at /series/<slug>.json. Use the clean seriesID; strip the
        // "series:" prefix as a fallback (matches the tvOS SeriesDetailView).
        let slug = card.seriesID ?? card.archiveID.replacingOccurrences(of: "series:", with: "")
        series = await SeriesStore.shared.load(seriesID: slug)
        loading = false
        if selectedSeason == nil { selectedSeason = series?.seasons.first?.seasonNumber }
    }

    /// The series page on archivewatch.org (slugs can be non-ASCII — encode).
    private var shareURL: URL {
        let slug = card.seriesID ?? card.archiveID.replacingOccurrences(of: "series:", with: "")
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        return URL(string: "https://archivewatch.org/series/\(encoded)")
            ?? URL(string: "https://archivewatch.org")!
    }

    private var seasons: [Season] { series?.seasons ?? [] }

    private var shownEpisodes: [Episode] {
        if seasons.count <= 1 { return series?.flatEpisodes ?? [] }
        return seasons.first(where: { $0.seasonNumber == selectedSeason })?.episodes
            ?? series?.flatEpisodes ?? []
    }

    @ViewBuilder private var seasonPicker: some View {
        if seasons.count > 1 {
            Menu {
                ForEach(seasons, id: \.displayTitle) { s in
                    Button(s.displayTitle) { selectedSeason = s.seasonNumber }
                }
            } label: {
                Label(currentSeasonTitle, systemImage: "chevron.down").font(.headline)
            }
            .padding(.top, 4)
        }
    }

    private var currentSeasonTitle: String {
        seasons.first(where: { $0.seasonNumber == selectedSeason })?.displayTitle
            ?? seasons.first?.displayTitle ?? "Episodes"
    }

    @ViewBuilder private var episodeList: some View {
        LazyVStack(spacing: 12) {
            ForEach(shownEpisodes) { ep in
                Button { playingEpisode = ep } label: { EpisodeRow(episode: ep) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var metaLine: String? {
        let yr: String? = {
            guard let s = series?.yearStart ?? card.year else { return nil }
            if let e = series?.yearEnd { return "\(s)–\(e)" }
            return String(s)
        }()
        let eps = (series?.episodesCount ?? card.episodesCount).map { "\($0) episodes" }
        let line = [yr, eps].compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }
}

// Hosts the player with manual prev/next episode controls (PARITY §3 "prev/next
// episode in player"). AVPlayerViewController on iOS has no custom-transport API,
// so the chevrons live in a small overlay capsule; switching recreates the player
// via .id, and each episode keeps its own resume position. Auto-advance (binge)
// reports back through onAdvance so the chevrons stay anchored to what's playing.
private struct EpisodePlayerContainer: View {
    let series: Series?
    @State private var episode: Episode

    init(start: Episode, in series: Series?) {
        self.series = series
        _episode = State(initialValue: start)
    }

    private var prev: Episode? { series?.episode(before: episode) }
    private var next: Episode? { series?.episode(after: episode) }

    var body: some View {
        PlayerView(episode: episode, in: series) { advancedID in
            if let e = series?.flatEpisodes.first(where: { $0.archiveID == advancedID }) {
                episode = e
            }
        }
        .id(episode.archiveID)
        .overlay(alignment: .topTrailing) {
            if series != nil, prev != nil || next != nil {
                HStack(spacing: 18) {
                    Button { if let p = prev { episode = p } } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(prev == nil)
                    if let n = episode.numberLabel {
                        Text(n).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    }
                    Button { if let n = next { episode = n } } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .disabled(next == nil)
                }
                .font(.body)
                .tint(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.45), in: .capsule)
                .padding(.top, 8).padding(.trailing, 16)
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: episode.stillURLParsed)
                .frame(width: 124, height: 70).clipShape(.rect(cornerRadius: 8))
                .overlay(Image(systemName: "play.circle.fill")
                    .font(.title2).foregroundStyle(.white.opacity(0.9)))
            VStack(alignment: .leading, spacing: 2) {
                if let n = episode.numberLabel {
                    Text(n).font(.caption).foregroundStyle(.secondary)
                }
                Text(episode.title).font(.subheadline).fontWeight(.medium).lineLimit(2)
                if let o = episode.overview, !o.isEmpty {
                    Text(o).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#endif
