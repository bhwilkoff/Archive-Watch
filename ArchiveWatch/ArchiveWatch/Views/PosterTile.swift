#if os(tvOS)
import SwiftUI

// Reusable poster tile used by Home shelves, the Detail "More Like
// This" row, and anywhere else a 2:3 portrait card with a title below
// is needed. Split out of HomeView.swift so SourceKit can parse it
// independently.
//
// Structural note: the Button wraps ONLY the image (PosterArt). The
// title sits as a sibling in the outer VStack. Without this,
// .buttonStyle(.card)'s focus clipping chops text that falls outside
// the poster frame — which was the "titles cut off under tiles" bug.

struct PosterTile: View {
    let item: Catalog.Item
    let action: () -> Void

    @Environment(AppStore.self) private var store
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat  = 240
    private let cardHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Button(action: action) {
                PosterArt(item: item, width: cardWidth, height: cardHeight)
            }
            .buttonStyle(.card)
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.78)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let year = item.year { Text(String(year)) }
                    if let r = item.runtimeSeconds, r > 0 {
                        Text("·")
                        Text(formatRuntime(r))
                    }
                }
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: cardWidth, alignment: .leading)
            .opacity(isFocused ? 1.0 : 0.85)
            .animation(Motion.focus, value: isFocused)
        }
    }

    private func formatRuntime(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

// Pure image component — no button, no focus state. Callers wrap it
// in whatever activation + focus scaffolding they need.

struct PosterArt: View {
    let item: Catalog.Item
    let width: CGFloat
    let height: CGFloat

    @Environment(AppStore.self) private var store
    // 0 = designed poster, 1 = archive.org frame fallback, 2 = procedural only.
    @State private var stage = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            // BASE — the brand procedural card is ALWAYS behind the poster, so a slot is NEVER blank
            // (during load OR when the designed/archive art fails). The real poster covers it on
            // success (owner: never show a blank poster on any platform).
            ProceduralPoster(
                item: item,
                accent: store.accentColor(forCategory: categoryID),
                aspectRatio: width / height
            )
            posterOverlay
            if let chip = categoryChipLabel {
                Text(chip.uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1.4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(10)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .task(id: item.archiveID) { stage = 0 }
    }

    // The real poster on TOP of the procedural base, with a CLEAR placeholder so the base shows
    // through during load + on failure. Designed poster → (fail) archive.org frame → (fail) nothing,
    // letting the procedural base remain.
    @ViewBuilder private var posterOverlay: some View {
        let size = CGSize(width: width, height: height)
        // Designed poster ONLY → (fail) the procedural base shows through. We never fall back to the
        // archive.org services/img thumbnail (owner 2026-06-29: "no instance of the archive.org
        // screenshot"); the cover pipeline supplies real generated posters for art-less items.
        if item.hasDesignedArtwork, let url = item.posterURLParsed, stage == 0 {
            RemoteImage(url: url, targetSize: size, contentMode: .fill,
                        placeholder: .clear, onLoadFailed: { stage = 1 })
        }
    }

    private var categoryChipLabel: String? {
        switch item.contentType {
        case "tv-series", "tv-special": return "TV"
        case "silent-film":             return "Silent"
        case "animation":               return "Animation"
        case "newsreel":                return "Newsreel"
        case "documentary":             return "Doc"
        case "ephemeral":               return "Ephemeral"
        case "short-film":              return "Short"
        default:                        return nil
        }
    }

    private var categoryID: String {
        switch item.contentType {
        case "tv-series", "tv-special": return "tv-series"
        case "silent-film": return "silent-film"
        case "animation":   return "animation"
        case "newsreel":    return "newsreel"
        case "documentary": return "documentary"
        case "ephemeral":   return "ephemeral"
        case "short-film":  return "short-film"
        default:            return "feature-film"
        }
    }
}

#endif
