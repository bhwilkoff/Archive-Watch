#if os(macOS)
import SwiftUI
import SwiftData

// Library = the user's state: Continue Watching, Favorites, Playlists — synced
// through the shared CloudKit container — and Downloads, which is NOT synced
// because it names a file on this Mac (iOS-DESIGN §9.7, Decision 099).
// archiveIDs resolve to items via the shared store.

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Query(sort: \Playlist.modifiedAt, order: .reverse) private var playlists: [Playlist]
    @Query(sort: \DownloadedFilm.addedAt, order: .reverse) private var downloads: [DownloadedFilm]
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var ctx
    /// The playlist a "Delete Playlist…" is asking about.
    @State private var deleting: Playlist?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !downloads.isEmpty { downloadsSection }
                let continueItems = store.itemsByIDs(progress.filter { !$0.isComplete }.map(\.archiveID))
                ShelfRow(title: "Continue Watching", items: continueItems)

                let favItems = store.itemsByIDs(favorites.map(\.archiveID))
                ShelfRow(title: "Favorites", items: favItems)
                    // §B15: a film dropped on Favorites is favorited.
                    .dropDestination(for: URL.self) { urls, _ in _ = addFavorites(urls) }

                ForEach(playlists) { pl in
                    let url = PlaylistShare.url(name: pl.name, archiveIDs: pl.archiveIDs)
                    // SHARE. The playlist travels inside the link (PlaylistShare)
                    // — no account for whoever receives it and nothing hosted by
                    // us. A visible icon beside the shelf title, because a verb
                    // that exists only under right-click cannot be found (the
                    // owner could not find the iOS swipe; same defect here).
                    ShelfRow(title: pl.name, items: store.itemsByIDs(pl.archiveIDs),
                             emptyText: "Empty playlist") {
                        if let url {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.borderless)
                                .help("Share this playlist as a link")
                                .accessibilityLabel("Share \(pl.name)")
                        }
                    }
                        // §B15: a film dropped on a playlist joins it.
                        .dropDestination(for: URL.self) { urls, _ in _ = add(urls, to: pl) }
                        .contextMenu {
                            if let url {
                                ShareLink(item: url) {
                                    Label("Share Playlist", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                } label: { Label("Copy Link", systemImage: "link") }
                            }
                            // The iPhone could delete a playlist and the Mac could not
                            // (Mac loop, 2026-09-27). Asked first: it syncs everywhere.
                            Divider()
                            Button("Delete Playlist…", role: .destructive) { deleting = pl }
                        }
                }

                // ONE watch surface (owner, 2026-08-17). A "Watched" shelf sat
                // above this holding the completed SUBSET of the same records,
                // so a finished film appeared in both and the rows could
                // disagree. Completion is a badge on the tile now.
                let historyItems = store.itemsByIDs(progress.map(\.archiveID))
                ShelfRow(title: "History", items: historyItems)

                if continueItems.isEmpty && favItems.isEmpty && playlists.isEmpty
                    && downloads.isEmpty {
                    ContentUnavailableView("Your library is empty",
                                           systemImage: "books.vertical",
                                           description: Text("Favorite a film or start watching to see it here."))
                        .padding(.top, 80)
                }
            }
            .padding(24)
        }
        .navigationTitle("Library")
        .confirmationDialog("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                if let pl = deleting {
                    ctx.delete(pl)
                    SyncNudge.recordDeletion("pl:\(pl.id)", in: ctx)   // as the iPhone does, so it stays deleted
                }
                deleting = nil
            }
        } message: {
            Text("It is removed from your other devices too.")
        }
    }

    // MARK: - Downloads (Decision 099)

    /// Rows, not a poster shelf: a download has a state and a size, and a shelf
    /// of artwork can show neither. Kept in the same ScrollView as the shelves
    /// rather than a List, so the page stays one scrolling surface.
    private func addFavorites(_ urls: [URL]) -> Bool {
        let have = Set(favorites.map(\.archiveID))
        let ids = urls.compactMap(FilmTransfer.archiveID(from:))
            .filter { store.item($0) != nil && !have.contains($0) }
        guard !ids.isEmpty else { return false }
        for id in ids { ctx.insert(Favorite(archiveID: id)) }
        try? ctx.save()
        return true
    }

    private func add(_ urls: [URL], to pl: Playlist) -> Bool {
        let ids = urls.compactMap(FilmTransfer.archiveID(from:))
            .filter { store.item($0) != nil && !pl.archiveIDs.contains($0) }
        guard !ids.isEmpty else { return false }
        pl.archiveIDs.append(contentsOf: ids)
        pl.touch()
        try? ctx.save()
        return true
    }

    @ViewBuilder private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Downloads").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("\(downloads.count) on this Mac · "
                     + OfflineLibrary.byteText(OfflineLibrary.bytesUsed()))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(downloads) { d in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.title).font(.headline)
                        Text(line(for: d)).font(.caption)
                            .foregroundStyle(d.state == .failed ? .orange : .secondary)
                        if d.state.isActive {
                            ProgressView(value: DownloadManager.shared
                                .progress(for: d.archiveID)?.fraction ?? d.fraction)
                                .frame(maxWidth: 320)
                        }
                    }
                    Spacer(minLength: 12)
                    if d.state.isActive {
                        Button("Pause") { DownloadManager.shared.pause(d.archiveID) }
                    } else if d.state == .paused || d.state == .failed {
                        Button("Resume") { DownloadManager.shared.resume(d.archiveID) }
                    } else if let item = store.item(d.archiveID) {
                        Button("Play") { router.play(item) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button {
                        DownloadManager.shared.remove(d.archiveID)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Remove this download from the Mac")
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private func line(for d: DownloadedFilm) -> String {
        switch d.state {
        case .completed:
            var parts = [d.qualityLabel
                         ?? OfflineLibrary.byteText(OfflineLibrary.bytesUsed(by: d.archiveID))]
            if d.hasSubtitles { parts.append("subtitles") }
            parts.append("plays offline")
            return parts.joined(separator: " · ")
        case .queued:      return "Waiting to start"
        case .downloading:
            let p = DownloadManager.shared.progress(for: d.archiveID)
            let received = p?.received ?? d.receivedBytes
            let expected = p?.expected ?? d.expectedBytes
            guard expected > 0 else { return "Downloading…" }
            return "Downloading — \(OfflineLibrary.byteText(received)) of "
                 + "\(OfflineLibrary.byteText(expected))"
        case .paused:      return "Paused"
        case .failed:      return d.errorText ?? "Download failed"
        }
    }
}
#endif
