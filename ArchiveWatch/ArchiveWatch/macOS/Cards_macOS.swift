#if os(macOS)
import SwiftUI

// Reusable poster card + a generic grid. Pointer-native: hover lifts the card, click
// opens Detail, double-click plays. (NSCollectionView migration for huge grids is a
// later optimization — docs/macOS-DESIGN.md Rule 7b.)

struct PosterCard: View {
    let item: Catalog.Item
    @Environment(AppRouter.self) private var router
    @State private var hovering = false

    var body: some View {
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
            if let y = item.year {
                Text(verbatim: String(y)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture { router.openDetail(item) }
        .contextMenu {
            Button("Open") { router.openDetail(item) }
            if item.videoURLParsed != nil {
                Button("Play") { router.play(item) }
            }
        }
        .help(item.title)
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

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "film.stack")
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: posterColumns, spacing: 18) {
                    ForEach(items) { PosterCard(item: $0) }
                }
                .padding()
            }
        }
        .navigationTitle(title)
    }
}

// Horizontal shelf for Home.
struct ShelfRow: View {
    let title: String
    let items: [Catalog.Item]
    var accent: Color = .primary

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3).fontWeight(.semibold).foregroundStyle(accent)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(items) { PosterCard(item: $0).frame(width: 150) }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }
}
#endif
