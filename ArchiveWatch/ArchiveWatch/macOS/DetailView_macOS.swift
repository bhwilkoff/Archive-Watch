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
    @State private var versions: [ArchiveVersions.Version] = []
    @State private var loadingVersions = false
    @State private var chosenVersionName: String?
    @State private var showGetSubtitles = false
    @State private var downloadError: String?
    @Query private var downloads: [DownloadedFilm]
    /// The live show, shared with the player surface — Detail is gone from the
    /// window by the time a player exists (§B2a), so the session holds it.
    private var studio: StudioSession { StudioSession.shared }

    /// Hand the film to the current FaceTime group, or — when there is no call —
    /// let the system's own sharing sheet place one. Either way the film starts
    /// only once a session is live, so "Watch Together" never silently degrades
    /// into ordinary solo playback (owner, 2026-09-01).
    private func startWatchTogether() {
        Task {
            let wt = WatchTogether.shared
            switch await wt.share(archiveID: item.archiveID, title: item.title, year: item.year) {
            case .started:
                router.play(item)
            case .needsCall:
                let activity = wt.activity(archiveID: item.archiveID,
                                           title: item.title, year: item.year)
                if await SharePlayStarter.present(activity) { router.play(item) }
            case .cancelled:
                break
            }
        }
    }

    /// Broadcast this film to the host's own YouTube or Twitch channel
    /// (macOS-DESIGN §B13a). The rights gate runs FIRST and its refusal is a
    /// sentence, never a greyed-out row — `StudioSession.arm` owns both.
    private func startStudio() {
        if StudioSession.shared.arm(film: item) {
            router.play(item)
        }
        // A refusal set by `arm` is drawn by the alert below; nothing else to
        // do here, and deliberately no fallback to ordinary playback — a host
        // who asked to broadcast has not asked to watch alone.
    }

    private var isFav: Bool { favorites.contains { $0.archiveID == item.archiveID } }
    private var shareURL: URL { URL(string: "https://archivewatch.org/item/\(item.archiveID)")! }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let s = item.displaySynopsis {
                    Text(s).font(.body).textSelection(.enabled)
                    if let prov = item.synopsisProvenance {
                        Text(prov).font(.caption).foregroundStyle(.secondary)
                    }
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
        .sheet(isPresented: $showGetSubtitles) {
            GetSubtitlesView(item: item, playbackChoice: Binding(
                get: { CaptionChoiceSession.byItem[item.archiveID] },
                set: { CaptionChoiceSession.byItem[item.archiveID] = $0 }))
                .frame(minWidth: 460, minHeight: 340)
        }
        // The rights refusal. NOT a disabled menu row: a host who cannot
        // broadcast this film is told which rule stopped them and what the
        // rule is (WATCH-TOGETHER §5, and the same wording every platform
        // uses via `StudioRights`).
        .alert("This film cannot be streamed",
               isPresented: Binding(get: { studio.refusal != nil },
                                    set: { if !$0 { studio.refusal = nil } })) {
            Button("OK", role: .cancel) { studio.refusal = nil }
        } message: {
            Text((studio.refusal ?? "") + "\n\n" + StudioRights.policy)
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
                // "Also known as" (Decision 100). The catalog has always
                // carried the film's primary title; showing it turns a
                // description that looked mismatched into the fact that one
                // film circulated under several names.
                if let aka = item.alsoKnownAs {
                    Text("Also known as \(aka)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
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
                // §D13 — A BUTTON SAYS WHAT IT DOES, AT EVERY WINDOW WIDTH.
                //
                // Owner, 2026-09-22: "Button text should never be truncated or
                // abbreviated … You need to figure out a native way of
                // displaying buttons on MacOS that doesn't break the functions
                // of a mac app." And, on seeing the first attempt: "We don't
                // want button wrapping. We want actual designed buttons that
                // say what they mean and perform like macOS buttons should."
                //
                // Both of those rule out something. An `HStack` COMPRESSES its
                // children, and a `Button`'s `Text` compresses by truncating,
                // so "Add to Playlist" became "Add to Pl…". A wrapping layout
                // fixes the words and ruins the design: seven large buttons
                // reflow into three ragged rows with "Share" stranded alone on
                // the last one, which is not a layout anybody chose.
                //
                // The macOS answer is neither. It is what Music, TV and Finder
                // all do: a SMALL, FIXED set of primary buttons, and everything
                // else in a native menu whose items still say their full names.
                // `ViewThatFits` picks between arrangements that were each
                // DESIGNED — it never reflows and never shrinks a label; it
                // chooses the richest bar that fits and the rest is one "More"
                // menu away. No icon-only fallback: an icon with a tooltip is
                // an abbreviation with extra steps.
                ViewThatFits(in: .horizontal) {
                    actionBar(secondary: [.playlist, .subtitles, .version, .download, .share])
                    actionBar(secondary: [.playlist, .subtitles], inMenu: [.version, .download, .share])
                    actionBar(secondary: [.playlist], inMenu: [.subtitles, .version, .download, .share])
                    actionBar(secondary: [], inMenu: [.playlist, .subtitles, .version, .download, .share])
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            Spacer()
        }
    }

    /// Open this title in Creation Studio's mark-in/out editor — the same scrubber the Add-a-Clip
    /// browser pushes to, but reachable from any title's Detail. Queue the item, then open a fresh
    /// project window; the editor's .task consumes `pendingClipItem` and presents MarkClipView.
    private var downloadRow: DownloadedFilm? {
        downloads.first { $0.archiveID == item.archiveID }
    }

    /// What the Download menu offers depends entirely on where the film is:
    /// nowhere yet (pick a copy), in flight (pause or cancel), or on disk
    /// (remove). Never all three at once.
    @ViewBuilder private var downloadMenuContents: some View {
        if let d = downloadRow {
            switch d.state {
            case .completed:
                Text(d.qualityLabel.map { "On this Mac · \($0)" } ?? "On this Mac")
                Divider()
                Button(role: .destructive) {
                    DownloadManager.shared.remove(item.archiveID)
                } label: { Label("Remove Download", systemImage: "trash") }
            case .queued, .downloading:
                Text("Downloading…")
                Button { DownloadManager.shared.pause(item.archiveID) } label: {
                    Label("Pause", systemImage: "pause")
                }
                Button(role: .destructive) {
                    DownloadManager.shared.remove(item.archiveID)
                } label: { Label("Cancel Download", systemImage: "xmark") }
            case .paused:
                Button { DownloadManager.shared.resume(item.archiveID) } label: {
                    Label("Resume Download", systemImage: "play")
                }
                Button(role: .destructive) {
                    DownloadManager.shared.remove(item.archiveID)
                } label: { Label("Cancel Download", systemImage: "xmark") }
            case .failed:
                if let why = d.errorText { Text(why) }
                Button { DownloadManager.shared.resume(item.archiveID) } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    DownloadManager.shared.remove(item.archiveID)
                } label: { Label("Remove", systemImage: "trash") }
            }
        } else if let err = downloadError {
            Text(err)
            Button("Dismiss") { downloadError = nil }
        } else if versions.isEmpty {
            // The file list could not be read; the catalog's own pick still works.
            Button { downloadError = DownloadManager.shared.start(item: item, version: nil) } label: {
                Label(loadingVersions ? "Loading copies…" : "Download the standard copy",
                      systemImage: "arrow.down.circle")
            }
        } else {
            ForEach(versions) { v in
                Button {
                    downloadError = DownloadManager.shared.start(item: item, version: v)
                } label: { Text(v.label) }
                .disabled(!OfflineLibrary.hasRoom(for: v.sizeBytes))
            }
            Divider()
            if let free = OfflineLibrary.availableBytes() {
                Text("\(OfflineLibrary.byteText(free)) free on this Mac")
            }
        }
    }

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

    // MARK: - The action bar (§D13)

    /// The things a host can do with a film, named so that a bar and a menu
    /// item can be the SAME action described the same way.
    ///
    /// One case per action, rather than two parallel lists of buttons and menu
    /// items: two lists is how "Add to Playlist" ends up called "Add to a
    /// playlist" in one of them, and how an action gets fixed in one place and
    /// not the other — the shape Decision 133 keeps finding.
    enum DetailAction: Hashable {
        case playlist, subtitles, version, download, share
    }

    /// One arrangement of the bar: `secondary` are drawn as real buttons,
    /// `inMenu` are folded into a single "More" menu.
    ///
    /// `Play` and `Favorite` are in EVERY arrangement and never move. They are
    /// the two verbs a person came for, and a control that relocates as the
    /// window resizes is one you have to find again each time.
    @ViewBuilder
    private func actionBar(secondary: [DetailAction],
                           inMenu: [DetailAction] = []) -> some View {
        HStack(spacing: 10) {
            if item.videoURLParsed != nil {
                Button { router.play(item) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(.large).fixedSize()
            }
            Button { toggleFavorite() } label: {
                Label(isFav ? "Favorited" : "Favorite",
                      systemImage: isFav ? "heart.fill" : "heart")
            }
            .controlSize(.large).fixedSize()
            .help(isFav ? "Remove from Favorites" : "Add to Favorites")

            ForEach(secondary.filter(isOffered), id: \.self) { action in
                actionControl(action)
            }

            let hidden = inMenu.filter(isOffered)
            if !hidden.isEmpty {
                Menu {
                    // THE SAME ACTIONS, STILL IN WORDS. A "More" menu that
                    // renamed or reordered its contents would make the bar and
                    // the menu two different products at two window widths.
                    ForEach(hidden, id: \.self) { action in
                        menuContents(action)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .controlSize(.large).fixedSize()
                .help("Everything else you can do with this film")
            }
        }
        // EVERY control is `.fixedSize()`, so this row is measured at the sum
        // of its childrens' ideal widths — which is exactly what lets
        // `ViewThatFits` tell "this arrangement fits" from "this arrangement
        // would have to truncate". Without it the first arrangement always
        // "fits", by squeezing.
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Whether this film offers the action at all. Asked in ONE place so the
    /// bar and the menu cannot disagree about whether something exists.
    private func isOffered(_ action: DetailAction) -> Bool {
        switch action {
        case .playlist: return true
        case .subtitles: return SubtitleFinder.shouldOffer(for: item)
        case .version, .download: return item.videoURLParsed != nil
        case .share: return true
        }
    }

    /// One action as a BAR control.
    @ViewBuilder
    private func actionControl(_ action: DetailAction) -> some View {
        switch action {
        case .playlist:
            Button { showPlaylistSheet = true } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
            .controlSize(.large).fixedSize()
        case .subtitles:
            Button { showGetSubtitles = true } label: {
                Label("Subtitles", systemImage: "captions.bubble")
            }
            .controlSize(.large).fixedSize()
            .help("Find or generate subtitles for this film")
        case .version:
            // Choose which copy plays — parity with tvOS and iOS. A Mac is
            // where someone is most likely to care about the difference
            // between transfers, and least likely to accept the app deciding.
            Menu { versionMenuContents } label: {
                Label("Version", systemImage: "rectangle.stack")
            }
            .controlSize(.large).fixedSize()
            .help("Choose which copy of this film to play")
            .task(id: item.archiveID) { await loadVersions() }
        case .download:
            // Keep it on this Mac (Decision 099). A menu rather than iOS's
            // sheet: the copies are already loaded for the Version control
            // right beside it, and a Mac has room to show them in place
            // instead of covering the film to ask.
            Menu { downloadMenuContents } label: {
                Label(downloadRow?.state == .completed ? "Downloaded" : "Download",
                      systemImage: downloadRow?.state == .completed
                          ? "arrow.down.circle.fill" : "arrow.down.circle")
            }
            .controlSize(.large).fixedSize()
            .help("Keep this film on the Mac so it plays with no internet")
        case .share:
            Menu { shareMenuContents } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .controlSize(.large).fixedSize()
        }
    }

    /// The same action as MENU CONTENT — a submenu where the bar had a menu,
    /// a plain item where the bar had a button.
    @ViewBuilder
    private func menuContents(_ action: DetailAction) -> some View {
        switch action {
        case .playlist:
            Button { showPlaylistSheet = true } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
        case .subtitles:
            Button { showGetSubtitles = true } label: {
                Label("Subtitles", systemImage: "captions.bubble")
            }
        case .version:
            Menu { versionMenuContents } label: {
                Label("Version", systemImage: "rectangle.stack")
            }
            .task(id: item.archiveID) { await loadVersions() }
        case .download:
            Menu { downloadMenuContents } label: {
                Label(downloadRow?.state == .completed ? "Downloaded" : "Download",
                      systemImage: downloadRow?.state == .completed
                          ? "arrow.down.circle.fill" : "arrow.down.circle")
            }
        case .share:
            Menu { shareMenuContents } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private var versionMenuContents: some View {
        if versions.isEmpty {
            Text(loadingVersions ? "Loading…" : "No other copies")
        } else {
            ForEach(versions) { v in
                Button {
                    ArchiveVersions.choose(v, for: item.archiveID)
                    chosenVersionName = v.name
                } label: {
                    Label(v.label, systemImage:
                        chosenVersionName == v.choiceKey ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
            Button {
                ArchiveVersions.choose(nil, for: item.archiveID)
                chosenVersionName = nil
            } label: { Label("Use the default copy", systemImage: "arrow.uturn.backward") }
        }
    }

    /// One consolidated Share menu (parity with iOS) — Callsheet + share link +
    /// archive.org, instead of three separate toolbar-ish buttons.
    @ViewBuilder
    private var shareMenuContents: some View {
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
        // Watch Together is ONE name with TWO halves (the owner's framing,
        // docs/WATCH-TOGETHER.md §1): with friends is SharePlay (Decision 098),
        // with the world is the Studio (Decision 127). A submenu rather than
        // two peer items, because the choice a host makes is "who is this
        // for", not "which feature".
        if item.videoURLParsed != nil {
            Menu {
                Button { startWatchTogether() } label: {
                    Label("With Friends…", systemImage: "shareplay")
                }
                Button { startStudio() } label: {
                    Label("With the World…", systemImage: "dot.radiowaves.left.and.right")
                }
            } label: {
                Label("Watch Together", systemImage: "shareplay")
            }
            Divider()
        }
        ShareLink(item: shareURL) { Label("Share Link…", systemImage: "square.and.arrow.up") }
        Link(destination: URL(string: item.sourceDetailsURL)!) {
            Label("View on archive.org", systemImage: "globe")
        }
    }

    private func loadVersions() async {
        chosenVersionName = ArchiveVersions.chosenName(for: item.archiveID)
        guard versions.isEmpty else { return }
        loadingVersions = true
        versions = await ArchiveVersions.list(itemID: item.archiveID)
        loadingVersions = false
    }

    private var castRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast & Crew").font(.title3).fontWeight(.semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                // TOP-ALIGNED, because the cells are not all the same height:
                // a director has a role line and a cast member may not, and
                // the default centre alignment then hangs the portraits at
                // different heights across the row (seen on the glass at 960
                // points, 2026-09-22). The circles are the thing the eye
                // tracks along, so it is the circles that must line up.
                LazyHStack(alignment: .top, spacing: 16) {
                    if let d = item.director, !d.isEmpty {
                        castBubble(name: d, role: "Director", profilePath: item.directorProfilePath, personID: nil)
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
                // §D13'S RULE REACHES PAST BUTTONS. A person's name and the
                // part they played are labels that mean something, and this
                // row was abbreviating both: "Rev. Arthur Di…", "Roger Prynne
                // a…", on the same screen where the buttons were fixed.
                //
                // `reservesSpace` is the other half — without it a one-line
                // name and a two-line name sit at different heights and the
                // row's role captions come out ragged, which is what made
                // "Giles" and "The Governor" land on different baselines.
                Text(name)
                    .font(.caption2)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .frame(width: 84)
                if let role, !role.isEmpty {
                    // THREE lines, and NOT reserving them. A part can be long
                    // — "The Girl's Father / Man on Film Screen" — and two
                    // lines still abbreviated it. The name above reserves its
                    // two so the names line up; the role does not, because a
                    // one-word part would otherwise hang a blank band under
                    // every short credit. The row is `.top` aligned, so cells
                    // of different heights are already handled.
                    Text(role)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .frame(width: 84)
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
