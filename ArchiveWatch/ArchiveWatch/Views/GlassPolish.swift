import SwiftUI

// Liquid Glass helpers (tvOS 26+).
//
// The app's deployment target is tvOS 26.0, so we use Apple's native
// `.glassEffect` material directly — no `.ultraThinMaterial` stand-in,
// no hand-drawn stroke. Centralized so chips, the sort picker, and
// overlays share one glass vocabulary and inherit the system's adaptive
// vibrancy + focus treatment instead of each view faking blur.
//
// Per the Liquid Glass guidance: glass is for floating chrome (chips,
// controls, overlays), never for large content areas, and multiple
// adjacent glass elements should sit in a `GlassEffectContainer`.

struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    /// When true (e.g. an active filter chip) the glass takes the
    /// category accent as a subtle tint so selection reads at 10 feet.
    let isOn: Bool
    let accent: Color

    func body(content: Content) -> some View {
        content
            .glassEffect(
                isOn ? .regular.tint(accent.opacity(0.55)) : .regular,
                in: shape
            )
    }
}

extension View {
    func glassBackground<S: Shape>(shape: S, isOn: Bool, accent: Color) -> some View {
        self.modifier(GlassBackground(shape: shape, isOn: isOn, accent: accent))
    }

    // Convenience for the common capsule chip case.
    func glassChip(isOn: Bool, accent: Color) -> some View {
        glassBackground(shape: Capsule(), isOn: isOn, accent: accent)
    }
}
