#if os(iOS)
import SwiftUI
import SwiftData

// One playlist, edited where it is seen (iOS-DESIGN §4.3a). A viewer,
// 2026-10-23: "I can't delete movies that I added to my lists ... And I can't
// alphabetically sort or selectively rearrange my vast number of lists, or the
// videos inside them." Before this the contents were a bare poster grid with
// no edit path, and a film left a list only by un-ticking it on its own page.
//
//  • Long-press a poster: Remove from Playlist (the tvOS verb, iOS idiom).
//  • The title menu: Rename. The toolbar menu: Sort, and Delete Playlist.
//  • Edit: the films as rows, to drag into My Order or swipe away.
struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var sort: PlaylistSort
    @State private var editMode: EditMode = .inactive
    @State private var confirmDelete = false
    @State private var lastName: String
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    init(playlist: Playlist) {
        self.playlist = playlist
        _sort = State(initialValue: PlaylistSort.remembered(PlaylistSort.contentsKey(playlist.id)))
        _lastName = State(initialValue: playlist.name)
    }

    /// The films this list names that the catalog still serves, in My Order.
    private var films: [Catalog.Item] { store.itemsByIDs(playlist.archiveIDs) }

    private var shown: [Catalog.Item] {
        switch sort {
        case .myOrder: films
        case .alphabetical:
            films.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .reverseAlphabetical:
            films.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .newest: films.sorted { ($0.year ?? Int.min) > ($1.year ?? Int.min) }
        case .oldest: films.sorted { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        }
    }

    private var shareURL: URL? { PlaylistShare.url(name: playlist.name, archiveIDs: playlist.archiveIDs) }

    var body: some View {
        Group {
            if films.isEmpty {
                ContentUnavailableView("Empty playlist", systemImage: "rectangle.stack")
            } else if editMode.isEditing {
                arrangeList
            } else {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(shown) { item in
                            Button { router.openDetail(item) } label: { PosterTile(item: item) }
                                .buttonStyle(.plain)
                        }
                    }.padding()
                }
                .environment(\.removeFromPlaylist, remove)
            }
        }
        .navigationTitle($playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu { RenameButton() }
        .toolbar {
            // SHARE stays a visible icon (iOS-DESIGN §3.5): swipe- or menu-only,
            // the owner could not find it (1.42.119).
            if let shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareURL) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
            if !films.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !editMode.isEditing {
                        Picker("Sort", selection: $sort) {
                            ForEach(PlaylistSort.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    RenameButton()
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete Playlist…", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: sort == .myOrder ? "ellipsis.circle" : "ellipsis.circle.fill")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .confirmationDialog("Delete “\(playlist.name)”?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) { deletePlaylist() }
        } message: {
            Text("It is removed from your other devices too.")
        }
        // Arranging is My Order by definition: the rows show the order being made.
        .onChange(of: editMode) { if editMode.isEditing { sort = .myOrder } }
        .onChange(of: sort) { sort.remember(PlaylistSort.contentsKey(playlist.id)) }
        .onChange(of: playlist.name) { rename() }
    }

    private var arrangeList: some View {
        List {
            ForEach(films) { item in
                HStack(spacing: 12) {
                    PosterThumb(item: item)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.headline).lineLimit(2)
                        if let y = item.year { Text(verbatim: String(y)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .onMove(perform: move)
            .onDelete { offsets in
                let ids = offsets.map { films[$0].archiveID }
                ids.forEach(remove)
            }
        }
        .listStyle(.plain)
        .readableListWidth()
    }

    private func save() {
        playlist.touch()
        try? ctx.save()
        SyncNudge.nudge(ctx)
    }

    private func remove(_ archiveID: String) {
        playlist.archiveIDs.removeAll { $0 == archiveID }
        save()
    }

    /// A move among the films shown. A film the catalog no longer serves is
    /// not shown, so it cannot be placed; it keeps its place after the rest.
    private func move(from: IndexSet, to: Int) {
        var ids = films.map(\.archiveID)
        ids.move(fromOffsets: from, toOffset: to)
        let unseen = playlist.archiveIDs.filter { !Set(ids).contains($0) }
        playlist.archiveIDs = ids + unseen
        save()
    }

    /// A name is the viewer's own words; an empty one is not a name.
    private func rename() {
        let name = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { playlist.name = lastName; return }
        guard name != lastName else { return }
        if name != playlist.name { playlist.name = name }
        lastName = name
        save()
    }

    private func deletePlaylist() {
        let id = playlist.id
        ctx.delete(playlist)
        SyncNudge.recordDeletion("pl:\(id)", in: ctx)
        dismiss()
    }
}

extension EnvironmentValues {
    /// Set by a playlist's grid: the film context menu then offers
    /// Remove from Playlist (IPadPlaces_iOS.swift, FilmContextMenu).
    @Entry var removeFromPlaylist: ((String) -> Void)? = nil
}
#endif
