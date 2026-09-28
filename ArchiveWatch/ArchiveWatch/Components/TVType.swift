#if os(tvOS)
import SwiftUI

/// The tvOS type ramp (tvOS-DESIGN §4.1), as sizes that follow the viewer's
/// Text Size (Settings > Accessibility, tvOS 27). A fixed `.system(size:)`
/// never scales, so beside the few semantic fonts that do it read as two
/// different apps at large sizes.
enum TVType {
    static let display: CGFloat = 76   // hero title
    static let title: CGFloat = 57     // page title (full-text page, sheets)
    static let heading: CGFloat = 38   // section heading
    static let body: CGFloat = 29      // reading text; the 10-ft floor
    static let meta: CGFloat = 23      // provenance, captions, the action name

    /// The text style a size scales with: the ramp level at or just below it.
    static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 70...: .largeTitle
        case 50..<70: .title
        case 42..<50: .title2
        case 33..<42: .title3
        case 27..<33: .body
        case 24..<27: .caption
        default: .caption2
        }
    }
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` at the default Text Size, scaled
    /// with the ramp level the size belongs to at every other.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular,
                    design: Font.Design = .default,
                    relativeTo style: Font.TextStyle? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design,
                                  relativeTo: style ?? TVType.style(for: size)))
    }
}
#endif
