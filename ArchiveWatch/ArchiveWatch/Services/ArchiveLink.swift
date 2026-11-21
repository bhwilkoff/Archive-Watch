import Foundation

/// The identifier in an archive.org (or archivewatch.org) details, download or
/// embed link, or nil — so a link pasted into search opens what it points at
/// (2026-09-26, from the Orphaned Films research). The web's
/// `ArchiveAddress.idFrom` and Android's `CatalogDatabase.archiveIdFromLink`
/// are the same rule; `tools/test_archive_link.swift` holds the shared table.
enum ArchiveLink {
    static func id(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:https?://)?(?:www\.)?(?:archive\.org|archivewatch\.org)/(?:details|download|embed)/[^/?#\s]+"#
        guard let r = t.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
              let kind = t[r].range(of: #"/(details|download|embed)/"#,
                                    options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let id = String(t[r][kind.upperBound...])
        return id.removingPercentEncoding ?? id
    }
}

/// "Something wrong with this film?" (2026-09-26, the Orphaned Films
/// research): archivewatch.org/report.html with only what identifies the
/// report — the film and where it was seen. The page offers an email and the
/// GitHub issue form; a GitHub-only link asked a viewer to make an account
/// (2026-11-17). Short, because the Apple TV shows it as a QR code. The web's
/// `filmProblemURL`, Android's and Roku's `FilmProblem` build the same URL.
enum FilmProblem {
    static func url(archiveID: String) -> URL? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        #if os(tvOS)
        let platform = "tvOS"
        #elseif os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        var c = URLComponents(string: "https://archivewatch.org/report.html")
        c?.queryItems = [URLQueryItem(name: "film", value: archiveID),
                         URLQueryItem(name: "where", value: "\(platform) \(version)")]
        return c?.url
    }
}
