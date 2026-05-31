import AppIntents
import SwiftUI

// Siri / Shortcuts entry points (Decision 015, M2).
//
// "Hey Siri, surprise me on Archive Watch" and friends. App Intents
// perform() runs in-process when openAppWhenRun is true, so it can't
// touch the SwiftUI @Environment Router/AppStore directly — it drops a
// request in this shared inbox, which RootView observes and acts on once
// the app is foreground. Pairs with the existing Surprise actions
// (Decision 014).

@MainActor
@Observable
final class IntentInbox {
    static let shared = IntentInbox()
    private init() {}

    enum Request: Equatable {
        case surprise        // jump to the Surprise tab
        case randomFilm      // play/open a random playable film
        case randomCategory  // open a random category's browse view
    }

    /// Set by an AppIntent; consumed (set back to nil) by RootView.
    var request: Request?
}

struct SurpriseMeIntent: AppIntent {
    static let title: LocalizedStringResource = "Surprise Me"
    static let description = IntentDescription("Open the Surprise screen to wander the archive.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.shared.request = .surprise
        return .result()
    }
}

struct RandomFilmIntent: AppIntent {
    static let title: LocalizedStringResource = "Random Film"
    static let description = IntentDescription("Open a random film from the archive.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.shared.request = .randomFilm
        return .result()
    }
}

struct RandomCategoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Random Category"
    static let description = IntentDescription("Open a random category to browse.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.shared.request = .randomCategory
        return .result()
    }
}

struct ArchiveWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SurpriseMeIntent(),
            phrases: [
                "Surprise me on \(.applicationName)",
                "\(.applicationName) surprise me"
            ],
            shortTitle: "Surprise Me",
            systemImageName: "dice.fill"
        )
        AppShortcut(
            intent: RandomFilmIntent(),
            phrases: [
                "Play a random film on \(.applicationName)",
                "Random film on \(.applicationName)"
            ],
            shortTitle: "Random Film",
            systemImageName: "film.fill"
        )
        AppShortcut(
            intent: RandomCategoryIntent(),
            phrases: [
                "Open a random category on \(.applicationName)"
            ],
            shortTitle: "Random Category",
            systemImageName: "square.grid.2x2.fill"
        )
    }
}
