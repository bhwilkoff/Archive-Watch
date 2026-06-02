import Foundation

enum CatalogLoader {

    enum LoadError: Error {
        case bundleMissing(String)
        case decodeFailed(String, Error)
    }

    // The catalog itself is no longer loaded from JSON — it lives in the
    // SQLite DB (Decision 017). Only featured.json (small) stays bundled JSON.
    static func loadFeatured() throws -> Featured {
        try loadBundled("featured", as: Featured.self)
    }

    private static func loadBundled<T: Decodable>(_ resource: String, as type: T.Type) throws -> T {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw LoadError.bundleMissing(resource + ".json")
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LoadError.decodeFailed(resource, error)
        }
    }
}
