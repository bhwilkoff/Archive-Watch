#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

// Detail: poster + metadata + play, favorite, share, add-to-playlist, synopsis, cast
// (tappable → person), More Like This, community reviews. The "Open in Creation Studio"
// affordance lands here in a later phase.

struct DetailView: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query private var favorites: [Favorite]
    @State private var showPlaylistSheet = false

    private var isFav: Bool { favorites.contains { $0.archiveID == item.archiveID } }
    private var shareURL: URL { URL(string: "https://archivewatch.org/item/\(item.archiveID)")! }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let s = item.displaySynopsis {
                    Text(s).font(.body).textSelection(.enabled)
                }
                // Episode item (Decision 045): jump to the full series.
                if item.isEpisode, let sid = item.seriesID {
                    Button {
                        if let card = store.db?.seriesCard(slug: sid) { router.openDetail(card) }
                    } label: {
                        Label("Part of \(item.seriesTitle ?? "the series")", systemImage: "tv")
                    }
                    .buttonStyle(.bordered)
                }
                if !item.cast.isEmpty { castRow }
                let related = store.related(to: item)
                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("More Like This").font(.title3).fontWeight(.semibold)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(related) { PosterCard(item: $0).frame(width: 140) }
                            }
                        }
                    }
                }
                if !item.displayReviews.isEmpty { reviews }
            }
            .padding(28)
        }
        .navigationTitle(item.title)
        .sheet(isPresented: $showPlaylistSheet) {
            AddToPlaylistSheet(archiveID: item.archiveID)
        }
    }

    private func toggleFavorite() {
        if let f = favorites.first(where: { $0.archiveID == item.archiveID }) {
            ctx.delete(f)
            // Tombstone so the removal propagates on CloudKit pull (documented "fav:<id>"
            // keying; the app's foreground/sign-in sync triggers push it).
            ctx.insert(Tombstone(key: "fav:\(item.archiveID)"))
        } else {
            ctx.insert(Favorite(archiveID: item.archiveID))
        }
        try? ctx.save()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                if let url = item.posterURLParsed {
                    RemoteImage(url: url, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: 240, height: 360)

            VStack(alignment: .leading, spacing: 12) {
                Text(item.title).font(.largeTitle).fontWeight(.bold)
                HStack(spacing: 10) {
                    if let y = item.year { Text(verbatim: String(y)) }
                    if let r = item.imdbRatingDisplay { Label(r, systemImage: "star.fill") }
                    if let rt = item.runtimeSeconds { Text("\(rt/60) min") }
                    if item.isBlackAndWhite { Text("B&W") }
                }
                .foregroundStyle(.secondary)
                if let by = item.byline { Text(by).foregroundStyle(.secondary) }
                if !item.genres.isEmpty {
                    Text(item.genres.prefix(4).joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let tagline = item.tagline, !tagline.isEmpty {
                    Text(tagline).font(.callout).italic().foregroundStyle(.secondary)
                }
                detailFacts
                HStack(spacing: 10) {
                    if item.videoURLParsed != nil {
                        Button { router.play(item) } label: {
                            Label("Play", systemImage: "play.fill")
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Button { toggleFavorite() } label: {
                        Label(isFav ? "Favorited" : "Favorite",
                              systemImage: isFav ? "heart.fill" : "heart")
                    }
                    .controlSize(.large)
                    .help(isFav ? "Remove from Favorites" : "Add to Favorites")
                    Button { showPlaylistSheet = true } label: {
                        Label("Add to Playlist", systemImage: "text.badge.plus")
                    }
                    .controlSize(.large)
                    // One consolidated Share menu (parity with iOS) — Callsheet + share link +
                    // archive.org, instead of three separate toolbar-ish buttons.
                    Menu {
                        if item.isClippable {
                            Button { openInCreationStudio() } label: {
                                Label("Open in Creation Studio", systemImage: "scissors")
                            }
                            Divider()
                        }
                        if Callsheet.supports(item) {
                            Button { Callsheet.open(Callsheet.url(for: item)) } label: {
                                Label(Callsheet.actionTitle, systemImage: Callsheet.actionIcon)
                            }
                        }
                        ShareLink(item: shareURL) { Label("Share Link…", systemImage: "square.and.arrow.up") }
                        Link(destination: URL(string: item.sourceDetailsURL)!) {
                            Label("View on archive.org", systemImage: "globe")
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.large)
                    .fixedSize()
                }
                .padding(.top, 4)
                Spacer()
            }
            Spacer()
        }
    }

    /// Open this title in Creation Studio's mark-in/out editor — the same scrubber the Add-a-Clip
    /// browser pushes to, but reachable from any title's Detail. Queue the item, then open a fresh
    /// project window; the editor's .task consumes `pendingClipItem` and presents MarkClipView.
    private func openInCreationStudio() {
        store.pendingClipItem = item
        NSDocumentController.shared.newDocument(nil)
    }

    /// TMDb profile paths are stored as "/abc.jpg" tokens; expand to a full image URL. (The bug:
    /// the raw token was passed to URL(string:) so cast photos never loaded.) Full URLs pass through.
    private func profileURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        return URL(string: "https://image.tmdb.org/t/p/w185\(p)")
    }

    // Tier 1+2 metadata-expansion facts (Decision 046): franchise, studios, full
    // crew, awards. Each row renders only when present.
    @ViewBuilder private var detailFacts: some View {
        let rows = facts
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.0).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(row.1).font(.caption).foregroundStyle(.primary.opacity(0.85))
                            .textSelection(.enabled)
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

    private var castRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast & Crew").font(.title3).fontWeight(.semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    if let d = item.director, !d.isEmpty {
                        castBubble(name: d, role: "Director", profilePath: nil, personID: nil)
                    }
                    ForEach(item.cast.prefix(16), id: \.name) { member in
                        castBubble(name: member.name, role: member.character,
                                   profilePath: member.profilePath, personID: member.tmdbPersonID)
                    }
                }
            }
        }
    }

    private func castBubble(name: String, role: String?, profilePath: String?, personID: Int?) -> some View {
        Button { router.openPerson(name) } label: {
            VStack(spacing: 4) {
                Circle().fill(.quaternary).frame(width: 64, height: 64)
                    .overlay {
                        if let u = profileURL(profilePath) {
                            RemoteImage(url: u, contentMode: .fill).clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill").foregroundStyle(.secondary)
                        }
                    }
                    .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                Text(name).font(.caption2).lineLimit(2).multilineTextAlignment(.center).frame(width: 76)
                if let role, !role.isEmpty {
                    Text(role).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).frame(width: 76)
                }
            }
        }
        .buttonStyle(.plain)
        .help("See more from \(name)")
        // Right-click → open this person directly in Callsheet (Decision 046
        // unblocks the person deep-link via tmdbPersonID; the primary click still
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

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reviews").font(.title3).fontWeight(.semibold)
            ForEach(item.displayReviews.prefix(6)) { r in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(r.displayName).fontWeight(.medium)
                        if let s = r.stars {
                            Text(String(repeating: "★", count: s)).foregroundStyle(.orange)
                        }
                        Spacer()
                        if let d = r.date { Text(d).font(.caption).foregroundStyle(.secondary) }
                    }
                    if let t = r.title, !t.isEmpty { Text(t).fontWeight(.semibold) }
                    if let b = r.body { Text(b).font(.callout).foregroundStyle(.secondary) }
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
#endif
