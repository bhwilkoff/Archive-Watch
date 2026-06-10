#if os(iOS)
import SwiftUI

// Brand tokens — mirror css/:root and the tvOS palette (Decision 013 split:
// brand chrome vs per-category semantic accents). Category accents come from
// featured.json at runtime; these are the chrome constants.
enum Brand {
    static let primary = Color(hex: "#FF5C35") ?? .orange   // marquee orange (CTA)
    static let accent  = Color(hex: "#0047FF") ?? .blue     // links / interactive
}

#endif
