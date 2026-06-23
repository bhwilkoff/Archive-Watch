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
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let url = item.posterURLParsed {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.clear }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(item.title)
                        .font(.caption).fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(6).foregroundStyle(.secondary)
                }
            }
            .aspectRatio(2.0/3.0, contentMode: .fit)
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
