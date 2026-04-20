import SwiftUI
import Combine

// Hero carousel for the Home screen. Displays one backdrop at a time
// at its native 16:9 aspect, full width, fading into the page below.
// Left/right arrows navigate between films. Auto-advance pauses while
// the hero has focus.
//
// Cropping fix: backdrops render at their intrinsic aspect using
// scaledToFill + a fixed 16:9 frame, anchored to .top so faces stay
// visible. The bottom ~260pt of the frame is a gradient fade to black
// so the image dissolves into the page's dark background — no hard
// line, no awkward "what is this image even showing" crop.

struct HeroCarousel: View {
    let items: [Catalog.Item]
    @State private var index: Int = 0
    @State private var autoAdvance = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    @FocusState private var isFocused: Bool

    private let heroHeight: CGFloat = 720

    var body: some View {
        ZStack(alignment: .bottom) {
            // Stacked banners — only the current one is visible AND
            // hit-tested (otherwise tvOS would focus invisible banners).
            ForEach(Array(items.enumerated()), id: \.element.archiveID) { i, item in
                HeroBanner(
                    item: item,
                    onMoveLeft: { step(-1) },
                    onMoveRight: { step(+1) }
                )
                .opacity(i == index ? 1 : 0)
                .allowsHitTesting(i == index)
                .animation(Motion.heroCrossfade, value: index)
                .focused($isFocused)
            }
            pageIndicator
                .padding(.bottom, 56)
        }
        .frame(height: heroHeight)
        .onReceive(autoAdvance) { _ in
            // Pause auto-advance while the user is interacting with
            // the hero — otherwise the carousel yanks the card out
            // from under them mid-decision.
            guard !isFocused else { return }
            step(+1)
        }
    }

    private func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        let count = items.count
        let next = ((index + delta) % count + count) % count
        withAnimation(Motion.heroCrossfade) { index = next }
    }

    private var pageIndicator: some View {
        HStack(spacing: 12) {
            ForEach(0..<items.count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.white : Color.white.opacity(0.35))
                    .frame(width: i == index ? 36 : 10, height: 10)
                    .animation(Motion.chrome, value: index)
            }
        }
    }
}

struct HeroBanner: View {
    let item: Catalog.Item
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.push(item) } label: {
            ZStack(alignment: .bottomLeading) {
                backdrop
                // Heavy bottom fade so the backdrop dissolves into the
                // page's dark background — no hard edge, no need to
                // pick a "safe" crop. Image reads as the hero of the
                // screen, page flows continuously below.
                LinearGradient(
                    colors: [
                        .clear,
                        .clear,
                        .black.opacity(0.45),
                        .black.opacity(0.9),
                        .black
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                heroOverlay
                    .padding(.leading, 80)
                    .padding(.trailing, 80)
                    .padding(.bottom, 112)
            }
        }
        .buttonStyle(.card)
        // Arrow keys navigate between hero items. onMoveCommand fires
        // independently of focus changes, so this takes priority over
        // the default focus-engine left/right behavior — which would
        // otherwise try to move focus off the hero entirely.
        .onMoveCommand { direction in
            switch direction {
            case .left:  onMoveLeft()
            case .right: onMoveRight()
            default:     break
            }
        }
    }

    private var heroOverlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(categoryLabel.uppercased())
                .font(.system(size: 15, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(store.accentColor(forCategory: categoryID))
            Text(item.title)
                .font(.system(size: 64, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            HStack(spacing: 18) {
                if let year = item.year { Text(String(year)) }
                if let r = item.runtimeSeconds, r > 0 { Text(formatRuntime(r)) }
                if let byline = item.byline { Text(byline) }
            }
            .font(.system(size: 25, weight: .regular))
            .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: 1200, alignment: .leading)
    }

    @ViewBuilder
    private var backdrop: some View {
        if item.hasDesignedArtwork, let url = item.backdropURLParsed ?? item.posterURLParsed {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: 1920, height: 1080),
                contentMode: .fill,
                placeholder: Color(white: 0.08)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        } else {
            LinearGradient(
                colors: [store.accentColor(forCategory: categoryID).opacity(0.85), .black],
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
        case "animation":   return "animation"
        case "newsreel":    return "newsreel"
        case "documentary": return "documentary"
        case "ephemeral":   return "ephemeral"
        case "short-film":  return "short-film"
        default:            return "feature-film"
        }
    }

    private func formatRuntime(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
