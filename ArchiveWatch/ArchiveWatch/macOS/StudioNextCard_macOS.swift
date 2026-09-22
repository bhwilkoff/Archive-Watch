#if os(macOS)
import AppKit
import CoreImage
import SwiftUI

// NEXT — macOS-DESIGN §D19, roadmap #5.
//
// §D5 is emphatic that the preview IS the programme, so that "what I see" and
// "what they see" cannot diverge. This is the one deliberate exception, and it
// earns it: a host composing a card mid-show writes words the audience will
// read, and today they write them blind — the editor is four text fields and
// the only way to see the result is to put it on air.
//
// The guards that keep §D5 intact are in the rule and in this file: it is a
// THUMBNAIL rather than a third pane, it is drawn only when something is
// staged, TAKE is the only route to the audience and taking it clears the
// staging — so NEXT never shows what is already out.
//
// AND IT RENDERS THROUGH THE PROGRAMME'S OWN RENDERER. A second drawing path
// would be a second chance to differ from the thing it previews, which is
// exactly the mistake §D5 forbids. `StudioOverlayRenderer` at 640x360 draws
// the same card the engine draws at 1920x1080 — it scales from a 1920
// reference, so the proportions are the programme's.

struct StudioNextCard: View {
    @Bindable var controls: StudioControls
    /// The film's title, because a "Starting soon" card names the film and a
    /// preview that left it out would not be a preview of the real thing.
    let filmTitle: String

    /// Rendered off the staged state, and cached on it — text layout is not
    /// free and this view redraws at the health tick.
    @State private var image: NSImage?

    private let marquee = Color(hex: "#FF5C35") ?? .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("NEXT").font(.caption2.weight(.bold)).foregroundStyle(marquee)
                // SAID OUT LOUD, every time it is on screen. §D19: this is the
                // one picture in the Studio that is not going out, and a host
                // who mistakes it for the programme has been misled by us.
                Text("not on air").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Clear") { controls.stagedCard = .none }
                    .font(.caption).buttonStyle(.borderless).fixedSize()
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: 260)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(marquee.opacity(0.7), lineWidth: 1))
            }
            Button("Show it now") {
                // TAKE. The staged card becomes the card, and the staging
                // clears — so NEXT is never a picture of what is already out.
                controls.cardChoice = controls.stagedCard
                controls.stagedCard = .none
            }
            .controlSize(.small)
            .disabled(controls.stagedCard == .none)
        }
        .task(id: renderKey) { image = render() }
    }

    /// Everything that changes the picture, and nothing that does not.
    private var renderKey: String {
        controls.stagedCard.label + "|" + filmTitle + "|"
            + controls.customCardLines.map { "\($0.rank.rawValue):\($0.text)" }
                .joined(separator: "\u{1F}")
    }

    private func render() -> NSImage? {
        guard controls.stagedCard != .none else { return nil }
        let card: StudioOverlay.Card? = controls.stagedCard == .custom
            ? (controls.customCardHasWords ? .custom(lines: controls.customCardLines) : nil)
            : controls.stagedCard.value
        guard let card else { return nil }

        // 640x360: the renderer scales everything from a 1920-wide reference,
        // so this is the programme's own layout at a third the size rather
        // than a re-proportioned copy.
        let size = CGSize(width: 640, height: 360)
        var overlay = StudioOverlay()
        overlay.title = filmTitle
        overlay.card = card
        guard let ci = StudioOverlayRenderer(size: size).image(for: overlay) else { return nil }

        // Over BLACK, because a card owns the frame and the renderer hands
        // back premultiplied alpha — composited over nothing it would show the
        // window behind it and look like a bug in the card.
        let ground = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        let composited = ci.composited(over: ground)
        let context = CIContext()
        guard let cg = context.createCGImage(composited, from: CGRect(origin: .zero, size: size))
        else { return nil }
        return NSImage(cgImage: cg, size: size)
    }
}
#endif
