#if os(tvOS)
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
    // When true, the image is drawn with `contentMode` over a blurred,
    // filled copy of itself. Lets a slot show an off-aspect image (e.g. a
    // 2:3 poster in a 16:9 episode-still slot) without an ugly center-crop:
    // the foreground fits whole, the blurred copy fills the rest. Callers
    // must clip the surrounding frame (the fill overflows by design).
    var blurredBackdrop: Bool = false
    /// Called when the load fails — lets a caller advance to a fallback (archive frame → procedural)
    /// so a poster slot is NEVER left blank (owner: a blank poster makes the app look broken).
    var onLoadFailed: (() -> Void)? = nil

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                if blurredBackdrop {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 24)
                        .opacity(0.55)
                        .allowsHitTesting(false)
                }
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
            } catch is CancellationError {
                // cell left the lazy window — not a real failure
            } catch {
                onLoadFailed?()   // let the caller fall through to its non-blank fallback
            }
        }
    }
}

#endif
