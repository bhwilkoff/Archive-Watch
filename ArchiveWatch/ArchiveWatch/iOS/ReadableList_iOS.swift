#if os(iOS)
import SwiftUI

/// IPAD-DESIGN §2.1 for a List: at regular width its rows end at the 700pt
/// measure while the list itself (its scrolling, its background, its swipe
/// actions) still fills the window. Capping the List's frame instead would
/// strand the scroll indicator mid-screen.
struct ReadableListWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var width: CGFloat = 0
    var measure: CGFloat = 700

    func body(content: Content) -> some View {
        content
            .contentMargins(.trailing, hSize == .regular ? max(0, width - measure) : 0,
                            for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    func readableListWidth(_ measure: CGFloat = 700) -> some View {
        modifier(ReadableListWidth(measure: measure))
    }
}
#endif

