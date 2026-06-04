import SwiftUI
import SwiftData

// #12 playlists / custom collections (tvOS-DESIGN §10.1). These views own the
// @Query<Playlist> so the macro stays isolated from HomeView etc.

struct PlaylistRoute: Hashable { let id: String }

// MARK: - Add to playlist (from Detail)

struct AddToPlaylistSheet: View {
    let archiveID: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Add to Playlist")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                TextField("New playlist name", text: $newName)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .focused($nameFocused)
                Button("Create") { createAndAdd() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if playlists.isEmpty {
                Text("No playlists yet — create one above.")
                    .font(.title3).foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 12)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(playlists) { pl in
                            Button { toggle(pl) } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: pl.contains(archiveID) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(pl.contains(archiveID) ? (Color(hex: "#FF5C35") ?? .orange) : .white.opacity(0.5))
                                    Text(pl.name).foregroundStyle(.white)
                                    Spacer()
                                    Text("\(pl.archiveIDs.count)").foregroundStyle(.white.opacity(0.4))
                                }
                                .font(.title3)
                                .padding(.vertical, 12).padding(.horizontal, 8)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(maxHeight: 500)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(60)
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.93).ignoresSafeArea())
    }

    private func toggle(_ pl: Playlist) {
        if let i = pl.archiveIDs.firstIndex(of: archiveID) { pl.archiveIDs.remove(at: i) }
        else { pl.archiveIDs.append(archiveID) }
        try? ctx.save()
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        ctx.insert(Playlist(name: name, archiveIDs: [archiveID]))
        try? ctx.save()
        newName = ""
    }
}

// MARK: - Playlist detail (grid + Play All)

struct PlaylistDetailView: View {
    let playlistID: String
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query private var playlists: [Playlist]
    @State private var playing: [Catalog.Item]?

    private var playlist: Playlist? { playlists.first { $0.id == playlistID } }
    private var items: [Catalog.Item] { (playlist?.archiveIDs ?? []).compactMap { store.dbItem($0) } }
    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    Text(playlist?.name ?? "Playlist")
                        .font(.system(size: 48, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                    if !items.isEmpty {
                        Button { playing = items } label: {
                            Label("Play All", systemImage: "play.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .padding(.horizontal, 24).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                if items.isEmpty {
                    Text("This playlist is empty. Add titles from their detail page.")
                        .font(.title3).foregroundStyle(.white.opacity(0.5))
                } else {
                    LazyVGrid(columns: cols, spacing: 36) {
                        ForEach(items) { item in
                            PosterTile(item: item) { router.push(item) }
                        }
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(item: Binding(get: { playing.map { LineupBox(items: $0) } },
                                       set: { playing = $0?.items })) { box in
            if let screen = PlayerScreen(lineup: box.items) { screen }
        }
    }
}

private struct LineupBox: Identifiable { let id = UUID(); let items: [Catalog.Item] }

// MARK: - Library Watched section (#12b, tvOS-DESIGN §10.1)

struct WatchedSection: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Query(sort: \WatchProgress.lastWatchedAt, order: .reverse) private var progress: [WatchProgress]

    private var items: [Catalog.Item] {
        store.dbItemsByIDs(progress.filter { $0.isComplete }.map { $0.archiveID })
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Watched")
                    .font(.title2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 80)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 28) {
                        ForEach(items) { item in
                            PosterTile(item: item) { router.push(item) }
                                .frame(width: 200)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 8)
                }
                .scrollClipDisabled()
            }
            .focusSection()
        }
    }
}

// MARK: - Library playlists section (Library tab)

struct PlaylistsSection: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]

    var body: some View {
        if !playlists.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Playlists")
                    .font(.title2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 80)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 28) {
                        ForEach(playlists) { pl in
                            Button { router.push(PlaylistRoute(id: pl.id)) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(LinearGradient(colors: [Color(hex: "#2D5BFF") ?? .blue, .black],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 300, height: 170)
                                        .overlay(alignment: .bottomLeading) {
                                            Image(systemName: "music.note.list")
                                                .font(.system(size: 44))
                                                .foregroundStyle(.white.opacity(0.85))
                                                .padding(20)
                                        }
                                    Text(pl.name).font(.title3.bold()).foregroundStyle(.white).lineLimit(1)
                                    Text("\(pl.archiveIDs.count) titles").font(.callout).foregroundStyle(.white.opacity(0.5))
                                }
                                .frame(width: 300)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 80)
                }
            }
            .focusSection()
        }
    }
}
