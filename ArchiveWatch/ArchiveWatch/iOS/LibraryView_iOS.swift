#if os(iOS)
import SwiftUI
import SwiftData

// Library: Downloads, Favorites, History, Playlists and Clips — backed by
// SwiftData. The tab is a LIST OF PLACES (iOS-DESIGN §2.7): each row opens one
// place, with its count, and Recently Watched sits beneath them.
//
// Everything here except Downloads is SYNCED to the Apple TV via CloudKit,
// because it records an intention. Downloads records a FILE, which exists on
// exactly one device, so it is deliberately local (iOS-DESIGN §9.7).
/// One Library place, pushed from the list (iOS-DESIGN §2.7).
struct LibraryPlaceRoute: Hashable { let place: LibraryView.Section }

struct LibraryView: View {
    /// nil = the list of places; a value = that one place, pushed.
    var place: Section? = nil
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Query private var progress: [WatchProgress]
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @Query(sort: \VideoClip.createdAt, order: .reverse) private var clips: [VideoClip]
    @Query(sort: \DownloadedFilm.addedAt, order: .reverse) private var downloads: [DownloadedFilm]

    // No `watched` case (owner, 2026-08-17): it listed the completed subset
    // of `history`, so a finished film appeared under both and the two
    // could disagree. Completion is a badge on the poster instead.
    //
    // Downloads leads the list: when the network is gone it is the only place
    // with anything playable in it, and the tab opens there (Decision 099).
    enum Section: String, CaseIterable, Identifiable {
        case downloads, favorites, history, playlists, clips
        var id: String { rawValue }
        /// "Downloads" again: it was "Offline" only because five SEGMENTS
        /// split a 390pt row equally and "Downloads" truncated; a list row
        /// has the width (iOS-DESIGN §2.7).
        var title: String { self == .downloads ? "Downloads" : rawValue.capitalized }
        var icon: String {
            switch self {
            case .downloads: "arrow.down.circle"
            case .favorites: "heart"
            case .history: "clock.arrow.circlepath"
            case .playlists: "rectangle.stack"
            case .clips: "scissors"
            }
        }
    }

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        Group {
            if let place {
                content(place)
                    .navigationTitle(place.title)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                places
                    .navigationTitle("Library")
                    // JOIN A ROOM (§11.9): a toolbar item, not a place — it
                    // opens a room, it is not a collection of yours.
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { JoinRoomButton_iOS() }
                    }
                    .task {
                        // Offline, Downloads is the only place that can play
                        // anything, so the tab opens there (Decision 099).
                        if !NetworkMonitor.shared.isOnline, !downloads.isEmpty,
                           router.libraryPath.isEmpty {
                            router.push(LibraryPlaceRoute(place: .downloads))
                        }
                    }
            }
        }
        .id(store.dbVersion)
    }

    @ViewBuilder private func content(_ place: Section) -> some View {
        switch place {
        case .downloads: downloadsList
        case .favorites: grid(store.itemsByIDs(favorites.map(\.archiveID)),
                              empty: "No favorites yet", icon: "heart")
        case .history: historyList
        case .playlists: playlistList
        case .clips: clipsList
        }
    }

    // MARK: - The list of places (iOS-DESIGN §2.7)
    //
    // Measured on the iPhone 12: five segments were the width limit of a 390pt
    // row ("Downloads" had already been shortened to "Offline" to fit), the
    // tab opened on an empty Favorites grid, and nothing said what the other
    // four held. A list of places names each one with its count, so an empty
    // one is visible as empty without being the first thing you see — the
    // shape of Apple Music's and the Apple TV app's libraries.

    private func count(_ place: Section) -> Int {
        switch place {
        case .downloads: downloads.count
        case .favorites: favorites.count
        case .history: progress.count
        case .playlists: playlists.count
        case .clips: clips.count
        }
    }

    private func countLabel(_ place: Section) -> String {
        let n = count(place)
        switch place {
        case .downloads: return n == 0 ? "None" : "\(n) \(n == 1 ? "film" : "films")"
        case .playlists: return n == 0 ? "None" : "\(n)"
        case .clips: return n == 0 ? "None" : "\(n)"
        default: return n == 0 ? "None" : "\(n)"
        }
    }

    private var recent: [Catalog.Item] {
        let ids = progress.sorted { $0.lastWatchedAt > $1.lastWatchedAt }.prefix(12).map(\.archiveID)
        return store.itemsByIDs(Array(ids))
    }

    private var places: some View {
        List {
            SwiftUI.Section {
                ForEach(Section.allCases) { place in
                    Button { router.push(LibraryPlaceRoute(place: place)) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: place.icon)
                                .font(.title3)
                                .foregroundStyle(Brand.primary)
                                .frame(minWidth: 30)
                            // Name and count side by side while they fit; at
                            // the accessibility sizes "Downloads" broke in two,
                            // so the count moves under the name.
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text(place.title).font(.body).foregroundStyle(.primary)
                                        .fixedSize()
                                    Spacer(minLength: 8)
                                    Text(countLabel(place)).font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary).fixedSize()
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.title).font(.body).foregroundStyle(.primary)
                                    Text(countLabel(place)).font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(place.title), \(countLabel(place))")
                }
            }
            if !recent.isEmpty {
                SwiftUI.Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(recent) { item in
                                Button { router.openDetail(item) } label: {
                                    PosterTile(item: item, width: 110)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Recently Watched")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Downloads (Decision 099)

    @ViewBuilder private var downloadsList: some View {
        if downloads.isEmpty {
            ContentUnavailableView(
                "No downloads yet", systemImage: "arrow.down.circle",
                description: Text("Download a film from its page to watch it with no "
                                  + "internet — on a plane, underground, anywhere."))
        } else {
            List {
                ForEach(downloads) { d in
                    Button {
                        if let item = store.item(d.archiveID) { router.openDetail(item) }
                    } label: {
                        HStack(spacing: 12) {
                            DownloadThumb(archiveID: d.archiveID, remote: d.posterURLString)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(d.title).font(.headline).lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text(downloadLine(d)).font(.caption)
                                    .foregroundStyle(d.state == .failed ? .orange : .secondary)
                                if d.state.isActive {
                                    ProgressView(value: liveFraction(d)).tint(.orange)
                                }
                            }
                            Spacer(minLength: 0)
                            if d.state == .completed {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Available offline")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    // §4.3: destructive verbs are swipe actions. Pause/resume
                    // rides along because an interrupted download is the common
                    // case on the network this feature exists for.
                    .swipeActions(edge: .leading) {
                        if d.state.isActive {
                            Button { DownloadManager.shared.pause(d.archiveID) } label: {
                                Label("Pause", systemImage: "pause")
                            }.tint(.gray)
                        } else if d.state == .paused || d.state == .failed {
                            Button { DownloadManager.shared.resume(d.archiveID) } label: {
                                Label("Resume", systemImage: "play")
                            }.tint(.orange)
                        }
                    }
                }
                .onDelete { offsets in
                    // A bare removal, and no tombstone: DownloadedFilm is
                    // device-local and never synced (iOS-DESIGN §9.7), so
                    // §9.4's SyncNudge rule does not apply and must not be
                    // copied here by habit.
                    for i in offsets { DownloadManager.shared.remove(downloads[i].archiveID) }
                }
            }
            .listStyle(.plain)
            .readableListWidth()
        }
    }

    private func liveFraction(_ d: DownloadedFilm) -> Double {
        DownloadManager.shared.progress(for: d.archiveID)?.fraction ?? d.fraction
    }

    private func downloadLine(_ d: DownloadedFilm) -> String {
        switch d.state {
        case .completed:
            var parts = [d.qualityLabel
                         ?? OfflineLibrary.byteText(OfflineLibrary.bytesUsed(by: d.archiveID))]
            if d.hasSubtitles { parts.append("subtitles") }
            return parts.joined(separator: " · ")
        case .queued:
            return "Waiting to start"
        case .downloading:
            let p = DownloadManager.shared.progress(for: d.archiveID)
            let received = p?.received ?? d.receivedBytes
            let expected = p?.expected ?? d.expectedBytes
            guard expected > 0 else { return "Downloading…" }
            return "Downloading — \(OfflineLibrary.byteText(received)) of "
                 + "\(OfflineLibrary.byteText(expected))"
        case .paused:
            return "Paused — swipe right to resume"
        case .failed:
            return d.errorText ?? "Download failed — swipe right to try again"
        }
    }

    @ViewBuilder private func grid(_ items: [Catalog.Item], empty: String, icon: String) -> some View {
        if items.isEmpty {
            ContentUnavailableView(empty, systemImage: icon)
        } else {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 18) {
                    ForEach(items) { item in
                        Button { router.openDetail(item) } label: { PosterTile(item: item) }
                            .buttonStyle(.plain)
                    }
                }.padding()
            }
        }
    }

    // The complete watch record (Decision 078): every title ever played on any
    // synced device — finished or not — most recent first, with when and how far.
    @ViewBuilder private var historyList: some View {
        let rows = progress.sorted { $0.lastWatchedAt > $1.lastWatchedAt }
        if rows.isEmpty {
            ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath",
                description: Text("Everything you watch, on any device, shows up here."))
        } else {
            List {
                ForEach(rows, id: \.archiveID) { w in
                    if let item = store.item(w.archiveID) {
                        Button { router.openDetail(item) } label: {
                            HStack(spacing: 12) {
                                PosterThumb(item: item)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.headline).lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text(historyLine(w)).font(.caption)
                                        .foregroundStyle(.secondary)
                                    if w.positionSeconds > 10, !w.isComplete, w.durationSeconds > 0 {
                                        ProgressView(value: w.fraction).tint(.orange)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { offsets in
                    for i in offsets {
                        let w = rows[i]
                        SyncNudge.recordDeletion("wp:\(w.archiveID)", in: ctx)
                        ctx.delete(w)
                    }
                }
            }
            .listStyle(.plain)
            .readableListWidth()
        }
    }

    /// Films dropped on a playlist row: only links naming a film we keep, each
    /// added once; anything else is refused (IPAD-DESIGN §12.2).
    private func add(_ urls: [URL], to pl: Playlist) -> Bool {
        let ids = urls.compactMap(FilmTransfer.archiveID(from:))
            .filter { store.item($0) != nil && !pl.archiveIDs.contains($0) }
        guard !ids.isEmpty else { return false }
        pl.archiveIDs.append(contentsOf: ids)
        pl.touch()
        try? ctx.save()
        SyncNudge.nudge(ctx)
        return true
    }

    private func historyLine(_ w: WatchProgress) -> String {
        let date = w.lastWatchedAt.formatted(date: .abbreviated, time: .omitted)
        var parts: [String] = []
        if w.isWatched { parts.append("Watched \(date)") }
        else if w.positionSeconds > 10, w.durationSeconds > 0 {
            parts.append("\(Int(w.fraction * 100))% · \(date)")
        } else { parts.append(date) }
        if let n = w.playCount, n > 1 { parts.append("\(n) sessions") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var playlistList: some View {
        if playlists.isEmpty {
            ContentUnavailableView("No playlists yet", systemImage: "rectangle.stack",
                description: Text("Add titles to a playlist from their detail page."))
        } else {
            List {
                ForEach(playlists) { pl in
                    let shareURL = PlaylistShare.url(name: pl.name, archiveIDs: pl.archiveIDs)
                    NavigationLink {
                        grid(store.itemsByIDs(pl.archiveIDs), empty: "Empty playlist", icon: "rectangle.stack")
                            .navigationTitle(pl.name)
                            // SHARE lives where Detail puts it (iOS-DESIGN §3.5): a
                            // visible toolbar icon. It was ONLY a leading swipe on the
                            // row until 1.42.119, and the owner could not find it —
                            // §4.3 reserves swipes for destructive verbs for that reason.
                            .toolbar {
                                if let shareURL {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        ShareLink(item: shareURL) {
                                            Image(systemName: "square.and.arrow.up")
                                        }
                                    }
                                }
                            }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(pl.name).font(.headline)
                            Text("\(pl.archiveIDs.count) titles").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    // IPAD-DESIGN §12.2: a film dropped on a playlist joins it.
                    .dropDestination(for: URL.self) { urls, _ in add(urls, to: pl) }
                    // The playlist rides inside the link (PlaylistShare), so the
                    // person who receives it needs no account and we host nothing.
                    .contextMenu {
                        if let shareURL {
                            ShareLink(item: shareURL) { Label("Share Playlist", systemImage: "square.and.arrow.up") }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if let shareURL {
                            ShareLink(item: shareURL) { Label("Share", systemImage: "square.and.arrow.up") }
                                .tint(.accentColor)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets {
                        let pl = playlists[i]
                        ctx.delete(pl)
                        SyncNudge.recordDeletion("pl:\(pl.id)", in: ctx)
                    }
                }
            }
            .readableListWidth()
        }
    }

    // Clips made in Clip Studio (Decision 033). Share the rendered file if it's
    // still cached; tap to revisit the source film. Delete removes the cached
    // render too. If a render was evicted under disk pressure, the clip stays
    // listed (re-create from its source) — the definition is the source of truth.
    @ViewBuilder private var clipsList: some View {
        if clips.isEmpty {
            ContentUnavailableView("No clips yet", systemImage: "scissors",
                description: Text("Make one with Create a Clip, in a film's More menu."))
        } else {
            List {
                ForEach(clips) { clip in
                    let fileURL = clip.renderFilename.map { ClipExporter.renderURL(filename: $0) }
                    let exists = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                    // A real button, not a tap gesture: it answers the
                    // pointer and the keyboard (IPAD-DESIGN §11.1).
                    HStack {
                        Button {
                            if let item = store.item(clip.sourceArchiveID) { router.openDetail(item) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clip.caption.isEmpty ? clip.sourceTitle : clip.caption)
                                        .font(.headline).lineLimit(2)
                                    Text("\(clip.format.uppercased()) · \(String(format: "%.1fs", clip.durationSeconds))"
                                         + (exists ? "" : " · render cleared"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        if exists, let fileURL {
                            ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                                .labelStyle(.iconOnly)
                        }
                    }
                    .contextMenu {
                        if let item = store.item(clip.sourceArchiveID) {
                            Button { router.openDetail(item) } label: {
                                Label("Open Film", systemImage: "film")
                            }
                        }
                        if exists, let fileURL {
                            ShareLink(item: fileURL) { Label("Share…", systemImage: "square.and.arrow.up") }
                        }
                        Button(role: .destructive) { delete(clip) } label: {
                            Label("Delete Clip", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { delete(clips[i]) }
                }
            }
            .readableListWidth()
        }
    }

    private func delete(_ clip: VideoClip) {
        if let f = clip.renderFilename {
            try? FileManager.default.removeItem(at: ClipExporter.renderURL(filename: f))
        }
        ctx.delete(clip)
    }
}

// Poster for a downloaded row. Prefers the copy on disk — the whole point of
// the section is that it renders with no network, and a remote AsyncImage would
// leave a wall of grey rectangles at 30,000 feet.
private struct DownloadThumb: View {
    let archiveID: String
    let remote: String?
    var body: some View {
        Group {
            if let local = OfflineLibrary.posterURL(for: archiveID),
               let data = try? Data(contentsOf: local),
               let img = UIImage(data: data) {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
            } else if let r = remote, let url = URL(string: r) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 44, height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// Small poster thumbnail for list rows (Library History).
private struct PosterThumb: View {
    let item: Catalog.Item
    var body: some View {
        AsyncImage(url: item.posterURLParsed) { phase in
            if let img = phase.image {
                img.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 44, height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#endif
