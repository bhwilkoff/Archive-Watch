import Foundation

/// Tonight (tvOS-DESIGN §2.4c, iOS-DESIGN §5.1d, macOS-DESIGN §B4d;
/// WEB-DESIGN §4.1c): one film a day, the same on every platform on that local
/// date, picked by rule in the pipeline (`build_catalog_index.tonight_schedule`)
/// and published as tonight.json. It leads the hero with a TONIGHT eyebrow and
/// only when it passes the hero's own gates; without the file the hero is
/// unchanged.
@MainActor
enum Tonight {
    private(set) static var currentID: String?
    private static var schedule: [String: String]?
    private static let url = URL(string: "https://archivewatch.org/tonight.json")!

    static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Fetched once per launch; the day is re-read on every call.
    @discardableResult
    static func load() async -> String? {
        if schedule == nil {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let file = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
                schedule = file["tonight"] ?? [:]
            }
        }
        currentID = schedule?[dayKey()]
        return currentID
    }

    static func lead(_ hero: [Catalog.Item], with tonight: Catalog.Item?) -> [Catalog.Item] {
        guard let tonight, tonight.backdropURLParsed != nil, tonight.isHeroRightsSafe else { return hero }
        let rest = hero.filter { $0.archiveID != tonight.archiveID }
        return [tonight] + rest.prefix(max(0, hero.count - 1))
    }
}
