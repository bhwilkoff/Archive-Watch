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
            Text(item.title)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2).truncationMode(.tail)
            if let y = item.year {
                Text(verbatim: String(y)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: width)
    }
}

// Cached async poster with a quiet placeholder (URLCache is configured at launch).
struct PosterImage: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: Rectangle().fill(.quaternary).overlay(
                Image(systemName: "film").font(.title3).foregroundStyle(.tertiary))
            }
        }
        .clipped()
    }
}
