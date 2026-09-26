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
