#if os(iOS)
import SwiftUI
import SwiftData

// Library: Favorites, Watched, and Playlists — backed by SwiftData (synced to the
// Apple TV via CloudKit). A segmented picker switches sections; each is a grid.
struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Query private var progress: [WatchProgress]
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @Query(sort: \VideoClip.createdAt, order: .reverse) private var clips: [VideoClip]
    @State private var section: Section = .favorites

    enum Section: String, CaseIterable, Identifiable { case favorites, watched, playlists, clips
        var id: String { rawValue }; var title: String { rawValue.capitalized } }

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).padding()

            switch section {
            case .favorites: grid(store.itemsByIDs(favorites.map(\.archiveID)),
                                  empty: "No favorites yet", icon: "heart")
            case .watched: grid(store.itemsByIDs(progress.filter(\.isComplete).map(\.archiveID)),
                                empty: "Nothing watched yet", icon: "checkmark.circle")
            case .playlists: playlistList
            case .clips: clipsList
            }
        }
        .navigationTitle("Library")
        .id(store.dbVersion)
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

#endif
