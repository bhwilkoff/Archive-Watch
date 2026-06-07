import SwiftUI

// SwiftUI wrapper for VHS.metal. Drives an animated `time` uniform through a
// TimelineView and feeds the view's pixel size + intensity into the stitchable
// `vhs` layer effect. `.visualEffect` supplies the GeometryProxy without
// disturbing layout, so this can wrap any view edge-to-edge.
//
// GPU-only and ~30 fps; gated behind a Settings toggle (AppStore.screensaverVHS).
extension View {
    @ViewBuilder
    func vhsEffect(enabled: Bool, amount: Double = 1.0) -> some View {
        if enabled {
            modifier(VHSEffectModifier(amount: amount))
        } else {
            self
        }
    }
}

/// A translucent analog-VHS layer to composite OVER live video (where a
/// sampling `.layerEffect` can't reach — AVPlayerViewController owns its video
/// layer). Place it as an `.overlay` on the player with `.allowsHitTesting(false)`
/// so the native transport still works. See `vhsOverlay` in VHS.metal.
struct VHSVideoOverlay: View {
    var amount: Double = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = Float(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600))
            Rectangle()
                .fill(.white)
                .visualEffect { view, proxy in
                    view.colorEffect(
                        ShaderLibrary.vhsOverlay(
                            .float2(proxy.size),
                            .float(t),
                            .float(Float(amount))
                        )
                    )
                }
                .ignoresSafeArea()
        }
    }
}

private struct VHSEffectModifier: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            // keep the clock bounded so noise hashes stay numerically stable
            let t = Float(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600))
            content.visualEffect { view, proxy in
                view.layerEffect(
                    ShaderLibrary.vhs(
                        .float2(proxy.size),
                        .float(t),
                        .float(Float(amount))
                    ),
                    maxSampleOffset: CGSize(width: 40, height: 4)
                )
            }
        }
    }
}
