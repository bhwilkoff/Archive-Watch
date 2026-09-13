import SwiftData
import SwiftUI

/// A shared playlist as a navigation destination. It carries the whole
/// playlist because there is nothing to look it up BY — the list travelled
/// inside the link and was never stored anywhere.
struct SharedListRoute: Hashable {
    let name: String
    let archiveIDs: [String]
    var shared: PlaylistShare.Shared { .init(name: name, archiveIDs: archiveIDs) }
}

#if os(tvOS)

/// A playlist somebody else made, opened from a link.
///
/// The list arrives INSIDE the URL (`PlaylistShare`), so there is nothing to
/// fetch and nothing of ours hosting it — the viewer is looking at a
/// collection that travelled in a QR code. Two things follow from that:
///
/// IT IS BROWSE-AND-PLAY BEFORE IT IS ANYTHING ELSE. Signed in or not, the
/// films are here and they play. That is the owner's rule for the web too:
/// "If you aren't logged in, it should just be a browse and play collection."
/// Nothing is withheld from a stranger, because nothing here is ours to
/// withhold.
///
/// ADDING IT IS THE VIEWER'S CHOICE, never a side effect of opening a link.
/// The app could silently copy the playlist into the library and land them in
/// it — fewer taps, and wrong: a link they tapped out of curiosity would have
/// edited their library. The web asks, and so does this.
struct SharedListView: View {
    let shared: PlaylistShare.Shared

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query private var playlists: [Playlist]

    @State private var playing: [Catalog.Item]?
    @State private var added = false

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    /// The films this catalogue can actually serve. A shared list is only as
    /// current as the catalogue it is opened against, and ids do go away.
    private var items: [Catalog.Item] { shared.archiveIDs.compactMap { store.dbItem($0) } }

    private var missing: Int { shared.archiveIDs.count - items.count }

    /// Already here? Matched on CONTENTS, not on name — two people can send the
    /// same collection under different names, and a viewer who opens the same
    /// link twice should not end up with two copies.
    private var alreadyHave: Bool {
        playlists.contains { $0.archiveIDs == shared.archiveIDs }
    }

