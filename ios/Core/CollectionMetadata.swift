import SwiftUI

// Single source of truth for Archive.org collection display metadata.
// The actual entries live in shared/editorial/collection_metadata.json at
// the repo root — both the Swift app and the Python pipeline read the
// same file so display titles, blurbs, and accents never drift.
//
// The JSON is bundled with the app as a resource. On first lookup we
// decode it lazily; subsequent calls are O(1) dictionary hits.

enum CollectionMetadata {

    struct Entry: Identifiable, Decodable {
        let id: String
        let title: String
        let blurb: String
        let accent: String     // hex
        let category: String?  // app contentType vocabulary: feature-film, silent-film, ...
    }

    // MARK: - Public API (unchanged from the previous hard-coded version)

    static var all: [Entry] { loaded.entries }

    static func entry(for id: String) -> Entry? {
        loaded.byID[id]
    }

    /// Display title for a collection id. Never returns the raw slug — falls
    /// back to a de-slugged variant for any collection we haven't catalogued
    /// yet (e.g., newly-surfaced Archive collection).
    static func title(for id: String) -> String {
        if let entry = loaded.byID[id] { return entry.title }
        return id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    static func accent(for id: String) -> Color {
        guard let hex = entry(for: id)?.accent else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }

    // MARK: - Loader

    private struct Payload: Decodable {
        let collections: [Entry]
    }

    private struct Loaded {
        let entries: [Entry]
        let byID: [String: Entry]
    }

    /// Decoded once per process. The bundle lookup fails silently and
    /// returns an empty catalog if the resource is missing — the UI still
    /// renders (collections just fall back to de-slugged titles) rather
    /// than crashing.
    private static let loaded: Loaded = {
        guard
            let url = Bundle.main.url(forResource: "collection_metadata", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            #if DEBUG
            print("⚠️ CollectionMetadata: collection_metadata.json not bundled — "
                + "add shared/editorial/collection_metadata.json to the app target's resources")
            #endif
            return Loaded(entries: [], byID: [:])
        }
        let byID = Dictionary(uniqueKeysWithValues: decoded.collections.map { ($0.id, $0) })
        return Loaded(entries: decoded.collections, byID: byID)
    }()
}
