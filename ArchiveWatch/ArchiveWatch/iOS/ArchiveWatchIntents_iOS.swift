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
        case openSharedList(PlaylistShare.Shared)   // a playlist someone sent as a link
        case joinRoom(code: String, film: String)   // a Watch Together room link (SHAREPLAY §11)
    }

    /// A room link: `https://archivewatch.org/together/#<code>-<film>` (the
    /// shape every platform emits and 404.html forwards) or
    /// `archivewatch://together/<code>-<film>`. The code is normalized the way
    /// a typed one is, so a link and the keyboard reach the same room.
    static func room(from url: URL) -> Request? {
        let raw: String
        if url.scheme == "archivewatch", url.host == "together" {
            raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if url.scheme == "https", url.host?.hasSuffix("archivewatch.org") == true,
                  url.path.hasPrefix("/together") {
            raw = url.fragment ?? ""
        } else {
            return nil
        }
        guard let dash = raw.firstIndex(of: "-"),
              let code = StudioRoom.normalize(String(raw[..<dash])) else { return nil }
        let film = String(raw[raw.index(after: dash)...])
        return film.isEmpty ? nil : .joinRoom(code: code, film: film)
    }

    /// Parse an `archivewatch://` deep link into a request.
    static func request(for url: URL) -> Request? {
        // A SHARED PLAYLIST FIRST, and before the scheme guard on purpose: it
        // arrives as an ordinary https link, because the whole point is that it
        // opens for somebody with no app at all. The playlist is INSIDE the
        // url, so this resolves completely here with nothing to look up.
        if let shared = PlaylistShare.shared(from: url) { return .openSharedList(shared) }
        if let room = room(from: url) { return room }
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
