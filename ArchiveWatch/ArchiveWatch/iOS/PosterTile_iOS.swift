#if os(iOS)
import SwiftUI

// A poster tile (2:3) + title/year, the touch analog of the tvOS focus card.
// Tapping routes to Detail. Used by Home shelves, Browse grid, Search results.
struct PosterTile: View {
    let item: Catalog.Item
    var width: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: item.posterURLParsed)
                .frame(width: width, height: width * 1.5)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
            // Reserve a uniform text block (2 title lines + 1 year line) so tiles
            // WITH a year aren't clipped by shorter year-less neighbors sharing a
            // LazyHStack row — the row adopts one height, and an un-reserved year
            // line gets cut on iPad where the larger metrics expose the mismatch.
            Text(item.title)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true).truncationMode(.tail)
            Text(verbatim: item.year.map(String.init) ?? " ")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}

// Cached async poster with a quiet placeholder (URLCache is configured at launch).
// `contentMode` defaults to .fill (tiles/grid/cast want the image to fill their
// fixed frame); pass .fit where the image must never be cropped (e.g. the Detail
// hero, where a 2:3 poster would otherwise be zoomed into a sliver).
struct PosterImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var body: some View {
        AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let img): img.resizable().aspectRatio(contentMode: contentMode)
            default: Rectangle().fill(.quaternary).overlay(
                Image(systemName: "film").font(.title3).foregroundStyle(.tertiary))
            }
        }
        .clipped()
    }
}

#endif
