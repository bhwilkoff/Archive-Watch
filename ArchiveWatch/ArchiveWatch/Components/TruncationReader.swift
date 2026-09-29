import SwiftUI

/// Whether a clamped text is hiding anything, MEASURED: the full text is laid
/// out hidden behind the clamped one and the two heights compared (the tvOS
/// loop v1.42.840; the iPad's v1.42.868). A character count guessed wrong both
/// ways — it offered More on a review whose whole text was already showing,
/// and missed short multi-paragraph ones. One implementation for every
/// platform's "More", where there were four copies.
struct TruncationReader: ViewModifier {
    let fullText: Text
    @Binding var isTruncated: Bool
    @State private var shown: CGFloat = 0
    @State private var full: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown = $0; update() }
            .background(alignment: .topLeading) {
                fullText
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full = $0; update() }
            }
    }

    private func update() {
        let now = full > shown + 1
        if now != isTruncated { isTruncated = now }
    }
}

extension View {
    /// Apply to the CLAMPED text; pass the same text, same font, unclamped.
    func readsTruncation(of fullText: Text, into isTruncated: Binding<Bool>) -> some View {
        modifier(TruncationReader(fullText: fullText, isTruncated: isTruncated))
    }
}
