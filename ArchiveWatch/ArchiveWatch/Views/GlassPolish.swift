import SwiftUI

// Liquid Glass helpers for tvOS 26. With the deployment target bumped
// to 26, these are unconditional — no `if #available` fallbacks.
//
// Liquid Glass is the tvOS 26 design language (WWDC 2025 "Meet Liquid
// Glass"). It replaces flat materials with refractive depth that
// adapts to whatever's behind it — perfect for a cinematheque app
// where hero posters and backdrops sit behind most chrome.
//
// Canonical API surface:
//   .glassEffect()                              // default glass
//   .glassEffect(.regular)                      // standard strength
//   .glassEffect(.clear)                        // translucent variant
//   .glassEffect(.regular, in: Capsule())       // shaped
//   .glassEffect(.regular.tint(.orange), in:)   // tinted
//   .glassEffect(.regular.interactive(), in:)   // focus/press-reactive
//   GlassEffectContainer { ... }                // group glass views so
//                                               // they morph together

extension View {

    /// Tinted Liquid Glass — glass + accent bleed. Use for selected
    /// states where a color cue is wanted.
    func liquidGlassTinted<S: Shape>(_ tint: Color, in shape: S) -> some View {
        self.glassEffect(.regular.tint(tint), in: shape)
    }

    /// Interactive Liquid Glass for buttons — animates on focus/press.
    func liquidGlassInteractive<S: Shape>(in shape: S) -> some View {
        self.glassEffect(.regular.interactive(), in: shape)
    }

    /// Legacy bridge used by SortPicker and chip call sites before the
    /// refactor. Maps isOn → tinted glass, off → clear glass. Keep so
    /// we can ship the upgrade without touching every call site at once.
    func glassBackground<S: InsettableShape & Shape>(shape: S, isOn: Bool, accent: Color) -> some View {
        Group {
            if isOn {
                self.glassEffect(.regular.tint(accent), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        }
    }
}