    private func addToLibrary() {
        let pl = Playlist(name: shared.name, archiveIDs: shared.archiveIDs)
        ctx.insert(pl)
        try? ctx.save()
        SyncNudge.nudge(ctx)      // so it reaches the viewer's other devices
        added = true
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("SHARED PLAYLIST")
                    .font(.system(size: 20, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))

                HStack(spacing: 24) {
                    Text(shared.name)
                        .font(.system(size: 48, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)

                    if !items.isEmpty {
                        Button { playing = items } label: {
                            Label("Play All", systemImage: "play.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .padding(.horizontal, 24).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)

                        if added || alreadyHave {
                            Label(added ? "Added to your library" : "Already in your library",
                                  systemImage: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 24).padding(.vertical, 12)
                        } else {
                            Button(action: addToLibrary) {
                                Label("Add to my library", systemImage: "plus.circle")
                                    .font(.system(size: 22, weight: .semibold))
                                    .padding(.horizontal, 24).padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Spacer()
                }

                // A title the link names that this catalogue no longer serves is
                // a FACT WORTH STATING rather than a silently shorter list —
                // otherwise the sharer and the viewer are looking at different
                // collections and neither can tell. The web says the same thing.
                Text(countLine)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))

                if items.isEmpty {
                    Text("None of these titles are in the catalogue any more.")
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
        .fullScreenCover(item: Binding(get: { playing.map { SharedLineupBox(items: $0) } },
                                       set: { playing = $0?.items })) { box in
            // Deliberate viewing, so it keeps resume — the same call
            // PlaylistDetailView makes, and the opposite of the ephemeral
            // channel lineups.
            if let screen = PlayerScreen(lineup: box.items, ephemeralLineup: false) { screen }
        }
    }

    private var countLine: String {
        let n = items.count
        if missing > 0 {
            return "\(n) of \(shared.archiveIDs.count) titles — "
                 + "\(missing) \(missing == 1 ? "is" : "are") no longer in the catalogue."
        }
        return "\(n) \(n == 1 ? "title" : "titles")."
    }
}

private struct SharedLineupBox: Identifiable { let id = UUID(); let items: [Catalog.Item] }

#endif

#if os(iOS)

/// The phone's shared playlist. The SAME rules as the Apple TV's — browse and
/// play for anyone, adding it is a choice — in the phone's idiom.
///
/// This is the surface a shared link is most likely to land on: the QR code an
/// Apple TV or a Roku draws is scanned by a PHONE, so this is where the
/// feature's main path ends up.
struct SharedListView: View {
    let shared: PlaylistShare.Shared

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query private var playlists: [Playlist]

    @State private var added = false

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    private var items: [Catalog.Item] { store.itemsByIDs(shared.archiveIDs) }
    private var missing: Int { shared.archiveIDs.count - items.count }

    /// Matched on CONTENTS, not name: the same collection sent under two names
    /// should not become two copies in the library.
    private var alreadyHave: Bool { playlists.contains { $0.archiveIDs == shared.archiveIDs } }

    private func addToLibrary() {
        let pl = Playlist(name: shared.name, archiveIDs: shared.archiveIDs)
        ctx.insert(pl)
        try? ctx.save()
        SyncNudge.nudge(ctx)
        added = true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // A title the link names that this catalogue no longer serves is
                // STATED, never silently dropped — otherwise the sharer and the
                // viewer see different collections and neither can tell.
                Text(countLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if items.isEmpty {
                    ContentUnavailableView("Nothing to show",
                        systemImage: "rectangle.stack",
                        description: Text("None of these titles are in the catalogue any more."))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(items) { item in
                            Button { router.push(item) } label: { PosterTile(item: item) }
                                .buttonStyle(.plain)
                        }
                    }.padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(shared.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if added || alreadyHave {
                    Label(added ? "Added" : "In your library", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                } else if !items.isEmpty {
                    Button(action: addToLibrary) {
                        Label("Add to my library", systemImage: "plus.circle")
                    }
                }
            }
        }
    }

    private var countLine: String {
        let n = items.count
        if missing > 0 {
            return "\(n) of \(shared.archiveIDs.count) titles — "
                 + "\(missing) \(missing == 1 ? "is" : "are") no longer in the catalogue."
        }
        return "Shared playlist · \(n) \(n == 1 ? "title" : "titles")"
    }
}

#endif

#if os(macOS)

/// The Mac's shared playlist. Same rules as the Apple TV and the phone —
/// browse and play for anyone, adding it is a choice — over the Mac's own
/// poster grid.
struct SharedListView: View {
    let shared: PlaylistShare.Shared

    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Query private var playlists: [Playlist]

    @State private var added = false

    private var items: [Catalog.Item] { store.itemsByIDs(shared.archiveIDs) }
    private var missing: Int { shared.archiveIDs.count - items.count }

    /// Matched on CONTENTS, not name: the same collection sent under two names
    /// should not become two copies in the library.
    private var alreadyHave: Bool { playlists.contains { $0.archiveIDs == shared.archiveIDs } }

    private func addToLibrary() {
        let pl = Playlist(name: shared.name, archiveIDs: shared.archiveIDs)
        ctx.insert(pl)
        try? ctx.save()
        SyncNudge.nudge(ctx)
        added = true
    }

    var body: some View {
        GridView(title: shared.name, items: items)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 12) {
                    // A title the link names that this catalogue no longer
                    // serves is STATED, never silently dropped.
                    Text(countLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if added || alreadyHave {
                        Label(added ? "Added to your library" : "In your library",
                              systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if !items.isEmpty {
                        Button(action: addToLibrary) {
                            Label("Add to my library", systemImage: "plus.circle")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
    }

    private var countLine: String {
        let n = items.count
        if missing > 0 {
            return "Shared playlist · \(n) of \(shared.archiveIDs.count) titles — "
                 + "\(missing) \(missing == 1 ? "is" : "are") no longer in the catalogue."
        }
        return "Shared playlist · \(n) \(n == 1 ? "title" : "titles")"
    }
}

#endif
