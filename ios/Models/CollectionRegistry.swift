import Foundation

// MARK: - CollectionRegistry
//
// Authoritative mapping from Archive.org collection identifiers to
// Archive Watch display + category metadata. The source of truth is
// docs/taxonomy/collections.json at the repo root; at build time that
// JSON is copied into the app bundle as `collections.json`.
//
// This registry also carries:
//   - adultCollections: the deny-list for Decision 012 (default filter on)
//   - subjectKeywordMap: extended Archive `subject` → Genre mapping,
//     supplementing the inline cases in Genre.fromSubject(_:).
//
// Keep in sync with:
//   - docs/taxonomy/collections.json  (source of truth)
//   - js/build-catalog.js            (browser generator reads the same JSON)

struct CollectionInfo: Codable, Sendable {
    let displayName: String
    let category: String          // matches ContentType.rawValue
    let description: String?
    let weight: Double
    let posterAspect: String?
    let popularityThreshold: Int?
}

struct CollectionRegistryData: Codable, Sendable {
    let version: Int
    let updatedAt: String
    let collections: [String: CollectionInfo]
    let adultCollections: [String]
    let subjectKeywordMap: [String: String]
}

enum CollectionRegistry {

    private static let cached: CollectionRegistryData? = load()

    /// Returns metadata for an Archive collection id, or nil if unknown.
    static func info(for collectionID: String) -> CollectionInfo? {
        cached?.collections[collectionID.lowercased()]
    }

    /// Is this collection in the adult deny-list?
    static func isAdult(_ collectionID: String) -> Bool {
        cached?.adultCollections.contains(collectionID.lowercased()) ?? false
    }

    /// Does any of the given collections hit the adult deny-list?
    static func containsAdult(_ collectionIDs: [String]) -> Bool {
        for c in collectionIDs where isAdult(c) { return true }
        return false
    }

    /// Registry-backed extension of Genre.fromSubject. Falls back to the
    /// inline keyword map if the bundled JSON isn't loaded.
    static func genre(forSubject subject: String) -> Genre? {
        let key = subject.lowercased()
        if let mapped = cached?.subjectKeywordMap.first(where: { key.contains($0.key) })?.value,
           let genre = Genre(rawValue: mapped) {
            return genre
        }
        return Genre.fromSubject(subject)
    }

    /// The highest-weight collection among the ones given.
    /// Used by ContentTypeClassifier to pick the dominant category
    /// when an item belongs to multiple collections.
    static func dominantCollection(from collectionIDs: [String]) -> (id: String, info: CollectionInfo)? {
        var best: (String, CollectionInfo)? = nil
        for raw in collectionIDs {
            let id = raw.lowercased()
            guard let info = cached?.collections[id] else { continue }
            if best == nil || info.weight > best!.1.weight {
                best = (id, info)
            }
        }
        return best
    }

    // MARK: Loading

    private static func load() -> CollectionRegistryData? {
        guard let url = Bundle.main.url(forResource: "collections", withExtension: "json") else {
            // In unit tests or preview builds the resource may be absent;
            // degrade gracefully.
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CollectionRegistryData.self, from: data)
        } catch {
            assertionFailure("Failed to decode collections.json: \(error)")
            return nil
        }
    }
}
