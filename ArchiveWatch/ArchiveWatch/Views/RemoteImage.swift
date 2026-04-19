import SwiftUI
import UIKit

// SwiftUI wrapper over ImageLoader. Drop-in replacement for AsyncImage
// anywhere the view sits inside a LazyHStack / LazyVGrid — which is to
// say most of this app.
//
// Key differences from AsyncImage:
// - Actually respects URLCache + NSCache on repeat views
// - Decodes off-main via ImageIO, downsampled in one pass
// - Shows a solid placeholder immediately (never gates layout on load)
// - .task(id: url) — free cancellation when cell leaves the lazy window

struct RemoteImage: View {
    let url: URL?
    let targetSize: CGSize
    var contentMode: ContentMode = .fill
    var placeholder: Color = Color.black.opacity(0.15)

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            do {
                let loaded = try await ImageLoader.shared.image(
                    for: url,
                    targetSize: targetSize,
                    scale: 2
                )
                try Task.checkCancellation()
                image = loaded
            } catch {
                // Silent failure; placeholder stays visible. Procedural
                // fallback is the caller's concern (see hasDesignedArtwork
                // checks upstream).
            }
        }
    }
}
