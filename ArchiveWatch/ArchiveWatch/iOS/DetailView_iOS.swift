#if os(iOS)
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
    @State private var addingToPlaylist = false
    @State private var clipping = false

    private var isFav: Bool { favorites.contains { $0.archiveID == item.archiveID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHero(poster: Self.upsized(item.posterURLParsed),
                           backdrop: Self.upsized(item.backdropURLParsed))

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

                        Button { addingToPlaylist = true } label: {
                            Image(systemName: "text.badge.plus")
                                .accessibilityLabel("Add to playlist")
                        }
                        .buttonStyle(.bordered)

                        // Create: clip / GIF / fan-edit this title (Decision 033).
                        // Rights-gated — only public-domain / CC content (the
                        // affordance is hidden, not disabled, when not clippable).
                        if item.isClippable {
                            Button { clipping = true } label: {
                                Image(systemName: "scissors")
                                    .accessibilityLabel("Create a clip or GIF")
                            }
                            .buttonStyle(.bordered)
                        }

                        Menu {
                            if Callsheet.supports(item) {
                                Button { Callsheet.open(Callsheet.url(for: item)) } label: {
                                    Label(Callsheet.actionTitle, systemImage: Callsheet.actionIcon)
                                }
                            }
                            ShareLink(item: shareURL) {
                                Label("Share link…", systemImage: "square.and.arrow.up")
                            }
                            Link(destination: archiveOrgURL) {
                                Label("View on archive.org", systemImage: "globe")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let s = item.synopsis, !s.isEmpty {
                        Text(s).font(.body).foregroundStyle(.primary.opacity(0.9))
                    }
                    if !item.cast.isEmpty || item.director?.isEmpty == false {
                        CastRow(cast: item.cast, director: item.director)
                    }
                    relatedSection
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing) {
            PlayerView(item: item, autoplayIn: store).ignoresSafeArea()
        }
        .sheet(isPresented: $addingToPlaylist) {
            AddToPlaylistSheet(archiveID: item.archiveID)
        }
        .sheet(isPresented: $clipping) {
            ClipStudioView(item: item)
        }
        // Dev affordance (with AW_START_ITEM): start playback immediately so
        // playback diagnostics can run unattended on the simulator.
        .task {
            if ProcessInfo.processInfo.environment["AW_AUTOPLAY"] == "1",
               item.videoURLParsed != nil {
                playing = true
            }
        }
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
        URL(string: "https://archivewatch.org/item/\(item.archiveID)")!
    }
    private var archiveOrgURL: URL {
        URL(string: "https://archive.org/details/\(item.archiveID)") ?? shareURL
    }

    /// Detail wants sharper art than shelf tiles: upgrade known CDN size tokens
    /// (TMDb /t/p/wNNN, OMDb/Amazon _SX300) to detail-appropriate sizes. URLs
    /// without a recognized token pass through untouched.
    static func upsized(_ url: URL?) -> URL? {
        guard let s = url?.absoluteString else { return nil }
        var out = s
        for small in ["/t/p/w185/", "/t/p/w342/", "/t/p/w500/"] {
            out = out.replacingOccurrences(of: small, with: "/t/p/w780/")
        }
        out = out.replacingOccurrences(of: "_SX300", with: "_SX800")
        return URL(string: out) ?? url
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

// Detail header artwork: the POSTER, aspect-fit and explicitly height-framed so
// it can never render fill-cropped (owner report 2026-06-10: posters were
// cropped/low-res on the title view), floating over a blurred ambient fill of
// the backdrop (or the poster itself). Taller on iPad/regular width.
private struct DetailHero: View {
    let poster: URL?
    let backdrop: URL?
    @Environment(\.horizontalSizeClass) private var hSize

    private var height: CGFloat { hSize == .regular ? 460 : 340 }

    var body: some View {
        PosterImage(url: poster ?? backdrop, contentMode: .fit)
            .frame(height: height - 32)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // Ambient fill MUST be a .background: a fill-mode image reports its
            // COVER size (not the proposal) and frame(maxWidth:.infinity) adopts
            // an oversized child — a 16:9 backdrop covering this 340pt hero
            // reported 604pt wide and dragged the whole Detail column off both
            // screen edges (owner screenshot 2026-06-10; poster-only items were
            // unaffected, which is why it was intermittent). A background can
            // never influence layout; the overflow just gets clipped.
            .background {
                PosterImage(url: backdrop ?? poster)
                    .blur(radius: 28)
                    .overlay(Color.black.opacity(0.45))
            }
            .clipped()
    }
}

// Tappable cast & crew (#4 parity with tvOS PersonChip): each bubble pushes a
// browse of that person's other titles via the FTS names index. Director leads.
private struct CastRow: View {
    let cast: [Catalog.CastMember]
    var director: String? = nil
    @Environment(Router.self) private var router

    /// TMDb profile paths are stored as "/abc.jpg"; full URLs pass through.
    static func profileURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        return URL(string: "https://image.tmdb.org/t/p/w185\(p)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast & Crew").font(.title3).fontWeight(.semibold)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    if let d = director, !d.isEmpty {
                        bubble(name: d, role: "Director", profilePath: nil)
                    }
                    ForEach(cast.prefix(12), id: \.name) { member in
                        bubble(name: member.name, role: member.character,
                               profilePath: member.profilePath)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private func bubble(name: String, role: String?, profilePath: String?) -> some View {
        Button {
            router.push(BrowseFilterRoute(title: name, person: name))
        } label: {
            VStack(spacing: 4) {
                PosterImage(url: Self.profileURL(profilePath))
                    .frame(width: 64, height: 64).clipShape(.circle)
                    .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                Text(name).font(.caption2).lineLimit(2)
                    .frame(width: 72).multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                if let role, !role.isEmpty {
                    Text(role).font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1).frame(width: 72)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#endif
