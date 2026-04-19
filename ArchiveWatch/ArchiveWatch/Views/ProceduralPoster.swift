import SwiftUI

// Typographic placeholder poster for items without real designed artwork.
// Shown instead of Archive.org's first-frame thumbnail (which is usually
// blurry, noisy, or completely black). Uses the item's category accent
// as the color field and leans on strong serif typography — the same
// editorial voice as the app identity.
//
// Visual: bold color field, title in serif display weight, year in a
// numeric corner, category tag at the top, producer/creator small at
// the bottom. Looks designed, not "missing."

struct ProceduralPoster: View {
    let item: Catalog.Item
    let accent: Color
    let aspectRatio: CGFloat     // e.g. 2/3 for poster, 16/9 for TV/newsreel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let scale = w / 260  // our design reference width

            ZStack {
                // Base color field — saturated near the bottom, deeper at top
                LinearGradient(
                    colors: [accent.opacity(0.95), accent.mix(with: .black, 0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Grain / noise overlay for warmth
                grain.opacity(0.12)

                VStack(alignment: .leading, spacing: 0) {
                    // Category tag
                    HStack(spacing: 6 * scale) {
                        Rectangle()
                            .frame(width: 12 * scale, height: 2 * scale)
                            .foregroundStyle(.white)
                        Text(categoryTag.uppercased())
                            .font(.system(size: 11 * scale, weight: .bold, design: .default))
                            .tracking(1.5 * scale)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Title — serif, tight leading
                    Text(item.title)
                        .font(.system(size: titleSize(scale), weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer().frame(height: 8 * scale)

                    // Byline: director / producer / network
                    if let byline = item.byline {
                        Text(byline)
                            .font(.system(size: 11 * scale, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer().frame(height: 12 * scale)

                    HStack(alignment: .bottom) {
                        // Year in numeric block
                        if let year = item.year {
                            Text(String(year))
                                .font(.system(size: 36 * scale, weight: .black, design: .serif))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        // Film-reel mark
                        Image(systemName: "film.fill")
                            .font(.system(size: 18 * scale))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20 * scale)
                .padding(.vertical, 22 * scale)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func titleSize(_ scale: CGFloat) -> CGFloat {
        let len = item.title.count
        if len < 14 { return 32 * scale }
        if len < 28 { return 26 * scale }
        if len < 48 { return 20 * scale }
        return 16 * scale
    }

    private var categoryTag: String {
        switch item.contentType {
        case "feature-film": return "Feature"
        case "silent-film":  return "Silent"
        case "short-film":   return "Short"
        case "animation":    return "Animation"
        case "tv-series":    return "Television"
        case "tv-special":   return "TV Special"
        case "newsreel":     return "Newsreel"
        case "documentary":  return "Documentary"
        case "ephemeral":    return "Ephemeral"
        case "home-movie":   return "Home Movie"
        default:             return "Archive"
        }
    }

    /// Subtle horizontal banding — reads as "film frame" texture. Zero cost
    /// at render time (just a repeating linear gradient).
    private var grain: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.0), location: 0.0),
                .init(color: .white.opacity(0.2), location: 0.5),
                .init(color: .white.opacity(0.0), location: 1.0)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .blendMode(.softLight)
    }
}

extension Color {
    /// Linearly blends this color toward `other` by `fraction` (0..1).
    func mix(with other: Color, _ fraction: CGFloat) -> Color {
        let f = max(0, min(1, fraction))
        let a = resolveRGB()
        let b = other.resolveRGB()
        return Color(
            red:   a.r * (1 - f) + b.r * f,
            green: a.g * (1 - f) + b.g * f,
            blue:  a.b * (1 - f) + b.b * f
        )
    }

    private func resolveRGB() -> (r: Double, g: Double, b: Double) {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #else
        return (0.5, 0.5, 0.5)
        #endif
    }
}
