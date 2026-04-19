import Foundation

// MARK: - Archive.org response types
//
// Archive.org's JSON is famously inconsistent. These types absorb the
// rough edges so the rest of the app can work with a clean surface.
// When in doubt, prefer optional + `OneOrMany` over crashes.

// MARK: Metadata endpoint — /metadata/{identifier}

struct ArchiveMetadataResponse: Codable, Sendable {
    let metadata: ArchiveItemMetadata?
    let files: [ArchiveFile]?
    let server: String?
    let dir: String?

    /// Build a download URL for a named file on this item.
    func downloadURL(for filename: String) -> URL? {
        guard let server = server, let dir = dir else { return nil }
        // Path components must be percent-encoded. `URLComponents` handles this.
        var components = URLComponents()
        components.scheme = "https"
        components.host = server
        components.path = "\(dir)/\(filename)"
        return components.url
    }
}

struct ArchiveItemMetadata: Codable, Sendable {
    let identifier: String?
    let title: String?
    let description: OneOrMany<String>?
    let creator: OneOrMany<String>?
    let subject: OneOrMany<String>?
    let collection: OneOrMany<String>?
    let mediatype: String?
    let date: String?
    let year: String?
    let runtime: String?
    let language: OneOrMany<String>?
    let licenseurl: String?
    let uploader: String?
    let addeddate: String?

    /// Archive items sometimes store `external-identifier` with IMDb URN.
    /// Key contains a hyphen, so we decode via `CodingKeys`.
    let externalIdentifier: OneOrMany<String>?

    enum CodingKeys: String, CodingKey {
        case identifier, title, description, creator, subject
        case collection, mediatype, date, year, runtime, language
        case licenseurl, uploader, addeddate
        case externalIdentifier = "external-identifier"
    }

    // MARK: Derived

    /// Year parsed from `year` or falling back to the first 4 digits of `date`.
    var parsedYear: Int? {
        if let y = year, let n = Int(y.prefix(4)) { return n }
        if let d = date, let n = Int(d.prefix(4)) { return n }
        return nil
    }

    /// Extract the IMDb tt-ID if present in `external-identifier`.
    var imdbID: String? {
        guard let urns = externalIdentifier?.values else { return nil }
        for urn in urns {
            if let id = Self.extractIMDbID(from: urn) { return id }
        }
        return nil
    }

    private static func extractIMDbID(from urn: String) -> String? {
        // Formats we've seen: "urn:imdb:tt0032138", "imdb:tt0032138", "tt0032138"
        let lower = urn.lowercased()
        if let range = lower.range(of: #"tt\d{6,10}"#, options: .regularExpression) {
            return String(lower[range])
        }
        return nil
    }

    /// Runtime in seconds, parsed from "HH:MM:SS", "MM:SS", or plain seconds.
    var runtimeSeconds: Int? {
        guard let r = runtime?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        let parts = r.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return nil
        }
    }
}

// MARK: Files

struct ArchiveFile: Codable, Sendable {
    let name: String?
    let source: String?    // "original" | "derivative" | "metadata"
    let format: String?    // "h.264", "MPEG4", "512Kb MPEG4", "Thumbnail", ...
    let size: String?      // bytes, as string
    let length: String?    // "HH:MM:SS" or seconds, for video files
    let original: String?  // for derivatives, the original filename
    let width: String?
    let height: String?

    var sizeBytes: Int64? { size.flatMap { Int64($0) } }

    var isVideo: Bool {
        guard let f = format?.lowercased() else { return false }
        return f.contains("mp4") || f.contains("h.264") || f.contains("mpeg4")
            || f.contains("ogg video") || f.contains("matroska") || f.contains("quicktime")
            || f.contains("avi") || f.contains("webm")
    }

    var isDerivative: Bool { source?.lowercased() == "derivative" }
    var isOriginal: Bool { source?.lowercased() == "original" }
}

// MARK: Scrape endpoint — /services/search/v1/scrape

struct ArchiveScrapeResponse: Codable, Sendable {
    let items: [ArchiveScrapeItem]?
    let count: Int?
    let cursor: String?
    let total: Int?
}

struct ArchiveScrapeItem: Codable, Sendable {
    let identifier: String
    let title: String?
    let creator: OneOrMany<String>?
    let date: String?
    let year: String?
    let mediatype: String?
    let collection: OneOrMany<String>?
    let subject: OneOrMany<String>?
    let downloads: Int?
    let description: OneOrMany<String>?
    let runtime: String?
}
