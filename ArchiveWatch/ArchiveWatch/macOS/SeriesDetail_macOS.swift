#if os(macOS)
import SwiftUI

// TV drill-in (parity with iOS/tvOS): a series card routes here instead of the
// movie DetailView. The episode list lazy-loads from /series/{slug}.json via the
// shared SeriesStore (the card's archiveID IS the series slug). Each episode plays
// through the router's episode player, keeping its own resume position.
// docs/macOS-DESIGN.md §1 (parity face) — same verb, Mac-native idiom.

struct SeriesRef: Hashable { let card: Catalog.Item }

struct SeriesDetailView: View {
    let card: Catalog.Item
    @Environment(AppRouter.self) private var router

    @State private var series: Series?
    @State private var loading = true
    @State private var selectedSeason: Int? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                backdrop
                VStack(alignment: .leading, spacing: 12) {
                    Text(series?.title ?? card.title).font(.largeTitle.bold())
                    if let meta = metaLine {
                        Text(meta).font(.title3).foregroundStyle(.secondary)
                    }
                    if let o = series?.overview ?? card.synopsis, !o.isEmpty {
                        Text(o).font(.body).foregroundStyle(.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if shownEpisodes.isEmpty {
                        ContentUnavailableView(
                            "No episodes yet", systemImage: "tv",
                            description: Text("This series is in the catalog, but no playable episodes have been matched yet."))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                    } else {
                        if seasons.count > 1 { seasonPicker }
                        episodeList
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(series?.title ?? card.title)
        .task { await load() }
    }

    // Sized container owns the layout; the fill image rides in .overlay + .clipped
    // so it can't drive layout (the fill-image trap fixed on the poster cards).
    private var backdrop: some View {
        Color.clear
            .frame(maxWidth: .infinity).frame(height: 280)
            .overlay {
                AsyncImage(url: series?.backdropURLParsed ?? card.backdropURLParsed
                           ?? series?.posterURLParsed ?? card.posterURLParsed) { img in
                    img.resizable().scaledToFill()
                } placeholder: { Color.black.opacity(0.15) }
            }
            .clipped()
    }

    private func load() async {
        // Series cards use "series:<slug>" as their archiveID, but the per-series
        // JSON lives at /series/<slug>.json. Prefer the clean seriesID; strip the
        // "series:" prefix as a fallback (matches the iOS/tvOS SeriesDetailView).
        let slug = card.seriesID ?? card.archiveID.replacingOccurrences(of: "series:", with: "")
        series = await SeriesStore.shared.load(seriesID: slug)
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
        Menu {
            ForEach(seasons, id: \.displayTitle) { s in
                Button(s.displayTitle) { selectedSeason = s.seasonNumber }
            }
        } label: {
            Label(currentSeasonTitle, systemImage: "chevron.down").font(.headline)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.top, 4)
    }

    private var currentSeasonTitle: String {
        seasons.first(where: { $0.seasonNumber == selectedSeason })?.displayTitle
            ?? seasons.first?.displayTitle ?? "Episodes"
    }

    @ViewBuilder private var episodeList: some View {
        LazyVStack(spacing: 10) {
            ForEach(shownEpisodes) { ep in
                Button { router.playEpisode(ep, in: series) } label: { EpisodeRow(episode: ep) }
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 124, height: 70)
                .overlay {
                    AsyncImage(url: episode.stillURLParsed) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { Rectangle().fill(.quaternary) }
                }
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.title2).foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                }
            VStack(alignment: .leading, spacing: 2) {
                if let n = episode.numberLabel {
                    Text(n).font(.caption).foregroundStyle(.secondary)
                }
                Text(episode.title).font(.headline).lineLimit(2)
                if let o = episode.overview, !o.isEmpty {
                    Text(o).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
#endif
