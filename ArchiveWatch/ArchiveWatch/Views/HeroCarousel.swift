import SwiftUI
import Combine

// Hero carousel + banner for the Home screen. Split out of HomeView
// so SourceKit can parse this unit independently.

struct HeroCarousel: View {
    let items: [Catalog.Item]
    @State private var index: Int = 0
    @State private var autoAdvanceTimer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(items.enumerated()), id: \.element.archiveID) { i, item in
                HeroBanner(item: item)
                    .opacity(i == index ? 1 : 0)
                    // Non-visible banners would still be focusable
                    // without this — tvOS happily focuses zero-opacity
                    // views, which stole focus from the visible hero
                    // and made the carousel feel unresponsive.
                    .allowsHitTesting(i == index)
                    .animation(Motion.heroCrossfade, value: index)
            }
            HStack(spacing: 12) {
                ForEach(0..<items.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.white : Color.white.opacity(0.35))
                        .frame(width: i == index ? 36 : 10, height: 10)
                        .animation(Motion.chrome, value: index)
                }
            }
            .padding(.bottom, 44)
        }
        .frame(height: 620)
        .onReceive(autoAdvanceTimer) { _ in
            withAnimation { index = (index + 1) % items.count }
        }
    }
}

struct HeroBanner: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.push(item) } label: {
            ZStack(alignment: .bottomLeading) {
                backdrop
                // Heavier bottom scrim so title/year/byline are always
                // legible regardless of what the backdrop shows behind
                // them. Playbook §5: target 7:1 contrast on art.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.25), .black.opacity(0.75), .black.opacity(0.98)],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
                HStack(alignment: .bottom, spacing: 48) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(categoryLabel.uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(store.accentColor(forCategory: categoryID))
                        Text(item.title)
                            .font(.system(size: 60, weight: .heavy, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.55)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                        HStack(spacing: 16) {
                            if let year = item.year { Text(String(year)) }
                            if let r = item.runtimeSeconds, r > 0 { Text(formatRuntime(r)) }
                            if let byline = item.byline { Text(byline) }
                        }
                        .font(.system(size: 29, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.leading, 80)
                    .padding(.bottom, 40)
                    .padding(.trailing, 40)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 620)
        }
        .buttonStyle(.card)
    }

    @ViewBuilder
    private var backdrop: some View {
        if item.hasDesignedArtwork, let url = item.backdropURLParsed ?? item.posterURLParsed {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: 1920, height: 620),
                contentMode: .fill,
                placeholder: Color(white: 0.08)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        } else {
            LinearGradient(
                colors: [store.accentColor(forCategory: categoryID).opacity(0.8), .black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var categoryLabel: String {
        store.featured?.category(id: categoryID)?.displayName ?? "Featured"
    }

    private var categoryID: String {
        switch item.contentType {
        case "tv-series", "tv-special": return "tv-series"
        case "silent-film": return "silent-film"
        case "animation": return "animation"
        case "newsreel": return "newsreel"
        case "documentary": return "documentary"
        case "ephemeral": return "ephemeral"
        case "short-film": return "short-film"
        default: return "feature-film"
        }
    }

    private func formatRuntime(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
