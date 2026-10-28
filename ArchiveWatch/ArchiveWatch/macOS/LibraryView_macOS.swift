#if os(macOS)
import SwiftUI
import SwiftData

// Library = the user's state: Continue Watching, Favorites, Playlists — synced
// through the shared CloudKit container — and Downloads, which is NOT synced
// because it names a file on this Mac (iOS-DESIGN §9.7, Decision 099).
// archiveIDs resolve to items via the shared store.

/// A saved id and the card it resolves to. A merged-away copy resolves to its
/// survivor (Decision 085), so the card's id is not always the saved one, and a
/// removal must use the saved one.
struct LibraryEntry {
    let storedID: String
    let item: Catalog.Item
}

/// The shelves the Library draws, resolved once per change rather than every
/// redraw.
private struct LibraryShelves {
    var continueWatching: [LibraryEntry] = []
    var favorites: [LibraryEntry] = []
    var history: [LibraryEntry] = []
    var playlists: [String: [LibraryEntry]] = [:]
}

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Query(sort: \Playlist.modifiedAt, order: .reverse) private var allPlaylists: [Playlist]
    /// The viewer's own order, the same on every device (Playlist.inMyOrder).
    private var playlists: [Playlist] { Playlist.inMyOrder(allPlaylists) }
    @State private var renaming: Playlist?
    @State private var showRename = false   // the target outlives the dialog (iOS LibraryView)
    @State private var newName = ""
    @Query private var downloads: [DownloadedFilm]
    @Environment(\.modelContext) private var ctx
    /// The playlist a "Delete Playlist…" is asking about.
    @State private var deleting: Playlist?
    @State private var showDelete = false
    @State private var shelves = LibraryShelves()

    /// Home's rule (HomeView_macOS.continueIDs), so the two rows agree.
    private var continueIDs: [String] {
        progress.filter { !$0.isComplete && $0.positionSeconds > 2 }.map(\.archiveID)
    }

    private var libraryIsEmpty: Bool {
        progress.isEmpty && favorites.isEmpty && playlists.isEmpty && downloads.isEmpty
    }

    /// Everything the shelves are computed from; a change re-resolves them.
    private var shelfKey: String {
        [String(store.dbVersion),
         continueIDs.joined(separator: ","),
         favorites.map(\.archiveID).joined(separator: ","),
         progress.map(\.archiveID).joined(separator: ","),
         playlists.map { $0.id + ":" + $0.archiveIDs.joined(separator: ",") }.joined(separator: ";")]
            .joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !downloads.isEmpty { LibraryDownloadsSection() }
                shelf("Continue Watching", shelves.continueWatching, progress: true)

                // Kept on screen when empty, so a film can still be dropped on it.
                shelf("Favorites", shelves.favorites,
                      emptyText: libraryIsEmpty ? nil
                          : favorites.isEmpty ? "No favorites yet."
                          : "These favorites are no longer in the catalog.")
                    // §B15: a film dropped on Favorites is favorited.
                    .dropDestination(for: URL.self) { urls, _ in _ = addFavorites(urls) }

                ForEach(playlists) { pl in
                    let url = PlaylistShare.url(name: pl.name, archiveIDs: pl.archiveIDs)
                    let entries = shelves.playlists[pl.id] ?? []
                    // SHARE. The playlist travels inside the link (PlaylistShare)
                    // — no account for whoever receives it and nothing hosted by
                    // us. A visible icon beside the shelf title, because a verb
                    // that exists only under right-click cannot be found (the
                    // owner could not find the iOS swipe; same defect here).
                    ShelfRow(title: pl.name, items: entries.map(\.item),
                             storedIDs: Self.storedIDs(entries),
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
                            Button("Rename…") { newName = pl.name; renaming = pl; showRename = true }
                            // My Order, arranged where the shelves are (2026-10-27).
                            Button("Move Up") { move(pl, by: -1) }
                                .disabled(playlists.first?.id == pl.id)
                            Button("Move Down") { move(pl, by: 1) }
                                .disabled(playlists.last?.id == pl.id)
                            // The iPhone could delete a playlist and the Mac could not
                            // (Mac loop, 2026-09-27). Asked first: it syncs everywhere.
                            Divider()
                            Button("Delete Playlist…", role: .destructive) { deleting = pl; showDelete = true }
                        }
                }

                // ONE watch surface (owner, 2026-08-17). A "Watched" shelf sat
                // above this holding the completed SUBSET of the same records,
                // so a finished film appeared in both and the rows could
                // disagree. Completion is a badge on the tile now.
                shelf("History", shelves.history)

                if libraryIsEmpty {
                    ContentUnavailableView("Your library is empty",
                                           systemImage: "books.vertical",
                                           description: Text("Favorite a film or start watching to see it here."))
                        .padding(.top, 80)
                }
            }
            .padding(24)
        }
        .navigationTitle("Library")
        .task(id: shelfKey) { resolveShelves() }
        .confirmationDialog("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
                            isPresented: $showDelete,
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
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let pl = renaming, !name.isEmpty, name != pl.name {
                    pl.name = name; pl.touch(); try? ctx.save(); SyncNudge.nudge(ctx)
                }
                renaming = nil
            }
        }
    }

    private func shelf(_ title: String, _ entries: [LibraryEntry], progress showsProgress: Bool = false,
                       emptyText: String? = nil) -> some View {
        let byStored = showsProgress
            ? Dictionary(progress.map { ($0.archiveID, $0) }, uniquingKeysWith: { a, _ in a }) : [:]
        var progressByID: [String: WatchProgress] = [:]
        for e in entries { if let p = byStored[e.storedID] { progressByID[e.item.archiveID] = p } }
        return ShelfRow(title: title, items: entries.map(\.item), progressByID: progressByID,
                        storedIDs: Self.storedIDs(entries), emptyText: emptyText)
    }

    private static func storedIDs(_ entries: [LibraryEntry]) -> [String: String] {
        Dictionary(entries.filter { $0.storedID != $0.item.archiveID }
            .map { ($0.item.archiveID, $0.storedID) }, uniquingKeysWith: { a, _ in a })
    }

    private func resolveShelves() {
        var next = LibraryShelves()
        next.continueWatching = resolve(continueIDs)
        next.favorites = resolve(favorites.map(\.archiveID))
        next.history = resolve(progress.map(\.archiveID))
        for pl in playlists { next.playlists[pl.id] = resolve(pl.archiveIDs) }
        shelves = next
    }

    /// Saved ids paired with the cards they resolve to, in saved order. One
    /// batch query; only an id that is not a card's own (a merged-away copy)
    /// is resolved on its own.
    private func resolve(_ ids: [String]) -> [LibraryEntry] {
        guard !ids.isEmpty else { return [] }
        let direct = Dictionary(store.itemsByIDs(ids).map { ($0.archiveID, $0) },
                                uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return ids.compactMap { id -> LibraryEntry? in
            guard let item = direct[id] ?? store.itemsByIDs([id]).first,
                  seen.insert(item.archiveID).inserted else { return nil }
            return LibraryEntry(storedID: id, item: item)
        }
    }

    /// Pull first: an order built from a stale copy of the lists would push
    /// over a rename or a move made on another device a moment ago.
    private func move(_ pl: Playlist, by step: Int) {
        let targetID = pl.id
        Task {
            await CloudKitSyncService.shared.sync(ctx)
            var ordered = Playlist.inMyOrder((try? ctx.fetch(FetchDescriptor<Playlist>())) ?? [])
            guard let i = ordered.firstIndex(where: { $0.id == targetID }),
                  ordered.indices.contains(i + step) else { return }
            ordered.swapAt(i, i + step)
            Playlist.arrange(ordered)
            try? ctx.save()
            SyncNudge.nudge(ctx)
        }
    }

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
}

// MARK: - Downloads (Decision 099)

/// Rows, not a poster shelf: a download has a state and a size, and a shelf
/// of artwork can show neither. Its own view, so a transfer's progress
/// redraws these rows and not every shelf in the Library.
private struct LibraryDownloadsSection: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Query(sort: \DownloadedFilm.addedAt, order: .reverse) private var downloads: [DownloadedFilm]

    var body: some View {
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
