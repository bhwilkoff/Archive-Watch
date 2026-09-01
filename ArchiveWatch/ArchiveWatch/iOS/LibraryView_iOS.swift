#if os(iOS)
import SwiftUI
import SwiftData

// Library: Downloads, Favorites, History, Playlists and Clips — backed by
// SwiftData. A segmented picker switches sections.
//
// Everything here except Downloads is SYNCED to the Apple TV via CloudKit,
// because it records an intention. Downloads records a FILE, which exists on
// exactly one device, so it is deliberately local (iOS-DESIGN §9.7).
struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Query private var progress: [WatchProgress]
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @Query(sort: \VideoClip.createdAt, order: .reverse) private var clips: [VideoClip]
    @Query(sort: \DownloadedFilm.addedAt, order: .reverse) private var downloads: [DownloadedFilm]
    @State private var section: Section = .favorites

    // No `watched` case (owner, 2026-08-17): it listed the completed subset
    // of `history`, so a finished film appeared under both and the two
    // could disagree. Completion is a badge on the poster instead.
    //
    // Downloads leads the list: when the network is gone it is the only section
    // with anything playable in it, and the tab opens there (Decision 099).
    enum Section: String, CaseIterable, Identifiable {
        case downloads, favorites, history, playlists, clips
        var id: String { rawValue }; var title: String { rawValue.capitalized } }

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    // IPAD-DESIGN §1.2: size class, never a device check.
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            // IPAD-DESIGN §2.2a — see BrowseView for the measurement.
            .frame(maxWidth: hSize == .regular ? 560 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            switch section {
            case .downloads: downloadsList
            case .favorites: grid(store.itemsByIDs(favorites.map(\.archiveID)),
                                  empty: "No favorites yet", icon: "heart")
            case .history: historyList
            case .playlists: playlistList
            case .clips: clipsList
            }
        }
        .navigationTitle("Library")
        .id(store.dbVersion)
        .task {
            // Offline, Downloads is the only section that can play anything, so
            // the tab opens there rather than on a grid of unreachable posters.
            if !NetworkMonitor.shared.isOnline, !downloads.isEmpty { section = .downloads }
        }
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
        }
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
                    NavigationLink {
                        grid(store.itemsByIDs(pl.archiveIDs), empty: "Empty playlist", icon: "rectangle.stack")
                            .navigationTitle(pl.name)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(pl.name).font(.headline)
                            Text("\(pl.archiveIDs.count) titles").font(.caption).foregroundStyle(.secondary)
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
        }
    }

    // Clips made in Clip Studio (Decision 033). Share the rendered file if it's
    // still cached; tap to revisit the source film. Delete removes the cached
    // render too. If a render was evicted under disk pressure, the clip stays
    // listed (re-create from its source) — the definition is the source of truth.
    @ViewBuilder private var clipsList: some View {
        if clips.isEmpty {
            ContentUnavailableView("No clips yet", systemImage: "scissors",
                description: Text("Make clips and GIFs from a film's detail page (the Create button)."))
        } else {
            List {
                ForEach(clips) { clip in
                    let fileURL = clip.renderFilename.map { ClipExporter.renderURL(filename: $0) }
                    let exists = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clip.caption.isEmpty ? clip.sourceTitle : clip.caption)
                                .font(.headline).lineLimit(1)
                            Text("\(clip.format.uppercased()) · \(String(format: "%.1fs", clip.durationSeconds))"
                                 + (exists ? "" : " · render cleared"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if exists, let fileURL {
                            ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                                .labelStyle(.iconOnly)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if let item = store.item(clip.sourceArchiveID) { router.openDetail(item) } }
                }
                .onDelete { offsets in
                    for i in offsets {
                        let clip = clips[i]
                        if let f = clip.renderFilename {
                            try? FileManager.default.removeItem(at: ClipExporter.renderURL(filename: f))
                        }
                        ctx.delete(clip)
                    }
                }
            }
        }
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
