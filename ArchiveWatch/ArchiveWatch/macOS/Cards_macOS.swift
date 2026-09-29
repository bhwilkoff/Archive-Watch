#if os(macOS)
import SwiftUI
import SwiftData

// Reusable poster card + a generic grid. Pointer-native: hover lifts the card, click
// opens Detail, right-click offers Play. (NSCollectionView migration for huge grids is a
// later optimization — docs/macOS-DESIGN.md Rule 7b.)

struct PosterCard: View {
    let item: Catalog.Item
    /// Continue Watching: a bar along the poster's foot and the time left in
    /// place of the year (the Apple TV card's two facts, tvOS v1.42.858).
    var progress: WatchProgress? = nil
    @Environment(AppRouter.self) private var router
    @State private var hovering = false

    var body: some View {
        // A Button, not a tap gesture: Keyboard Navigation (Tab) and VoiceOver
        // reach only real controls, and a gesture reached neither (iPad loop
        // cross-platform queue, 2026-09-28).
        Button { router.openDetail(item) } label: { card }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .accessibilityLabel([item.title, item.year.map(String.init)].compactMap { $0 }.joined(separator: ", "))
            .draggable(FilmTransfer(archiveID: item.archiveID))   // §B15
            .filmContextMenu(item)
            .help(item.title)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The RoundedRectangle owns the 2:3 layout size; the poster fills via
            // .overlay so a fill-mode AsyncImage (which reports oversized "cover"
            // dimensions) can never drive the card's layout. Without this the cards
            // adopt the image's cover size and overlap (the fill-image layout trap;
            // see iOS Detail fix + tvOS playbook).
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemotePoster(item: item) }
                .overlay(alignment: .bottom) {
                    if let progress {
                        ProgressView(value: progress.fraction)
                            .tint(Brand.primary)
                            .padding(.horizontal, 6).padding(.bottom, 6)
                            .accessibilityHidden(true)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) {
                    if let r = item.imdbRatingDisplay {
                        Label(r, systemImage: "star.fill")
                            .font(.caption2).padding(4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                }
                .shadow(radius: hovering ? 8 : 2, y: hovering ? 4 : 1)
                .scaleEffect(hovering ? 1.03 : 1.0)

            Text(item.title).font(.caption).fontWeight(.medium).lineLimit(1)
            // The year line is always laid out: a grid centers its cells, so a
            // card with no year sat half a line lower than its row (The Pink
            // Panther in Movies; Mac loop, 2026-09-27).
            Text(verbatim: progress?.remainingLabel ?? item.year.map(String.init) ?? " ")
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityHidden(progress == nil && item.year == nil)
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// Right-click on a film anywhere it appears as a card or a guide block:
    /// Open, Play, Favorites, Share — the menu iPhone and iPad offer on a
    /// poster (IPAD-DESIGN §11.2), in the Mac's Title Case.
    func filmContextMenu(_ item: Catalog.Item) -> some View {
        modifier(FilmContextMenuMac(item: item))
    }
}

private struct FilmContextMenuMac: ViewModifier {
    let item: Catalog.Item
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var ctx

    /// Read when the menu opens, so a grid of cards does not each observe
    /// every favorite.
    private var favorite: Favorite? {
        let id = item.archiveID
        var d = FetchDescriptor<Favorite>(predicate: #Predicate { $0.archiveID == id })
        d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Open") { router.openDetail(item) }
            if item.videoURLParsed != nil {
                Button("Play") { router.play(item) }
            }
            Divider()
            if let f = favorite {
                Button("Remove from Favorites") {
                    ctx.delete(f)
                    ctx.insert(Tombstone(key: "fav:\(item.archiveID)"))
                    try? ctx.save()
                }
            } else {
                Button("Add to Favorites") {
                    ctx.insert(Favorite(archiveID: item.archiveID))
                    try? ctx.save()
                }
            }
            if let url = URL(string: "https://archivewatch.org/item/\(item.archiveID)") {
                ShareLink("Share…", item: url)
            }
        }
    }
}

/// A poster that NEVER shows an empty gray box: the designed poster → (on load failure, e.g. a
/// dead/throttled Wikimedia/omdb URL) the archive.org item frame → (if that fails) a typographic
/// title card. Fixes "missing posters" on Home where an item has hasProfessionalArtwork=true but
/// its poster URL no longer loads (the issue is the same on tvOS — it's the DATA, not the layout).
struct RemotePoster: View {
    let item: Catalog.Item
    // Cached + connection-capped via ImagePipeline (bare AsyncImage re-downloaded/re-decoded on
    // every view reveal and stormed archive.org — the "posters load slowly" report). The fallback
    // chain (designed poster → archive.org item frame → typographic card) runs once per item.
    @State private var image: NSImage?
    @State private var exhausted = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if exhausted {
                titleCard
            } else {
                Color.clear                                   // quaternary fill shows through while loading
            }
        }
        .task(id: item.archiveID) {
            image = nil; exhausted = false
            // Designed poster ONLY — never the archive.org services/img thumbnail (owner 2026-06-29);
            // an art-less item falls through to the typographic titleCard, not a frame grab.
            if item.hasDesignedArtwork, let u = item.posterURLParsed, let img = await ImagePipeline.shared.image(u) {
                image = img; return
            }
            exhausted = true
        }
    }

    private var titleCard: some View {
        Text(item.title)
            .font(.caption).fontWeight(.semibold)
            .multilineTextAlignment(.center).lineLimit(4)
            .padding(6).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private let posterColumns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

struct GridView: View {
    let title: String
    let items: [Catalog.Item]
    /// macOS-DESIGN §B7a: a collection's grid carries Browse's sort.
    var sortable = false
    /// A collection's own words (archive.org's, SCRATCHPAD 2026-09-27), above its films as
    /// the iPhone shows them; the Mac opened straight onto posters.
    var blurb: String? = nil
    @State private var sort: CatalogDB.Sort = .popular

    private var shown: [Catalog.Item] { sortable ? CatalogDB.ordered(items, by: sort) : items }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "film.stack")
                    .padding(.top, 80)
            } else {
                if let blurb, !blurb.isEmpty {
                    Text(blurb).font(.body).foregroundStyle(.secondary)
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top])
                        .textSelection(.enabled)
                }
                LazyVGrid(columns: posterColumns, spacing: 18) {
                    ForEach(shown) { PosterCard(item: $0) }
                }
                .padding()
            }
        }
        .navigationTitle(title)
        .toolbar {
            if sortable {
                ToolbarItem {
                    Picker("Sort", selection: $sort) {
                        Text("Popular").tag(CatalogDB.Sort.popular)
                        Text("Top Rated").tag(CatalogDB.Sort.rating)
                        Text("A–Z").tag(CatalogDB.Sort.alphabetical)
                        Text("Newest").tag(CatalogDB.Sort.newest)
                        Text("Oldest").tag(CatalogDB.Sort.oldest)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}

// Horizontal shelf for Home.
struct ShelfRow<Trailing: View>: View {
    let title: String
    let items: [Catalog.Item]
    var accent: Color = .primary
    var progressByID: [String: WatchProgress] = [:]
    /// Shown in place of the posters when there are none; nil hides the shelf.
    /// A playlist uses it: hidden, a playlist whose films all left the catalog
    /// could not be seen, added to (§B15) or deleted.
    var emptyText: String? = nil
    // A visible control beside the title (a playlist's Share). A row verb
    // that lives only behind right-click cannot be found — iOS learned the
    // same lesson with a swipe, so the shelf offers the slot.
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, items: [Catalog.Item], accent: Color = .primary,
         progressByID: [String: WatchProgress] = [:], emptyText: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.items = items; self.accent = accent
        self.progressByID = progressByID; self.emptyText = emptyText; self.trailing = trailing
    }

    var body: some View {
        if !items.isEmpty || emptyText != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    // A heading, so VoiceOver can jump shelf to shelf (VO-⌘-H); as plain text the
                    // only way down Home was every poster in turn (Mac loop, 2026-09-27).
                    Text(title).font(.title3).fontWeight(.semibold).foregroundStyle(accent).accessibilityAddTraits(.isHeader)
                    trailing()
                }
                if items.isEmpty, let emptyText {
                    Text(emptyText).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .contentShape(Rectangle())
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(items) { PosterCard(item: $0, progress: progressByID[$0.archiveID]).frame(width: 150) }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
    }
}

extension ShelfRow where Trailing == EmptyView {
    init(title: String, items: [Catalog.Item], accent: Color = .primary,
         progressByID: [String: WatchProgress] = [:]) {
        self.init(title: title, items: items, accent: accent, progressByID: progressByID) { EmptyView() }
    }
}
#endif
