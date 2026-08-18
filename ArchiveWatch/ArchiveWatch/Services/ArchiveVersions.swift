import Foundation

// Every playable copy of a film that lives on its archive.org item, so the
// VIEWER can choose (owner, 2026-08-17: "providing the user with the ability
// to select themselves from the different video, audio, and captions
// available for each title").
//
// An archive.org item routinely holds several transfers of the same film — an
// uploader's original plus Archive-generated derivatives at lower bitrates —
// and the pipeline picks one. When that pick streams badly on a particular
// evening, or is simply a worse transfer, the app has been the only one with
// a say. This is the escape hatch, and it is also honest about what the
// Archive is: a place where the same film exists in several conditions.
//
// Fetched ON DEMAND when the viewer opens the picker, never at Detail load.
// The file list is exactly what /metadata returns, so it needs no catalog
// column (Decision 046's rule: detail-only data does not earn hot storage),
// costs nothing until asked for, and cannot go stale.
enum ArchiveVersions {

    struct Version: Identifiable, Hashable {
        let name: String            // the file name on the item
        let url: URL
        let sizeBytes: Int64
        let format: String          // archive.org's own label, e.g. "h.264"
        let heightPixels: Int?
        let isDerivative: Bool      // Archive-generated (h.264 by construction)

        var id: String { name }

        /// `480p · H.264 · 575 MB — Archive derivative`. Literal, not a
        /// judgement: "Best"/"Auto" labels hide what is actually being chosen,
        /// and the point of this screen is that the viewer can see it.
        var label: String {
            var parts: [String] = []
            if let h = heightPixels, h > 0 { parts.append("\(h)p") }
            let codec = format
                .replacingOccurrences(of: "h.264", with: "H.264", options: .caseInsensitive)
            if !codec.isEmpty { parts.append(codec) }
            parts.append(Self.sizeText(sizeBytes))
            let origin = isDerivative ? "Archive derivative" : "uploader original"
            return parts.joined(separator: " · ") + " — " + origin
        }

        /// Same facts, no origin clause. The transport-bar menu is narrow and
        /// truncated the full label mid-phrase on the Apple TV — "H.264 -
        /// 563.2 MB — Archive" with the rest cut — which defeats a menu whose
        /// only job is to show what you are choosing. Where the copy CAME from
        /// matters when browsing on Detail; mid-film, resolution and size are
        /// what the viewer is deciding between.
        var compactLabel: String {
            var parts: [String] = []
            if let h = heightPixels, h > 0 { parts.append("\(h)p") }
            let codec = format
                .replacingOccurrences(of: "h.264", with: "H.264", options: .caseInsensitive)
            if !codec.isEmpty { parts.append(codec) }
            parts.append(Self.sizeText(sizeBytes))
            return parts.joined(separator: " · ")
        }

        private static func sizeText(_ bytes: Int64) -> String {
            let f = ByteCountFormatter()
            f.allowedUnits = [.useMB, .useGB]
            f.countStyle = .file
            return f.string(fromByteCount: bytes)
        }
    }

    /// Playable video copies on the item, best quality first.
    ///
    /// Containers Apple cannot open are filtered OUT rather than shown
    /// disabled — an option that cannot play is not a choice, it is a
    /// dead end with an explanation attached.
    static func list(itemID: String) async -> [Version] {
        guard let metaURL = URL(string: "https://archive.org/metadata/\(itemID)") else { return [] }
        var req = URLRequest(url: metaURL)
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = obj["files"] as? [[String: Any]] else { return [] }

        var out: [Version] = []
        for f in files {
            guard let name = f["name"] as? String,
                  name.lowercased().hasSuffix(".mp4"),
                  let sizeStr = f["size"] as? String, let size = Int64(sizeStr),
                  size > 5_000_000,                  // a stub, a sample, or a thumbnail
                  let encoded = name.addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://archive.org/download/\(itemID)/\(encoded)")
            else { continue }
            let format = (f["format"] as? String) ?? ""
            out.append(Version(
                name: name,
                url: url,
                sizeBytes: size,
                format: format,
                heightPixels: (f["height"] as? String).flatMap { Int($0) },
                isDerivative: (f["source"] as? String) == "derivative"))
        }
        // RESOLUTION first, size only to break ties. Sorting by size alone
        // was wrong and the device showed it: Utopia's 240p MPEG-4 copy is
        // 591 MB against 563 MB for its 480p H.264, because MPEG-4 Part 2 is
        // far less efficient — so the worse picture sorted above the better
        // one. Bytes measure the encoder, not the transfer.
        return out.sorted {
            let (a, b) = ($0.heightPixels ?? 0, $1.heightPixels ?? 0)
            return a == b ? $0.sizeBytes > $1.sizeBytes : a > b
        }
    }

    // MARK: - Per-title choice

    /// The viewer's chosen file for a title, if they have made one.
    ///
    /// Device-local on purpose, and NOT synced with favorites and progress:
    /// the right copy depends on this screen and this network, so an Apple TV
    /// on wired gigabit and a phone on cellular should not have to agree.
    /// Stored by file NAME rather than URL so it survives archive.org moving
    /// its storage nodes around (Decisions 031/034).
    static func chosenName(for archiveID: String) -> String? {
        defaults.dictionary(forKey: key)?[archiveID] as? String
    }

    static func choose(_ version: Version?, for archiveID: String) {
        var map = defaults.dictionary(forKey: key) ?? [:]
        if let version { map[archiveID] = version.name } else { map.removeValue(forKey: archiveID) }
        defaults.set(map, forKey: key)
    }

    /// The URL to actually play: the viewer's choice when they made one,
    /// otherwise the pipeline's pick unchanged.
    ///
    /// Rebuilt from the stored file NAME rather than looked up in a list, so
    /// the player never has to fetch /metadata to honour a choice — the
    /// download URL for a file on an item is deterministic. That also keeps
    /// the choice working when the Archive is slow to answer, which is
    /// precisely the evening someone reaches for a lighter copy.
    static func preferredURL(for archiveID: String, default fallback: URL) -> URL {
        guard let name = chosenName(for: archiveID),
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://archive.org/download/\(archiveID)/\(encoded)")
        else { return fallback }
        return url
    }

    private static var defaults: UserDefaults { .standard }
    private static let key = "aw.versionChoice.byArchiveID"
}
