import SwiftUI
import CoreTransferable

// Shared by iPad (IPAD-DESIGN §12) and Mac (macOS-DESIGN §B15).

/// A film picked up by drag (IPAD-DESIGN §12.1, macOS-DESIGN §B15). The payload is its archivewatch.org link,
/// so a film dropped into Notes or Mail arrives as a link someone can open.
struct FilmTransfer: Transferable {
    let archiveID: String

    var url: URL { URL(string: "https://archivewatch.org/item/\(archiveID)")! }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
    }

    /// The film a dropped link names: our own /item/ link, or an archive.org /
    /// archivewatch.org details, download or embed link. Anything else is not a
    /// film, and is refused rather than guessed (§12.2 / §B15).
    static func archiveID(from url: URL) -> String? {
        let parts = url.pathComponents
        if let host = url.host?.lowercased(), host.hasSuffix("archivewatch.org"),
           parts.count >= 3, parts[1] == "item" {
            return parts[2].removingPercentEncoding ?? parts[2]
        }
        return ArchiveLink.id(from: url.absoluteString)
    }
}
