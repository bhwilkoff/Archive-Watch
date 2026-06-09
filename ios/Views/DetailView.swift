import SwiftUI
import SwiftData

// Detail: full-bleed backdrop, metadata, Play, Favorite, synopsis, cast, and
// "More Like This". Native iOS: a scroll view with a prominent Play button and a
// fullScreenCover player; favorite is a toolbar/heart toggle backed by SwiftData.
struct DetailView: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query private var favorites: [Favorite]
    @State private var playing = false

    private var isFav: Bool { favorites.contains { $0.archiveID == item.archiveID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PosterImage(url: item.backdropURLParsed ?? item.posterURLParsed)
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxWidth: .infinity).frame(height: 220).clipped()

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title).font(.title.bold())
                    Text(metaLine).font(.subheadline).foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button { playing = true } label: {
                            Label(playLabel, systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                        .disabled(item.videoURLParsed == nil)

                        Button { toggleFavorite() } label: {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                        }
                        .buttonStyle(.bordered)

                        ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                    }

                    if let s = item.synopsis, !s.isEmpty {
                        Text(s).font(.body).foregroundStyle(.primary.opacity(0.9))
                    }
                    if !item.cast.isEmpty { CastRow(cast: item.cast) }
                    relatedSection
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing) { PlayerView(item: item).ignoresSafeArea() }
    }

    private var metaLine: String {
        [item.year.map(String.init), item.runtimeSeconds.map { "\($0/60) min" },
         item.contentType.replacingOccurrences(of: "-", with: " ").capitalized,
         item.director.map { "Dir. \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
    private var playLabel: String {
        item.runtimeSeconds.map { "Play · \($0/60) min" } ?? "Play"
    }
    private var shareURL: URL {
        URL(string: "https://bhwilkoff.github.io/Archive-Watch/item/\(item.archiveID)")!
    }

    private func toggleFavorite() {
        if let f = favorites.first(where: { $0.archiveID == item.archiveID }) {
            ctx.delete(f)
            SyncNudge.recordDeletion("fav:\(item.archiveID)", in: ctx)
        } else {
            ctx.insert(Favorite(archiveID: item.archiveID)); try? ctx.save()
            SyncNudge.nudge(ctx)
        }
    }

    @ViewBuilder private var relatedSection: some View {
        let related = store.related(to: item)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("More Like This").font(.title3).fontWeight(.semibold)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(related) { r in
                            Button { router.openDetail(r) } label: { PosterTile(item: r, width: 100) }
                                .buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
    }
}

private struct CastRow: View {
    let cast: [Catalog.CastMember]
    /// TMDb profile paths are stored as "/abc.jpg"; full URLs pass through.
    static func profileURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        return URL(string: "https://image.tmdb.org/t/p/w185\(p)")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast").font(.title3).fontWeight(.semibold)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(cast.prefix(12), id: \.name) { member in
                        VStack(spacing: 4) {
                            PosterImage(url: Self.profileURL(member.profilePath))
                                .frame(width: 64, height: 64).clipShape(.circle)
                            Text(member.name).font(.caption2).lineLimit(2)
                                .frame(width: 72).multilineTextAlignment(.center)
                        }
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }
}
