#if os(iOS)
import SwiftUI
import CoreTransferable

// iPad places, pointer and drag and drop (IPAD-DESIGN §10–§12).

/// A film picked up by drag (§12.1). The payload is its archivewatch.org link,
/// so a film dropped into Notes or Mail arrives as a link someone can open.
struct FilmTransfer: Transferable {
    let archiveID: String

    var url: URL { URL(string: "https://archivewatch.org/item/\(archiveID)")! }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
    }

    /// The film a dropped link names: our own /item/ link, or an archive.org /
    /// archivewatch.org details, download or embed link. Anything else is not a
    /// film, and is refused rather than guessed (§12.2).
    static func archiveID(from url: URL) -> String? {
        let parts = url.pathComponents
        if let host = url.host?.lowercased(), host.hasSuffix("archivewatch.org"),
           parts.count >= 3, parts[1] == "item" {
            return parts[2].removingPercentEncoding ?? parts[2]
        }
        return ArchiveLink.id(from: url.absoluteString)
    }
}

extension View {
    /// Poster tiles at regular width: they lift under the pointer (§11.1) and
    /// can be picked up (§12.1). Compact width is left exactly as it was.
    func iPadFilmTile(_ archiveID: String) -> some View {
        modifier(IPadFilmTile(archiveID: archiveID))
    }
}

private struct IPadFilmTile: ViewModifier {
    let archiveID: String
    @Environment(\.horizontalSizeClass) private var hSize

    func body(content: Content) -> some View {
        if hSize == .regular {
            content
                .hoverEffect(.lift)
                .draggable(FilmTransfer(archiveID: archiveID))
        } else {
            content
        }
    }
}

/// The sidebar's Watch Together place (§10.2): what this device can do, in one
/// sentence (Decision 131), and the way into a room.
struct WatchTogetherLanding: View {
    @State private var joining = false

    var body: some View {
        ContentUnavailableView {
            Label("Watch Together", systemImage: "person.2.wave.2")
        } description: {
            Text(WatchTogetherHere.summary)
        } actions: {
            Button("Join a Room") { joining = true }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Watch Together")
        .sheet(isPresented: $joining) { JoinRoomSheet_iOS() }
    }
}
#endif
