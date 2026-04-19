import SwiftUI

// Liquid Glass polish for tvOS 26+, with graceful fallback for tvOS 17.
// Apply `.glassBackground(shape:isOn:accent:)` to any chip-like surface.
// On tvOS 17 the modifier falls back to the existing opacity fill.

extension View {
    /// Replaces the flat opacity background with a glass material on tvOS 26+.
    func glassBackground<S: InsettableShape>(shape: S, isOn: Bool, accent: Color) -> some View {
        modifier(GlassBackground(shape: shape, isOn: isOn, accent: accent))
    }
}

private struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let isOn: Bool
    let accent: Color

    func body(content: Content) -> some View {
        if #available(tvOS 26.0, *) {
            content
                .background {
                    if isOn {
                        shape.fill(accent)
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                }
        } else {
            content
                .background(isOn ? accent : Color.white.opacity(0.08), in: shape)
        }
    }
}
