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
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                Text("Add to Playlist")
                    .font(.system(size: 48, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)

                // New playlist: full-width field, then a full-width primary action
                // (stacked, so it never collides with the field and stays uniform).
                VStack(alignment: .leading, spacing: 12) {
                    Text("New Playlist").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                    TextField("Name", text: $newName)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .padding(.horizontal, 24).padding(.vertical, 18)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                        .focused($nameFocused)
                    Button { createAndAdd() } label: {
                        Label("Create Playlist", systemImage: "plus.circle.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !playlists.isEmpty {
                    Text("Your Playlists").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 8)
                    LazyVStack(spacing: 14) {
                        ForEach(playlists) { pl in
                            PlaylistPickRow(name: pl.name,
                                            count: pl.archiveIDs.count,
                                            isOn: pl.contains(archiveID)) { toggle(pl) }
                        }
                    }
                }

                Button { dismiss() } label: {
                    Text("Done").font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(BarButtonStyle())
                .padding(.top, 12)
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 80)
            .padding(.vertical, 80)
        }
        .background(Color.black.ignoresSafeArea())
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

/// A large, focusable playlist row (native .card treatment) — replaces the tiny
/// borderless rows the picker used to show.
private struct PlaylistPickRow: View {
    let name: String
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30))
                    .foregroundStyle(isOn ? (Color(hex: "#FF5C35") ?? .orange) : .white.opacity(0.5))
                Text(name).font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("\(count) \(count == 1 ? "title" : "titles")")
                    .font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.card)
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
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(items) { item in
                            // PosterTile self-sizes to 240 wide (poster + title);
                            // an outer .frame(width: 200) was clipping it narrower
                            // than its content, so adjacent titles overlapped.
                            PosterTile(item: item) { router.push(item) }
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
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(playlists) { pl in
                            PlaylistTile(playlist: pl) { router.push(PlaylistRoute(id: pl.id)) }
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

// Playlist cover tile — mirrors PosterTile's structure (poster-shaped card in a
// .card Button, label text BELOW and OUTSIDE the button) so it matches every
// other shelf. The old version was a one-off 300x170 landscape card with the
// name+count INSIDE the .card button, which clipped the text on focus and didn't
// match the portrait posters anywhere else in the app.
private struct PlaylistTile: View {
    let playlist: Playlist
    let action: () -> Void
    @Environment(AppStore.self) private var store
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat = 240
    private let cardHeight: CGFloat = 360

    // #9: build the cover from the playlist's own item posters, not a flat color.
    private var posters: [URL] {
        playlist.archiveIDs.prefix(8).compactMap { store.dbItem($0) }
            .compactMap { $0.hasDesignedArtwork ? $0.posterURLParsed : nil }
    }

    var body: some View {
        // Matches PosterTile exactly: 28pt between the .card button and the title
        // block (14pt let the focus-scaled card bloom over the text), title styled
        // identically, and a focus opacity/animation.
        VStack(alignment: .leading, spacing: 28) {
            Button(action: action) {
                PlaylistCover(posters: posters, width: cardWidth, height: cardHeight)
            }
            .buttonStyle(.card)
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.78)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(playlist.archiveIDs.count) \(playlist.archiveIDs.count == 1 ? "title" : "titles")")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: cardWidth, alignment: .leading)
            .opacity(isFocused ? 1.0 : 0.85)
            .animation(Motion.focus, value: isFocused)
        }
    }
}

/// A playlist cover composed from the posters of its items: 1 → full bleed,
/// 2–3 → split, 4+ → 2×2 mosaic. Falls back to a film icon when none of the
/// items have designed artwork yet (#9).
private struct PlaylistCover: View {
    let posters: [URL]
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            switch posters.count {
            case 0:
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(hex: "#2D5BFF") ?? .blue, .black],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "film.stack")
                            .font(.system(size: 72)).foregroundStyle(.white.opacity(0.85))
                    }
            case 1:
                tile(posters[0], width, height)
            case 2:
                HStack(spacing: 2) {
                    tile(posters[0], width / 2, height)
                    tile(posters[1], width / 2, height)
                }
            default:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        tile(posters[0], width / 2, height / 2)
                        tile(posters[1], width / 2, height / 2)
                    }
                    HStack(spacing: 2) {
                        tile(posters[2], width / 2, height / 2)
                        tile(posters.count > 3 ? posters[3] : posters[0], width / 2, height / 2)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func tile(_ url: URL, _ w: CGFloat, _ h: CGFloat) -> some View {
        RemoteImage(url: url, targetSize: CGSize(width: w * 2, height: h * 2),
                    contentMode: .fill, placeholder: Color(white: 0.1))
            .frame(width: w, height: h).clipped()
    }
}
