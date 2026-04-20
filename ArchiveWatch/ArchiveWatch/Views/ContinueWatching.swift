import SwiftUI
import SwiftData

// Continue Watching row + tile. Split out of HomeView so the SwiftData
// @Query machinery stays in its own file, reducing SourceKit's
// cross-file work when editing nearby views.

struct ContinueWatchingRow: View {
    @Environment(Router.self) private var router
    let entries: [(item: Catalog.Item, progress: WatchProgress)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue Watching")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 28) {
                    ForEach(entries, id: \.item.archiveID) { entry in
                        ContinueWatchingTile(item: entry.item, progress: entry.progress) {
                            router.push(entry.item)
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
    }
}

struct ContinueWatchingTile: View {
    let item: Catalog.Item
    let progress: WatchProgress
    let action: () -> Void

    @Environment(AppStore.self) private var store
    @FocusState private var isFocused: Bool

    private var isLandscape: Bool {
        item.contentType == "tv-series" || item.contentType == "tv-special" ||
        item.contentType == "newsreel" || item.contentType == "documentary" ||
        item.contentType == "home-movie"
    }

    private var cardHeight: CGFloat { isLandscape ? 180 : 240 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: action) {
                ZStack(alignment: .bottom) {
                    posterArea
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.75)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 88)
                    }
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 19, weight: .bold))
                            Text(remainingLabel)
                                .font(.system(size: 19, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        ProgressBar(fraction: progress.fraction)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                }
                .frame(width: 320, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.card)
            .focused($isFocused)

            Text(item.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 320, alignment: .leading)
                .opacity(isFocused ? 1.0 : 0.85)
                .animation(Motion.focus, value: isFocused)
                .padding(.top, 14)
        }
    }

    @ViewBuilder
    private var posterArea: some View {
        let url = item.backdropURLParsed ?? item.posterURLParsed
        if item.hasDesignedArtwork, let url {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: 320, height: cardHeight),
                contentMode: .fill
            )
        } else {
            ProceduralPoster(
                item: item,
                accent: store.accentColor(forCategory: categoryID),
                aspectRatio: isLandscape ? 16.0/9.0 : 4.0/3.0
            )
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

    private var remainingLabel: String {
        if progress.durationSeconds > 0 {
            let remaining = max(0, Int(progress.durationSeconds - progress.positionSeconds))
            let m = remaining / 60
            if m >= 60 { return "\(m / 60)h \(m % 60)m left" }
            return "\(m)m left"
        }
        let watched = Int(progress.positionSeconds) / 60
        return "\(watched)m watched"
    }
}
