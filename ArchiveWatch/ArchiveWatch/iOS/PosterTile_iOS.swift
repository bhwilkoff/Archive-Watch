#if os(iOS)
import SwiftUI

// A poster tile (2:3) + title/year, the touch analog of the tvOS focus card.
// Tapping routes to Detail. Used by Home shelves, Browse grid, Search results.
struct PosterTile: View {
    let item: Catalog.Item
    var width: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResilientPosterArt(item: item)
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

// A poster that is NEVER blank (owner: a blank poster makes the app look broken). A brand title
// card sits ALWAYS behind, so the slot is filled during load + on failure; the designed poster
// covers it on success, and a failed designed poster falls through to the archive.org item frame
// before revealing the title card.
struct ResilientPosterArt: View {
    let item: Catalog.Item
    @State private var stage = 0   // 0 designed poster, 1 archive frame, 2 title card

    var body: some View {
        ZStack {
            PosterFallbackCard(item: item)   // base — never blank
            poster
        }
        .clipped()
        .task(id: item.archiveID) { stage = 0 }
    }

    @ViewBuilder private var poster: some View {
        if let url = item.posterURLParsed, stage == 0 {
            phased(url) { stage = 1 }
        } else if stage == 1, let frame = item.archiveThumbURL {
            phased(frame) { stage = 2 }
        }
    }

    private func phased(_ url: URL, onFail: @escaping () -> Void) -> some View {
        AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
            case .failure:          Color.clear.onAppear(perform: onFail)   // → next stage
            default:                Color.clear                            // loading → base shows
            }
        }
    }
}

// The brand placeholder card (Decision 013 typographic poster, touch idiom): accent gradient +
// centered title. Always non-blank.
struct PosterFallbackCard: View {
    let item: Catalog.Item
    private var accent: Color {
        switch item.contentType {
        case "tv-series", "tv-special": Color(hex: "#2D5BFF") ?? .blue
        case "silent-film": Color(hex: "#C9A66B") ?? .brown
        case "animation":   Color(hex: "#FF4D8D") ?? .pink
        case "newsreel":    Color(hex: "#8A8F98") ?? .gray
        case "documentary": Color(hex: "#3FA796") ?? .teal
        case "ephemeral":   Color(hex: "#7C5BBA") ?? .purple
        case "short-film":  Color(hex: "#E8A317") ?? .yellow
        default:            Color(hex: "#FF5C35") ?? .orange
        }
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.85), accent.mix(with: .black, by: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(item.title)
                .font(.caption.weight(.bold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.7)
                .padding(8)
        }
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
