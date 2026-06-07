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
