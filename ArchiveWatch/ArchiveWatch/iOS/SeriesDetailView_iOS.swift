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
        .fullScreenCover(item: $playingEpisode) { ep in
            PlayerView(episode: ep, in: series).ignoresSafeArea()
        }
        .task { await load() }
    }

    private func load() async {
        series = await SeriesStore.shared.load(seriesID: card.archiveID)
        loading = false
        if selectedSeason == nil { selectedSeason = series?.seasons.first?.seasonNumber }
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
