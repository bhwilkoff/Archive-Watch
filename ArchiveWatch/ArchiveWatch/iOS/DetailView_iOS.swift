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
    @State private var isWatchedState = false
    @State private var versions: [ArchiveVersions.Version] = []
    @State private var loadingVersions = false
    @State private var chosenVersionName: String?
    @State private var addingToPlaylist = false
    @State private var clipping = false
    @State private var gettingSubtitles = false
    @State private var captionPlaybackChoice: CaptionPlaybackChoice?
    @State private var playbackError: String?

    private var isFav: Bool { favorites.contains { $0.archiveID == item.archiveID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHero(poster: Self.upsized(item.posterURLParsed),
                           backdrop: Self.upsized(item.backdropURLParsed))

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title).font(.title.bold())
                    Text(metaLine).font(.subheadline).foregroundStyle(.secondary)

                    // Play gets its OWN row. It used to share one HStack with the
                    // icon buttons, so each icon added stole width from it — and
                    // once the subtitles button made five, "Play · 28 min" was
                    // squeezed to one character per line. A row whose layout
                    // degrades as actions are added is a row that will break
                    // again, so the fix is structural rather than a tighter font.
                    Button { playing = true } label: {
                        Label(playLabel, systemImage: "play.fill")
                            .lineLimit(1)              // never wrap, whatever happens
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.primary)
                    .controlSize(.large)
                    .disabled(item.videoURLParsed == nil)

                    HStack(spacing: 12) {
                        Button { toggleFavorite() } label: {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                        }
                        .buttonStyle(.bordered)

                        Button { addingToPlaylist = true } label: {
                            Image(systemName: "text.badge.plus")
                                .accessibilityLabel("Add to playlist")
                        }
                        .buttonStyle(.bordered)

                        // Watched is a badge on tiles; this is where the viewer
                        // corrects it (tvOS parity — a film abandoned near the
                        // end reads as finished, one seen elsewhere never
                        // registers at all).
                        Button {
                            if WatchProgress.setWatched(
                                !isWatchedState, in: ctx, archiveID: item.archiveID) {
                                isWatchedState.toggle()
                            }
                            SyncNudge.nudge(ctx)
                            if isWatchedState {
                                store.completedArchiveIDs.insert(item.archiveID)
                            } else {
                                store.completedArchiveIDs.remove(item.archiveID)
                            }
                        } label: {
                            Image(systemName: isWatchedState
                                  ? "checkmark.circle.fill" : "checkmark.circle")
                                .accessibilityLabel(isWatchedState
                                    ? "Mark as not watched" : "Mark as watched")
                        }
                        .buttonStyle(.bordered)

                        // Subtitles. This lived inside the share menu, which is
                        // where nobody looks for subtitles — a viewer who wants
                        // them looks at the film, not at a share sheet. Now the
                        // caption-type hub (owner 2026-08-26), it shows for
                        // every playable title: a film WITH a subtitle file is
                        // exactly where choosing File vs Automatic matters.
                        if item.videoURLParsed != nil {
                            Button { gettingSubtitles = true } label: {
                                Image(systemName: "captions.bubble")
                                    .accessibilityLabel("Get subtitles")
                            }
                            .buttonStyle(.bordered)
                        }

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

                        // Choose which copy of the film to play — the same
                        // control tvOS has, since a phone on cellular has even
                        // more reason to want a lighter transfer than a TV on
                        // wifi does (owner, 2026-08-17).
                        if item.videoURLParsed != nil {
                            Menu {
                                if versions.isEmpty {
                                    Text(loadingVersions ? "Loading…" : "No other copies")
                                } else {
                                    ForEach(versions) { v in
                                        Button {
                                            ArchiveVersions.choose(v, for: item.archiveID)
                                            chosenVersionName = v.name
                                        } label: {
                                            Label(v.label, systemImage:
                                                chosenVersionName == v.name
                                                    ? "checkmark.circle.fill" : "circle")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        ArchiveVersions.choose(nil, for: item.archiveID)
                                        chosenVersionName = nil
                                    } label: { Label("Use the default copy", systemImage: "arrow.uturn.backward") }
                                }
                            } label: {
                                Image(systemName: "rectangle.stack")
                            }
                            .buttonStyle(.bordered)
                            .tint(chosenVersionName == nil ? nil : .accentColor)
                            .task {
                                chosenVersionName = ArchiveVersions.chosenName(for: item.archiveID)
                                guard versions.isEmpty else { return }
                                loadingVersions = true
                                versions = await ArchiveVersions.list(itemID: item.archiveID)
                                loadingVersions = false
                            }
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
                        Spacer(minLength: 0)
                    }

                    if let tagline = item.tagline, !tagline.isEmpty {
                        Text(tagline).font(.callout).italic().foregroundStyle(.secondary)
                    }
                    if let s = item.synopsis, !s.isEmpty {
                        Text(s).font(.body).foregroundStyle(.primary.opacity(0.9))
                    }
                    DetailFacts(item: item)
                    // Episode item (Decision 045): a way back to the full series.
                    if item.isEpisode, let sid = item.seriesID {
                        Button {
                            if let card = store.seriesCard(seriesID: sid) { router.push(SeriesRef(card: card)) }
                        } label: {
                            Label("Part of \(item.seriesTitle ?? "the series")", systemImage: "tv")
                        }
                        .buttonStyle(.bordered)
                    }
                    if !item.cast.isEmpty || item.director?.isEmpty == false {
                        CastRow(cast: item.cast, director: item.director,
                                directorProfilePath: item.directorProfilePath)
                    }
                    CommunityDetailSection(item: item)
                    relatedSection
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing) {
            PlayerView(item: item, autoplayIn: store, onUnplayable: { message in
                playing = false
                playbackError = message
            }, captionChoice: captionPlaybackChoice).ignoresSafeArea()
        }
        .alert("Can't play this title", isPresented: .constant(playbackError != nil)) {
            Button("OK") { playbackError = nil }
        } message: {
            Text(playbackError ?? "")
        }
        .sheet(isPresented: $addingToPlaylist) {
            AddToPlaylistSheet(archiveID: item.archiveID)
        }
        .sheet(isPresented: $clipping) {
            ClipStudioView(source: item.clipSource)
        }
        .sheet(isPresented: $gettingSubtitles) {
            GetSubtitlesView(item: item, playbackChoice: $captionPlaybackChoice)
                .presentationDetents([.medium, .large])
        }
        // Dev affordance (with AW_START_ITEM): start playback immediately so
        // playback diagnostics can run unattended on the simulator.
        .task(id: item.archiveID) {
            isWatchedState = store.completedArchiveIDs.contains(item.archiveID)
                || WatchProgress.isWatched(archiveID: item.archiveID, in: ctx)
        }
        .task {
            if ProcessInfo.processInfo.environment["AW_AUTOPLAY"] == "1",
               item.videoURLParsed != nil {
                playing = true
            }
            // Screen-audit hook (caption loop W6): present the subtitles sheet
            // deterministically — simctl cannot tap, and a sheet nobody can
            // open unattended is a sheet nobody can regression-test. No-op in
            // production like every AW_ hook.
            if ProcessInfo.processInfo.environment["AW_SHOW_SUBTITLES"] == "1" {
                gettingSubtitles = true
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
    var directorProfilePath: String? = nil
    @Environment(Router.self) private var router

    /// TMDb profile paths are stored as "/abc.jpg"; full URLs pass through.
    static func profileURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        return URL(string: "https://image.tmdb.org/t/p/w185\(p)")
    }

    /// Up-to-two-letter initials for a photoless avatar (e.g. the director).
    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast & Crew").font(.title3).fontWeight(.semibold)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    if let d = director, !d.isEmpty {
                        bubble(name: d, role: "Director", profilePath: directorProfilePath, personID: nil)
                    }
                    ForEach(cast.prefix(12), id: \.name) { member in
                        bubble(name: member.name, role: member.character,
                               profilePath: member.profilePath, personID: member.tmdbPersonID)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private func bubble(name: String, role: String?, profilePath: String?, personID: Int?) -> some View {
        Button {
            router.push(BrowseFilterRoute(title: name, person: name))
        } label: {
            VStack(spacing: 4) {
                Group {
                    // A photoless member (e.g. the director — stored name-only, no profile path)
                    // degrades to an initials circle, not PosterImage's "film" glyph which reads
                    // as a broken image (owner 2026-06-29).
                    if let url = Self.profileURL(profilePath) {
                        PosterImage(url: url)
                    } else {
                        Circle().fill(.quaternary)
                            .overlay(Text(Self.initials(name)).font(.headline).foregroundStyle(.secondary))
                    }
                }
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
        // Long-press → open this person directly in Callsheet (Decision 046
        // unblocks the person deep-link via tmdbPersonID; the primary tap still
        // browses their other titles).
        .contextMenu {
            if let pid = personID, Callsheet.isInstalled,
               let url = Callsheet.personURL(tmdbPersonID: pid) {
                Button { Callsheet.open(url) } label: {
                    Label("Open in Callsheet", systemImage: "person.text.rectangle")
                }
            }
        }
    }
}

// Tier 1+2 metadata-expansion facts (Decision 046): franchise, studios, full
// crew, awards. Each row only renders when the field is present, so unmatched
// films show nothing extra.
private struct DetailFacts: View {
    let item: Catalog.Item

    var body: some View {
        let rows = facts
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.0).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(row.1).font(.caption).foregroundStyle(.primary.opacity(0.85))
                    }
                }
            }
            .padding(.top, 2)
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
}

#endif
