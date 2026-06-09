#if os(iOS)
import AppIntents
import SwiftUI

// Siri / Shortcuts entry points for iOS (Decision 015). Mirrors the tvOS intents:
// perform() drops a request in a shared inbox that RootView observes and acts on
// once the app is foreground (the intent can't touch the SwiftUI Router directly).
// Pairs with the Home Surprise action (Decision 014).

@MainActor
@Observable
final class IntentInbox {
    static let shared = IntentInbox()
    private init() {}

    enum Request: Equatable {
        case surprise          // open a random title
        case randomFilm        // open a random playable film
        case randomCategory    // jump to Browse
        case openItem(String)  // open a specific title (deep link / widget)
    }

    /// Parse an `archivewatch://` deep link into a request.
    static func request(for url: URL) -> Request? {
        guard url.scheme == "archivewatch" else { return nil }
        switch url.host {
        case "item":           let id = url.lastPathComponent
                               return id.isEmpty ? nil : .openItem(id)
        case "surprise":       return .surprise
        case "random":         return .randomFilm
        case "randomcategory": return .randomCategory
        default:               return nil
        }
    }

    /// Set by an AppIntent / deep link; consumed (set back to nil) by RootView.
    var request: Request?
}

struct SurpriseMeIntent: AppIntent {
    static let title: LocalizedStringResource = "Surprise Me"
    static let description = IntentDescription("Open a random title to wander the archive.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        IntentInbox.shared.request = .surprise
        return .result()
    }
}

struct RandomFilmIntent: AppIntent {
    static let title: LocalizedStringResource = "Random Film"
    static let description = IntentDescription("Open a random film from the archive.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        IntentInbox.shared.request = .randomFilm
        return .result()
    }
}

struct RandomCategoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Browse the Archive"
    static let description = IntentDescription("Open Browse to wander films, TV, and collections.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        IntentInbox.shared.request = .randomCategory
        return .result()
    }
}

struct ArchiveWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SurpriseMeIntent(),
            phrases: ["Surprise me on \(.applicationName)", "\(.applicationName) surprise me"],
            shortTitle: "Surprise Me", systemImageName: "shuffle"
        )
        AppShortcut(
            intent: RandomFilmIntent(),
            phrases: ["Play a random film on \(.applicationName)", "Random film on \(.applicationName)"],
            shortTitle: "Random Film", systemImageName: "film.fill"
        )
        AppShortcut(
            intent: RandomCategoryIntent(),
            phrases: ["Browse \(.applicationName)"],
            shortTitle: "Browse", systemImageName: "square.grid.2x2.fill"
        )
    }
}

#endif
